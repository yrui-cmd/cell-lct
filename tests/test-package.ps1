#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$pluginRoot = Join-Path $repoRoot "plugins\cell-lct"
$skillsRoot = Join-Path $pluginRoot "skills"
$requiredSkills = @("cell-lct")

foreach ($relativePath in @(
    ".agents\plugins\marketplace.json",
    "install.ps1",
    "plugins\cell-lct\.codex-plugin\plugin.json",
    "plugins\cell-lct\skills\cell-lct\scripts\run_cell_lct.ps1",
    "plugins\cell-lct\skills\cell-lct\scripts\run_from_image.ps1",
    "plugins\cell-lct\skills\cell-lct\scripts\xiaomiao.ps1",
    "plugins\cell-lct\skills\cell-lct\scripts\vectorize-xiaomiao.ps1",
    "plugins\cell-lct\skills\cell-lct\scripts\run_cell_lct_direct.ps1"
)) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required package file is missing: $relativePath"
    }
}

$manifest = Get-Content -LiteralPath (Join-Path $pluginRoot ".codex-plugin\plugin.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.name -ne "cell-lct" -or $manifest.skills -ne "./skills/") {
    throw "Plugin manifest does not expose the bundled skills correctly."
}

$marketplace = Get-Content -LiteralPath (Join-Path $repoRoot ".agents\plugins\marketplace.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not ($marketplace.plugins | Where-Object { $_.name -eq "cell-lct" })) {
    throw "Marketplace entry is missing."
}

foreach ($skillName in $requiredSkills) {
    $skillFile = Join-Path $skillsRoot "$skillName\SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
        throw "Bundled skill is missing: $skillName"
    }
}

$trackedFiles = & git -C $repoRoot ls-files --cached --others --exclude-standard
$secretPattern = "img" + "_live_[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"
foreach ($relativePath in $trackedFiles) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($content -and [regex]::IsMatch($content, $secretPattern)) {
        throw "A live API key marker was found in a tracked file: $relativePath"
    }
}

$pythonCommand = if (Get-Command py -ErrorAction SilentlyContinue) { @("py", "-3") } elseif (Get-Command python -ErrorAction SilentlyContinue) { @("python") } else { throw "Python 3 is required." }
function Invoke-Python([string[]]$Arguments) {
    if ($pythonCommand.Count -eq 2) {
        & $pythonCommand[0] $pythonCommand[1] -X utf8 @Arguments
    }
    else {
        & $pythonCommand[0] -X utf8 @Arguments
    }
    if ($LASTEXITCODE -ne 0) { throw "Python validation failed." }
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$tempRoot = Join-Path $tempBase ("cell-lct-package-test-" + [Guid]::NewGuid().ToString("N"))
$resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
if (-not $resolvedTempRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Temporary test directory escaped the system temporary root."
}

try {
    $installRoot = Join-Path $resolvedTempRoot "skills"
    & (Join-Path $repoRoot "install.ps1") -Destination $installRoot
    foreach ($skillName in $requiredSkills) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot "$skillName\SKILL.md") -PathType Leaf)) {
            throw "Install smoke test failed for: $skillName"
        }
    }

    $fixture = Join-Path $repoRoot "tests\fixtures\simple.svg"
    $validator = Join-Path $skillsRoot "cell-lct\scripts\validate_vector_svg.py"
    Invoke-Python @($validator, "--svg", $fixture)

    $cacheRoot = Join-Path $resolvedTempRoot "cache"
    $cacheBuilder = Join-Path $skillsRoot "cell-lct\scripts\prepare_geometry_cache.py"
    Invoke-Python @($cacheBuilder, "--input", $fixture, "--output-dir", $cacheRoot, "--job-id", "package-smoke")
    foreach ($cacheFile in @("geometry-cache.json", "playback.json")) {
        if (-not (Test-Path -LiteralPath (Join-Path $cacheRoot $cacheFile) -PathType Leaf)) {
            throw "Geometry-cache smoke test did not create $cacheFile."
        }
    }
    $geometryCache = Get-Content -LiteralPath (Join-Path $cacheRoot "geometry-cache.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $editableText = $geometryCache.atoms | Where-Object { $_.kind -eq "text" -and $_.text.contents -eq "Cell-lct" }
    if (-not $editableText) {
        throw "Geometry-cache smoke test did not preserve the editable text atom."
    }
}
finally {
    if (Test-Path -LiteralPath $resolvedTempRoot) {
        $checkedTarget = [IO.Path]::GetFullPath($resolvedTempRoot)
        if (-not $checkedTarget.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove a directory outside the system temporary root."
        }
        Remove-Item -LiteralPath $checkedTarget -Recurse -Force
    }
}

Write-Output "PACKAGE_OK|skills=$($requiredSkills.Count)|api_adapter=bundled|cache=validated"
