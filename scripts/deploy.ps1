param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("DEV", "QA")]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,

    [Parameter(Mandatory = $true)]
    [int]$Port
)

$ErrorActionPreference = "Stop"

$DeployRoot = if ($env:SALES_DEPLOY_ROOT) {
    $env:SALES_DEPLOY_ROOT
} else {
    "C:\users\veens\Deployment\SalesAnalyticsCICD"
}

$EnvironmentPath = Join-Path $DeployRoot $EnvironmentName
$StagePath = Join-Path $EnvironmentPath "_staging"
$LogPath = Join-Path $EnvironmentPath "logs"
$PidFile = Join-Path $EnvironmentPath "streamlit.pid"
$PythonPath = Join-Path $EnvironmentPath ".venv\Scripts\python.exe"

if (-not (Test-Path $ArtifactPath)) {
    throw "Artifact not found: $ArtifactPath"
}
if (-not (Test-Path (Join-Path $EnvironmentPath ".env"))) {
    throw "Missing environment configuration: $EnvironmentPath\.env"
}

New-Item -ItemType Directory -Force -Path $EnvironmentPath, $LogPath | Out-Null
if (Test-Path $StagePath) {
    Remove-Item $StagePath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StagePath | Out-Null
Expand-Archive -Path $ArtifactPath -DestinationPath $StagePath -Force

if (-not (Test-Path $PythonPath)) {
    py -3.11 -m venv (Join-Path $EnvironmentPath ".venv")
}
if (-not (Test-Path $PythonPath)) {
    throw "Python 3.11 virtual environment could not be created."
}

if (Test-Path $PidFile) {
    $OldPid = Get-Content $PidFile
    if ($OldPid) {
        $OldProcess = Get-Process -Id ([int]$OldPid) -ErrorAction SilentlyContinue
        if ($OldProcess) {
            Stop-Process -Id ([int]$OldPid) -Force
            Start-Sleep -Seconds 2
        }
    }
    Remove-Item $PidFile -Force
}

$WheelsPath = Join-Path $StagePath "wheels"
$RuntimeRequirements = Join-Path $StagePath "requirements-runtime.txt"
& $PythonPath -m pip install --no-index --find-links $WheelsPath -r $RuntimeRequirements

$BusinessWheel = Get-ChildItem $WheelsPath -Filter "sales_analytics-*.whl" |
    Select-Object -First 1
if (-not $BusinessWheel) {
    throw "Business package wheel was not found in the artifact."
}
& $PythonPath -m pip install --no-index --no-deps --force-reinstall $BusinessWheel.FullName

Copy-Item (Join-Path $StagePath "app.py") $EnvironmentPath -Force
Copy-Item (Join-Path $StagePath "build-info.txt") $EnvironmentPath -Force

$StdOut = Join-Path $LogPath "streamlit-stdout.log"
$StdErr = Join-Path $LogPath "streamlit-stderr.log"
$Process = Start-Process -FilePath $PythonPath `
    -ArgumentList @("-m", "streamlit", "run", (Join-Path $EnvironmentPath "app.py"),
                    "--server.port", "$Port", "--server.headless", "true") `
    -WorkingDirectory $EnvironmentPath `
    -RedirectStandardOutput $StdOut `
    -RedirectStandardError $StdErr `
    -PassThru

Set-Content -Path $PidFile -Value $Process.Id
Write-Host "$EnvironmentName deployment started. PID=$($Process.Id), port=$Port"
Write-Host "URL: http://localhost:$Port"
Write-Host "Build information:"
Get-Content (Join-Path $EnvironmentPath "build-info.txt")
