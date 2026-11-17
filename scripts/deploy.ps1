
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("DEV", "QA")]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $true)]
    [int]$Port
)

$ErrorActionPreference = "Stop"

# =====================================================
# 1. ENVIRONMENT CONFIGURATION
# =====================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$DeployRoot = "C:\Users\veens\Deployment\SalesAnalyticsCICD"

$EnvPath  = Join-Path $DeployRoot $EnvironmentName
$VenvPath = Join-Path $EnvPath ".venv"
$Python   = Join-Path $VenvPath "Scripts\python.exe"

$PidFile = Join-Path $EnvPath "streamlit.pid"

$LogFolder = Join-Path $EnvPath "logs"

$StdOut = Join-Path $LogFolder "streamlit_stdout.log"
$StdErr = Join-Path $LogFolder "streamlit_stderr.log"

$AppAddress = "127.0.0.1"

$ApplicationUrl = "http://localhost:$Port"

Write-Host ""
Write-Host "================================================="
Write-Host " SALES ANALYTICS - $EnvironmentName DEPLOYMENT"
Write-Host "================================================="
Write-Host "Environment : $EnvironmentName"
Write-Host "Port        : $Port"
Write-Host "Location    : $EnvPath"
Write-Host ""

New-Item -ItemType Directory -Force -Path $EnvPath | Out-Null
New-Item -ItemType Directory -Force -Path $LogFolder | Out-Null


# =====================================================
# 2. COPY ENVIRONMENT CONFIGURATION
# =====================================================

Write-Host "[1/8] Preparing environment configuration..."

$SourceEnv = @(
    "$ProjectRoot\$EnvironmentName\.env",
    "C:\Users\veens\Python_Projects\SalesAnalyticsCICD\$EnvironmentName\.env"
) |
Where-Object { Test-Path $_ } |
Select-Object -First 1

if ($SourceEnv) {

    Copy-Item $SourceEnv "$EnvPath\.env" -Force

    Write-Host "Environment configuration copied."

}
elseif (-not (Test-Path "$EnvPath\.env")) {

    throw "No .env file found for $EnvironmentName."

}
else {

    Write-Host "Using existing environment configuration."

}


# =====================================================
# 3. IDENTIFY LATEST BUILD ARTIFACT
# =====================================================

Write-Host "[2/8] Identifying latest wheel artifact..."

$ArtifactFolder = Join-Path $DeployRoot "artifacts"

$ArtifactWheel = Get-ChildItem `
    -Path $ArtifactFolder `
    -Filter "sales_analytics-*.whl" `
    -File |
Sort-Object LastWriteTime -Descending |
Select-Object -First 1

if (-not $ArtifactWheel) {

    throw "No sales_analytics wheel found in $ArtifactFolder"

}

Write-Host "Artifact: $($ArtifactWheel.Name)"

# Remove previous wheel from environment folder

Get-ChildItem $EnvPath -Filter "sales_analytics-*.whl" -File |
Remove-Item -Force

# Copy latest wheel

Copy-Item $ArtifactWheel.FullName $EnvPath -Force

$DeployedWheel = Join-Path $EnvPath $ArtifactWheel.Name


# =====================================================
# 4. CREATE VIRTUAL ENVIRONMENT
# =====================================================

Write-Host "[3/8] Checking Python virtual environment..."

if (-not (Test-Path $Python)) {

    Write-Host "Creating Python 3.11 virtual environment..."

    py -3.11 -m venv $VenvPath

    if ($LASTEXITCODE -ne 0) {

        throw "Virtual environment creation failed."

    }

}

if (-not (Test-Path $Python)) {

    throw "Python executable not found: $Python"

}

Write-Host "Python environment ready."


# =====================================================
# 5. STOP EXISTING APPLICATION
# =====================================================

Write-Host "[4/8] Stopping existing application..."

if (Test-Path $PidFile) {

    $OldPidText = (Get-Content $PidFile -Raw).Trim()

    $OldPidValue = 0

    if ([int]::TryParse($OldPidText, [ref]$OldPidValue)) {

        $OldProcess = Get-Process `
            -Id $OldPidValue `
            -ErrorAction SilentlyContinue

        if ($OldProcess) {

            Write-Host "Stopping previous Streamlit process: $OldPidValue"

            Stop-Process -Id $OldPidValue -Force

            Wait-Process -Id $OldPidValue `
                -Timeout 10 `
                -ErrorAction SilentlyContinue

        }

    }

    Remove-Item $PidFile -Force

}

# Ensure the deployment port is freed if an older process is still listening
$PortOwner = Get-NetTCPConnection `
    -LocalPort $Port `
    -State Listen `
    -ErrorAction SilentlyContinue

if ($PortOwner) {
    $PortOwner | ForEach-Object {
        Write-Host "Stopping process $($_.OwningProcess) occupying port $Port..."
        Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

Write-Host "Previous application stopped."


# =====================================================
# 6. INSTALL APPLICATION PACKAGE
# =====================================================

Write-Host "[5/8] Installing application package..."

& $Python -m pip install --upgrade pip

if ($LASTEXITCODE -ne 0) {

    throw "Pip upgrade failed."

}

# Install latest wheel and dependencies

& $Python -m pip install --force-reinstall $DeployedWheel

if ($LASTEXITCODE -ne 0) {

    throw "Application installation failed."

}

# Verify Streamlit

& $Python -m pip show streamlit

if ($LASTEXITCODE -ne 0) {

    throw "Streamlit is not installed."

}

Write-Host "Application package installed successfully."


# =====================================================
# 7. START STREAMLIT APPLICATION
# =====================================================

Write-Host "[6/8] Starting Streamlit application..."

$InstalledApp = Join-Path `
    $VenvPath `
    "Lib\site-packages\sales_analytics\app.py"

if (-not (Test-Path $InstalledApp)) {

    throw "Installed application not found: $InstalledApp"

}

# Clear old logs

Remove-Item $StdOut, $StdErr `
    -Force `
    -ErrorAction SilentlyContinue

# Start Streamlit detached from the GitHub Actions Runner job object
# so the runner does not kill Streamlit when the workflow step finishes.
$env:RUNNER_TRACKING_ID = $null

$CommandLine = "`"$Python`" -m streamlit run `"$InstalledApp`" --server.address $AppAddress --server.port $Port --server.headless true --browser.gatherUsageStats false"

$WmiResult = Invoke-CimMethod `
    -ClassName Win32_Process `
    -MethodName Create `
    -Arguments @{
        CommandLine      = $CommandLine
        CurrentDirectory = $EnvPath
    }

if ($WmiResult.ReturnValue -ne 0 -or -not $WmiResult.ProcessId) {
    throw "Unable to start Streamlit (WMI return code: $($WmiResult.ReturnValue))."
}

$ProcessId = [int]$WmiResult.ProcessId

# Save PID
Set-Content -Path $PidFile -Value $ProcessId

Write-Host "Streamlit started."
Write-Host "Process ID: $ProcessId"


# =====================================================
# 8. VERIFY APPLICATION HEALTH
# =====================================================

Write-Host "[7/8] Checking application health..."

$MaxAttempts = 30

$ApplicationReady = $false

for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {

    Start-Sleep -Seconds 2

    $RunningProcess = Get-Process `
        -Id $ProcessId `
        -ErrorAction SilentlyContinue

    if (-not $RunningProcess) {

        break

    }

    try {

        $Response = Invoke-WebRequest `
            -Uri "http://$AppAddress`:$Port/_stcore/health" `
            -UseBasicParsing `
            -TimeoutSec 2

        if ($Response.StatusCode -eq 200) {

            $ApplicationReady = $true

            break

        }

    }
    catch {

        # Wait for Streamlit startup.

    }

    Write-Host "Waiting for application... $Attempt/$MaxAttempts"

}

if (-not $ApplicationReady) {

    Stop-Process -Id $ProcessId -Force `
        -ErrorAction SilentlyContinue

    Remove-Item $PidFile -Force `
        -ErrorAction SilentlyContinue

    Write-Host "Application startup failed."

    throw "Streamlit health check failed."

}


# =====================================================
# 9. OPEN APPLICATION IN BROWSER
# =====================================================

Write-Host "[8/8] Opening application in browser..."

Write-Host ""
Write-Host "================================================="
Write-Host " DEPLOYMENT SUCCESSFUL"
Write-Host "================================================="

Write-Host "Environment : $EnvironmentName"
Write-Host "URL         : $ApplicationUrl"
Write-Host "Process ID  : $ProcessId"
Write-Host "PID File    : $PidFile"
Write-Host "Logs        : $LogFolder"

# Open default Windows browser

Start-Process -FilePath $ApplicationUrl

Write-Host ""
Write-Host "$EnvironmentName application opened in browser."

Write-Host "================================================="
