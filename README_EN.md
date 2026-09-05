# cell_gd

Send the original PNG/JPEG/WebP directly to path recognition, then let the user choose PowerPoint or Adobe Illustrator. No text extraction, text manifest, Image 2 cleanup, or text reinsertion. Lettering recognized from images may remain vector paths.

Both original repositories distribute the same self-contained `cell_gd` skill; install only one. Windows: run `setup.ps1`. macOS: run `bash setup.sh` for the editable PPTX backend. Illustrator retains its Windows / open Illustrator 2026 requirement.

Use `scripts/run_cell_gd.ps1 -InputImage original.png -OutputRoot output -Application ppt` or `-Application ai`. On macOS use `scripts/run_from_image.py --input-image original.png --output-root output`.

PowerPoint retains exact-path deduplication, literal paint order, native editable objects, existing-artwork protection and OOXML output. Illustrator retains its cache, persistent connection, batching, resumable playback, periodic AI saving and final PNG export. The original secure credentials and credit gates remain in use.
