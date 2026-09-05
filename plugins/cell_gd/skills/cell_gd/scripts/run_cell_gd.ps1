#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputImage,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [Parameter(Mandatory = $true)][ValidateSet('ppt', 'ai')][string]$Application,
    [ValidateRange(0, 1000000)][int]$EstimatedCredits = 1,
    [switch]$ApproveHighCost
)
$ErrorActionPreference = 'Stop'
$runner = if ($Application -eq 'ppt') { 'run_from_image.ps1' } else { 'run_illustrator_from_image.ps1' }
& (Join-Path $PSScriptRoot $runner) -InputImage $InputImage -OutputRoot $OutputRoot -EstimatedCredits $EstimatedCredits -ApproveHighCost:$ApproveHighCost
