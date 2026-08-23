# `Cell-lct` Skill

[中文说明](README.md)

**Science Speaks in Vectors**

`Cell-lct` is a scientific vector-illustration Skill for Codex Desktop and Adobe Illustrator 2026. It creates, recreates, and continues editable scientific artwork inside the Illustrator document that the user already has open, while preserving existing canvas content.

> This is an independent third-party project and is not affiliated with, sponsored by, or endorsed by Adobe.

## What To Use It For

- Draw scientific subjects such as cells, organs, animals, protein molecules, and laboratory equipment.
- Recreate mechanism diagrams, workflows, graphical abstracts, and review schematics.
- Turn PNG, JPG, JPEG, or WebP references into newly generated editable vector artwork.
- Append new artwork at a specified position without clearing existing objects.
- Keep ordinary labels as editable Illustrator text rather than outlined glyphs.

## Workflow

`Cell-lct` treats the current Illustrator document as the only live canvas:

1. Interpret the research content, reference image, target position, and protected regions.
2. Generate and validate fresh vector artwork.
3. Append editable paths and text to the current canvas in visual order.
4. Preserve completed artwork when paused and resume from the unfinished point.
5. Leave native editable objects in the Illustrator document after completion.

The Skill does not launch, restart, close, focus, or resize Illustrator. Open Illustrator 2026 and the target document yourself before drawing.

## Typical Requests

- “Use `$cell-lct` to draw a rabbit in the upper-right corner of the current canvas. Preserve all existing content.”
- “Use `$cell-lct` to recreate my uploaded reference in the upper-middle area without covering existing text.”
- “Use `$cell-lct` to make a flat 2D mechanism diagram from this research description and keep all labels editable.”
- “Continue the paused drawing without deleting anything already completed.”

## What You Need To Provide

- Research content, a target subject, or a reference image.
- Intended position, size, or proportion of the artboard.
- Text, artwork, or other areas that must not be covered.
- Required labels, colors, arrows, and structural relationships.

## Outputs

- Native editable vector paths in the current Illustrator document.
- Editable Illustrator text objects.
- New artwork that coexists with current canvas content.
- SVG and other intermediate files when required, named sequentially as `shibielujing1`, `shibielujing2`, `shibielujing3`, and so on.

## Quick Install

### Ask Codex on another computer

Send this instruction to Codex:

```text
Install the Cell-lct Skill from plugins/cell-lct/skills/cell-lct in https://github.com/yrui-cmd/cell-lct, check its dependencies, and configure the API Key I provide through hidden input. After installation, remind me to restart Codex, create a new task, and invoke $cell-lct to begin drawing.
```

Share the API Key separately and privately. Never place it in a public prompt, Git commit, issue, screenshot, or generated artifact.

### Manual installation

Run in Windows PowerShell:

```powershell
git clone https://github.com/yrui-cmd/cell-lct.git
Set-Location .\cell-lct
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

To replace an existing Skill with the same name:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

Restart Codex and create a new task after installation or update.

## First-Time Setup

### Requirements

- Windows 10/11.
- Codex Desktop.
- Adobe Illustrator 2026 with the target document open.
- Python 3 available through `py -3`.
- The Python package `fontTools`.
- Windows `curl.exe`.
- A valid conversion-service API Key with available credits.

Install `fontTools` when missing:

```powershell
py -3 -m pip install --user fonttools
```

Configure the API Key through hidden input and verify the connection:

```powershell
powershell -ExecutionPolicy Bypass -File .\plugins\cell-lct\skills\cell-lct\scripts\set-xiaomiao-key.ps1
powershell -ExecutionPolicy Bypass -File .\plugins\cell-lct\skills\cell-lct\scripts\xiaomiao.ps1 verify
```

The API Key is not stored in this repository. The setup script encrypts it for the current Windows user.

## Start Drawing

### Simple subject

```text
Use $cell-lct to draw a flat 2D mouse in the upper-left corner of the current canvas. Preserve all existing content.
```

### Reference-image recreation

Upload a reference image and send:

```text
Use $cell-lct to recreate my uploaded image in the current Illustrator canvas. Preserve all existing content and do not cover existing text.
```

### Pause and resume

```text
Pause.
```

```text
Continue the previous drawing and preserve everything already completed.
```

## Figure Standards

- Use a white background, flat 2D vector styling, and a clear visual hierarchy.
- Avoid photographic realism, 3D rendering, complex textures, mirror effects, and realistic lighting.
- Keep repeated subjects consistent in color, shape, proportion, line width, structure, and detail.
- Keep repeated small elements as separate editable objects.
- Preserve ordinary labels as editable text rather than outlining them by default.
- Never delete, hide, replace, or cover existing canvas content.

## Project Structure

The project centers on one unified Skill:

```text
plugins/cell-lct/skills/cell-lct/
├── SKILL.md
├── agents/openai.yaml
├── references/
└── scripts/
```

The repository also contains a Codex plugin compatibility wrapper. Regular users only need the `cell-lct` Skill; they do not need a local Marketplace link or any legacy LCT Skills.

## Boundaries

- Researchers must verify the scientific meaning, labels, and causal relationships in AI-generated schematics.
- Generated artwork is not treated as experimental evidence or a quantitative data panel.
- The Skill does not invent experimental data, statistics, sample sizes, or unsupported mechanisms.
- Do not commit patient information, confidential data, passwords, or API Keys to the public repository or issues.
- Save a backup of important Illustrator documents before using the Skill.

## Troubleshooting

### Codex cannot find `$cell-lct`

Confirm that the Skill is installed in the active Codex Skills directory, then restart Codex and create a new task.

### Illustrator is unavailable

Open Adobe Illustrator 2026 and the target document, then ask Codex to continue.

### The API Key is missing or invalid

Run `set-xiaomiao-key.ps1` again, then run `xiaomiao.ps1 verify`.

### An uploaded image does not enter the vector workflow

Explicitly include “Use `$cell-lct`” in the request, then confirm the API Key, network connection, and account credits.

## Trademark Notice

Adobe and Adobe Illustrator are trademarks or registered trademarks of Adobe in the United States and other countries. Their names are used only to describe compatibility.
