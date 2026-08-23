#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SecretPath = "$env:USERPROFILE\.codex\secrets\xiaomiao-api-key.dpapi"
)

$ErrorActionPreference = "Stop"

$secret = Read-Host "Paste the Xiaomiao API key" -AsSecureString
$pointer = [IntPtr]::Zero
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    $plainText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ($plainText -notmatch '^img_live_[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$') {
        throw "The value does not match the Xiaomiao API-key format."
    }
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

Write-Output "Xiaomiao API key stored with Windows DPAPI."
