(function () {
  if (typeof CELL_LCT_DIRECT_CONFIG === "undefined") {
    return "ERROR|Missing CELL_LCT_DIRECT_CONFIG|0|configuration";
  }

  var config = CELL_LCT_DIRECT_CONFIG;
  var sourceDoc = null;
  var destinationGroup = null;
  var targetDoc = null;
  var previousInteractionLevel = app.userInteractionLevel;
  var context = "initialization";
  var sourcePathCount = 0;
  var atomicItems = [];

  function safeProperty(object, propertyName, fallback) {
    try { return object[propertyName]; } catch (error) { return fallback; }
  }

  function serializeColor(sourceColor) {
    if (!sourceColor) return null;
    if (sourceColor.typename === "RGBColor") {
      return { type: "RGBColor", red: sourceColor.red, green: sourceColor.green, blue: sourceColor.blue };
    }
    if (sourceColor.typename === "CMYKColor") {
      return {
        type: "CMYKColor",
        cyan: sourceColor.cyan,
        magenta: sourceColor.magenta,
        yellow: sourceColor.yellow,
        black: sourceColor.black
      };
    }
    if (sourceColor.typename === "GrayColor") return { type: "GrayColor", gray: sourceColor.gray };
    if (sourceColor.typename === "LabColor") {
      return { type: "LabColor", l: sourceColor.l, a: sourceColor.a, b: sourceColor.b };
    }
    if (sourceColor.typename === "NoColor") return { type: "NoColor" };
    throw new Error("Unsupported color type: " + sourceColor.typename);
  }

  function deserializeColor(colorData) {
    var result;
    if (!colorData) return null;
    if (colorData.type === "RGBColor") {
      result = new RGBColor();
      result.red = colorData.red;
      result.green = colorData.green;
      result.blue = colorData.blue;
      return result;
    }
    if (colorData.type === "CMYKColor") {
      result = new CMYKColor();
      result.cyan = colorData.cyan;
      result.magenta = colorData.magenta;
      result.yellow = colorData.yellow;
      result.black = colorData.black;
      return result;
    }
    if (colorData.type === "GrayColor") {
      result = new GrayColor();
      result.gray = colorData.gray;
      return result;
    }
    if (colorData.type === "LabColor") {
      result = new LabColor();
      result.l = colorData.l;
      result.a = colorData.a;
      result.b = colorData.b;
      return result;
    }
    if (colorData.type === "NoColor") return new NoColor();
    throw new Error("Unsupported serialized color type: " + colorData.type);
  }

  function snapshotPath(sourcePath) {
    var data = {
      points: [],
      closed: safeProperty(sourcePath, "closed", false),
      evenodd: safeProperty(sourcePath, "evenodd", false),
      polarity: safeProperty(sourcePath, "polarity", null),
      clipping: safeProperty(sourcePath, "clipping", false),
      opacity: safeProperty(sourcePath, "opacity", 100),
      filled: safeProperty(sourcePath, "filled", false),
      stroked: safeProperty(sourcePath, "stroked", false)
    };

    for (var pointIndex = 0; pointIndex < sourcePath.pathPoints.length; pointIndex += 1) {
      var sourcePoint = sourcePath.pathPoints[pointIndex];
      data.points.push({
        anchor: [sourcePoint.anchor[0], sourcePoint.anchor[1]],
        leftDirection: [sourcePoint.leftDirection[0], sourcePoint.leftDirection[1]],
        rightDirection: [sourcePoint.rightDirection[0], sourcePoint.rightDirection[1]],
        pointType: sourcePoint.pointType
      });
    }

    if (data.filled) {
      data.fillColor = serializeColor(sourcePath.fillColor);
      data.fillOverprint = safeProperty(sourcePath, "fillOverprint", false);
    }
    if (data.stroked) {
      data.strokeColor = serializeColor(sourcePath.strokeColor);
      data.strokeWidth = sourcePath.strokeWidth;
      data.strokeCap = safeProperty(sourcePath, "strokeCap", null);
      data.strokeJoin = safeProperty(sourcePath, "strokeJoin", null);
      data.strokeMiterLimit = safeProperty(sourcePath, "strokeMiterLimit", 4);
      data.strokeOverprint = safeProperty(sourcePath, "strokeOverprint", false);
    }
    return data;
  }

  function collectBottomToTop(container, output) {
    for (var itemIndex = container.pageItems.length - 1; itemIndex >= 0; itemIndex -= 1) {
      var item = null;
      var itemType = "";
      var itemAccessError = null;
      for (var accessAttempt = 1; accessAttempt <= 20; accessAttempt += 1) {
        try {
          item = container.pageItems[itemIndex];
          itemType = item.typename;
          itemAccessError = null;
          break;
        } catch (accessError) {
          itemAccessError = accessError;
          $.sleep(50);
        }
      }
      if (itemAccessError !== null || item === null || !itemType) throw itemAccessError;
      if (itemType === "GroupItem" && !safeProperty(item, "clipped", false)) {
        collectBottomToTop(item, output);
      } else if (itemType === "PathItem") {
        if (!safeProperty(item, "filled", false) && !safeProperty(item, "stroked", false)) continue;
        output.push({ type: "PathItem", paths: [snapshotPath(item)] });
      } else if (itemType === "CompoundPathItem") {
        var compound = { type: "CompoundPathItem", paths: [] };
        for (var compoundIndex = 0; compoundIndex < item.pathItems.length; compoundIndex += 1) {
          compound.paths.push(snapshotPath(item.pathItems[compoundIndex]));
        }
        output.push(compound);
      } else if (itemType === "GroupItem") {
        throw new Error("Clipped groups are not supported; expand the clipping group first.");
      } else {
        throw new Error("Unsupported imported item type: " + itemType);
      }
    }
  }

  function resolveSourceBounds(importedRoot, sourceDocument) {
    var boundsError = null;
    for (var boundsAttempt = 1; boundsAttempt <= 20; boundsAttempt += 1) {
      try {
        return importedRoot.geometricBounds;
      } catch (attemptError) {
        boundsError = attemptError;
        $.sleep(50);
      }
    }
    throw boundsError;
  }

  function mapPoint(point, sourceBounds, scale, targetLeft, targetTop) {
    return [
      targetLeft + (point[0] - sourceBounds[0]) * scale,
      targetTop + (point[1] - sourceBounds[1]) * scale
    ];
  }

  function writePathGeometry(pathData, destinationPath, sourceBounds, scale, targetLeft, targetTop) {
    var mappedAnchors = [];
    for (var pointIndex = 0; pointIndex < pathData.points.length; pointIndex += 1) {
      mappedAnchors.push(mapPoint(pathData.points[pointIndex].anchor, sourceBounds, scale, targetLeft, targetTop));
    }
    destinationPath.setEntirePath(mappedAnchors);

    for (var handleIndex = 0; handleIndex < pathData.points.length; handleIndex += 1) {
      var sourcePoint = pathData.points[handleIndex];
      var destinationPoint = destinationPath.pathPoints[handleIndex];
      destinationPoint.leftDirection = mapPoint(sourcePoint.leftDirection, sourceBounds, scale, targetLeft, targetTop);
      destinationPoint.rightDirection = mapPoint(sourcePoint.rightDirection, sourceBounds, scale, targetLeft, targetTop);
      destinationPoint.pointType = sourcePoint.pointType;
    }

    destinationPath.closed = pathData.closed;
  }

  function writePathAppearance(pathData, destinationPath, scale) {
    try { destinationPath.evenodd = pathData.evenodd; } catch (e1) {}
    if (pathData.polarity !== null) {
      try { destinationPath.polarity = pathData.polarity; } catch (e2) {}
    }
    try { destinationPath.clipping = pathData.clipping; } catch (e3) {}
    try { destinationPath.opacity = pathData.opacity; } catch (e4) {}

    destinationPath.filled = pathData.filled;
    if (pathData.filled) {
      destinationPath.fillColor = deserializeColor(pathData.fillColor);
      try { destinationPath.fillOverprint = pathData.fillOverprint; } catch (e5) {}
    }

    destinationPath.stroked = pathData.stroked;
    if (pathData.stroked) {
      destinationPath.strokeColor = deserializeColor(pathData.strokeColor);
      destinationPath.strokeWidth = pathData.strokeWidth * scale;
      if (pathData.strokeCap !== null) {
        try { destinationPath.strokeCap = pathData.strokeCap; } catch (e6) {}
      }
      if (pathData.strokeJoin !== null) {
        try { destinationPath.strokeJoin = pathData.strokeJoin; } catch (e7) {}
      }
      try { destinationPath.strokeMiterLimit = pathData.strokeMiterLimit; } catch (e8) {}
      try { destinationPath.strokeOverprint = pathData.strokeOverprint; } catch (e9) {}
    }
  }

  function writePath(pathData, destinationPath, sourceBounds, scale, targetLeft, targetTop) {
    writePathGeometry(pathData, destinationPath, sourceBounds, scale, targetLeft, targetTop);
    writePathAppearance(pathData, destinationPath, scale);
  }

  function createAtomic(atomicData, destination, sourceBounds, scale, targetLeft, targetTop) {
    var created;
    if (atomicData.type === "PathItem") {
      created = destination.pathItems.add();
      writePath(atomicData.paths[0], created, sourceBounds, scale, targetLeft, targetTop);
    } else {
      var stagingParent = destination.parent;
      created = stagingParent.compoundPathItems.add();
      try {
        var pendingAppearance = [];
        for (var pathIndex = atomicData.paths.length - 1; pathIndex >= 0; pathIndex -= 1) {
          var child = created.pathItems.add();
          writePathGeometry(atomicData.paths[pathIndex], child, sourceBounds, scale, targetLeft, targetTop);
          pendingAppearance.push({ pathData: atomicData.paths[pathIndex], destinationPath: child });
        }
        for (var appearanceIndex = 0; appearanceIndex < pendingAppearance.length; appearanceIndex += 1) {
          writePathAppearance(
            pendingAppearance[appearanceIndex].pathData,
            pendingAppearance[appearanceIndex].destinationPath,
            scale
          );
        }
        created.move(destination, ElementPlacement.PLACEATEND);
      } catch (compoundError) {
        try { created.remove(); } catch (compoundCleanupError) {}
        throw compoundError;
      }
    }
    created.zOrder(ZOrderMethod.BRINGTOFRONT);
  }

  function placementOrigin(placement, artboard, width, height, margin) {
    var artboardWidth = artboard[2] - artboard[0];
    var artboardHeight = artboard[1] - artboard[3];
    if (placement === "bottom-right") return [artboard[2] - margin - width, artboard[3] + margin + height];
    if (placement === "top-right") return [artboard[2] - margin - width, artboard[1] - margin];
    if (placement === "bottom-left") return [artboard[0] + margin, artboard[3] + margin + height];
    if (placement === "top-left") return [artboard[0] + margin, artboard[1] - margin];
    return [
      artboard[0] + (artboardWidth - width) / 2,
      artboard[1] - (artboardHeight - height) / 2
    ];
  }

  function createNamedDestinationGroup(parentLayer, groupName) {
    var groupError = null;
    for (var groupAttempt = 1; groupAttempt <= 20; groupAttempt += 1) {
      var candidateGroup = null;
      try {
        candidateGroup = parentLayer.groupItems.add();
        candidateGroup.name = groupName;
        candidateGroup.zOrder(ZOrderMethod.BRINGTOFRONT);
        return candidateGroup;
      } catch (attemptError) {
        groupError = attemptError;
        if (candidateGroup !== null) {
          try { candidateGroup.remove(); } catch (cleanupError) {}
        }
        $.sleep(50);
      }
    }
    throw groupError;
  }

  try {
    app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS;
    var sourceFile = new File(config.inputSvg);
    if (!sourceFile.exists) throw new Error("SVG file does not exist: " + config.inputSvg);

    if (config.createNewDocument || app.documents.length < 1) {
      targetDoc = app.documents.add(DocumentColorSpace.RGB, config.documentWidth, config.documentHeight);
    } else {
      targetDoc = app.activeDocument;
    }

    if (config.replaceExistingGroup) {
      for (var cleanupIndex = targetDoc.pageItems.length - 1; cleanupIndex >= 0; cleanupIndex -= 1) {
        if (targetDoc.pageItems[cleanupIndex].name === config.groupName) targetDoc.pageItems[cleanupIndex].remove();
      }
    }

    context = "non-ui import";
    sourceDoc = app.documents.addDocumentNoUI(app.startupPresetsList[0]);
    var importedRoot = sourceDoc.groupItems.createFromFile(sourceFile);
    $.sleep(150);
    var sourceBounds = resolveSourceBounds(importedRoot, sourceDoc);
    var sourceWidth = sourceBounds[2] - sourceBounds[0];
    var sourceHeight = sourceBounds[1] - sourceBounds[3];
    if (sourceWidth <= 0 || sourceHeight <= 0) throw new Error("Imported SVG has invalid geometry bounds.");

    context = "geometry snapshot";
    var snapshotError = null;
    for (var snapshotAttempt = 1; snapshotAttempt <= 8; snapshotAttempt += 1) {
      atomicItems = [];
      try {
        context = "geometry snapshot attempt " + snapshotAttempt;
        collectBottomToTop(importedRoot, atomicItems);
        snapshotError = null;
        break;
      } catch (attemptError) {
        snapshotError = attemptError;
        $.sleep(120);
      }
    }
    if (snapshotError !== null) throw snapshotError;
    sourcePathCount = sourceDoc.pathItems.length;
    if (atomicItems.length < 1 || sourcePathCount < 1) throw new Error("Imported SVG contains no editable paths.");

    var replayStart = 0;
    var replayEnd = atomicItems.length;
    var batchMode = config.atomicBatch && typeof config.atomicBatch.length === "number" && config.atomicBatch.length > 0;
    var batchRequests = [];
    if (batchMode) {
      for (var requestIndex = 0; requestIndex < config.atomicBatch.length; requestIndex += 1) {
        var requestedAtomicIndex = Number(config.atomicBatch[requestIndex].atomicIndex);
        var requestedGroupName = String(config.atomicBatch[requestIndex].groupName);
        if (requestedAtomicIndex < 0 || requestedAtomicIndex >= atomicItems.length) {
          throw new Error("Requested batch atomic index is outside the imported artwork range: " + requestedAtomicIndex);
        }
        if (!requestedGroupName) throw new Error("A batch request is missing its destination group name.");
        batchRequests.push({ atomicIndex: requestedAtomicIndex, groupName: requestedGroupName });
      }
    }
    if (typeof config.atomicIndex === "number" && config.atomicIndex >= 0) {
      if (config.atomicIndex >= atomicItems.length) {
        throw new Error("Requested atomic index is outside the imported artwork range: " + config.atomicIndex);
      }
      replayStart = config.atomicIndex;
      replayEnd = config.atomicIndex + 1;
    }

    if (!batchMode) {
      context = "non-ui geometry preflight";
      var validationGroup = sourceDoc.activeLayer.groupItems.add();
      validationGroup.name = "CELL_LCT_NON_UI_PREFLIGHT";
      for (var validationIndex = replayStart; validationIndex < replayEnd; validationIndex += 1) {
        context = "non-ui preflight object " + validationIndex + " of " + atomicItems.length;
        createAtomic(atomicItems[validationIndex], validationGroup, sourceBounds, 1, sourceBounds[0], sourceBounds[1]);
      }
      validationGroup.remove();
    }

    sourceDoc.closeNoUI();
    sourceDoc = null;

    targetDoc.activate();
    var artboard = targetDoc.artboards[targetDoc.artboards.getActiveArtboardIndex()].artboardRect;
    var artboardWidth = artboard[2] - artboard[0];
    var artboardHeight = artboard[1] - artboard[3];
    var scale = Math.min(
      (artboardWidth * config.maxWidthFraction) / sourceWidth,
      (artboardHeight * config.maxHeightFraction) / sourceHeight
    );
    var destinationWidth = sourceWidth * scale;
    var destinationHeight = sourceHeight * scale;
    var margin = Math.min(28, artboardWidth * 0.025);
    var origin = placementOrigin(config.placement, artboard, destinationWidth, destinationHeight, margin);

    var createdCount = 0;
    var lastVisibleBounds = "";
    if (batchMode) {
      for (var visibleRequestIndex = 0; visibleRequestIndex < batchRequests.length; visibleRequestIndex += 1) {
        var visibleRequest = batchRequests[visibleRequestIndex];
        var visibleCreationError = null;
        for (var visibleCreationAttempt = 1; visibleCreationAttempt <= 20; visibleCreationAttempt += 1) {
          context = "create visible batch group " + visibleRequest.atomicIndex + " of " + atomicItems.length;
          destinationGroup = createNamedDestinationGroup(targetDoc.activeLayer, visibleRequest.groupName);
          try {
            context = "visible batch object " + visibleRequest.atomicIndex + " of " + atomicItems.length;
            createAtomic(atomicItems[visibleRequest.atomicIndex], destinationGroup, sourceBounds, scale, origin[0], origin[1]);
            visibleCreationError = null;
            break;
          } catch (attemptError) {
            visibleCreationError = attemptError;
            try { destinationGroup.remove(); } catch (cleanupError) {}
            destinationGroup = null;
            $.sleep(50);
          }
        }
        if (visibleCreationError !== null) throw visibleCreationError;
        lastVisibleBounds = safeProperty(destinationGroup, "visibleBounds", []).join(",");
        destinationGroup = null;
        createdCount += 1;
        app.redraw();
        $.sleep(config.delayMs);
      }
    } else {
      context = "create visible destination group";
      destinationGroup = createNamedDestinationGroup(targetDoc.activeLayer, config.groupName);

      for (var atomicIndex = replayStart; atomicIndex < replayEnd; atomicIndex += 1) {
        context = "visible object " + atomicIndex + " of " + atomicItems.length;
        createAtomic(atomicItems[atomicIndex], destinationGroup, sourceBounds, scale, origin[0], origin[1]);
        app.redraw();
        $.sleep(config.delayMs);
      }
      createdCount = replayEnd - replayStart;
      lastVisibleBounds = safeProperty(destinationGroup, "visibleBounds", []).join(",");
    }

    if (config.saveOutputs !== false) {
      context = "save";
      var saveOptions = new IllustratorSaveOptions();
      saveOptions.pdfCompatible = true;
      saveOptions.compressed = true;
      targetDoc.saveAs(new File(config.outputAi), saveOptions);

      var pngOptions = new ExportOptionsPNG24();
      pngOptions.antiAliasing = true;
      pngOptions.transparency = false;
      pngOptions.artBoardClipping = true;
      pngOptions.horizontalScale = 100;
      pngOptions.verticalScale = 100;
      targetDoc.exportFile(new File(config.outputPng), ExportType.PNG24, pngOptions);
      targetDoc.save();
    }
    app.redraw();

    return [
      "OK",
      config.outputAi,
      config.outputPng,
      "atomicObjects=" + createdCount,
      "sourceAtomicObjects=" + atomicItems.length,
      "sourcePaths=" + sourcePathCount,
      "saved=" + (config.saveOutputs !== false),
      "scale=" + scale,
      "bounds=" + lastVisibleBounds
    ].join("|");
  } catch (error) {
    if (destinationGroup !== null) {
      try { destinationGroup.remove(); } catch (cleanupError) {}
    }
    return ["ERROR", error.message, error.line, context].join("|");
  } finally {
    if (sourceDoc !== null) {
      try { sourceDoc.closeNoUI(); } catch (closeError) {}
    }
    app.userInteractionLevel = previousInteractionLevel;
  }
}());
