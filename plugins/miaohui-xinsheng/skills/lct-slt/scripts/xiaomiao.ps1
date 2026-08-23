#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("health", "verify", "upload", "status", "download")]
    [string]$Action = "health",

    [string]$ImagePath,
    [string]$ImageId,
    [string]$OutputPath,
    [uri]$BaseUrl = "https://xiaomiao-ai.com",
    [string]$SecretPath = "$env:USERPROFILE\.codex\secrets\xiaomiao-api-key.dpapi"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

function Get-XiaomiaoToken {
    if (-not (Test-Path -LiteralPath $SecretPath -PathType Leaf)) {
        throw "Xiaomiao API key is not configured. Run set-key.ps1 first."
    }

    $cipherText = [IO.File]::ReadAllText($SecretPath, [Text.Encoding]::UTF8).Trim()
    $secureValue = ConvertTo-SecureString $cipherText
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function New-XiaomiaoClient([switch]$Authenticated) {
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(90)
    if ($Authenticated) {
        $token = Get-XiaomiaoToken
        try {
            $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $token)
        }
        finally {
            $token = $null
        }
    }
    return $client
}

function Read-ResponseBody([Net.Http.HttpResponseMessage]$Response) {
    return $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
}

function Convert-ResponseJson([string]$Body) {
    try {
        return $Body | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{ raw = $Body }
    }
}

function Get-ServerError([string]$Body) {
    try {
        $payload = $Body | ConvertFrom-Json
        if ($payload.error) { return [string]$payload.error }
    }
    catch { }
    return "The server rejected the request."
}

$root = $BaseUrl.AbsoluteUri.TrimEnd('/')

switch ($Action) {
    "health" {
        $client = New-XiaomiaoClient
        try {
            $response = $client.GetAsync("$root/api/health").GetAwaiter().GetResult()
            $body = Read-ResponseBody $response
            if (-not $response.IsSuccessStatusCode) {
                throw "Xiaomiao health check failed (HTTP $([int]$response.StatusCode))."
            }
            Convert-ResponseJson $body
        }
        finally {
            if ($response) { $response.Dispose() }
            $client.Dispose()
        }
    }

    "verify" {
        $client = New-XiaomiaoClient -Authenticated
        try {
            $probeId = "__codex_connection_probe__"
            $response = $client.GetAsync("$root/api/images/$probeId").GetAwaiter().GetResult()
            $statusCode = [int]$response.StatusCode
            $body = Read-ResponseBody $response

            if ($statusCode -eq 404) {
                [pscustomobject]@{
                    ok = $true
                    authenticated = $true
                    service = "xiaomiao"
                    credits_charged = 0
                }
                break
            }
            if ($statusCode -in 401, 403) {
                throw "Xiaomiao API-key authentication failed (HTTP $statusCode)."
            }
            throw "Xiaomiao authentication probe returned unexpected HTTP ${statusCode}: $(Get-ServerError $body)"
        }
        finally {
            if ($response) { $response.Dispose() }
            $client.Dispose()
        }
    }

    "upload" {
        if (-not $ImagePath) { throw "-ImagePath is required for upload." }
        $resolvedImage = (Resolve-Path -LiteralPath $ImagePath).Path
        $fileInfo = Get-Item -LiteralPath $resolvedImage
        if ($fileInfo.Length -gt 10MB) { throw "The image exceeds Xiaomiao's 10 MB limit." }

        $mimeTypes = @{
            ".png" = "image/png"
            ".jpg" = "image/jpeg"
            ".jpeg" = "image/jpeg"
            ".webp" = "image/webp"
        }
        $extension = [IO.Path]::GetExtension($resolvedImage).ToLowerInvariant()
        if (-not $mimeTypes.ContainsKey($extension)) {
            throw "Xiaomiao accepts PNG, JPEG, or WebP files."
        }

        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
            throw "curl.exe is required for Xiaomiao uploads on Windows."
        }

        $token = Get-XiaomiaoToken
        try {
            # Feed the Authorization header through stdin so the secret never
            # appears in the curl process command line or in shell history.
            $marker = "__XIAOMIAO_HTTP_STATUS__"
            $formValue = "image=@$resolvedImage;type=$($mimeTypes[$extension]);filename=$($fileInfo.Name)"
            $curlArguments = @(
                "--silent", "--show-error", "--max-time", "90",
                "--header", "@-",
                "--write-out", "`n${marker}:%{http_code}",
                "--form", $formValue,
                "--url", "$root/api/images"
            )
            $rawOutput = "Authorization: Bearer $token" | & curl.exe @curlArguments 2>&1 | Out-String
            $curlExitCode = $LASTEXITCODE
            if ($curlExitCode -ne 0) {
                throw "Xiaomiao upload transport failed (curl exit $curlExitCode)."
            }

            $match = [regex]::Match($rawOutput, "(?s)^(.*)\r?\n${marker}:(\d{3})\s*$")
            if (-not $match.Success) { throw "Xiaomiao upload returned an unreadable response." }
            $body = $match.Groups[1].Value.Trim()
            $statusCode = [int]$match.Groups[2].Value
            if ($statusCode -lt 200 -or $statusCode -ge 300) {
                throw "Xiaomiao upload failed (HTTP ${statusCode}): $(Get-ServerError $body)"
            }
            Convert-ResponseJson $body
        }
        finally {
            $token = $null
        }
    }

    "status" {
        if (-not $ImageId) { throw "-ImageId is required for status." }
        $escapedId = [Uri]::EscapeDataString($ImageId)
        $client = New-XiaomiaoClient -Authenticated
        try {
            $response = $client.GetAsync("$root/api/images/$escapedId").GetAwaiter().GetResult()
            $body = Read-ResponseBody $response
            if (-not $response.IsSuccessStatusCode) {
                throw "Xiaomiao status request failed (HTTP $([int]$response.StatusCode)): $(Get-ServerError $body)"
            }
            Convert-ResponseJson $body
        }
        finally {
            if ($response) { $response.Dispose() }
            $client.Dispose()
        }
    }

    "download" {
        if (-not $ImageId) { throw "-ImageId is required for download." }
        if (-not $OutputPath) { throw "-OutputPath is required for download." }
        $escapedId = [Uri]::EscapeDataString($ImageId)
        $client = New-XiaomiaoClient -Authenticated
        try {
            $response = $client.GetAsync("$root/api/images/$escapedId/file").GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode -and [int]$response.StatusCode -eq 410) {
                $response.Dispose()
                $response = $client.GetAsync("$root/api/images/$escapedId/result").GetAwaiter().GetResult()
            }
            if (-not $response.IsSuccessStatusCode) {
                $body = Read-ResponseBody $response
                throw "Xiaomiao download failed (HTTP $([int]$response.StatusCode)): $(Get-ServerError $body)"
            }
            $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $target = [IO.Path]::GetFullPath($OutputPath)
            $targetDirectory = Split-Path -Parent $target
            if ($targetDirectory) { New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null }
            [IO.File]::WriteAllBytes($target, $bytes)
            [pscustomobject]@{ ok = $true; output_path = $target; bytes = $bytes.Length }
        }
        finally {
            if ($response) { $response.Dispose() }
            $client.Dispose()
        }
    }
}
