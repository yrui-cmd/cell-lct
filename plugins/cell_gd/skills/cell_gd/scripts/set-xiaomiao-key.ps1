#requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$FromStdin,
    [string]$SecretPath = "$env:USERPROFILE\.codex\secrets\xiaomiao-api-key.dpapi"
)

$ErrorActionPreference = "Stop"
Import-Module Microsoft.PowerShell.Security -ErrorAction Stop

$plainText = $null
$secret = $null
$pointer = [IntPtr]::Zero
try {
    if (-not $FromStdin) {
        throw "Cell_ppt credential setup must be driven by Codex with -FromStdin."
    }
    $plainText = [Console]::In.ReadLine()
    if ($null -eq $plainText) { throw "No API key was received on standard input." }
    $plainText = $plainText.Trim()
    if ($plainText -notmatch '^img_live_[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$') {
        throw "The value does not match the Xiaomiao API-key format."
    }
    $secret = ConvertTo-SecureString $plainText -AsPlainText -Force
}
finally {
    if ($pointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    $plainText = $null
}

$secretDirectory = Split-Path -Parent $SecretPath
New-Item -ItemType Directory -Force -Path $secretDirectory | Out-Null

$cipherText = ConvertFrom-SecureString $secret
$temporaryPath = "$SecretPath.tmp.$PID"
[IO.File]::WriteAllText($temporaryPath, $cipherText, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $SecretPath -Force

$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $SecretPath '/inheritance:r' '/grant:r' "${identity}:(F)" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "The key was encrypted, but its file permissions could not be restricted."
}

Write-Output "KEY_CONFIG_OK|storage=windows-dpapi|plaintext_logged=false"
