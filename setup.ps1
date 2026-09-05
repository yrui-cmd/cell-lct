#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Destination = "$env:USERPROFILE\.codex\skills",
    [switch]$Force,
    [switch]$SkipDependencies,
    [switch]$SkipApiKey,
    [switch]$SkipIllustratorCheck,
    [switch]$VerifyApi
)

$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath($PSScriptRoot)

if (-not $SkipDependencies) {
    $requirements = Join-Path $repoRoot "requirements.lock"
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 -m pip install --disable-pip-version-check -r $requirements
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        & python -m pip install --disable-pip-version-check -r $requirements
    } else {
        throw "Python 3.11-3.14 is required. Install Python, then run setup.ps1 again."
    }
    if ($LASTEXITCODE -ne 0) { throw "Locked Python dependency installation failed." }
}

& (Join-Path $repoRoot "install.ps1") -Destination $Destination -Force:$Force

$installedSkill = Join-Path ([IO.Path]::GetFullPath($Destination)) "cell-lct"
$secretPath = "$env:USERPROFILE\.codex\secrets\xiaomiao-api-key.dpapi"
if (-not $SkipApiKey -and -not (Test-Path -LiteralPath $secretPath -PathType Leaf)) {
    & (Join-Path $installedSkill "scripts\set-xiaomiao-key.ps1") -SecretPath $secretPath
}

$doctorArgs = @{ SkillRoot = $installedSkill }
if ($SkipApiKey) { $doctorArgs.SkipApi = $true }
if ($SkipIllustratorCheck) { $doctorArgs.SkipIllustrator = $true }
if ($VerifyApi) { $doctorArgs.VerifyApi = $true }
& (Join-Path $repoRoot "doctor.ps1") @doctorArgs
if ($LASTEXITCODE -ne 0) { throw "Installation completed, but diagnostics found a blocking requirement." }

Write-Output "SETUP_OK|version=0.2.1|skill=$installedSkill"
Write-Output "Restart Codex and start a new task before first use."
