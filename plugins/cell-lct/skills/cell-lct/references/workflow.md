# Cell-lct workflow

## 1. Prepare one complete reference

Keep the untouched source. Before upload, record all visible text as a text manifest with content, coordinates, dimensions, font, size, weight, color, rotation, alignment, opacity, z-index, and paint order.

Use Codex Image 2 once to remove text only. The cleaned reference must retain arrows and arrow tails, connectors, frames, axes, heatmaps, legends, scientific subjects, colors, spacing, and layout. Do not split a complete reference into mandatory per-subject uploads.

## 2. Build one Master SVG

Send the complete text-cleaned reference to the bundled vector service. Reject raster wrappers and incomplete results. Add the recorded text back as live SVG `<text>` elements before caching, at the original coordinates and z-order. Do not add text after Illustrator playback and do not outline it.

The Master SVG and all job outputs share one allocated `shibielujingN` basename.

## 3. Normalize and cache once

Resolve transforms and convert supported primitives to Illustrator-compatible solid geometry while preserving paint order, style, open/closed state, compound-path membership, stable identity, and live text.

Run `prepare_geometry_cache.py` exactly once. It creates `geometry-cache.json` and `playback.json`. Playback reads only these files and never reopens or reparses the SVG.

## 4. Batch policy

- Ordinary batches contain 20–50 consecutive atoms.
- Rebalance the final ordinary batch so it is not reduced to 1–4 atoms.
- Only a genuinely complex atom may form a singleton batch.
- A whole job with fewer than 20 ordinary atoms may use one smaller batch.
- Retry an unchanged failed batch; do not shrink normal batches.
- Preserve compound and clipping units that would change appearance if split.

## 5. One Illustrator session

Capture the active Illustrator document and create one COM connection at playback start. Reuse both until completion. Do not open, restart, quit, focus, maximize, minimize, move, resize, reconnect per batch, reopen SVG, or control document visibility.

Append each batch in Master SVG paint order. Existing artwork remains untouched. Stable root, batch, and atom names make retries idempotent.

## 6. Save, export, and recover

Save on a timer and at completion. Export PNG once after all batches finish. Resume from the first incomplete batch in `playback.json`; preserve earlier batches, the cache, target document, placement, and layer.

## 7. QA

Verify text-only cleanup, preservation of every non-text structure, no raster node, live text position and z-order, one cache parse, compliant batches, one Illustrator connection, unchanged existing content, final AI save, one PNG export, and visual correctness in Illustrator.

Follow the public-response contract in `SKILL.md` without exposing implementation details.
