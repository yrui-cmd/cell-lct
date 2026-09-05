# PowerPoint post-processing

## Fixed drawing rules

Treat this section as the finalized drawing baseline. Do not reinterpret, relax, or override it unless the user explicitly asks to update `cell_gd` itself.

- Convert every path retained by the duplicate-path filter to a native editable PowerPoint object. Use WPS only as an explicitly experimental backend.
- Sole filtering rule: remove exact duplicate drawing paths only. Preserve every non-duplicate path, including invisible, fully covered, and partially visible paths.
- Apply that rule to actual drawing paths, including separate subpaths inside one source SVG element.
- Put each retained drawing path into the cache exactly once. Draw it exactly once; never create a duplicate copy or a temporary covering layer.
- Convert paths to editable freeform Bézier shapes, text to text boxes, and preserve paint order.
- Traverse the Master SVG in its literal paint order from the first atom to the last: the first atom is the backmost object and must appear first. Explicitly bring each newly committed object in front of the earlier job objects.
- Never reorder by semantic categories such as background, large fill, outline, internal structure, detail, highlight, or text.
- Keep repeated elements independent. Do not flatten the whole figure into one picture.
- On Windows, keep one presentation automation connection for the full job. On macOS, perform one atomic OOXML edit transaction and reopen the saved result for verification.
- On Windows, draw into the currently active slide by default. On macOS, require a saved input PPTX path for appending to an existing deck; otherwise create a new PPTX. Never modify an open unsaved macOS presentation externally.
- On Windows, bring PowerPoint/WPS forward once when drawing starts. On macOS, do not pretend that file-backed OOXML creation is live drawing; open the verified output only after the atomic save if the user asks.
- On Windows, commit and display each native freeform path or text box immediately in literal source order from back to front, with a fixed 8 ms delay after each object. On macOS, write the same retained objects in the same order within one atomic OOXML transaction; visibility begins when the saved output is opened or reloaded.
- Parse the SVG exactly once and process ordinary atoms in cached batches of 20–50.
- Never delete, hide, replace, close, rename, or move objects that existed on the slide before the current job. This protection does not retain redundant paths from the new drawing. Never clear the slide before or after drawing.
- Do not preload, hide, reveal, swap, or replace a completed figure. After culling, keep each retained drawing object in place; do not clear it after drawing.
- Save one editable `.pptx`. Export PDF or PNG only when requested.

## Host selection

- Use the installed runtime profile automatically. Prefer live PowerPoint COM on Windows, then experimental WPS COM, then native editable OOXML. Use native editable OOXML on macOS. This automatic backend choice applies only after the user selects PPT.
- Never require a "PowerPoint 2026" edition. On Windows support PowerPoint 2016, 2019, 2021, LTSC 2021, LTSC 2024, and Microsoft 365 desktop through the unversioned `PowerPoint.Application` interface. On macOS support PowerPoint 2019, 2021, 2024, and Microsoft 365 desktop through standard saved-PPTX OOXML.
- Windows `auto`: prefer Microsoft PowerPoint, then WPS Presentation.
- Windows `powerpoint`: use `PowerPoint.Application` with native freeform shapes.
- macOS `ooxml`: use `run_cell_ppt_ooxml.py` to append native custom-geometry shapes and native text boxes to a saved PPTX. This is editable but not a live per-path animation.
- `wps`: use WPS Presentation automation and the same standard PPTX object model.
- If the selected host lacks freeform automation, stop rather than inserting a whole-figure raster fallback.

## Completion gate

Do not report success until the Master SVG has no raster node, exact duplicates have been removed at drawing-path level, every non-duplicate path is retained, any native SVG text is preserved, retained paths are native freeforms, literal source order is correct, the PPTX reopens, and pre-existing content remains unchanged.
