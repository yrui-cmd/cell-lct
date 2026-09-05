#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [switch]$ConfirmDisposableOpenDocument,
    [string]$OutputDirectory = "$env:TEMP\cell-lct-illustrator-e2e"
)

$ErrorActionPreference = "Stop"
if (-not $ConfirmDisposableOpenDocument) {
    throw "Open a disposable Illustrator 2026 document yourself, then pass -ConfirmDisposableOpenDocument."
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$skillRoot = Join-Path $repoRoot "plugins\cell_gd\skills\cell_gd"
$inputSvg = Join-Path $repoRoot "tests\fixtures\simple.svg"
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$before = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "Illustrator" }
if (-not $before) { throw "Illustrator must already be open; this test will not launch it." }

& (Join-Path $skillRoot "scripts\run_cell_lct.ps1") `
    -InputSvg $inputSvg `
    -WorkDir (Join-Path $outputRoot "cache") `
    -OutputAi (Join-Path $outputRoot "cell-lct-e2e.ai") `
    -OutputPng (Join-Path $outputRoot "cell-lct-e2e.png") `
    -MinBatchSize 20 `
    -MaxBatchSize 50

if ($LASTEXITCODE -ne 0) { throw "Illustrator end-to-end playback failed." }
foreach ($path in @((Join-Path $outputRoot "cell-lct-e2e.ai"), (Join-Path $outputRoot "cell-lct-e2e.png"))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Expected Illustrator output is missing: $path" }
}

$after = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "Illustrator" }
if (-not $after) { throw "Illustrator unexpectedly stopped during the test." }
Write-Output "ILLUSTRATOR_E2E_OK|version=0.2.1|output=$outputRoot"
