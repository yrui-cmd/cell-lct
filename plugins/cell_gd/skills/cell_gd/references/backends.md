# Presentation backends

## Microsoft PowerPoint

Use the unversioned `PowerPoint.Application` ProgID. Support PowerPoint 2016, 2019, 2021, LTSC 2021, LTSC 2024, and Microsoft 365 desktop on Windows; do not require or claim a special "2026" edition. These releases use the 16.x automation family needed by `Shapes.BuildFreeform`, `Shapes.AddTextbox`, and standard `.pptx` saving. Keep one COM application object and one presentation reference for the entire drawing job.

## Microsoft PowerPoint on macOS

macOS does not expose Windows COM. Support PowerPoint 2019, 2021, 2024, and Microsoft 365 desktop editions that open standard `.pptx` files; do not require a "2026" edition. Use the bundled `run_cell_ppt_ooxml.py` backend against a saved `.pptx`: it appends native DrawingML custom-geometry shapes and native text boxes, preserves existing slide objects, saves once, and reopens the result for structural verification. It must not be described as live per-path drawing in the currently open PowerPoint window. If the user requires an existing deck, require its saved path and write a new output copy; never mutate an open unsaved document externally.

Use `setup.sh`, `install.py`, `doctor.py`, macOS Keychain, `xiaomiao.py`, `vectorize_xiaomiao.py`, `run_from_image.py`, and `run_from_svg.py` on macOS. Do not call Windows `.ps1` COM or DPAPI entry points there.

## Automatic PPT backend selection

This applies after the user chooses PPT, not to the PPT versus Illustrator decision.

Installation runs `configure_runtime.py` and writes the non-secret `runtime-profile.json`. Use its selected host without asking the user: PowerPoint live COM first on Windows, experimental WPS COM second, editable OOXML fallback otherwise, and editable OOXML on macOS. Regenerate the profile automatically if it is missing or the machine environment changes.

## WPS Presentation

Treat WPS as experimental. Try `KWPP.Application`, then `WPP.Application`. Use the same standard PowerPoint object model and save as `.pptx`. WPS editions differ in automation coverage. Require working `Presentations`, `Slides`, `Shapes.BuildFreeform`, `AddTextbox`, and `SaveAs`; if any required method is unavailable, stop and report the missing capability. Never describe WPS as stable until its live end-to-end suite passes on a declared WPS build.

## Compatibility boundary

Solid fills, solid strokes, cubic Bézier paths, basic opacity, rotations, and text boxes are supported. Gradients, masks, clipping paths, patterns, linked resources, embedded raster nodes, and compound-hole semantics require preprocessing or explicit rejection. Never conceal an unsupported feature by inserting the complete figure as an image.

The Windows COM and macOS OOXML backends share geometry cache schema 3 and literal paint order. Their UI behavior differs: Windows can display each path as it is committed; macOS file-backed output becomes visible after the saved PPTX is opened or reloaded.
