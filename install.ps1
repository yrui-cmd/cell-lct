#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Destination = "$env:USERPROFILE\.codex\skills",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'install.py'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Missing cross-platform installer: $installer" }
$pythonCommand = Get-Command py -ErrorAction SilentlyContinue
$arguments = @('-3', '-X', 'utf8', $installer, '--destination', ([IO.Path]::GetFullPath($Destination)))
if (-not $pythonCommand) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    $arguments = @('-X', 'utf8', $installer, '--destination', ([IO.Path]::GetFullPath($Destination)))
}
if (-not $pythonCommand) { throw 'Python 3.11-3.14 was not found.' }
if ($Force) { $arguments += '--force' }
& $pythonCommand.Source @arguments
if ($LASTEXITCODE -ne 0) { throw 'cell_gd installation failed.' }
