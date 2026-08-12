# escape=`
# =============================================================================
# LabVIEW Windows + VIPM, with local .vip packages baked in
# =============================================================================
# Standalone, fresh build -- NOT wired into this repo's GitHub Actions worker
# pipeline under .github/. Starts from the official NI LabVIEW Windows
# container, installs VIPM, then installs every *.vip file found in
# ./packages directly into the image. Windows counterpart of
# ../labview-vipm-linux/.
# =============================================================================
FROM nationalinstruments/labview:latest-windows

SHELL ["powershell", "-NoLogo", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG VIPM_INSTALLER_URL=https://traffic.libsyn.com/secure/jkinc/vipm-26.3.3954-windows-setup.exe
ARG LABVIEW_VERSION=2026
ARG LABVIEW_BITNESS=64

RUN $ErrorActionPreference = 'Continue'; `
    $vipmSetup = Join-Path $env:TEMP 'vipm-setup.exe'; `
    Write-Host "Downloading VIPM installer: $env:VIPM_INSTALLER_URL"; `
    try { `
      Invoke-WebRequest -Uri $env:VIPM_INSTALLER_URL -OutFile $vipmSetup -UseBasicParsing; `
      Write-Host ('Downloaded {0:N1} MB; installing VIPM silently (/exenoui /qn) ...' -f ((Get-Item $vipmSetup).Length / 1MB)); `
      $p = Start-Process -Wait -PassThru -FilePath $vipmSetup -ArgumentList '/exenoui','/qn'; `
      Write-Host "VIPM installer exit code: $($p.ExitCode)"; `
      if ($p.ExitCode -ne 0) { throw "VIPM installer exited with code $($p.ExitCode)" } `
    } catch { `
      Remove-Item $vipmSetup -Force -ErrorAction SilentlyContinue; `
      throw `
    } finally { `
      Remove-Item $vipmSetup -Force -ErrorAction SilentlyContinue `
    }

COPY packages/ C:/vipm/packages/
COPY install-packages.ps1 C:/vipm/install-packages.ps1

RUN & C:\vipm\install-packages.ps1

LABEL labview-vipm.platform=windows
