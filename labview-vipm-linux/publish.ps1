<#
.SYNOPSIS
    Builds this folder's image and pushes it to GHCR, from your own machine
    (no GitHub Actions involved).

.DESCRIPTION
    Runs `docker build` against this folder, then pushes
    ghcr.io/<Owner>/<ImageName>:latest and :<Tag>.

    Requires Docker Desktop running in LINUX container mode, and either a
    prior `docker login ghcr.io`, or pass -Login to do it here.

.PARAMETER Owner
    GitHub username or org that owns the GHCR package.

.PARAMETER ImageName
    GHCR image name. Default: labview-vipm-linux.

.PARAMETER Tag
    Extra tag to push alongside :latest (e.g. a version, or "dev"). Default: dev.

.PARAMETER Login
    Prompt for a GitHub PAT (needs the write:packages scope) and run
    `docker login ghcr.io` before building. Skip this if you're already
    logged in.

.PARAMETER VipmDebUrl
    Optional override for the VIPM_DEB_URL build arg.

.PARAMETER LabviewVersion
    Optional override for the LABVIEW_VERSION build arg.

.EXAMPLE
    ./publish.ps1 -Owner myghusername
    Builds and pushes ghcr.io/myghusername/labview-vipm-linux:latest and :dev.

.EXAMPLE
    ./publish.ps1 -Owner myghusername -Tag v1 -Login
    Logs in to GHCR interactively, then pushes :latest and :v1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Owner,

    [string]$ImageName = 'labview-vipm-linux',

    [string]$Tag = 'dev',

    [switch]$Login,

    [string]$VipmDebUrl,

    [string]$LabviewVersion
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
if ($serverOs -ne 'linux') {
    throw "Docker Desktop is set to '$serverOs' containers, but this image needs Linux containers. Switch Docker Desktop to Linux containers and try again."
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
if ($VipmDebUrl)     { $buildArgs += @('--build-arg', "VIPM_DEB_URL=$VipmDebUrl") }
if ($LabviewVersion) { $buildArgs += @('--build-arg', "LABVIEW_VERSION=$LabviewVersion") }

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
