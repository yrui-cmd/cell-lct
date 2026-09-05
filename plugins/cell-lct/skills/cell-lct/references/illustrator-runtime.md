# Illustrator runtime reference

## Supported workflow

The runtime uses Illustrator 2026 as both SVG importer and native path author:

1. Create a non-UI source document.
2. Import the SVG with `groupItems.createFromFile()`.
3. Traverse the imported artwork tree bottom-to-top.
4. Snapshot anchors, Bézier handles, closure, fill, stroke, and compound-path membership.
5. Close the non-UI source document.
6. Create final native paths in the visible target, one atomic object per redraw.

No complete artwork is ever inserted, hidden, moved off-canvas, or later swapped in the target document.

## Stacking rule

SVG paint order and Illustrator collection indexes use opposite traversal directions after import:

- `pageItems[0]`: topmost.
- `pageItems[pageItems.length - 1]`: bottommost.

Traverse from the final index to `0`. Each newly created destination object is brought to the front, so later source layers remain above earlier layers.

Never reorder by semantic labels such as background, outline, fill, detail, or text.

## Compatibility

- Required: Illustrator 2026 / version 30.x / `Illustrator.Application.30`.
- Illustrator 2020 version 24.x can create a non-UI document but does not reliably expose imported child path points or mutable child visibility. Do not use it for this workflow.
- Illustrator 2025 may work, but this skill's tested default is 2026.

## Supported SVG content

Designed for editable scientific figures and flat vector illustrations containing:

- Regular paths.
- Compound paths.
- Solid RGB, CMYK, Gray, or Lab fills and strokes.
- Bézier handles, open paths, closed paths, opacity, stroke caps, and stroke joins.

The runtime intentionally refuses:

- Clipped groups.
- Gradient, pattern, or spot colors.
- Raster images, meshes, live effects, symbols, or unsupported imported item types.

Pre-expand or simplify these features in a source copy before rerunning. Never flatten the target artwork to hide a compatibility problem.

## Placement

Available placements: `center`, `bottom-right`, `top-right`, `bottom-left`, and `top-left`.

Coordinates are mapped from the imported Illustrator geometry bounds to the active artboard. Stroke widths scale with artwork. Use the same `MaxWidthFraction` and `MaxHeightFraction` for predictable proportional fitting.

## Failure behavior

The runtime creates one named destination group. On failure it removes that group, closes the non-UI source document, restores Illustrator's interaction level, and returns an `ERROR|...` result. Existing target artwork remains untouched.
