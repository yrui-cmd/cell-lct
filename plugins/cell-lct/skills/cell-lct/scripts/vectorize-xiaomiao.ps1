#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputImage,

    [Parameter(Mandatory = $true)]
    [string]$OutputSvg,

    [ValidateRange(2, 60)]
    [int]$PollSeconds = 5,

    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 900,

    [ValidateRange(1, 1000000)]
    [int]$MaxCreditsWithoutConfirmation = 1,

    [ValidateRange(0, 1000000)]
    [int]$EstimatedCredits = 1,

    [switch]$ApproveHighCost,

    [uri]$BaseUrl = "https://xiaomiao-ai.com"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$inputPath = (Resolve-Path -LiteralPath $InputImage).Path
$outputPath = [IO.Path]::GetFullPath($OutputSvg)
$outputDirectory = Split-Path -Parent $outputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$adapter = Join-Path $PSScriptRoot "xiaomiao.ps1"
$validator = Join-Path $PSScriptRoot "validate_vector_svg.py"
$creditPolicy = Join-Path $PSScriptRoot "assert-credit-policy.ps1"
foreach ($required in @($adapter, $validator, $creditPolicy)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing required runtime file: $required"
    }
}

# This gate runs before authentication or upload so no image bytes leave the
# computer when a known estimate exceeds the user's threshold.
& $creditPolicy -EstimatedCredits $EstimatedCredits -MaxWithoutConfirmation $MaxCreditsWithoutConfirmation -ImageId "preflight" -Approved:$ApproveHighCost | Out-Null

# Authentication is checked without charging credits.
$verification = & $adapter verify -BaseUrl $BaseUrl
if ($null -eq $verification -or $verification.authenticated -ne $true) {
    throw "Xiaomiao authentication could not be verified."
}

$submission = & $adapter upload -ImagePath $inputPath -BaseUrl $BaseUrl
$imageId = [string]$submission.image_id
if ([string]::IsNullOrWhiteSpace($imageId)) {
    throw "Xiaomiao did not return an image id."
}

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$job = $null
$lastStatusError = $null
do {
    try {
        $job = & $adapter status -ImageId $imageId -BaseUrl $BaseUrl
        $lastStatusError = $null
    }
    catch {
        $lastStatusError = $_.Exception.Message
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Seconds $PollSeconds
        continue
    }
    $status = [string]$job.status
    if ($status -eq "completed") { break }
    if ($status -in @("failed", "expired", "rejected")) {
        throw "Xiaomiao job ended with status: $status"
    }
    if ($null -ne $job.credits_left -and [int]$job.credits_left -lt 0) {
        throw "Xiaomiao credits are unavailable."
    }
    if ([DateTime]::UtcNow -ge $deadline) {
        throw "Xiaomiao job timed out after $TimeoutSeconds seconds."
    }
    Start-Sleep -Seconds $PollSeconds
} while ($true)

if ($null -eq $job -or [string]$job.status -ne "completed") {
    $suffix = if ($lastStatusError) { " Last status error: $lastStatusError" } else { "" }
    throw "Xiaomiao job timed out after $TimeoutSeconds seconds.$suffix"
}

$temporarySvg = "$outputPath.download.$PID"
try {
    $downloaded = $false
    $lastDownloadError = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            & $adapter download -ImageId $imageId -OutputPath $temporarySvg -BaseUrl $BaseUrl | Out-Null
            $downloaded = $true
            break
        }
        catch {
            $lastDownloadError = $_.Exception.Message
            if ($attempt -lt 5) { Start-Sleep -Seconds $PollSeconds }
        }
    }
    if (-not $downloaded) {
        throw "Xiaomiao SVG download failed after retries: $lastDownloadError"
    }

    $validationOutput = & py -3 -X utf8 $validator --svg $temporarySvg 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Downloaded result is not a valid true-vector SVG: $validationOutput"
    }

    Move-Item -LiteralPath $temporarySvg -Destination $outputPath -Force
}
finally {
    if (Test-Path -LiteralPath $temporarySvg -PathType Leaf) {
        Remove-Item -LiteralPath $temporarySvg -Force
    }
}

[ordered]@{
    ok = $true
    image_id = $imageId
    output_svg = $outputPath
    credits_left = $job.credits_left
} | ConvertTo-Json -Compress
