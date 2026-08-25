#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Version = "0.2.0",
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$manifestPath = Join-Path $repoRoot "plugins\cell-lct\.codex-plugin\plugin.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -ne $Version) { throw "Manifest version $($manifest.version) does not match requested release $Version." }
if (Test-Path -LiteralPath (Join-Path $repoRoot ".agents\plugins\marketplace.json")) { throw "Marketplace entry is forbidden in this release." }

if (-not $SkipTests) {
    & (Join-Path $repoRoot "tests\test-package.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Package tests failed." }
    & (Join-Path $repoRoot "tests\test-windows-e2e.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Windows end-to-end tests failed." }
}

$distRoot = Join-Path $repoRoot "dist"
$tempRoot = Join-Path $repoRoot ".release-tmp"
$stageRoot = Join-Path $tempRoot ("cell-lct-v" + $Version)
$zipPath = Join-Path $distRoot ("cell-lct-v" + $Version + ".zip")
$hashPath = "$zipPath.sha256"

if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageRoot, $distRoot | Out-Null

$excludedTop = @(".git", ".agents", "dist", ".release-tmp", ".dry-run", ".dry-run-out", ".test-tmp")
Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object { $excludedTop -notcontains $_.Name } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stageRoot -Recurse -Force
}

$releaseManifest = [ordered]@{
    product = "Cell-lct"
    version = $Version
    tag = "v$Version"
    createdUtc = [DateTime]::UtcNow.ToString("o")
    marketplaceEntry = $false
    credentialsIncluded = $false
    dependencyLock = "requirements.lock"
    runtimeLock = "runtime-lock.json"
}
$releaseManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stageRoot "RELEASE-MANIFEST.json") -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -LiteralPath $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($hashPath, "$hash  $([IO.Path]::GetFileName($zipPath))`r`n", [Text.UTF8Encoding]::new($false))
Remove-Item -LiteralPath $tempRoot -Recurse -Force

Write-Output "RELEASE_OK|version=$Version|zip=$zipPath|sha256=$hash"
