<#
.SYNOPSIS
    Installs every .vip file found in C:\vipm\packages into the image's LabVIEW.
    Runs INSIDE the Docker build container (Windows Server Core).

.NOTES
    Windows counterpart of ../labview-vipm-linux/install-packages.sh.

    The ORDER of the four steps below matters, and was established empirically
    against this exact image (VIPM 26.3.0 + LabVIEW 2026, Windows Server Core):

      1. Seed C:\ProgramData\JKI\VIPM\Settings.ini
         A fresh image never launched VIPM interactively, so the file does not
         exist and vipm.exe aborts with "IO error: Failed to load ...
         Settings.ini ... (os error 2)".

      2. Run ONE lightweight `vipm list --installed` BEFORE launching the
         VIPM Desktop engine.
         *** This is the non-obvious one. *** It initializes the VIPM database
         (it reports "No VIPM database found for LabVIEW <ver>" the first
         time). If VIPM Desktop is launched WITHOUT this, it never completes
         its startup handshake, and every subsequent install hangs at
         "Adding N local package(s) to VIPM library..." until the timeout
         expires with:
             error: Failed to add packages to VIPM library:
                    Operation 'wait for VIPM startup' timed out after <N>s
         Verified: identical script minus this call fails 100% of the time;
         with it, the install succeeds.

      3. Launch LabVIEW headless and wait for VI Server (port 3363).
         Packages install INTO a running LabVIEW.

      4. Launch VIPM Desktop (VI Package Manager.exe) and give it time.
         vipm.exe delegates the actual install to it.

    Then install with --labview-version / --labview-bitness, which are GLOBAL
    options and must PRECEDE the 'install' subcommand.

    NOT required for local .vip installs (verified by testing): git on PATH, a
    public-Git-repository working directory, `vipm refresh --force`, GITHUB_*
    environment variables, or any VIPM Pro activation. Community Edition
    installs local .vip files with none of those.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$PackagesDir    = 'C:\vipm\packages'
$LabVIEWVersion = if ($env:LABVIEW_VERSION) { $env:LABVIEW_VERSION } else { '2026' }
$LabVIEWBitness = if ($env:LABVIEW_BITNESS) { $env:LABVIEW_BITNESS } else { '64' }
# Per-operation ceiling handed to vipm's --timeout. The install itself is quick
# once the engine is healthy; this only bounds a pathological wedge.
$VipmTimeout    = if ($env:VIPM_TIMEOUT) { $env:VIPM_TIMEOUT } else { '600' }

$env:VIPM_NONINTERACTIVE = '1'
$env:VIPM_ASSUME_YES     = '1'
$env:NO_COLOR            = '1'

$vipFiles = @(Get-ChildItem -Path $PackagesDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.vip' })
if ($vipFiles.Count -eq 0) {
    Write-Host "No .vip files found in $PackagesDir; nothing to install."
    exit 0
}
Write-Host ("Found {0} package(s) to install: {1}" -f $vipFiles.Count, (($vipFiles | ForEach-Object { $_.Name }) -join ', '))

# -- Locate the VIPM CLI ------------------------------------------------------
$vipmCandidates = @(
    'C:\Program Files\JKI\VIPM\vipm.exe',
    'C:\Program Files (x86)\JKI\VIPM\vipm.exe',
    'C:\Program Files\JKI\VI Package Manager\vipm.exe',
    'C:\Program Files\JKI\VI Package Manager\support\vipm.exe'
)
$VipmExe = $vipmCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $VipmExe) {
    $found = Get-ChildItem -Path 'C:\Program Files\JKI', 'C:\Program Files (x86)\JKI' `
        -Filter 'vipm.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $VipmExe = $found.FullName }
}
if (-not $VipmExe) {
    Write-Error 'VIPM CLI (vipm.exe) was not found under C:\Program Files\JKI. Was VIPM installed in an earlier Dockerfile layer?'
    exit 1
}

# -- Locate LabVIEW.exe and the VIPM Desktop engine ---------------------------
$lvExe = @(
    'C:\Program Files\National Instruments',
    'C:\Program Files (x86)\National Instruments'
) | Where-Object { Test-Path $_ } |
    ForEach-Object { Get-ChildItem -Path $_ -Directory -Filter 'LabVIEW*' -ErrorAction SilentlyContinue } |
    ForEach-Object { Join-Path $_.FullName 'LabVIEW.exe' } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $lvExe) {
    Write-Error 'LabVIEW.exe was not found under C:\Program Files\National Instruments.'
    exit 1
}

$VipmEngineExe = @(
    'C:\Program Files\JKI\VI Package Manager\VI Package Manager.exe',
    'C:\Program Files (x86)\JKI\VI Package Manager\VI Package Manager.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1

Write-Host "VIPM CLI    : $VipmExe"
Write-Host "LabVIEW     : $lvExe"
Write-Host "VIPM Desktop: $(if ($VipmEngineExe) { $VipmEngineExe } else { '<not found>' })"

# Native vipm.exe writes normal progress to stderr. Do not let that abort the
# script, and do not redirect it with 2>&1 (PowerShell 5.1 wraps each redirected
# stderr line in a NativeCommandError, making success look like failure).
# Control flow is driven off $LASTEXITCODE from here on.
$ErrorActionPreference = 'Continue'
& $VipmExe --version

# -- STEP 1: seed Settings.ini ------------------------------------------------
$VipmSettingsDir = 'C:\ProgramData\JKI\VIPM'
$VipmSettings    = Join-Path $VipmSettingsDir 'Settings.ini'
if (-not (Test-Path $VipmSettings)) {
    $fi  = (Get-Item $lvExe).VersionInfo
    $ver = '{0}.{1} ({2}-bit)' -f $fi.ProductMajorPart, $fi.ProductMinorPart, $LabVIEWBitness
    $lvIni = '/' + (($lvExe -replace ':', '') -replace '\\', '/')
    $settingsText = @"
[General]
IsFirstLaunch="FALSE"

[Targets]
Names.<size(s)>="1"
Names 0="LabVIEW"
Versions.<size(s)>="1"
Versions 0="$ver"
Locations.<size(s)>="1"
Locations 0="$lvIni"
Ports="<size(s)=1> 3363"
Tested.<size(s)>="1"
Tested 0="TRUE"
Disabled.<size(s)>="1"
Disabled 0="FALSE"
Connection Timeout="120"
Active Target.Name="LabVIEW"
Active Target.Version="$ver"
CommunityEdition.<size(s)>="1"
CommunityEdition 0="TRUE"
"@
    New-Item -ItemType Directory -Path $VipmSettingsDir -Force | Out-Null
    Set-Content -Path $VipmSettings -Value $settingsText -Encoding ASCII
    Write-Host "[1/4] Seeded VIPM Settings.ini for target: LabVIEW $ver"
} else {
    Write-Host '[1/4] VIPM Settings.ini already present; leaving it as-is.'
}

# -- STEP 2: initialize the VIPM database BEFORE starting VIPM Desktop --------
# See the .NOTES block: skipping this makes every install hang on
# "wait for VIPM startup". Expect a "No VIPM database found" warning here on a
# fresh image -- that is this call doing its job.
Write-Host '[2/4] Initializing the VIPM database (vipm list --installed) ...'
& $VipmExe --timeout $VipmTimeout --color-mode never --labview-version $LabVIEWVersion --labview-bitness $LabVIEWBitness list --installed

# -- STEP 3: headless LabVIEW -------------------------------------------------
function Start-HeadlessLabVIEW {
    Write-Host "[3/4] Launching headless LabVIEW: $lvExe"
    Start-Process -FilePath $lvExe -ArgumentList '--headless' -PassThru | Out-Null
    $deadline = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $deadline) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect('127.0.0.1', 3363)
            if ($client.Connected) { $client.Close(); Write-Host '      LabVIEW VI Server is ready (port 3363).'; return $true }
        } catch { Start-Sleep -Seconds 3 }
    }
    Write-Warning '      Timed out waiting for LabVIEW VI Server (port 3363); continuing anyway.'
    return $false
}

# -- STEP 4: VIPM Desktop engine ----------------------------------------------
function Start-VipmEngine {
    if (-not $VipmEngineExe) {
        Write-Warning '[4/4] VIPM Desktop was not found; the CLI will try to start it itself.'
        return
    }
    if (Get-Process -Name 'VI Package Manager' -ErrorAction SilentlyContinue) { return }
    Write-Host "[4/4] Launching VIPM Desktop: $VipmEngineExe"
    Start-Process -FilePath $VipmEngineExe -PassThru | Out-Null
    Start-Sleep -Seconds 45
    Write-Host '      VIPM Desktop launched (allowed 45s to initialize).'
}

Start-HeadlessLabVIEW | Out-Null
Start-VipmEngine

# -- Wedged-engine recovery ---------------------------------------------------
# With the ordering above the install path is reliable, but a cold VIPM Desktop
# can still occasionally miss its startup handshake. Tear the stack down and
# relaunch rather than failing the image on a transient.
$MaxEngineRestarts = if ($env:VIPM_MAX_ENGINE_RESTARTS -match '^\d+$') { [int]$env:VIPM_MAX_ENGINE_RESTARTS } else { 2 }
$script:RestartsUsed = 0

function Restart-VipmStack([int]$Attempt) {
    Write-Warning "  VIPM Desktop wedged; restarting the stack (attempt $Attempt/$MaxEngineRestarts) and retrying ..."
    foreach ($procName in @('vipm', 'VI Package Manager', 'LabVIEW', 'LabVIEWCLI')) {
        Get-Process -Name $procName -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 10   # let the killed processes release port 3363 and file locks
    # Re-initialize the database before VIPM Desktop comes back up (see STEP 2).
    & $VipmExe --timeout $VipmTimeout --color-mode never --labview-version $LabVIEWVersion --labview-bitness $LabVIEWBitness list --installed
    Start-HeadlessLabVIEW | Out-Null
    Start-VipmEngine
}

# -- Install each local .vip file ---------------------------------------------
# --labview-version / --labview-bitness are GLOBAL options and must PRECEDE the
# 'install' subcommand. -v prints live VIPM Desktop status, which is what makes
# a stall diagnosable instead of silent.
$failed = $null
foreach ($vip in $vipFiles) {
    Write-Host ''
    Write-Host "=== Installing: $($vip.Name) ==="
    for (;;) {
        & $VipmExe --timeout $VipmTimeout --color-mode never -v --labview-version $LabVIEWVersion --labview-bitness $LabVIEWBitness install -y $vip.FullName
        $rc = $LASTEXITCODE
        if ($rc -eq 0) { break }
        if ($script:RestartsUsed -ge $MaxEngineRestarts) {
            Write-Warning "Failed to install $($vip.Name) (exit $rc) after $($script:RestartsUsed) restart(s)."
            $failed = $vip.Name
            break
        }
        $script:RestartsUsed++
        Restart-VipmStack $script:RestartsUsed
    }
    if ($failed) { break }
}

if ($failed) {
    Write-Error "VIPM could not install '$failed'. See the vipm output above for the reason."
    exit 1
}

Write-Host ''
Write-Host '=== Installed packages ==='
& $VipmExe --timeout $VipmTimeout --color-mode never --labview-version $LabVIEWVersion --labview-bitness $LabVIEWBitness list --installed
Write-Host ''
Write-Host 'All local .vip packages installed successfully.'

