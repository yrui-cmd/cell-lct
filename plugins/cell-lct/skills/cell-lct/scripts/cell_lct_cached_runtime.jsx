(function () {
  if (typeof CELL_LCT_CACHED_CONFIG === "undefined") {
    return "ERROR|Missing CELL_LCT_CACHED_CONFIG";
  }

  var config = CELL_LCT_CACHED_CONFIG;

  function readJson(path) {
    var file = new File(path);
    if (!file.exists) throw new Error("JSON file does not exist: " + path);
    file.encoding = "UTF-8";
    if (!file.open("r")) throw new Error("Could not open JSON file: " + path);
    var content = file.read();
    file.close();
    if (content.length && content.charCodeAt(0) === 65279) content = content.substring(1);
    // Illustrator's ExtendScript engine does not expose JSON consistently.
    // The cache is generated locally by prepare_geometry_cache.py, so parsing
    // it as a parenthesized object literal keeps the runtime compatible with
    // older and newer Illustrator releases without another process bridge.
    return eval("(" + content + ")");
  }

  function findDocument(name) {
    for (var index = 0; index < app.documents.length; index += 1) {
      if (app.documents[index].name === name) return app.documents[index];
    }
    throw new Error("Target Illustrator document is no longer open: " + name);
  }

  function findTargetLayer(document) {
    if (!config.targetLayerName) return document.activeLayer;
    for (var index = 0; index < document.layers.length; index += 1) {
      if (document.layers[index].name === config.targetLayerName) return document.layers[index];
    }
    throw new Error("Target Illustrator layer is missing: " + config.targetLayerName);
  }

  function findNamedGroup(container, name) {
    for (var index = 0; index < container.groupItems.length; index += 1) {
      try {
        var candidate = container.groupItems[index];
        if (candidate && candidate.name === name) return candidate;
      } catch (ignoredInvalidGroup) {}
    }
    return null;
  }

  function findNamedArtwork(container, name) {
    var group = findNamedGroup(container, name);
    if (group !== null) return group;
    var collections = [container.pathItems, container.compoundPathItems];
    try { collections.push(container.textFrames); } catch (ignoredTextCollection) {}
    for (var collectionIndex = 0; collectionIndex < collections.length; collectionIndex += 1) {
      var collection = collections[collectionIndex];
      for (var index = 0; index < collection.length; index += 1) {
        try {
          var candidate = collection[index];
          if (candidate && candidate.name === name) return candidate;
        } catch (ignoredInvalidArtwork) {}
      }
    }
    return null;
  }

  function paintItemName(atom, paintIndex) {
    if (atom.kind === "text") return atom.objectName;
    if (atom.paintParts.length === 1) return atom.objectName;
    return atom.objectName + "_P" + paintIndex;
  }

  function atomIsComplete(container, atom) {
    if (findNamedArtwork(container, atom.objectName) !== null) return true;
    if (atom.kind === "text") return false;
    if (atom.paintParts.length === 1) return false;
    for (var paintIndex = 0; paintIndex < atom.paintParts.length; paintIndex += 1) {
      if (findNamedArtwork(container, paintItemName(atom, paintIndex)) === null) return false;
    }
    return true;
  }

  function ensureRootGroup(document, targetLayer, name) {
    var existing = null;
    for (var index = 0; index < document.groupItems.length; index += 1) {
      try {
        var candidate = document.groupItems[index];
        if (candidate && candidate.name === name) {
          existing = candidate;
          break;
        }
      } catch (ignoredInvalidGroup) {}
    }
    if (existing !== null) return existing;
    var created = targetLayer.groupItems.add();
    created.name = name;
    created.zOrder(ZOrderMethod.BRINGTOFRONT);
    return created;
  }

  function rgbColor(values) {
    var color = new RGBColor();
    color.red = values[0];
    color.green = values[1];
    color.blue = values[2];
    return color;
  }

  function pointType(value) {
    return value === "smooth" ? PointType.SMOOTH : PointType.CORNER;
  }

  function mapPoint(point, viewBox, scale, originLeft, originTop) {
    return [
      originLeft + (point[0] - viewBox[0]) * scale,
      originTop - (point[1] - viewBox[1]) * scale
    ];
  }

  function writeGeometry(pathData, destination, viewBox, scale, originLeft, originTop, forceMode) {
    var index;
    var pointCount = pathData.points.length;
    var closeRepeatedEndpoint = false;
    if (!pathData.closed && pointCount > 2) {
      var firstAnchor = pathData.points[0].a;
      var lastAnchor = pathData.points[pointCount - 1].a;
      closeRepeatedEndpoint = Math.abs(firstAnchor[0] - lastAnchor[0]) < 0.000001 &&
        Math.abs(firstAnchor[1] - lastAnchor[1]) < 0.000001;
      if (closeRepeatedEndpoint) pointCount -= 1;
    }

    // Illustrator 2026 is fastest and most stable with setEntirePath for
    // ordinary short paths, while longer paths are more reliable when their
    // cached points are appended incrementally.
    var useEntirePath = forceMode === "entire" || (forceMode !== "incremental" && pointCount <= 10);
    // Illustrator may silently merge nearly coincident anchors passed to
    // setEntirePath, leaving fewer pathPoints than the cached source and
    // causing an out-of-range PARM error when handles are assigned. Build
    // these short, tightly spaced paths incrementally so every source anchor
    // remains addressable.
    if (useEntirePath && forceMode !== "entire") {
      for (index = 1; index < pointCount; index += 1) {
        var previousMapped = mapPoint(pathData.points[index - 1].a, viewBox, scale, originLeft, originTop);
        var currentMapped = mapPoint(pathData.points[index].a, viewBox, scale, originLeft, originTop);
        var deltaX = currentMapped[0] - previousMapped[0];
        var deltaY = currentMapped[1] - previousMapped[1];
        if (Math.sqrt(deltaX * deltaX + deltaY * deltaY) < 2.0) {
          useEntirePath = false;
          break;
        }
      }
      if (useEntirePath && pathData.closed && pointCount > 1) {
        var firstMapped = mapPoint(pathData.points[0].a, viewBox, scale, originLeft, originTop);
        var lastMapped = mapPoint(pathData.points[pointCount - 1].a, viewBox, scale, originLeft, originTop);
        var closingDeltaX = firstMapped[0] - lastMapped[0];
        var closingDeltaY = firstMapped[1] - lastMapped[1];
        if (Math.sqrt(closingDeltaX * closingDeltaX + closingDeltaY * closingDeltaY) < 2.0) {
          useEntirePath = false;
        }
      }
    }
    if (useEntirePath) {
      var anchors = [];
      for (index = 0; index < pointCount; index += 1) {
        anchors.push(mapPoint(pathData.points[index].a, viewBox, scale, originLeft, originTop));
      }
      destination.setEntirePath(anchors);
    }
    for (index = 0; index < pointCount; index += 1) {
      if (!useEntirePath && index > 0 && index % 96 === 0) $.sleep(1);
      var sourcePoint = pathData.points[index];
      var destinationPoint = useEntirePath ? destination.pathPoints[index] : destination.pathPoints.add();
      var leftDirection = sourcePoint.l;
      if (closeRepeatedEndpoint && index === 0) {
        leftDirection = pathData.points[pathData.points.length - 1].l;
      }
      destinationPoint.anchor = mapPoint(sourcePoint.a, viewBox, scale, originLeft, originTop);
      destinationPoint.leftDirection = mapPoint(leftDirection, viewBox, scale, originLeft, originTop);
      destinationPoint.rightDirection = mapPoint(sourcePoint.r, viewBox, scale, originLeft, originTop);
      destinationPoint.pointType = pointType(sourcePoint.t);
    }
    destination.closed = pathData.closed || closeRepeatedEndpoint;
  }

  function writeAppearance(style, destination, scale) {
    destination.opacity = style.opacity;
    destination.evenodd = style.fillRule === "evenodd";
    destination.filled = style.filled;
    if (style.filled) destination.fillColor = rgbColor(style.fillColor);
    destination.stroked = style.stroked;
    if (style.stroked) {
      destination.strokeColor = rgbColor(style.strokeColor);
      destination.strokeWidth = style.strokeWidth * (style.nonScalingStroke ? 1 : scale);
      if (style.strokeCap === "round") destination.strokeCap = StrokeCap.ROUNDENDCAP;
      else if (style.strokeCap === "square") destination.strokeCap = StrokeCap.PROJECTINGENDCAP;
      else destination.strokeCap = StrokeCap.BUTTENDCAP;
      if (style.strokeJoin === "round") destination.strokeJoin = StrokeJoin.ROUNDENDJOIN;
      else if (style.strokeJoin === "bevel") destination.strokeJoin = StrokeJoin.BEVELENDJOIN;
      else destination.strokeJoin = StrokeJoin.MITERENDJOIN;
      destination.strokeMiterLimit = style.strokeMiterLimit;
    }
  }

  function resolveTextFont(textStyle) {
    var preferred = textStyle.fontFamily || "Arial";
    try { return app.textFonts.getByName(preferred); } catch (ignoredExactFont) {}
    var preferredLower = preferred.toLowerCase();
    var wantsBold = (textStyle.fontWeight || "").indexOf("bold") >= 0 || parseInt(textStyle.fontWeight, 10) >= 600;
    var wantsItalic = (textStyle.fontStyle || "").indexOf("italic") >= 0 || (textStyle.fontStyle || "").indexOf("oblique") >= 0;
    var familyFallback = null;
    for (var fontIndex = 0; fontIndex < app.textFonts.length; fontIndex += 1) {
      try {
        var candidate = app.textFonts[fontIndex];
        var candidateFamily = (candidate.family || candidate.name || "").toLowerCase();
        if (candidateFamily !== preferredLower && (candidate.name || "").toLowerCase() !== preferredLower) continue;
        if (familyFallback === null) familyFallback = candidate;
        var styleLower = (candidate.style || "").toLowerCase();
        var candidateBold = styleLower.indexOf("bold") >= 0;
        var candidateItalic = styleLower.indexOf("italic") >= 0 || styleLower.indexOf("oblique") >= 0;
        if (candidateBold === wantsBold && candidateItalic === wantsItalic) return candidate;
      } catch (ignoredFont) {}
    }
    return familyFallback;
  }

  function createText(atom, parent, stagingLayer, viewBox, scale, originLeft, originTop) {
    var textStyle = atom.text;
    var position = mapPoint(textStyle.position, viewBox, scale, originLeft, originTop);
    var created = stagingLayer.textFrames.pointText(position);
    try {
      created.contents = textStyle.contents;
      var range = created.textRange;
      range.characterAttributes.size = textStyle.fontSize * scale;
      range.characterAttributes.fillColor = rgbColor(textStyle.fillColor);
      var resolvedFont = resolveTextFont(textStyle);
      if (resolvedFont !== null) range.characterAttributes.textFont = resolvedFont;
      if (textStyle.letterSpacing && textStyle.fontSize) {
        range.characterAttributes.tracking = Math.round((textStyle.letterSpacing / textStyle.fontSize) * 1000);
      }
      if (textStyle.textAnchor === "middle") range.paragraphAttributes.justification = Justification.CENTER;
      else if (textStyle.textAnchor === "end") range.paragraphAttributes.justification = Justification.RIGHT;
      else range.paragraphAttributes.justification = Justification.LEFT;
      created.opacity = textStyle.opacity;
      if (textStyle.rotationDegrees) created.rotate(-textStyle.rotationDegrees);
      created.move(parent, ElementPlacement.PLACEATEND);
      created.zOrder(ZOrderMethod.BRINGTOFRONT);
      return created;
    } catch (error) {
      try { created.remove(); } catch (cleanupError) {}
      throw error;
    }
  }

  function createPaint(atom, style, parent, stagingLayer, viewBox, scale, originLeft, originTop) {
    var created;
    var index;
    if (atom.subpaths.length === 1) {
      // Prefer constructing an ordinary path directly inside its stable batch
      // group. This avoids accumulating Illustrator staging/move operations
      // during very large jobs; the older staging route remains the fallback
      // for groups that reject direct path creation.
      created = parent.pathItems.add();
      try {
        writeGeometry(atom.subpaths[0], created, viewBox, scale, originLeft, originTop);
        writeAppearance(style, created, scale);
        created.zOrder(ZOrderMethod.BRINGTOFRONT);
        return created;
      } catch (directGroupError) {
        try { created.remove(); } catch (directGroupCleanupError) {}
      }

      // Illustrator can reject direct PathItem creation inside a newly nested
      // group with PARM. Create on the owning layer, then move the finished
      // native path into its stable atom group in the same transaction.
      created = stagingLayer.pathItems.add();
      try {
        writeGeometry(atom.subpaths[0], created, viewBox, scale, originLeft, originTop);
        writeAppearance(style, created, scale);
        created.move(parent, ElementPlacement.PLACEATEND);
        created.zOrder(ZOrderMethod.BRINGTOFRONT);
        return created;
      } catch (firstError) {
        try { created.remove(); } catch (cleanupError) {}
        created = stagingLayer.pathItems.add();
        try {
          var retryMode = atom.subpaths[0].points.length <= 10 ? "incremental" : "entire";
          writeGeometry(atom.subpaths[0], created, viewBox, scale, originLeft, originTop, retryMode);
          writeAppearance(style, created, scale);
          created.move(parent, ElementPlacement.PLACEATEND);
          created.zOrder(ZOrderMethod.BRINGTOFRONT);
          return created;
        } catch (secondError) {
          try { created.remove(); } catch (secondCleanupError) {}
          // Some valid single closed paths can be constructed on the staging
          // layer but Illustrator rejects moving the bare PathItem directly
          // into a deeply nested batch group. Wrap the same native path in one
          // native group and move the group as the final compatibility fallback.
          var singleFallbackGroup = stagingLayer.groupItems.add();
          try {
            var singleFallbackPath = stagingLayer.pathItems.add();
            writeGeometry(atom.subpaths[0], singleFallbackPath, viewBox, scale, originLeft, originTop, "incremental");
            writeAppearance(style, singleFallbackPath, scale);
            singleFallbackPath.move(singleFallbackGroup, ElementPlacement.PLACEATEND);
            singleFallbackGroup.move(parent, ElementPlacement.PLACEATEND);
            singleFallbackGroup.zOrder(ZOrderMethod.BRINGTOFRONT);
            return singleFallbackGroup;
          } catch (singleFallbackError) {
            try { singleFallbackGroup.remove(); } catch (singleFallbackCleanupError) {}
            // A very short open segment can occasionally be rejected by
            // Illustrator when its anchors are appended one at a time. Make
            // one final native-path attempt with setEntirePath before giving
            // up; this preserves the cached geometry and keeps playback
            // resumable without skipping the source atom.
            var entireFallbackGroup = stagingLayer.groupItems.add();
            try {
              var entireFallbackPath = stagingLayer.pathItems.add();
              writeGeometry(atom.subpaths[0], entireFallbackPath, viewBox, scale, originLeft, originTop, "entire");
              writeAppearance(style, entireFallbackPath, scale);
              entireFallbackPath.move(entireFallbackGroup, ElementPlacement.PLACEATEND);
              entireFallbackGroup.move(parent, ElementPlacement.PLACEATEND);
              entireFallbackGroup.zOrder(ZOrderMethod.BRINGTOFRONT);
              return entireFallbackGroup;
            } catch (entireFallbackError) {
              try { entireFallbackGroup.remove(); } catch (entireFallbackCleanupError) {}
              throw entireFallbackError;
            }
          }
        }
      }
    }

    created = stagingLayer.compoundPathItems.add();
    try {
      var pendingAppearance = [];
      for (index = atom.subpaths.length - 1; index >= 0; index -= 1) {
        var compoundData = atom.subpaths[index];
        if (!compoundData.points || compoundData.points.length < 2) continue;
        var firstCompoundAnchor = compoundData.points[0].a;
        var compoundHasExtent = false;
        for (var extentIndex = 1; extentIndex < compoundData.points.length; extentIndex += 1) {
          var extentAnchor = compoundData.points[extentIndex].a;
          if (Math.abs(extentAnchor[0] - firstCompoundAnchor[0]) > 0.000001 ||
              Math.abs(extentAnchor[1] - firstCompoundAnchor[1]) > 0.000001) {
            compoundHasExtent = true;
            break;
          }
        }
        if (!compoundHasExtent) continue;
        var child = created.pathItems.add();
        try {
          writeGeometry(compoundData, child, viewBox, scale, originLeft, originTop);
        } catch (compoundFirstError) {
          try { child.remove(); } catch (compoundChildCleanupError) {}
          child = created.pathItems.add();
          var compoundRetryMode = compoundData.points.length <= 10 ? "incremental" : "entire";
          writeGeometry(compoundData, child, viewBox, scale, originLeft, originTop, compoundRetryMode);
        }
        pendingAppearance.push(child);
      }
      for (index = 0; index < pendingAppearance.length; index += 1) {
        writeAppearance(style, pendingAppearance[index], scale);
      }
      created.move(parent, ElementPlacement.PLACEATEND);
      created.zOrder(ZOrderMethod.BRINGTOFRONT);
      return created;
    } catch (error) {
      try { created.remove(); } catch (cleanupError) {}

      // Some provider SVGs contain one very large compound path with many
      // disconnected, very short subpaths. Illustrator can reject a single
      // child while constructing that compound path. Preserve the visible
      // geometry by rebuilding its subpaths as native paths in one group.
      var fallbackGroup = stagingLayer.groupItems.add();
      var directFallbackPaths = [];
      try {
        for (index = 0; index < atom.subpaths.length; index += 1) {
          var fallbackData = atom.subpaths[index];
          if (!fallbackData.points || fallbackData.points.length < 2) continue;
          var fallbackPath = stagingLayer.pathItems.add();
          try {
            writeGeometry(fallbackData, fallbackPath, viewBox, scale, originLeft, originTop);
          } catch (fallbackFirstError) {
            try { fallbackPath.remove(); } catch (fallbackCleanupError) {}
            fallbackPath = stagingLayer.pathItems.add();
            var fallbackMode = fallbackData.points.length <= 10 ? "incremental" : "entire";
            writeGeometry(fallbackData, fallbackPath, viewBox, scale, originLeft, originTop, fallbackMode);
          }
          writeAppearance(style, fallbackPath, scale);
          try {
            fallbackPath.move(fallbackGroup, ElementPlacement.PLACEATEND);
          } catch (fallbackMoveError) {
            try {
              fallbackPath.move(parent, ElementPlacement.PLACEATEND);
              directFallbackPaths.push(fallbackPath);
            } catch (fallbackParentMoveError) {
              try { fallbackPath.remove(); } catch (fallbackMoveCleanupError) {}
              fallbackPath = fallbackGroup.pathItems.add();
              writeGeometry(fallbackData, fallbackPath, viewBox, scale, originLeft, originTop, "incremental");
              writeAppearance(style, fallbackPath, scale);
            }
          }
          fallbackPath.zOrder(ZOrderMethod.BRINGTOFRONT);
        }
        fallbackGroup.move(parent, ElementPlacement.PLACEATEND);
        fallbackGroup.zOrder(ZOrderMethod.BRINGTOFRONT);
        return fallbackGroup;
      } catch (fallbackError) {
        for (var directFallbackIndex = directFallbackPaths.length - 1; directFallbackIndex >= 0; directFallbackIndex -= 1) {
          try { directFallbackPaths[directFallbackIndex].remove(); } catch (directFallbackCleanupError) {}
        }
        try { fallbackGroup.remove(); } catch (fallbackGroupCleanupError) {}
        throw fallbackError;
      }
    }
  }

  function placementOrigin(placement, artboard, width, height, margin) {
    var artboardWidth = artboard[2] - artboard[0];
    var artboardHeight = artboard[1] - artboard[3];
        if (placement === "bottom-center") return [artboard[0] + (artboardWidth - width) / 2, artboard[3] + margin + height];
        if (placement === "bottom-right") return [artboard[2] - margin - width, artboard[3] + margin + height];
    if (placement === "top-right") return [artboard[2] - margin - width, artboard[1] - margin];
    if (placement === "bottom-left") return [artboard[0] + margin, artboard[3] + margin + height];
    if (placement === "top-left") return [artboard[0] + margin, artboard[1] - margin];
    if (placement === "top-center") return [artboard[0] + (artboardWidth - width) / 2, artboard[1] - margin];
    if (placement === "left-center") return [artboard[0] + margin, artboard[1] - (artboardHeight - height) / 2];
    return [
      artboard[0] + (artboardWidth - width) / 2,
      artboard[1] - (artboardHeight - height) / 2
    ];
  }

  function drawBatch() {
    var payload = readJson(config.batchJsonPath);
    var targetDocument = findDocument(config.targetDocumentName);
    var targetLayer = findTargetLayer(targetDocument);
    var rootGroup = ensureRootGroup(targetDocument, targetLayer, config.rootGroupName);
    var batchGroup = findNamedGroup(rootGroup, config.batchGroupName);
    if (batchGroup === null) {
      batchGroup = rootGroup.groupItems.add();
      batchGroup.name = config.batchGroupName;
      batchGroup.zOrder(ZOrderMethod.BRINGTOFRONT);
    }

    var artboard = targetDocument.artboards[targetDocument.artboards.getActiveArtboardIndex()].artboardRect;
    var viewBox = payload.viewBox;
    var sourceWidth = viewBox[2];
    var sourceHeight = viewBox[3];
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
    var skippedCount = 0;

    for (var atomIndex = 0; atomIndex < payload.atoms.length; atomIndex += 1) {
      var atom = payload.atoms[atomIndex];
      if (atomIsComplete(batchGroup, atom)) {
        skippedCount += 1;
        continue;
      }
      var createdItems = [];
      try {
        if (atom.kind === "text") {
          var createdText = createText(atom, batchGroup, targetLayer, viewBox, scale, origin[0], origin[1]);
          createdText.name = atom.objectName;
          createdItems.push(createdText);
        } else {
          for (var paintIndex = 0; paintIndex < atom.paintParts.length; paintIndex += 1) {
            var itemName = paintItemName(atom, paintIndex);
            if (findNamedArtwork(batchGroup, itemName) !== null) continue;
            var createdItem = createPaint(atom, atom.paintParts[paintIndex], batchGroup, targetLayer, viewBox, scale, origin[0], origin[1]);
            createdItem.name = itemName;
            createdItems.push(createdItem);
          }
        }
        createdCount += 1;
        app.redraw();
        // Long Illustrator 2026 sessions can retain native PathPoint proxies
        // until ExtendScript performs a collection, eventually surfacing a
        // PARM failure after many otherwise valid atoms. Collect periodically
        // while preserving the same connection and source-order playback.
        if ((atomIndex + 1) % 16 === 0) $.gc();
        if (config.delayMs > 0) $.sleep(config.delayMs);
      } catch (error) {
        for (var cleanupIndex = createdItems.length - 1; cleanupIndex >= 0; cleanupIndex -= 1) {
          try { createdItems[cleanupIndex].remove(); } catch (cleanupError) {}
        }
        return [
          "PARTIAL",
          "created=" + createdCount,
          "skipped=" + skippedCount,
          "total=" + payload.atoms.length,
          "failed=" + atom.objectName,
          "message=" + error.message,
          "line=" + error.line
        ].join("|");
      }
    }
    return [
      "OK",
      "created=" + createdCount,
      "skipped=" + skippedCount,
      "total=" + payload.atoms.length,
      "documentName=" + targetDocument.name
    ].join("|");
  }

  function saveAi() {
    var targetDocument = findDocument(config.targetDocumentName);
    var outputFile = new File(config.outputAi);
    var sameFile = false;
    try { sameFile = targetDocument.fullName.fsName === outputFile.fsName; } catch (error) {}
    if (sameFile) {
      targetDocument.save();
    } else {
      var options = new IllustratorSaveOptions();
      options.pdfCompatible = true;
      options.compressed = true;
      targetDocument.saveAs(outputFile, options);
    }
    return "OK|documentName=" + targetDocument.name;
  }

  function exportPng() {
    var targetDocument = findDocument(config.targetDocumentName);
    var options = new ExportOptionsPNG24();
    options.antiAliasing = true;
    options.transparency = false;
    options.artBoardClipping = true;
    options.horizontalScale = 100;
    options.verticalScale = 100;
    targetDocument.exportFile(new File(config.outputPng), ExportType.PNG24, options);
    return "OK|documentName=" + targetDocument.name;
  }

  try {
    if (app.documents.length < 1) return "ERROR|AI_DOCUMENT_REQUIRED";
    if (config.operation === "draw") return drawBatch();
    if (config.operation === "save") return saveAi();
    if (config.operation === "export") return exportPng();
    return "ERROR|Unsupported operation";
  } catch (error) {
    return ["ERROR", error.message, error.line].join("|");
  }
}());
