param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("DEV", "QA")]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $true)]
    [int]$Port
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DeployRoot  = "C:\Users\veens\Deployment\SalesAnalyticsCICD"
$EnvPath     = "$DeployRoot\$EnvironmentName"
$VenvPath    = "$EnvPath\.venv"
$Python      = "$VenvPath\Scripts\python.exe"
$PidFile     = "$EnvPath\streamlit.pid"

Write-Host "Deploying to $EnvironmentName ($EnvPath) on port $Port..."
New-Item -ItemType Directory -Force -Path $EnvPath | Out-Null

# 1. Copy .env and built .whl artifact (no .py files in deployment folder)
Copy-Item "$ProjectRoot\$EnvironmentName\.env" "$EnvPath\.env" -Force
Remove-Item "$EnvPath\*.py" -Force -ErrorAction SilentlyContinue

$ArtifactWheel = Get-ChildItem "$DeployRoot\artifacts\sales_analytics-*.whl" | Select-Object -First 1
if (-not $ArtifactWheel) {
    throw "Built wheel not found in $DeployRoot\artifacts"
}
Copy-Item $ArtifactWheel.FullName $EnvPath -Force
$DeployedWheel = Join-Path $EnvPath $ArtifactWheel.Name

# 2. Create separate .venv for this environment if needed
if (-not (Test-Path $Python)) {
    Write-Host "Creating virtual environment for $EnvironmentName..."
    py -3.11 -m venv $VenvPath
}

# 3. Stop existing running instance if any
if (Test-Path $PidFile) {
    $OldPid = (Get-Content $PidFile -Raw).Trim()
    Stop-Process -Id ([int]$OldPid) -Force -ErrorAction SilentlyContinue
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

# 4. Install dependencies & latest wheel into environment .venv
& $Python -m pip install $DeployedWheel
& $Python -m pip install --no-deps --force-reinstall $DeployedWheel

# 5. Start Streamlit from the installed package inside .venv
$InstalledApp = "$VenvPath\Lib\site-packages\sales_analytics\app.py"
$Process = Start-Process -FilePath $Python `
    -ArgumentList "-m", "streamlit", "run", $InstalledApp, "--server.port", "$Port", "--server.headless", "true" `
    -WorkingDirectory $EnvPath `
    -PassThru

Set-Content -Path $PidFile -Value $Process.Id
Write-Host "$EnvironmentName deployed successfully at http://localhost:$Port (PID: $($Process.Id))"
