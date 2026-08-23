#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Destination = "$env:USERPROFILE\.codex\skills",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$sourceRoot = Join-Path $PSScriptRoot "plugins\cell-lct\skills"
$destinationRoot = [IO.Path]::GetFullPath($Destination)
$skillNames = @("cell-lct")

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Plugin skill directory is missing: $sourceRoot"
}

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null

foreach ($skillName in $skillNames) {
    $source = Join-Path $sourceRoot $skillName
    $target = Join-Path $destinationRoot $skillName
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Required skill is missing: $skillName"
    }
    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        throw "Skill already exists: $target. Re-run with -Force only if replacement is intended."
    }
    if (Test-Path -LiteralPath $target) {
        $resolvedDestination = [IO.Path]::GetFullPath($destinationRoot).TrimEnd('\') + '\'
        $resolvedTarget = [IO.Path]::GetFullPath($target)
        if (-not $resolvedTarget.StartsWith($resolvedDestination, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to replace a target outside the destination root."
        }
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    }
    Copy-Item -LiteralPath $source -Destination $target -Recurse
}

Write-Output "INSTALLED|skills=$($skillNames.Count)|destination=$destinationRoot"
Write-Output "Restart Codex and start a new task before first use."
