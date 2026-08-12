<#
.SYNOPSIS
    Builds this folder's image and pushes it to GHCR, from your own machine
    (no GitHub Actions involved).

.DESCRIPTION
    Runs `docker build` against this folder, then pushes
    ghcr.io/<Owner>/<ImageName>:latest and :<Tag>.

    Requires Docker Desktop running in WINDOWS container mode, and either a
    prior `docker login ghcr.io`, or pass -Login to do it here.

.PARAMETER Owner
    GitHub username or org that owns the GHCR package.

.PARAMETER ImageName
    GHCR image name. Default: labview-vipm-windows.

.PARAMETER Tag
    Extra tag to push alongside :latest (e.g. a version, or "dev"). Default: dev.

.PARAMETER Login
    Prompt for a GitHub PAT (needs the write:packages scope) and run
    `docker login ghcr.io` before building. Skip this if you're already
    logged in.

.PARAMETER VipmInstallerUrl
    Optional override for the VIPM_INSTALLER_URL build arg.

.PARAMETER LabviewVersion
    Optional override for the LABVIEW_VERSION build arg.

.PARAMETER LabviewBitness
    Optional override for the LABVIEW_BITNESS build arg.

.EXAMPLE
    ./publish.ps1 -Owner myghusername
    Builds and pushes ghcr.io/myghusername/labview-vipm-windows:latest and :dev.

.EXAMPLE
    ./publish.ps1 -Owner myghusername -Tag v1 -Login
    Logs in to GHCR interactively, then pushes :latest and :v1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Owner,

    [string]$ImageName = 'soliton/labview-genvi',

    [string]$Tag = 'latest-windows',

    [switch]$Login,

    [string]$VipmInstallerUrl,

    [string]$LabviewVersion,

    [string]$LabviewBitness
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$Repo = "ghcr.io/$($Owner.ToLower())/$($ImageName.ToLower())"

try {
    $serverOs = (docker version --format '{{.Server.Os}}' 2>$null).Trim()
} catch {
    throw 'Could not reach the Docker daemon. Is Docker Desktop running?'
}
if (-not $serverOs) { throw 'Could not reach the Docker daemon. Is Docker Desktop running?' }
if ($serverOs -ne 'windows') {
    throw "Docker Desktop is set to '$serverOs' containers, but this image needs Windows containers. Switch Docker Desktop to Windows containers and try again."
}

if ($Login) {
    $secure = Read-Host -AsSecureString -Prompt 'GitHub PAT (needs the write:packages scope)'
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    Write-Host "Logging in to ghcr.io as $Owner ..."
    $plainToken | docker login ghcr.io -u $Owner --password-stdin
    $plainToken = $null
    if ($LASTEXITCODE -ne 0) { throw "docker login failed (exit $LASTEXITCODE)" }
}

$buildArgs = @()
if ($VipmInstallerUrl) { $buildArgs += @('--build-arg', "VIPM_INSTALLER_URL=$VipmInstallerUrl") }
if ($LabviewVersion)   { $buildArgs += @('--build-arg', "LABVIEW_VERSION=$LabviewVersion") }
if ($LabviewBitness)   { $buildArgs += @('--build-arg', "LABVIEW_BITNESS=$LabviewBitness") }

Write-Host "Building $Repo (tags: latest, $Tag) ..."
docker build @buildArgs -t "${Repo}:latest" -t "${Repo}:$Tag" $ScriptDir
if ($LASTEXITCODE -ne 0) { throw "docker build failed (exit $LASTEXITCODE)" }

Write-Host "Pushing ${Repo}:latest ..."
docker push "${Repo}:latest"
if ($LASTEXITCODE -ne 0) { throw "docker push failed for :latest (exit $LASTEXITCODE)" }

Write-Host "Pushing ${Repo}:$Tag ..."
docker push "${Repo}:$Tag"
if ($LASTEXITCODE -ne 0) { throw "docker push failed for :$Tag (exit $LASTEXITCODE)" }

Write-Host ''
Write-Host 'Published:'
Write-Host "  ${Repo}:latest"
Write-Host "  ${Repo}:$Tag"
Write-Host ''
Write-Host 'New GHCR packages are private by default -- manage visibility from your GitHub profile/org Packages tab.'
