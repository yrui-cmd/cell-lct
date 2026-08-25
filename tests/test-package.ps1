#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$pluginRoot = Join-Path $repoRoot "plugins\cell-lct-next"
$skillsRoot = Join-Path $pluginRoot "skills"
$skillRoot = Join-Path $skillsRoot "cell-lct-next"
$requiredSkills = @("cell-lct-next")

foreach ($relativePath in @(
    "install.ps1",
    "setup.ps1",
    "doctor.ps1",
    "build-release.ps1",
    "requirements.lock",
    "runtime-lock.json",
    "plugins\cell-lct-next\.codex-plugin\plugin.json",
    "plugins\cell-lct-next\skills\cell-lct-next\SKILL.md",
    "plugins\cell-lct-next\skills\cell-lct-next\scripts\run_cell_lct.ps1",
    "plugins\cell-lct-next\skills\cell-lct-next\scripts\run_from_image.ps1",
    "plugins\cell-lct-next\skills\cell-lct-next\scripts\merge_live_text.py",
    "plugins\cell-lct-next\skills\cell-lct-next\scripts\xiaomiao.ps1",
    "plugins\cell-lct-next\skills\cell-lct-next\scripts\vectorize-xiaomiao.ps1"
)) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required package file is missing: $relativePath" }
}

$manifest = Get-Content -LiteralPath (Join-Path $pluginRoot ".codex-plugin\plugin.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.name -ne "cell-lct-next" -or $manifest.version -ne "0.2.0" -or $manifest.skills -ne "./skills/") {
    throw "Plugin manifest identity or stable version is incorrect."
}

if (Test-Path -LiteralPath (Join-Path $repoRoot ".agents\plugins\marketplace.json")) {
    throw "Marketplace installation entry must not be included in this release."
}

$runtimeLock = Get-Content -LiteralPath (Join-Path $repoRoot "runtime-lock.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if ($runtimeLock.release -ne "0.2.0" -or $runtimeLock.gitTag -ne "v0.2.0" -or $runtimeLock.pythonDependencies.fonttools -ne "4.61.1") {
    throw "Runtime lock is inconsistent with the stable release."
}
if ((Get-Content -LiteralPath (Join-Path $repoRoot "requirements.lock") -Raw -Encoding UTF8).Trim() -ne "fonttools==4.61.1") {
    throw "Python dependency lock is not exact."
}

foreach ($skillName in $requiredSkills) {
    if (-not (Test-Path -LiteralPath (Join-Path $skillsRoot "$skillName\SKILL.md") -PathType Leaf)) { throw "Bundled skill is missing: $skillName" }
}

$allFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
$secretPattern = "img" + "_live_[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"
foreach ($file in $allFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($content -and [regex]::IsMatch($content, $secretPattern)) { throw "A live API key marker was found in: $($file.FullName)" }
}

$skillText = Get-Content -LiteralPath (Join-Path $skillRoot "SKILL.md") -Raw -Encoding UTF8
$specText = Get-Content -LiteralPath (Join-Path $skillRoot "references\workflow-spec.md") -Raw -Encoding UTF8
function Decode-Utf8Base64([string]$Value) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
foreach ($phrase in @(
    "Image 2 may remove text only",
    "Preserve arrows and arrow tails, connectors, frames, coordinate axes, heatmaps, legends",
    (Decode-Utf8Base64 "5oSf6LCi5bCP57qi5Lmm77ya5pyo57q55bCP6Lev44CC"),
    (Decode-Utf8Base64 "6K+G5Yir57uT5p6E44CC"),
    (Decode-Utf8Base64 "5q2j5Zyo55S75Zu+44CC")
)) {
    if ($skillText -notlike "*$phrase*") { throw "Required workflow phrase is missing: $phrase" }
}
if ($skillText -notmatch '20.50') { throw "The 20-50 batch policy is missing." }

$quotaMessage = Decode-Utf8Base64 "5b2T5YmN6aKd5bqm5LiN6Laz77yM6K+35Zyo5bCP57qi5Lmm5pCc57Si4oCc5pyo57q55bCP6Lev4oCd77yI57qmMjAw5Liq57KJ5Lid55qE5bCP5Y2a5Li777yJ6I635Y+W5YWF5YC844CC5YWE5byf5Lus77yM5bCP57qi5Lmm5LiN6KaB6LCI6K665qKv5a2Q562J5pWP5oSf6K+d6aKY77yb5pyJ6Zeu6aKY6K+356eB5L+h5oqW6Z+z4oCc5pyo57q54oCd77yI57qmOTAw5Liq57KJ5Lid55qE5bCP5Y2a5Li777yJ44CC"
if ($specText -notlike "*$quotaMessage*") { throw "The fixed quota message is missing." }

foreach ($forbiddenPhrase in @(
    (Decode-Utf8Base64 "5oSf6LCi5oqW6Z+z77ya5pyo57q55o+Q5L6b55qE5biu5Yqp44CC"),
    (Decode-Utf8Base64 "SW1hZ2UgMiDlj6rliKDpmaTmloflrZfjgIHnrq3lpLTjgIHnrq3lpLTlsL7lt7TjgIHng63lm77lkozmuJDlj5jlm77kvos="),
    (Decode-Utf8Base64 "5q+P5Liq5a6M5pW057Sg5p2Q5Y2V54us6LCD55So"),
    (Decode-Utf8Base64 "5Zue5aGr5YWo6YOo6KeE5YiZ5YWD57Sg")
)) {
    if ($skillText -like "*$forbiddenPhrase*" -or $specText -like "*$forbiddenPhrase*") { throw "Conflicting legacy rule remains: $forbiddenPhrase" }
}

$pythonCommand = if (Get-Command py -ErrorAction SilentlyContinue) { @("py", "-3") } elseif (Get-Command python -ErrorAction SilentlyContinue) { @("python") } else { throw "Python 3 is required." }
function Invoke-Python([string[]]$Arguments) {
    if ($pythonCommand.Count -eq 2) { & $pythonCommand[0] $pythonCommand[1] -X utf8 @Arguments }
    else { & $pythonCommand[0] -X utf8 @Arguments }
    if ($LASTEXITCODE -ne 0) { throw "Python validation failed." }
}

$tempBase = Join-Path $repoRoot ".test-tmp"
$tempRoot = Join-Path $tempBase ([Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $installRoot = Join-Path $tempRoot "skills"
    & (Join-Path $repoRoot "install.ps1") -Destination $installRoot
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot "cell-lct-next\SKILL.md") -PathType Leaf)) { throw "Install smoke test failed." }

    $fixture = Join-Path $repoRoot "tests\fixtures\simple.svg"
    Invoke-Python @((Join-Path $skillRoot "scripts\validate_vector_svg.py"), "--svg", $fixture)

    $cleanFixture = Join-Path $repoRoot "tests\fixtures\clean-reference.svg"
    $textManifest = Join-Path $repoRoot "tests\fixtures\text-manifest.json"
    $mergedFixture = Join-Path $tempRoot "master-with-live-text.svg"
    Invoke-Python @((Join-Path $skillRoot "scripts\merge_live_text.py"), "--input-svg", $cleanFixture, "--text-manifest", $textManifest, "--output-svg", $mergedFixture)
    Invoke-Python @((Join-Path $skillRoot "scripts\validate_vector_svg.py"), "--svg", $mergedFixture)
    $mergedXml = Get-Content -LiteralPath $mergedFixture -Raw -Encoding UTF8
    foreach ($preservedId in @('frame', 'subject', 'arrow', 'legend')) {
        if ($mergedXml -notmatch ('id=["'']' + [regex]::Escape($preservedId) + '["'']')) { throw "Non-text structure was lost: $preservedId" }
    }
    if ($mergedXml -notmatch '<text\b' -or $mergedXml -match '<image\b') { throw "Merged Master SVG text/raster contract failed." }

    $cacheRoot = Join-Path $tempRoot "cache"
    Invoke-Python @((Join-Path $skillRoot "scripts\prepare_geometry_cache.py"), "--input", $mergedFixture, "--output-dir", $cacheRoot, "--job-id", "package-smoke")
    foreach ($cacheFile in @("geometry-cache.json", "playback.json")) {
        if (-not (Test-Path -LiteralPath (Join-Path $cacheRoot $cacheFile) -PathType Leaf)) { throw "Geometry cache did not create $cacheFile." }
    }
    $geometryCache = Get-Content -LiteralPath (Join-Path $cacheRoot "geometry-cache.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $editableText = $geometryCache.atoms | Where-Object { $_.kind -eq "text" -and $_.text.contents -eq "Cell-lct Next" }
    if (-not $editableText) { throw "Geometry cache did not preserve the live text atom." }
    if ($geometryCache.atoms | Where-Object { $_.kind -eq "image" }) { throw "Raster atom was found in the geometry cache." }

    $dryRunOutput = & (Join-Path $skillRoot "scripts\run_cell_lct.ps1") -InputSvg $mergedFixture -WorkDir (Join-Path $tempRoot "dry-cache") -OutputAi (Join-Path $tempRoot "dry.ai") -OutputPng (Join-Path $tempRoot "dry.png") -MinBatchSize 20 -MaxBatchSize 50 -DryRun | Out-String
    if ($dryRunOutput -notmatch 'DRY_RUN\|' -or $dryRunOutput -notmatch 'illustrator_untouched=true') { throw "Illustrator dry-run contract failed." }
}
finally {
    if (Test-Path -LiteralPath $tempBase) {
        $checked = [IO.Path]::GetFullPath($tempBase)
        if (-not $checked.StartsWith($repoRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove a directory outside the project." }
        Remove-Item -LiteralPath $checked -Recurse -Force
    }
}

Write-Output "PACKAGE_OK|skill=cell-lct-next|version=0.2.0|text=live|cache=validated|secret_scan=clean|marketplace=absent"
