
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

# =====================================================
# 1. ENVIRONMENT CONFIGURATION
# =====================================================

$DeployRoot = if ($env:SALES_DEPLOY_ROOT) {
    $env:SALES_DEPLOY_ROOT
} else {
    "C:\users\veens\Deployment\SalesAnalyticsCICD"
}

$EnvironmentKey = $EnvironmentName.ToLowerInvariant()

# DEV and QA have separate folders and virtual environments
$EnvironmentPath = Join-Path $DeployRoot "environments\$EnvironmentKey"

$StagePath = Join-Path $EnvironmentPath "_staging"
$LogPath = Join-Path $EnvironmentPath "logs"

$VenvPath = Join-Path $EnvironmentPath ".venv"
$PythonPath = Join-Path $VenvPath "Scripts\python.exe"

$EnvFile = Join-Path $EnvironmentPath ".env"
$PidFile = Join-Path $EnvironmentPath "streamlit.pid"

Write-Host "========================================="
Write-Host "Starting $EnvironmentName deployment"
Write-Host "========================================="

Write-Host "Environment path: $EnvironmentPath"
Write-Host "Virtual environment: $VenvPath"
Write-Host "Port: $Port"

# =====================================================
# 2. VALIDATE INPUTS AND CONFIGURATION
# =====================================================

if (-not (Test-Path $ArtifactPath)) {
    throw "Artifact not found: $ArtifactPath"
}

if (-not (Test-Path $EnvFile)) {
    throw "Missing environment configuration: $EnvFile"
}

New-Item -ItemType Directory -Force -Path $EnvironmentPath, $LogPath | Out-Null

# =====================================================
# 3. EXTRACT DEPLOYMENT ARTIFACT
# =====================================================

if (Test-Path $StagePath) {
    Remove-Item $StagePath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $StagePath | Out-Null

Expand-Archive -Path $ArtifactPath -DestinationPath $StagePath -Force

$WheelsPath = Join-Path $StagePath "wheels"
$RuntimeRequirements = Join-Path $StagePath "requirements-runtime.txt"

if (!(Test-Path $WheelsPath)) {
    throw "Wheels directory missing in deployment artifact."
}

if (!(Test-Path $RuntimeRequirements)) {
    throw "Runtime requirements file missing."
}

if (!(Test-Path (Join-Path $StagePath "app.py"))) {
    throw "Application entry point app.py missing."
}

# =====================================================
# 4. CREATE ENVIRONMENT-SPECIFIC VIRTUAL ENVIRONMENT
# =====================================================

if (!(Test-Path $PythonPath)) {

    Write-Host "Creating $EnvironmentName virtual environment..."

    py -3.11 -m venv $VenvPath

    if ($LASTEXITCODE -ne 0) {
        throw "Virtual environment creation failed."
    }
}

if (!(Test-Path $PythonPath)) {
    throw "Python virtual environment could not be created."
}

& $PythonPath --version

# =====================================================
# 5. STOP EXISTING STREAMLIT PROCESS
# =====================================================

if (Test-Path $PidFile) {

    $OldPid = Get-Content $PidFile -Raw

    if ($OldPid -match '^\s*\d+\s*$') {

        $OldProcess = Get-Process -Id ([int]$OldPid.Trim()) `
            -ErrorAction SilentlyContinue

        if ($OldProcess) {

            Write-Host "Stopping existing $EnvironmentName application..."

            Stop-Process -Id ([int]$OldPid.Trim()) -Force

            Start-Sleep -Seconds 2
        }
    }

    Remove-Item $PidFile -Force
}

# =====================================================
# 6. INSTALL RUNTIME DEPENDENCIES OFFLINE
# =====================================================

Write-Host "Installing runtime dependencies for $EnvironmentName..."

& $PythonPath -m pip install `
    --no-index `
    --find-links $WheelsPath `
    -r $RuntimeRequirements

if ($LASTEXITCODE -ne 0) {
    throw "Runtime dependency installation failed."
}

# =====================================================
# 7. INSTALL BUSINESS PACKAGE
# =====================================================

$BusinessWheel = Get-ChildItem $WheelsPath -Filter "sales_analytics-*.whl" |
    Select-Object -First 1

if (-not $BusinessWheel) {
    throw "Business package wheel was not found in artifact."
}

& $PythonPath -m pip install `
    --no-index `
    --no-deps `
    --force-reinstall `
    $BusinessWheel.FullName

if ($LASTEXITCODE -ne 0) {
    throw "Business package installation failed."
}

# =====================================================
# 8. COPY APPLICATION FILES
# =====================================================

Copy-Item (Join-Path $StagePath "app.py") $EnvironmentPath -Force

Copy-Item (Join-Path $StagePath "build-info.txt") $EnvironmentPath -Force

# =====================================================
# 9. CONFIGURE APPLICATION ENVIRONMENT
# =====================================================

$env:APP_ENV = $EnvironmentKey

# The application should load the .env file from its
# current working directory.

# =====================================================
# 10. START STREAMLIT APPLICATION
# =====================================================

$StdOut = Join-Path $LogPath "streamlit-stdout.log"
$StdErr = Join-Path $LogPath "streamlit-stderr.log"

Write-Host "Starting Streamlit for $EnvironmentName..."

$Process = Start-Process -FilePath $PythonPath `
    -ArgumentList @(
        "-m",
        "streamlit",
        "run",
        (Join-Path $EnvironmentPath "app.py"),
        "--server.port",
        "$Port",
        "--server.headless",
        "true"
    ) `
    -WorkingDirectory $EnvironmentPath `
    -RedirectStandardOutput $StdOut `
    -RedirectStandardError $StdErr `
    -PassThru

Start-Sleep -Seconds 3

$Process.Refresh()

if ($Process.HasExited) {
    Write-Host "Streamlit failed to start. Check logs:"
    Get-Content $StdErr -ErrorAction SilentlyContinue
    throw "Streamlit process exited during startup."
}

Set-Content -Path $PidFile -Value $Process.Id

# =====================================================
# 11. DEPLOYMENT SUMMARY
# =====================================================

Write-Host "========================================="
Write-Host "$EnvironmentName deployment started"
Write-Host "========================================="

Write-Host "PID: $($Process.Id)"
Write-Host "Port: $Port"
Write-Host "URL: http://localhost:$Port"
Write-Host "Python: $PythonPath"
Write-Host "Environment: $env:APP_ENV"

Write-Host "Build information:"

Get-Content (Join-Path $EnvironmentPath "build-info.txt")
