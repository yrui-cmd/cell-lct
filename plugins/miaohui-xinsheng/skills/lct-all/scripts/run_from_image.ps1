#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputImage,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [ValidateSet("center", "top-center", "left-center", "bottom-center", "bottom-right", "top-right", "bottom-left", "top-left")]
    [string]$Placement = "center",

    [ValidateRange(0.01, 1.0)]
    [double]$MaxWidthFraction = 0.72,

    [ValidateRange(0.01, 1.0)]
    [double]$MaxHeightFraction = 0.78,

    [ValidateRange(0, 1000)]
    [int]$DelayMs = 0,

    [ValidateRange(1, 50)]
    [int]$MinBatchSize = 20,

    [ValidateRange(1, 50)]
    [int]$MaxBatchSize = 50,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$inputPath = (Resolve-Path -LiteralPath $InputImage).Path
$outputRootPath = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $outputRootPath | Out-Null

$allocator = Join-Path $PSScriptRoot "allocate_shibielujing_name.py"
$runner = Join-Path $PSScriptRoot "run_lct_all.ps1"
$lctAllRoot = Split-Path $PSScriptRoot -Parent
$skillsRoot = Split-Path $lctAllRoot -Parent
$vectorizer = Join-Path $skillsRoot "lct-slt\scripts\vectorize-xiaomiao.ps1"
foreach ($required in @($allocator, $runner, $vectorizer)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing required runtime file: $required"
    }
}

$baseName = (& py -3 -X utf8 $allocator --root $outputRootPath | Select-Object -Last 1).Trim()
if ($baseName -notmatch '^shibielujing\d+$') {
    throw "Could not allocate the required output name."
}

$jobRoot = Join-Path $outputRootPath $baseName
$internalRoot = Join-Path $jobRoot ".lct-internal\live-cache"
$outputSvg = Join-Path $jobRoot "$baseName.svg"
$outputAi = Join-Path $jobRoot "$baseName.ai"
$outputPng = Join-Path $jobRoot "$baseName.png"
New-Item -ItemType Directory -Force -Path $jobRoot | Out-Null

& $vectorizer -InputImage $inputPath -OutputSvg $outputSvg | Out-Null

$arguments = @{
    InputSvg = $outputSvg
    WorkDir = $internalRoot
    OutputAi = $outputAi
    OutputPng = $outputPng
    Placement = $Placement
    MaxWidthFraction = $MaxWidthFraction
    MaxHeightFraction = $MaxHeightFraction
    DelayMs = $DelayMs
    MinBatchSize = $MinBatchSize
    MaxBatchSize = $MaxBatchSize
}
if ($DryRun) { $arguments.DryRun = $true }

& $runner @arguments | Out-Null

[ordered]@{
    ok = $true
    mode = $(if ($DryRun) { "dry-run" } else { "draw" })
    base_name = $baseName
    svg = $outputSvg
    ai = $(if ($DryRun) { $null } else { $outputAi })
    png = $(if ($DryRun) { $null } else { $outputPng })
    work_dir = $internalRoot
} | ConvertTo-Json -Compress
