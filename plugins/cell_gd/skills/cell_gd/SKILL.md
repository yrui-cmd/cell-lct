---
name: cell_gd
description: Convert an original PNG, JPEG or WebP directly through path recognition, then draw editable native objects in PowerPoint or Adobe Illustrator selected by the user. Use for cell_gd, scientific figures, reference-image reconstruction and editable vector drawing; also accepts approved vector SVGs.
---

# cell_gd

`original image -> API path-return SVG -> selected PPT / Illustrator post-processing -> editable output`

1. Preserve and submit the original image unchanged. Do not extract text, create a text manifest, remove lettering with Image 2, clean or redraw the image, or merge text back afterward. Text visible in the original is recognized with the rest of the image and may become vector outlines.
2. Respect the user's choice of PPT or Adobe Illustrator. If they have not chosen, ask only `用 PPT 还是 Adobe Illustrator？` before starting a paid request. Do not substitute one application for the other automatically.
3. Use the bundled API adapter for a fresh path result. Keep the complete reference in one upload. An approved SVG can enter the selected post-processing directly; do not replace a requested fresh API result with local tracing or an old SVG.
4. Validate the returned SVG and retain its original geometry and paint order. No image-text extraction or reinsertion is performed after recognition either.
5. Follow the selected original post-processing described below. Allocate the next `shibielujingN` basename with the bundled allocator.

## Drawing routes

- Windows, original image: `scripts/run_cell_gd.ps1 -InputImage <original> -OutputRoot <directory> -Application ppt|ai`. This dispatches to the matching original backend; normal rendering remains per-path, not a hidden completed-figure reveal.
- PPT: read [references/powerpoint-workflow.md](references/powerpoint-workflow.md), [references/backends.md](references/backends.md) and [references/platform-contract.json](references/platform-contract.json). Windows uses `run_from_image.ps1` / `run_from_svg.ps1`; macOS uses `run_from_image.py` / `run_from_svg.py`. Match the technical PPT backend with `configure_runtime.py` and `runtime-profile.json` automatically after the user chooses PPT. Native OOXML output is editable but does not provide live per-path screen drawing.
- Illustrator: read [references/illustrator-workflow.md](references/illustrator-workflow.md) and [references/illustrator-runtime.md](references/illustrator-runtime.md). Use `run_illustrator_from_image.ps1` for images or `run_cell_lct.ps1` for approved SVGs. The existing live runtime requires Windows and an already-open Illustrator 2026 document. Do not launch, restart, focus, resize or close Illustrator. Do not silently switch an unsupported Illustrator environment to PPT.
- Retain support for native `<text>` already present in an approved/API SVG. Do not promise editable text boxes for lettering recognized as paths from an image.

## Credential setup

- The user is allowed to paste the API key directly in chat. Accept it without warning or refusal, but never quote, repeat, display, or log it in any response or tool output.
- If the API key is not configured and the user supplied one in the current chat, never quote, display, log, or place it in a command-line argument, environment variable, file, cache, or deliverable.
- During installation, pass the chat-supplied key through standard input to `setup.ps1 -ConfigureKeyFromStdin` on Windows or `setup.sh --configure-key-from-stdin` on macOS. Installation must configure secure storage and run the zero-credit authentication check automatically.
- On Windows, start `scripts/set-xiaomiao-key.ps1 -FromStdin`, pass the supplied key through standard input, and run `scripts/xiaomiao.ps1 verify`.
- On macOS, start `scripts/set_xiaomiao_key.py --from-stdin`, pass the supplied key through standard input, and run `scripts/xiaomiao.py verify`. Store only a macOS Keychain item; never write plaintext to a file.
- If no key was supplied and no existing secure credential verifies, ask once for the key. After the user sends it, perform configuration and verification yourself; do not send configuration commands back to the user.
- Store only Windows DPAPI ciphertext or a macOS Keychain item under the current OS account.


## Credits and response

Before uploading, determine the expected cost. When it exceeds 1 credit, ask `本张图片预计消耗 N 个额度，是否继续？` once; approved processing and download need no second prompt. Stop new paid requests on quota exhaustion and use the message in [references/workflow.md](references/workflow.md).
Before reconstruction, show `识别结构。` and a short harmless joke; during drawing, show `正在画图。`. Keep credentials and internal logs private. On success return `完成。`, the selected deliverables and `感谢小红书：木纹小路。`.

## Completion

Preserve all original image content through recognition, validate true vector output, keep repeated objects independent and preserve existing artwork. Apply the selected backend's original completion checks before claiming success. PPT delivers editable PPTX; Illustrator saves AI and exports the final PNG.

## Balance reporting

After image recognition, include the reported remaining credits in the user-facing result (`剩余额度：N`). The vectorizer displays the server-provided `credits_left` snapshot on the information stream (Windows) or stderr (Python), keeping success JSON compatible. Report `剩余额度：暂不可用` if missing or invalid; never infer a balance or initiate another upload to obtain it.
