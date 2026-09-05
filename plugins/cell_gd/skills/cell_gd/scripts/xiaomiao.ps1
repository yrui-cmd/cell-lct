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
        throw "Xiaomiao API key is not configured. Codex must request it in chat and configure it automatically through standard input."
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

        $client = New-XiaomiaoClient -Authenticated
        $bodyContent = $null
        $imageBytes = $null
        $bodyBytes = $null
        $response = $null
        try {
            $boundary = "cell-ppt-$([Guid]::NewGuid().ToString('N'))"
            $crlf = "`r`n"
            $prefix = "--$boundary$crlf" +
                "Content-Disposition: form-data; name=`"image`"; filename=`"$($fileInfo.Name)`"$crlf" +
                "Content-Type: $($mimeTypes[$extension])$crlf$crlf"
            $suffix = "$crlf--$boundary--$crlf"
            $prefixBytes = [Text.Encoding]::UTF8.GetBytes($prefix)
            $imageBytes = [IO.File]::ReadAllBytes($resolvedImage)
            $suffixBytes = [Text.Encoding]::UTF8.GetBytes($suffix)
            $bodyBytes = [byte[]]::new($prefixBytes.Length + $imageBytes.Length + $suffixBytes.Length)
            [Buffer]::BlockCopy($prefixBytes, 0, $bodyBytes, 0, $prefixBytes.Length)
            [Buffer]::BlockCopy($imageBytes, 0, $bodyBytes, $prefixBytes.Length, $imageBytes.Length)
            [Buffer]::BlockCopy($suffixBytes, 0, $bodyBytes, $prefixBytes.Length + $imageBytes.Length, $suffixBytes.Length)
            $bodyContent = [Net.Http.ByteArrayContent]::new($bodyBytes)
            $bodyContent.Headers.TryAddWithoutValidation("Content-Type", "multipart/form-data; boundary=$boundary") | Out-Null

            $response = $client.PostAsync("$root/api/images", $bodyContent).GetAwaiter().GetResult()
            $body = Read-ResponseBody $response
            if (-not $response.IsSuccessStatusCode) {
                throw "Xiaomiao upload failed (HTTP $([int]$response.StatusCode)): $(Get-ServerError $body)"
            }
            Convert-ResponseJson $body
        }
        finally {
            if ($response) { $response.Dispose() }
            if ($bodyContent) { $bodyContent.Dispose() }
            $bodyBytes = $null
            $imageBytes = $null
            $client.Dispose()
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
