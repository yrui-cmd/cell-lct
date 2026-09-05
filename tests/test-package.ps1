#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pluginRoot = Join-Path $repoRoot 'plugins\cell_gd'
$skillRoot = Join-Path $pluginRoot 'skills\cell_gd'
$required = @(
    'README.md', 'README_EN.md', 'LICENSE', 'CHANGELOG.md', '.gitignore',
    'setup.ps1', 'setup.sh', 'install.ps1', 'install.py', 'doctor.ps1', 'doctor.py',
    'build-release.ps1', 'requirements.lock', 'runtime-lock.json',
    'plugins\cell_gd\.codex-plugin\plugin.json',
    'plugins\cell_gd\skills\cell_gd\SKILL.md',
    'plugins\cell_gd\skills\cell_gd\references\platform-contract.json',
    'plugins\cell_gd\skills\cell_gd\scripts\run_cell_ppt.ps1',
    'plugins\cell_gd\skills\cell_gd\scripts\run_cell_ppt_ooxml.py',
    'plugins\cell_gd\skills\cell_gd\scripts\run_from_svg.ps1',
    'plugins\cell_gd\skills\cell_gd\scripts\run_from_svg.py',
    'plugins\cell_gd\skills\cell_gd\scripts\run_from_image.ps1',
    'plugins\cell_gd\skills\cell_gd\scripts\run_from_image.py',
    'plugins\cell_gd\skills\cell_gd\scripts\set-xiaomiao-key.ps1',
    'plugins\cell_gd\skills\cell_gd\scripts\set_xiaomiao_key.py',
    'plugins\cell_gd\skills\cell_gd\scripts\configure_runtime.py',
    'plugins\cell_gd\skills\cell_gd\scripts\xiaomiao.ps1',
    'plugins\cell_gd\skills\cell_gd\scripts\xiaomiao.py'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) { throw "Required package file is missing: $relative" }
}
foreach ($forbidden in @('FROZEN-MANIFEST.json', 'update-frozen-manifest.ps1')) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $forbidden)) { throw "Obsolete freeze file remains: $forbidden" }
}

$plugin = Get-Content -LiteralPath (Join-Path $pluginRoot '.codex-plugin\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($plugin.name -ne 'cell_gd' -or $plugin.version -ne '0.3.0' -or $plugin.skills -ne './skills/' -or $plugin.license -ne 'MIT') { throw 'Plugin identity is invalid.' }
if ($plugin.interface.displayName -ne 'cell_gd' -or $plugin.author.name -ne 'yrui-cmd') { throw 'Plugin display identity is invalid.' }
if (Test-Path -LiteralPath (Join-Path $repoRoot '.agents\plugins\marketplace.json')) { throw 'Marketplace metadata must not be included.' }

$runtime = Get-Content -LiteralPath (Join-Path $repoRoot 'runtime-lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($runtime.codex.skillId -ne 'cell_gd' -or $runtime.platform.macBackend -ne 'editable-ooxml') { throw 'Runtime contract identity is invalid.' }
$contract = Get-Content -LiteralPath (Join-Path $skillRoot 'references\platform-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($contract.ordinaryBatchMin -ne 20 -or $contract.ordinaryBatchMax -ne 50 -or $contract.geometryCacheSchema -ne 3 -or $contract.complexPointThreshold -ne 320 -or $contract.maxBatchPoints -ne 2200 -or $contract.windowsStepDelayMs -ne 8 -or $contract.visibilityRule -ne 'remove-exact-duplicates-only') { throw 'Fixed core defaults are invalid.' }
if ($contract.powerPointCompatibility.notYearLocked -ne $true -or $contract.powerPointCompatibility.windows -notcontains '2016' -or $contract.powerPointCompatibility.windows -notcontains 'Microsoft 365 desktop') { throw 'PowerPoint compatibility must not be year-locked.' }
if ($contract.installation.autoDetectRuntime -ne $true -or $contract.installation.chatApiKeyAllowed -ne $true -or $contract.installation.credentialTransport -ne 'stdin-only') { throw 'Automatic installation contract is invalid.' }
$expectedRequirements = "python-pptx==1.0.2`nfonttools==4.61.1`nshapely==2.1.2"
$actualRequirements = (Get-Content -LiteralPath (Join-Path $repoRoot 'requirements.lock') -Raw -Encoding UTF8).Trim() -replace "`r`n", "`n"
if ($actualRequirements -ne $expectedRequirements) { throw 'Python dependencies are not exactly locked.' }

$allFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]dist[\\/]' -and $_.FullName -notmatch '[\\/]\.test-tmp[\\/]'
}
$secretPattern = 'img_live_[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'
foreach ($file in $allFiles) {
    if ($file.Extension -notin @('.md','.ps1','.sh','.py','.json','.yaml','.yml','.txt','.lock','.svg')) { continue }
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($content -and [regex]::IsMatch($content, $secretPattern)) { throw "A live API key marker was found in: $($file.FullName)" }
}

$skillText = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw -Encoding UTF8
foreach ($phrase in @('name: cell_gd', 'platform-contract.json', 'runtime-profile.json', 'chat', 'macOS', 'standard input', 'path-return SVG')) {
    if ($skillText -notlike "*$phrase*") { throw "Required Skill contract is missing: $phrase" }
}
foreach ($forbidden in @('Read-Host', 'FROZEN-MANIFEST', 'fixed Git tag')) {
    if ($skillText -like "*$forbidden*") { throw "Conflicting Skill rule remains: $forbidden" }
}

$tempBase = Join-Path $repoRoot '.test-tmp'
$tempRoot = Join-Path $tempBase ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    $installRoot = Join-Path $tempRoot 'skills'
    & (Join-Path $repoRoot 'install.ps1') -Destination $installRoot
    $installed = Join-Path $installRoot 'cell_gd\SKILL.md'
    if (-not (Test-Path -LiteralPath $installed -PathType Leaf)) { throw 'Install smoke test failed.' }
    if ((Get-Item -LiteralPath (Split-Path -Parent $installed)).LinkType) { throw 'Public installer created a link instead of a copy.' }
    $profilePath = Join-Path $installRoot 'cell_gd\runtime-profile.json'
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw 'Automatic runtime profile was not created.' }
    $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($profile.core.stepDelayMs -ne 8 -or $profile.core.filter -ne 'remove-exact-duplicates-only' -or [string]::IsNullOrWhiteSpace($profile.backend)) { throw 'Automatic runtime profile is invalid.' }

    $secretPath = Join-Path $tempRoot 'fake-key.dpapi'
    $setter = Join-Path $skillRoot 'scripts\set-xiaomiao-key.ps1'
    $fakeKey = ('img' + '_live_TESTKEY123456.TESTSECRET123456')
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Process -Id $PID).Path
    $start.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$setter`" -FromStdin -SecretPath `"$secretPath`""
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    $process.StandardInput.WriteLine($fakeKey)
    $process.StandardInput.Close()
    $output = $process.StandardOutput.ReadToEnd()
    $errorOutput = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Stdin credential setup failed: $errorOutput" }
    if ($output -notmatch 'KEY_CONFIG_OK' -or $output -match [regex]::Escape($fakeKey)) { throw 'Credential output contract failed.' }
    $cipher = Get-Content -LiteralPath $secretPath -Raw -Encoding UTF8
    if ($cipher -match [regex]::Escape($fakeKey)) { throw 'Credential plaintext was written to storage.' }
}
finally {
    if (Test-Path -LiteralPath $tempBase) {
        $checked = [IO.Path]::GetFullPath($tempBase)
        if (-not $checked.StartsWith($repoRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a directory outside the project.' }
        Remove-Item -LiteralPath $checked -Recurse -Force
    }
}

Write-Output 'PACKAGE_OK|skill=cell_gd|version=0.3.0|platforms=windows,macos|freeze=removed|secret_scan=clean'
