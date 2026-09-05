#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputImage,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [ValidateRange(0, 1000000)]
    [int]$EstimatedCredits = 1,

    [switch]$ApproveHighCost,

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
$runner = Join-Path $PSScriptRoot "run_cell_lct.ps1"
$vectorizer = Join-Path $PSScriptRoot "vectorize-xiaomiao.ps1"
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
$internalRoot = Join-Path $jobRoot ".cell-lct-internal\live-cache"
$rawSvg = Join-Path $jobRoot "$baseName-vector.svg"
$outputSvg = Join-Path $jobRoot "$baseName.svg"
$outputAi = Join-Path $jobRoot "$baseName.ai"
$outputPng = Join-Path $jobRoot "$baseName.png"
New-Item -ItemType Directory -Force -Path $jobRoot | Out-Null

& $vectorizer -InputImage $inputPath -OutputSvg $rawSvg -EstimatedCredits $EstimatedCredits -ApproveHighCost:$ApproveHighCost | Out-Null
Copy-Item -LiteralPath $rawSvg -Destination $outputSvg
& py -3 -X utf8 (Join-Path $PSScriptRoot "validate_vector_svg.py") --svg $outputSvg | Out-Null
if ($LASTEXITCODE -ne 0) { throw "SVG validation failed." }

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
    vector_svg = $rawSvg
    ai = $(if ($DryRun) { $null } else { $outputAi })
    png = $(if ($DryRun) { $null } else { $outputPng })
    work_dir = $internalRoot
} | ConvertTo-Json -Compress
