#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputImage,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [ValidateSet('auto', 'powerpoint', 'wps', 'ooxml')]
    [string]$HostApplication = 'auto',

    [ValidateRange(0, 1000000)]
    [int]$EstimatedCredits = 1,

    [switch]$ApproveHighCost,

    [switch]$UseActivePresentation,

    [switch]$Foreground,

    [switch]$CreateNewPresentation,

    [switch]$KeepBackground,

    [ValidateRange(0, 10000)]
    [int]$StepDelayMs = 8
)

$ErrorActionPreference = 'Stop'
$pythonCommand = Get-Command py -ErrorAction SilentlyContinue
$pythonPrefix = @('-3', '-X', 'utf8')
if (-not $pythonCommand) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    $pythonPrefix = @('-X', 'utf8')
}
if (-not $pythonCommand) { throw 'Python 3.11-3.14 was not found.' }
$pythonExe = $pythonCommand.Source
$inputPath = (Resolve-Path -LiteralPath $InputImage).Path
$outputRootPath = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $outputRootPath | Out-Null

$allocator = Join-Path $PSScriptRoot 'allocate_shibielujing_name.py'
$vectorizer = Join-Path $PSScriptRoot 'vectorize-xiaomiao.ps1'
$cacheBuilder = Join-Path $PSScriptRoot 'prepare_geometry_cache.py'
$visibilityCuller = Join-Path $PSScriptRoot 'cull_hidden_geometry.py'
$pptRuntime = Join-Path $PSScriptRoot 'run_cell_ppt.ps1'
$ooxmlRuntime = Join-Path $PSScriptRoot 'run_cell_ppt_ooxml.py'
$runtimeConfigurator = Join-Path $PSScriptRoot 'configure_runtime.py'
foreach ($required in @($allocator, $vectorizer, $cacheBuilder, $visibilityCuller, $pptRuntime, $ooxmlRuntime, $runtimeConfigurator)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing runtime file: $required" }
}

$baseName = (& $pythonExe @pythonPrefix $allocator --root $outputRootPath | Select-Object -Last 1).Trim()
if ($baseName -notmatch '^shibielujing\d+$') { throw 'Could not allocate output name.' }
$jobRoot = Join-Path $outputRootPath $baseName
$cacheRoot = Join-Path $jobRoot '.cell-ppt-cache'
$rawSvg = Join-Path $jobRoot "$baseName-vector.svg"
$masterSvg = Join-Path $jobRoot "$baseName.svg"
$outputPptx = Join-Path $jobRoot "$baseName.pptx"
New-Item -ItemType Directory -Force -Path $jobRoot | Out-Null

$vectorizerArgs = @{
    InputImage = $inputPath
    OutputSvg = $rawSvg
    EstimatedCredits = $EstimatedCredits
}
if ($ApproveHighCost) { $vectorizerArgs.ApproveHighCost = $true }
& $vectorizer @vectorizerArgs | Out-Null
Copy-Item -LiteralPath $rawSvg -Destination $masterSvg
& $pythonExe @pythonPrefix (Join-Path $PSScriptRoot 'validate_vector_svg.py') --svg $masterSvg | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'SVG validation failed.' }
& $pythonExe @pythonPrefix $cacheBuilder --input $masterSvg --output-dir $cacheRoot --job-id $baseName | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Geometry cache preparation failed.' }
& $pythonExe @pythonPrefix $visibilityCuller --cache (Join-Path $cacheRoot 'geometry-cache.json') --state (Join-Path $cacheRoot 'drawing-state.json') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Duplicate-path filtering failed.' }

$profilePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime-profile.json'
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    & $pythonExe @pythonPrefix $runtimeConfigurator --output $profilePath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Automatic runtime matching failed.' }
}
$resolvedHost = $HostApplication
if ($resolvedHost -eq 'auto') {
    $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $resolvedHost = [string]$profile.host
}
if ($resolvedHost -eq 'ooxml') {
    & $pythonExe @pythonPrefix $ooxmlRuntime --geometry-cache (Join-Path $cacheRoot 'geometry-cache.json') --output-pptx $outputPptx | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Editable OOXML drawing failed.' }
}
else {
    $runtimeArgs = @{
        GeometryCache = (Join-Path $cacheRoot 'geometry-cache.json')
        OutputPptx = $outputPptx
        HostApplication = $resolvedHost
        StepDelayMs = $StepDelayMs
    }
    $drawIntoActive = -not $CreateNewPresentation
    if ($UseActivePresentation) { $drawIntoActive = $true }
    if ($drawIntoActive) { $runtimeArgs.UseActivePresentation = $true }
    $bringForwardOnce = -not $KeepBackground
    if ($Foreground) { $bringForwardOnce = $true }
    if ($bringForwardOnce) { $runtimeArgs.Foreground = $true }
    & $pptRuntime @runtimeArgs | Out-Null
}

[pscustomobject][ordered]@{
    ok = $true
    base_name = $baseName
    pptx = $outputPptx
    svg = $masterSvg
    vector_svg = $rawSvg
    cache = (Join-Path $cacheRoot 'geometry-cache.json')
} | ConvertTo-Json -Compress
