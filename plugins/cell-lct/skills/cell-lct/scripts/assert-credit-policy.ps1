#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 1000000)]
    [int]$EstimatedCredits,

    [ValidateRange(1, 1000000)]
    [int]$MaxWithoutConfirmation = 1,

    [string]$ImageId,

    [switch]$Approved
)

$ErrorActionPreference = "Stop"

if ($EstimatedCredits -gt $MaxWithoutConfirmation -and -not $Approved) {
    throw "COST_CONFIRMATION_REQUIRED|estimated_credits=$EstimatedCredits|image_id=$ImageId"
}

[pscustomobject]@{
    ok = $true
    estimated_credits = $EstimatedCredits
    confirmation_required = ($EstimatedCredits -gt $MaxWithoutConfirmation)
    approved = $Approved.IsPresent
}
