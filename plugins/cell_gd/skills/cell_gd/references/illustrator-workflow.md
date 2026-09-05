# Illustrator post-processing

Use the original cached Illustrator runtime: `run_cell_lct.ps1`, `prepare_illustrator_cache.py`, and `cell_lct_cached_runtime.jsx`.
Validate the API-returned SVG; preserve geometry, proportions and literal paint order. Parse the Master SVG once into `geometry-cache.json` and `playback.json`; reuse the immutable cache for every batch.
Keep ordinary consecutive batches at 20–50 atoms. A whole job smaller than 20 may use one batch; only genuinely complex atoms may be singletons. Rebalance a short final batch and retry unchanged batches.
Keep one Illustrator connection and the original target document throughout playback. Save periodically and at completion; export PNG once after all batches finish. Resume from the first incomplete batch without changing the target, placement or completed objects.

## Illustrator behavior

- Draw into the document already open when playback begins.
- Append visible native paths and live text in exact Master SVG paint order.
- Preserve every existing object. Never delete, hide, replace, rename, move, or cover existing artwork.
- Do not hide, preload, reveal, or replace a completed result.
- Keep completed objects in place and resume from the first incomplete batch after interruption.
- Default inter-object delay is `0`; change it only when the user explicitly requests a delay.


## Completion

Check complete vector geometry, no raster wrapper, correct paint order and proportions, one cache parse, compliant batches, one connection, unchanged existing artwork, saved AI, one final PNG export and visual correctness in Illustrator. Letter outlines returned by path recognition remain paths; native SVG text, if present, stays supported by the existing renderer. Do not reconstruct image text separately.
