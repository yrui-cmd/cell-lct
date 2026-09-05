#requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$ConfigureKeyFromStdin
)

$ErrorActionPreference = 'Stop'
$pendingKey = $null
if ($ConfigureKeyFromStdin) {
    $pendingKey = [Console]::In.ReadLine()
    if ([string]::IsNullOrWhiteSpace($pendingKey)) { throw 'No API key was received on standard input.' }
}
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$requirements = Join-Path $projectRoot 'requirements.lock'
$installer = Join-Path $projectRoot 'install.ps1'
$doctor = Join-Path $projectRoot 'doctor.ps1'
foreach ($required in @($requirements, $installer, $doctor)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing setup component: $required" }
}

$pythonCommand = Get-Command py -ErrorAction SilentlyContinue
$pythonPrefix = @('-3', '-X', 'utf8')
if (-not $pythonCommand) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    $pythonPrefix = @('-X', 'utf8')
}
if (-not $pythonCommand) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & $winget.Source install --id Python.Python.3.12 --exact --scope user --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { throw 'Automatic Python installation failed.' }
        $candidate = Get-ChildItem -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Python') -Filter python.exe -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($candidate) {
            $pythonExe = $candidate.FullName
            $pythonPrefix = @('-X', 'utf8')
        }
    }
}
if (-not $pythonExe) {
    if (-not $pythonCommand) { throw 'Python 3.11-3.14 was not found and no automatic package installer was available.' }
    $pythonExe = $pythonCommand.Source
}
& $pythonExe @pythonPrefix -c "import sys; assert (3,11) <= sys.version_info[:2] < (3,15)" | Out-Null
if ($LASTEXITCODE -ne 0) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { throw 'The available Python version is incompatible and no automatic package installer was found.' }
    & $winget.Source install --id Python.Python.3.12 --exact --scope user --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw 'Automatic compatible Python installation failed.' }
    $candidate = Get-ChildItem -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Python') -Filter python.exe -Recurse -File -ErrorAction SilentlyContinue | Where-Object FullName -Match 'Python312' | Select-Object -First 1
    if (-not $candidate) { throw 'Python 3.12 was installed but its executable could not be located.' }
    $pythonExe = $candidate.FullName
    $pythonPrefix = @('-X', 'utf8')
}

& $pythonExe @pythonPrefix -m pip install --disable-pip-version-check --requirement $requirements
if ($LASTEXITCODE -ne 0) { throw 'Locked Python dependency installation failed.' }

& $installer -Force:$Force
$installedSkill = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\skills\cell_gd'
$profile = Join-Path $installedSkill 'runtime-profile.json'
& $pythonExe @pythonPrefix (Join-Path $installedSkill 'scripts\configure_runtime.py') --output $profile
if ($LASTEXITCODE -ne 0) { throw 'Automatic runtime matching failed.' }

$keyConfigured = $false
if ($ConfigureKeyFromStdin) {
    $setter = Join-Path $installedSkill 'scripts\set-xiaomiao-key.ps1'
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Process -Id $PID).Path
    $start.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$setter`" -FromStdin"
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    try {
        $process = [Diagnostics.Process]::Start($start)
        $process.StandardInput.WriteLine($pendingKey)
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEnd()
        $errors = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
    }
    finally { $pendingKey = $null }
    if ($process.ExitCode -ne 0) { throw "API-key configuration failed: $errors" }
    if ($output -notmatch 'KEY_CONFIG_OK') { throw 'API-key configuration did not return success.' }
    $verification = & (Join-Path $installedSkill 'scripts\xiaomiao.ps1') verify
    if ($verification.authenticated -ne $true) { throw 'API-key authentication verification failed.' }
    $keyConfigured = $true
}
elseif (Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\secrets\xiaomiao-api-key.dpapi')) {
    try {
        $verification = & (Join-Path $installedSkill 'scripts\xiaomiao.ps1') verify
        $keyConfigured = $verification.authenticated -eq $true
    }
    catch { $keyConfigured = $false }
}

& $doctor -VerifyApi:$keyConfigured
Write-Output "SETUP_OK|skill=cell_gd|platform=windows|runtime_matched=true|api_key_configured=$($keyConfigured.ToString().ToLowerInvariant())|restart_codex=true"
