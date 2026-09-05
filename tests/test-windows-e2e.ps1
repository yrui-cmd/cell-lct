#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$skillRoot = Join-Path $repoRoot 'plugins\cell_gd\skills\cell_gd'
$fixture = Join-Path $PSScriptRoot 'fixtures\visibility.svg'
$tempBase = Join-Path $repoRoot '.test-tmp'
$tempRoot = Join-Path $tempBase ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $master = Join-Path $tempRoot 'master.svg'
    Copy-Item -LiteralPath $fixture -Destination $master
    py -3 -X utf8 (Join-Path $skillRoot 'scripts\validate_vector_svg.py') --svg $master | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Master SVG validation failed.' }

    $cacheRoot = Join-Path $tempRoot 'cache'
    py -3 -X utf8 (Join-Path $skillRoot 'scripts\prepare_geometry_cache.py') --input $master --output-dir $cacheRoot --job-id windows-e2e | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Geometry cache creation failed.' }
    py -3 -X utf8 (Join-Path $skillRoot 'scripts\cull_hidden_geometry.py') --cache (Join-Path $cacheRoot 'geometry-cache.json') --state (Join-Path $cacheRoot 'drawing-state.json') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Visibility culling failed.' }

    $cache = Get-Content -LiteralPath (Join-Path $cacheRoot 'geometry-cache.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$cache.source_total_drawing_paths -le [int]$cache.total_atoms) { throw 'Fixture did not remove its exact duplicate path.' }
    if ([int]$cache.culled_atom_count -ne 1) { throw 'Only the exact duplicate path should be removed.' }
    if (@($cache.culled_atoms | Where-Object { $_.reason -ne 'exact_duplicate' }).Count -ne 0) { throw 'A non-duplicate path was removed.' }
    if (@($cache.atoms | Where-Object { $_.sourceId -eq 'green-hidden' }).Count -ne 1) { throw 'A covered non-duplicate path was not preserved.' }
    if (@($cache.atoms | Where-Object { $_.kind -ne 'text' -and $_.subpaths.Count -ne 1 }).Count -ne 0) { throw 'Drawing units were not normalized to one subpath.' }
    if (@($cache.batches | Where-Object { $_.atomic_count -gt 50 }).Count -ne 0) { throw 'Batch size exceeded 50.' }

    $runtimeText = Get-Content -LiteralPath (Join-Path $skillRoot 'scripts\run_cell_ppt.ps1') -Raw -Encoding UTF8
    foreach ($contract in @('$application = $hostInfo.Application', '$shape.ZOrder(0)', 'Show-ObjectStep', '$UseActivePresentation')) {
        if ($runtimeText -notlike "*$contract*") { throw "PowerPoint runtime contract is missing: $contract" }
    }
    $fromSvgText = Get-Content -LiteralPath (Join-Path $skillRoot 'scripts\run_from_svg.ps1') -Raw -Encoding UTF8
    if ($fromSvgText -notmatch 'StepDelayMs = 8' -or $fromSvgText -notmatch 'cull_hidden_geometry.py') { throw 'SVG wrapper does not enforce fixed core drawing defaults.' }
}
finally {
    if (Test-Path -LiteralPath $tempBase) {
        $checked = [IO.Path]::GetFullPath($tempBase)
        if (-not $checked.StartsWith($repoRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a directory outside the project.' }
        Remove-Item -LiteralPath $checked -Recurse -Force
    }
}

Write-Output 'WINDOWS_E2E_OK|cache=single-parse|duplicates=removed-only|text=editable|batch=20-50|delay_ms=8'
