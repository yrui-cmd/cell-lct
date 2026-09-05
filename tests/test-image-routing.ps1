#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $root 'plugins\cell_gd\skills\cell_gd\scripts'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('cell_gd-routing-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $testScripts = Join-Path $temp 'scripts'
    Copy-Item -LiteralPath $scripts -Destination $testScripts -Recurse
    $image = Join-Path $temp 'original.png'
    [IO.File]::WriteAllBytes($image, [byte[]](137,80,78,71,13,10,26,10,65,66,67))
    $env:CELL_GD_TEST_INPUT = $image
    $env:CELL_GD_TEST_FIXTURE = Join-Path $root 'tests\fixtures\visibility.svg'
    $originalHash = (Get-FileHash $image).Hash
    @'
param($InputImage, $OutputSvg, $EstimatedCredits, [switch]$ApproveHighCost)
if ($InputImage -ne $env:CELL_GD_TEST_INPUT) { throw 'Original image was replaced before recognition.' }
if ((Get-FileHash $InputImage).Hash -ne (Get-FileHash $env:CELL_GD_TEST_INPUT).Hash) { throw 'Input changed.' }
Copy-Item -LiteralPath $env:CELL_GD_TEST_FIXTURE -Destination $OutputSvg
'@ | Set-Content (Join-Path $testScripts 'vectorize-xiaomiao.ps1')
    & (Join-Path $testScripts 'run_from_image.ps1') -InputImage $image -OutputRoot (Join-Path $temp 'ppt') -HostApplication ooxml
    if (@(Get-ChildItem (Join-Path $temp 'ppt') -Recurse -Filter '*.pptx').Count -ne 1) { throw 'No PPTX produced.' }
    & (Join-Path $testScripts 'run_illustrator_from_image.ps1') -InputImage $image -OutputRoot (Join-Path $temp 'ai') -DryRun
    if (@(Get-ChildItem (Join-Path $temp 'ai') -Force -Recurse -Filter 'playback.json').Count -ne 1) { throw 'AI playback state missing.' }
    if ((Get-FileHash $image).Hash -ne $originalHash) { throw 'Original image mutated.' }
    foreach ($svg in @(Get-ChildItem $temp -Recurse -Filter 'shibielujing*.svg')) {
        if ((Get-FileHash $svg.FullName).Hash -ne (Get-FileHash $env:CELL_GD_TEST_FIXTURE).Hash) { throw 'SVG was altered by image wrapper.' }
    }
    # Verify the public selector forwards each explicit app choice.
    foreach ($app in @('ppt', 'ai')) {
        $filename = if ($app -eq 'ppt') { 'run_from_image.ps1' } else { 'run_illustrator_from_image.ps1' }
        $stub = "param(`$InputImage, `$OutputRoot, `$EstimatedCredits, [switch]`$ApproveHighCost)`nWrite-Output '$app'"
        Set-Content (Join-Path $testScripts $filename) $stub
        $result = & (Join-Path $testScripts 'run_cell_gd.ps1') -InputImage $image -OutputRoot $temp -Application $app
        if ($result -ne $app) { throw 'App dispatch mismatch.' }
    }
}
finally {
    Remove-Item $temp -Recurse -Force
    Remove-Item Env:CELL_GD_TEST_INPUT -ErrorAction SilentlyContinue
    Remove-Item Env:CELL_GD_TEST_FIXTURE -ErrorAction SilentlyContinue
}
Write-Output 'IMAGE_ROUTING_OK|original=preserved|ppt=editable|ai=dry-run|dispatch=ppt,ai'
