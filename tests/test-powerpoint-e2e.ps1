#requires -Version 5.1

[CmdletBinding()]
param([switch]$ConfirmDisposablePresentation)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmDisposablePresentation) { throw 'Pass -ConfirmDisposablePresentation to run the live PowerPoint test.' }
if (@(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Close all user PowerPoint windows before running the disposable live test.' }

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$skillRoot = Join-Path $repoRoot 'plugins\cell_gd\skills\cell_gd'
$tempBase = Join-Path $repoRoot '.test-tmp'
$tempRoot = Join-Path $tempBase ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$application = $null
$presentation = $null
try {
    $cacheRoot = Join-Path $tempRoot 'cache'
    py -3 -X utf8 (Join-Path $skillRoot 'scripts\prepare_geometry_cache.py') --input (Join-Path $PSScriptRoot 'fixtures\visibility.svg') --output-dir $cacheRoot --job-id powerpoint-e2e | Out-Null
    py -3 -X utf8 (Join-Path $skillRoot 'scripts\cull_hidden_geometry.py') --cache (Join-Path $cacheRoot 'geometry-cache.json') --state (Join-Path $cacheRoot 'drawing-state.json') | Out-Null

    $application = New-Object -ComObject PowerPoint.Application
    $application.Visible = -1
    $presentation = $application.Presentations.Add(-1)
    $slide = $presentation.Slides.Add(1, 12)
    $sentinel = $slide.Shapes.AddShape(1, 5, 5, 10, 10)
    $sentinel.Name = 'CELL_PPT_PREEXISTING_SENTINEL'
    $output = Join-Path $tempRoot 'powerpoint-e2e.pptx'
    & (Join-Path $skillRoot 'scripts\run_cell_ppt.ps1') -GeometryCache (Join-Path $cacheRoot 'geometry-cache.json') -OutputPptx $output -HostApplication powerpoint -UseActivePresentation -StepDelayMs 0
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw 'PowerPoint runtime did not save the PPTX.' }
    $saved = $application.ActivePresentation
    $savedSlide = $saved.Slides.Item(1)
    if ($savedSlide.Shapes.Item('CELL_PPT_PREEXISTING_SENTINEL').Name -ne 'CELL_PPT_PREEXISTING_SENTINEL') { throw 'Pre-existing object was changed.' }
    $saved.Close()
    $presentation = $null
    $application.Quit()
    $application = $null

    py -3 -X utf8 -c "from pptx import Presentation; p=Presentation(r'$output'); assert len(p.slides)==1; assert any(s.name=='CELL_PPT_PREEXISTING_SENTINEL' for s in p.slides[0].shapes); assert not any(s.shape_type==13 for s in p.slides[0].shapes); print('PPTX_REOPEN_OK')" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Saved PPTX did not pass reopen/editability checks.' }
}
finally {
    if ($presentation) { try { $presentation.Close() } catch {} }
    if ($application) { try { $application.Quit() } catch {} }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    if (Test-Path -LiteralPath $tempBase) {
        $checked = [IO.Path]::GetFullPath($tempBase)
        if (-not $checked.StartsWith($repoRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a directory outside the project.' }
        Remove-Item -LiteralPath $checked -Recurse -Force
    }
}

Write-Output 'POWERPOINT_E2E_OK|native=true|preexisting=preserved|raster=false|reopen=true'
