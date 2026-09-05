#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GeometryCache,

    [Parameter(Mandatory = $true)]
    [string]$OutputPptx,

    [ValidateSet('auto', 'powerpoint', 'wps')]
    [string]$HostApplication = 'auto',

    [switch]$UseActivePresentation,

    [switch]$Foreground,

    [ValidateRange(0, 10000)]
    [int]$StepDelayMs = 8,

    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

function Get-OfficeRgb([int[]]$Rgb) {
    return [int]($Rgb[0] + (256 * $Rgb[1]) + (65536 * $Rgb[2]))
}

function Test-SamePoint($A, $B) {
    return ([math]::Abs([double]$A[0] - [double]$B[0]) -lt 0.000001) -and
        ([math]::Abs([double]$A[1] - [double]$B[1]) -lt 0.000001)
}

function Open-PresentationHost([string]$RequestedHost) {
    $candidates = if ($RequestedHost -eq 'powerpoint') {
        @([pscustomobject]@{ Name = 'powerpoint'; ProgId = 'PowerPoint.Application' })
    }
    elseif ($RequestedHost -eq 'wps') {
        @(
            [pscustomobject]@{ Name = 'wps'; ProgId = 'KWPP.Application' },
            [pscustomobject]@{ Name = 'wps'; ProgId = 'WPP.Application' }
        )
    }
    else {
        @(
            [pscustomobject]@{ Name = 'powerpoint'; ProgId = 'PowerPoint.Application' },
            [pscustomobject]@{ Name = 'wps'; ProgId = 'KWPP.Application' },
            [pscustomobject]@{ Name = 'wps'; ProgId = 'WPP.Application' }
        )
    }

    foreach ($candidate in $candidates) {
        try {
            $application = New-Object -ComObject $candidate.ProgId
            return [pscustomobject]@{ Name = $candidate.Name; Application = $application }
        }
        catch {
            continue
        }
    }
    throw "Neither Microsoft PowerPoint nor WPS Presentation automation is available."
}

function Map-Point($Point, [double]$Scale, [double]$OffsetX, [double]$OffsetY, [double]$ViewX, [double]$ViewY) {
    $mappedX = $OffsetX + (([double]$Point[0] - $ViewX) * $Scale)
    $mappedY = $OffsetY + (([double]$Point[1] - $ViewY) * $Scale)
    return [double[]]@($mappedX, $mappedY)
}

function Show-ObjectStep($Application, $Slide, [bool]$BringForward, [int]$DelayMs) {
    # Foreground activation happens once before playback. Re-navigating the
    # active slide after every object can make PowerPoint reject COM calls.
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

$cachePath = (Resolve-Path -LiteralPath $GeometryCache).Path
$outputPath = [IO.Path]::GetFullPath($OutputPptx)
if ([IO.Path]::GetExtension($outputPath) -ne '.pptx') {
    throw 'OutputPptx must use the .pptx extension.'
}
if ((Test-Path -LiteralPath $outputPath) -and -not $Overwrite) {
    throw "Output already exists: $outputPath. Use -Overwrite to replace it."
}
$outputDirectory = Split-Path -Parent $outputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$cache = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$cache.schema_version -ne 3) {
    throw "Unsupported geometry cache schema: $($cache.schema_version)"
}
if ($cache.atoms.Count -lt 1) {
    throw 'Geometry cache contains no atoms.'
}

$hostInfo = Open-PresentationHost $HostApplication
$application = $hostInfo.Application
$presentation = $null
$createdPresentation = $false
try {
    $application.Visible = -1
    if ($UseActivePresentation -and $application.Presentations.Count -gt 0) {
        $presentation = $application.ActivePresentation
    }
    else {
        $presentation = $application.Presentations.Add(-1)
        $createdPresentation = $true
    }

    if ($presentation.Slides.Count -eq 0) {
        $slide = $presentation.Slides.Add(1, 12)
    }
    elseif ($UseActivePresentation) {
        try { $slide = $application.ActiveWindow.View.Slide } catch { $slide = $presentation.Slides.Item($presentation.Slides.Count) }
    }
    else {
        $slide = $presentation.Slides.Item(1)
    }

    if ($Foreground) {
        try { $application.Activate() } catch {}
        try { $application.ActiveWindow.Activate() } catch {}
    }

    $slideWidth = [double]$presentation.PageSetup.SlideWidth
    $slideHeight = [double]$presentation.PageSetup.SlideHeight
    $viewBox = @($cache.view_box)
    $viewX = [double]$viewBox[0]
    $viewY = [double]$viewBox[1]
    $viewWidth = [double]$viewBox[2]
    $viewHeight = [double]$viewBox[3]
    $margin = 18.0
    $scale = [math]::Min(($slideWidth - (2 * $margin)) / $viewWidth, ($slideHeight - (2 * $margin)) / $viewHeight)
    $offsetX = ($slideWidth - ($viewWidth * $scale)) / 2.0
    $offsetY = ($slideHeight - ($viewHeight * $scale)) / 2.0
    $createdNames = New-Object System.Collections.Generic.List[string]
    $existingNames = @{}
    for ($shapeIndex = 1; $shapeIndex -le $slide.Shapes.Count; $shapeIndex++) {
        try { $existingNames[[string]$slide.Shapes.Item($shapeIndex).Name] = $true } catch {}
    }

    foreach ($batch in $cache.batches) {
        foreach ($atomIndex in $batch.atom_indices) {
            $atom = $cache.atoms[[int]$atomIndex]
            if ($atom.kind -eq 'text') {
                if ($existingNames.ContainsKey([string]$atom.objectName)) {
                    $createdNames.Add([string]$atom.objectName)
                    continue
                }
                $text = $atom.text
                $position = Map-Point $text.position $scale $offsetX $offsetY $viewX $viewY
                $fontSize = [math]::Max(4.0, [double]$text.fontSize * $scale)
                $boxWidth = [math]::Max($fontSize * 2.0, $fontSize * ([string]$text.contents).Length * 0.7)
                $boxHeight = $fontSize * 1.5
                $left = [double]$position[0]
                if ($text.textAnchor -eq 'middle') { $left -= $boxWidth / 2.0 }
                elseif ($text.textAnchor -eq 'end') { $left -= $boxWidth }
                $top = [double]$position[1] - ($fontSize * 1.05)
                $shape = $slide.Shapes.AddTextbox(1, [single]$left, [single]$top, [single]$boxWidth, [single]$boxHeight)
                $shape.Name = [string]$atom.objectName
                $shape.Line.Visible = 0
                $shape.Fill.Visible = 0
                $shape.TextFrame2.MarginLeft = 0
                $shape.TextFrame2.MarginRight = 0
                $shape.TextFrame2.MarginTop = 0
                $shape.TextFrame2.MarginBottom = 0
                $shape.TextFrame2.WordWrap = 0
                $shape.TextFrame2.TextRange.Text = [string]$text.contents
                $shape.TextFrame2.TextRange.Font.Name = [string]$text.fontFamily
                $shape.TextFrame2.TextRange.Font.Size = [single]$fontSize
                $shape.TextFrame2.TextRange.Font.Bold = if ([string]$text.fontWeight -match 'bold|[6-9]00') { -1 } else { 0 }
                $shape.TextFrame2.TextRange.Font.Italic = if ([string]$text.fontStyle -eq 'italic') { -1 } else { 0 }
                $shape.TextFrame2.TextRange.Font.Fill.ForeColor.RGB = Get-OfficeRgb @($text.fillColor)
                $shape.TextFrame2.TextRange.Font.Fill.Transparency = [single](1.0 - ([double]$text.opacity / 100.0))
                $shape.Rotation = [single]$text.rotationDegrees
                $shape.ZOrder(0)
                $createdNames.Add([string]$shape.Name)
                Show-ObjectStep $application $slide ([bool]$Foreground) $StepDelayMs
            }
            elseif ($atom.kind -eq 'path') {
                $partIndex = 0
                foreach ($subpath in $atom.subpaths) {
                    if ($subpath.points.Count -lt 2) { continue }
                    $shapeName = "{0}_PART_{1:D3}" -f [string]$atom.objectName, $partIndex
                    if ($existingNames.ContainsKey($shapeName)) {
                        $shape = $slide.Shapes.Item($shapeName)
                    }
                    else {
                        $first = $subpath.points[0]
                        $firstAnchor = Map-Point $first.a $scale $offsetX $offsetY $viewX $viewY
                        $builder = $slide.Shapes.BuildFreeform(1, [single]$firstAnchor[0], [single]$firstAnchor[1])
                        for ($pointIndex = 1; $pointIndex -lt $subpath.points.Count; $pointIndex++) {
                            $previous = $subpath.points[$pointIndex - 1]
                            $current = $subpath.points[$pointIndex]
                            $end = Map-Point $current.a $scale $offsetX $offsetY $viewX $viewY
                            if ((Test-SamePoint $previous.r $previous.a) -and (Test-SamePoint $current.l $current.a)) {
                                $builder.AddNodes(0, 1, [single]$end[0], [single]$end[1])
                            }
                            else {
                                $control1 = Map-Point $previous.r $scale $offsetX $offsetY $viewX $viewY
                                $control2 = Map-Point $current.l $scale $offsetX $offsetY $viewX $viewY
                                $builder.AddNodes(1, 1, [single]$control1[0], [single]$control1[1], [single]$control2[0], [single]$control2[1], [single]$end[0], [single]$end[1])
                            }
                        }
                        if ($subpath.closed) {
                            $previous = $subpath.points[$subpath.points.Count - 1]
                            $current = $first
                            if ((Test-SamePoint $previous.r $previous.a) -and (Test-SamePoint $current.l $current.a)) {
                                $builder.AddNodes(0, 1, [single]$firstAnchor[0], [single]$firstAnchor[1])
                            }
                            else {
                                $control1 = Map-Point $previous.r $scale $offsetX $offsetY $viewX $viewY
                                $control2 = Map-Point $current.l $scale $offsetX $offsetY $viewX $viewY
                                $builder.AddNodes(1, 1, [single]$control1[0], [single]$control1[1], [single]$control2[0], [single]$control2[1], [single]$firstAnchor[0], [single]$firstAnchor[1])
                            }
                        }
                        $shape = $builder.ConvertToShape()
                        $shape.Name = $shapeName
                        $existingNames[$shapeName] = $true
                    }
                    $paint = $atom.paintParts[[math]::Min($partIndex, $atom.paintParts.Count - 1)]
                    if ($paint.filled -and $subpath.closed) {
                        $shape.Fill.Visible = -1
                        $shape.Fill.Solid()
                        $shape.Fill.ForeColor.RGB = Get-OfficeRgb @($paint.fillColor)
                        $shape.Fill.Transparency = [single](1.0 - ([double]$paint.opacity / 100.0))
                    }
                    else {
                        $shape.Fill.Visible = 0
                    }
                    if ($paint.stroked) {
                        $shape.Line.Visible = -1
                        $shape.Line.ForeColor.RGB = Get-OfficeRgb @($paint.strokeColor)
                        $shape.Line.Weight = [single]([math]::Max(0.25, [double]$paint.strokeWidth * $scale))
                        $shape.Line.Transparency = [single](1.0 - ([double]$paint.opacity / 100.0))
                    }
                    else {
                        $shape.Line.Visible = 0
                    }
                    $shape.ZOrder(0)
                    $createdNames.Add([string]$shape.Name)
                    $partIndex++
                    Show-ObjectStep $application $slide ([bool]$Foreground) $StepDelayMs
                }
            }
        }
    }

    if ((Test-Path -LiteralPath $outputPath) -and $Overwrite) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    $presentation.SaveAs($outputPath, 24)
    [pscustomobject][ordered]@{
        ok = $true
        host_application = $hostInfo.Name
        output_pptx = $outputPath
        slide_index = $slide.SlideIndex
        native_object_count = $createdNames.Count
        source_atom_count = $cache.total_atoms
        used_active_presentation = [bool]$UseActivePresentation
    } | ConvertTo-Json -Compress
}
catch {
    if ($createdPresentation -and $null -ne $presentation) {
        try { $presentation.Close() } catch {}
    }
    throw
}
finally {
    if ($null -ne $presentation) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) }
    if ($null -ne $application) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($application) }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
