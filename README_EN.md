# Cell-lct

Cell-lct `v0.2.0` is the stable Windows release for reconstructing editable scientific vectors and live SVG text in a user-opened Adobe Illustrator 2026 document through Codex Desktop.

## Stable-release contract

- Immutable source reference: Git tag `v0.2.0`.
- Exact Python lock: `requirements.lock`.
- Runtime contract: `runtime-lock.json`.
- One-command setup and diagnostics: `setup.ps1` and `doctor.ps1`.
- Automated Windows end-to-end coverage plus an opt-in Illustrator 2026 hardware test.
- Release ZIP with a separate SHA256 checksum.
- No Marketplace installation entry; install from the pinned tag or Release ZIP.
- API credentials are never shipped and are stored with per-user Windows DPAPI.

## Requirements

Windows 10/11 x64, Codex Desktop with built-in Image 2 editing, Illustrator 2026 (30.x), PowerShell 5.1+, and Python 3.11–3.14.

## Install from the pinned tag

```powershell
git clone --branch v0.2.0 --depth 1 https://github.com/yrui-cmd/cell-lct.git
Set-Location .\cell-lct
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

Setup installs the locked dependency, copies the Skill, securely prompts for the API key when needed, and runs diagnostics. Never put an API key in a command, repository, screenshot, or chat message.

Restart Codex, create a new task, open Illustrator 2026 and the target document yourself, then invoke:

```text
Use $cell-lct to reconstruct my uploaded content or image in the current Illustrator canvas while preserving all existing content.
```

## Diagnose, test, and build

```powershell
.\doctor.ps1
.\doctor.ps1 -VerifyApi -RequireIllustratorOpen
.\tests\test-package.ps1
.\tests\test-windows-e2e.ps1
.\build-release.ps1
```

The live Illustrator test writes into the currently open document and therefore requires an explicitly disposable document:

```powershell
.\tests\test-illustrator-e2e.ps1 -ConfirmDisposableOpenDocument
```

Build outputs are written to `dist`. The ZIP contains no credentials and no Marketplace entry.

## Reproducibility boundary

The repository pins its Skill, scripts, dependency, tests, and release artifacts. Codex's built-in Image 2 capability and Adobe Illustrator itself cannot be bundled; another computer must satisfy `runtime-lock.json` and configure its own DPAPI-protected API key.
