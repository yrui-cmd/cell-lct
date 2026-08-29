---
name: cell-lct-image
description: Use Image 2 through a user-configured OpenAI-compatible relay to create raster reference images for the cell-lct vector workflow. Use for scientific figure references, flat 2D subjects, reference-image edits, and image generation before handing a PNG to $cell-lct.
---

# Cell-lct Image

Use Image 2 to create a clean raster reference, then use `$cell-lct` when the user wants an editable Illustrator vector result. This skill is the image-generation stage; it does not replace the vector playback workflow in `$cell-lct`.

## Configuration

- Store the API key only in the user environment variable `CELL_LCT_IMAGE_API_KEY`; never put it in chat, a command line, a file, or a result receipt.
- Store the relay base URL in `CELL_LCT_IMAGE_BASE_URL`. The URL is required at runtime and is never embedded in this skill.
- The relay must expose OpenAI-compatible Image endpoints under the configured base URL: `/images/generations` and `/images/edits`, with JSON or SSE responses containing `b64_json` or an image URL.
- Configure both values through hidden input, then restart Codex so new tasks inherit them:

```powershell
$relayUrl = Read-Host '请输入 Image 2 中转站地址'
[Environment]::SetEnvironmentVariable('CELL_LCT_IMAGE_BASE_URL', $relayUrl, 'User')
$secureKey = Read-Host '请输入 Image 2 API 密钥' -AsSecureString
$plainKey = [System.Net.NetworkCredential]::new('', $secureKey).Password
[Environment]::SetEnvironmentVariable('CELL_LCT_IMAGE_API_KEY', $plainKey, 'User')
Remove-Variable plainKey, relayUrl
```

## Workflow

1. Resolve the skill directory from this `SKILL.md`; execute the sibling `scripts/cell_lct_image.py`.
2. Use `generate` for text-to-image, `edit` for reference-image editing, `text` for specified readable text, and `batch` for several different prompts.
3. Default to `gpt-image-2`, `1536x1024`, and `standard` unless the user specifies another supported value.
4. For cell-lct input, prefer flat 2D scientific illustration, white background, clean solid fills, clear contours, and no unrequested labels, arrows, legends, or decorative effects. Keep the user's prompt semantically intact.
5. Save every returned PNG and validate the absolute paths from the JSON receipt. Do not scan an output directory to infer results.
6. If the user requested editable vectors, pass the validated PNG to `$cell-lct` as the next stage. Do not locally trace the PNG or substitute an old SVG.

## Execution rules

- Run the bundled script directly; do not use inline Python or a guessed absolute path.
- Every final command must include one unique absolute `--result-file` path.
- Do not retry a failed creation request outside the script. The script may retry only the documented read operations.
- If the relay returns a partial batch, deliver every valid returned PNG and report the safe error summary.
- Never expose API keys, authorization headers, raw prompts, internal commands, or response bodies.

## Supported commands

```powershell
py -3 -X utf8 <skill-dir>\scripts\cell_lct_image.py generate --prompt '...' --result-file <absolute-json>
py -3 -X utf8 <skill-dir>\scripts\cell_lct_image.py edit --prompt '...' --reference <absolute-image> --result-file <absolute-json>
py -3 -X utf8 <skill-dir>\scripts\cell_lct_image.py text --text '...' --description '...' --result-file <absolute-json>
py -3 -X utf8 <skill-dir>\scripts\cell_lct_image.py batch --prompt '...' --prompt '...' --result-file <absolute-json>
```

Only report success after the command exits with code `0`, the receipt is valid, and every listed file is an existing PNG. When the next stage is requested, `$cell-lct` remains responsible for vector validation, live text, Illustrator playback, saving, and final visual inspection.
