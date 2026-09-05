#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$testBase = Join-Path $repoRoot ".test-tmp"
$testRoot = Join-Path $testBase ("windows-e2e-" + [Guid]::NewGuid().ToString("N"))
$skillDestination = Join-Path $testRoot "skills"

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

    $setupOutput = & (Join-Path $repoRoot "setup.ps1") -Destination $skillDestination -SkipDependencies -SkipApiKey -SkipIllustratorCheck | Out-String
    if ($setupOutput -notmatch "SETUP_OK\|version=0.2.1") { throw "One-click setup did not complete." }

    $installedSkill = Join-Path $skillDestination "cell-lct"
    $doctorOutput = & (Join-Path $repoRoot "doctor.ps1") -SkillRoot $installedSkill -SkipApi -SkipIllustrator | Out-String
    if ($doctorOutput -notmatch "DOCTOR_OK\|version=0.2.1") { throw "Offline diagnostics did not pass." }

    $fixture = Join-Path $repoRoot "tests\fixtures\clean-reference.svg"
    $manifest = Join-Path $repoRoot "tests\fixtures\text-manifest.json"
    $masterSvg = Join-Path $testRoot "master.svg"
    $python = if (Get-Command py -ErrorAction SilentlyContinue) { @("py", "-3") } else { @("python") }
    if ($python.Count -eq 2) {
        & $python[0] $python[1] -X utf8 (Join-Path $installedSkill "scripts\merge_live_text.py") --input-svg $fixture --text-manifest $manifest --output-svg $masterSvg
    } else {
        & $python[0] -X utf8 (Join-Path $installedSkill "scripts\merge_live_text.py") --input-svg $fixture --text-manifest $manifest --output-svg $masterSvg
    }
    if ($LASTEXITCODE -ne 0) { throw "Live-text Master SVG construction failed." }

    $dryOutput = & (Join-Path $installedSkill "scripts\run_cell_lct.ps1") -InputSvg $masterSvg -WorkDir (Join-Path $testRoot "cache") -OutputAi (Join-Path $testRoot "result.ai") -OutputPng (Join-Path $testRoot "result.png") -MinBatchSize 20 -MaxBatchSize 50 -DryRun | Out-String
    if ($dryOutput -notmatch "illustrator_untouched=true") { throw "Dry-run touched or attempted to manage Illustrator." }

    Write-Output "WINDOWS_E2E_OK|version=0.2.1|setup=pass|doctor=pass|text=live|illustrator=dry-run"
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $checkedRoot = [IO.Path]::GetFullPath($testRoot)
        $checkedBase = [IO.Path]::GetFullPath($testBase).TrimEnd('\') + '\'
        if (-not $checkedRoot.StartsWith($checkedBase, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove a directory outside the test root."
        }
        Remove-Item -LiteralPath $checkedRoot -Recurse -Force
        if ((Test-Path -LiteralPath $testBase) -and -not (Get-ChildItem -LiteralPath $testBase -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $testBase -Force
        }
    }
}
