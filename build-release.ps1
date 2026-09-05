#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Version,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot 'plugins\cell_gd\.codex-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = [string]$manifest.version }
if ($manifest.version -ne $Version) { throw "Plugin version $($manifest.version) does not match release $Version." }
if (Test-Path -LiteralPath (Join-Path $repoRoot '.agents\plugins\marketplace.json')) { throw 'Marketplace metadata is forbidden in this release.' }

if (-not $SkipTests) {
    & (Join-Path $repoRoot 'tests\test-package.ps1')
    & (Join-Path $repoRoot 'tests\test-windows-e2e.ps1')
}

$distRoot = Join-Path $repoRoot 'dist'
$tempRoot = Join-Path $repoRoot '.release-tmp'
$stageRoot = Join-Path $tempRoot "cell_gd-v$Version"
$zipPath = Join-Path $distRoot "cell_gd-v$Version.zip"
$hashPath = "$zipPath.sha256"
if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageRoot, $distRoot | Out-Null

$excludedTop = @('.git', '.tmp', '.tmp-cache', '.test-tmp', '.visibility-test', '.visibility-test-v2', '.release-tmp', 'dist')
Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object { $excludedTop -notcontains $_.Name } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stageRoot -Recurse -Force
}
Get-ChildItem -LiteralPath $stageRoot -Recurse -Directory -Filter '__pycache__' | ForEach-Object {
    $checked = [IO.Path]::GetFullPath($_.FullName)
    if (-not $checked.StartsWith($stageRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to clean outside the release stage.' }
    Remove-Item -LiteralPath $checked -Recurse -Force
}
Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Include '*.pyc','*.pyo','*.dpapi','*.pptx','*.png','*.jpg','*.jpeg','*.webp','*.pdf' | ForEach-Object {
    $checked = [IO.Path]::GetFullPath($_.FullName)
    if (-not $checked.StartsWith($stageRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to clean outside the release stage.' }
    Remove-Item -LiteralPath $checked -Force
}

$releaseManifest = [ordered]@{
    product = 'cell_gd'
    version = $Version
    tag = "v$Version"
    createdUtc = [DateTime]::UtcNow.ToString('o')
    marketplaceEntry = $false
    credentialsIncluded = $false
    dependencyLock = 'requirements.lock'
    runtimeLock = 'runtime-lock.json'
    platformContract = 'plugins/cell_gd/skills/cell_gd/references/platform-contract.json'
}
$releaseManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stageRoot 'RELEASE-MANIFEST.json') -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -LiteralPath $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($hashPath, "$hash  $([IO.Path]::GetFileName($zipPath))`r`n", [Text.UTF8Encoding]::new($false))
Remove-Item -LiteralPath $tempRoot -Recurse -Force
Write-Output "RELEASE_OK|version=$Version|zip=$zipPath|sha256=$hash"
