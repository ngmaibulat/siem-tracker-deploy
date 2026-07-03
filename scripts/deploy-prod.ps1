param(
    # Prod host/user are deliberately not stored in this public repo — always
    # pass them explicitly (see scripts/DEPLOY.md).
    [string]$ProdHost = "",
    [string]$ProdUser = "",
    [string]$SshKey = "",

    # Path to the app source repo (siem-tracker) — the Docker build context.
    # Defaults to a `siem-tracker` checkout next to this deploy repo.
    [string]$AppRepo = "",

    # Version tag to build and push (alongside `latest`, which is what prod
    # actually runs — docker-compose.yml hardcodes it). If empty, a UTC
    # timestamp is used.
    [string]$ImageTag = "",

    # Skip docker build + push and just re-run the prod deploy (pulls the
    # registry's current `latest`). To roll back to an older version, first
    # re-point `latest` at that tag in the registry (see DEPLOY.md), then run
    # with -NoBuild.
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

if ($ProdHost -eq "" -or $ProdUser -eq "") {
    throw "ProdHost and ProdUser are required (not stored in this public repo). Run with -ProdHost <host> -ProdUser <user> [-SshKey <path>]."
}

function Run-Command {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    Write-Host "==> $Command $($Arguments -join ' ')"

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $Command $($Arguments -join ' ')"
    }
}

# This script lives in scripts/ of the standalone deploy repo; the Docker build
# context is the APP source repo (siem-tracker), which by default is a checkout
# next to this deploy repo.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployRepoRoot = Split-Path -Parent $ScriptDir
if ($AppRepo -eq "") {
    $AppRepo = Join-Path (Split-Path -Parent $DeployRepoRoot) "siem-tracker"
}
if (-not (Test-Path (Join-Path $AppRepo "Dockerfile"))) {
    throw "App repo not found at '$AppRepo' (no Dockerfile). Pass -AppRepo <path-to-siem-tracker>."
}
Set-Location $AppRepo

# Published image repository on Docker Hub (public — prod pulls it without login).
$ImageName = "ngmaibulat/usiem-tracker"
$SshTarget = "${ProdUser}@${ProdHost}"

$SshBaseArgs = @(
    "-o", "IdentitiesOnly=yes",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "ServerAliveInterval=10",
    "-o", "ServerAliveCountMax=3"
)

if ($SshKey -ne "") {
    $SshBaseArgs = @("-i", $SshKey) + $SshBaseArgs
}

# For ssh remote commands only.
# -n prevents ssh from reading stdin and helps avoid PowerShell hangs.
$SshRemoteArgs = @("-n") + $SshBaseArgs

function Run-RemoteCommand {
    param(
        [string]$RemoteCommand
    )

    Run-Command "ssh" ($SshRemoteArgs + @($SshTarget, $RemoteCommand))
}

if ($ImageTag -eq "") {
    $ImageTag = Get-Date -Format "yyyyMMdd-HHmmss"
}

$FullImageName = "${ImageName}:${ImageTag}"

if (-not $NoBuild) {
    Write-Host "==> Build + push mode"

    # Requires `docker login` on this dev machine for the $ImageName namespace.
    # Tag both the version and `latest` — prod runs `latest` (hardcoded in
    # docker-compose.yml); the version tag stays in the registry for rollback.
    Write-Host "==> Building Docker image: $FullImageName (+ ${ImageName}:latest)"
    Run-Command "docker" @("build", "--no-cache", "-t", $FullImageName, "-t", "${ImageName}:latest", ".")

    Write-Host "==> Pushing image to registry"
    Run-Command "docker" @("push", $FullImageName)
    Run-Command "docker" @("push", "${ImageName}:latest")
}
else {
    Write-Host "==> NoBuild mode — deploying the registry's current 'latest' (label: $ImageTag)"
}

Write-Host "==> Deployment parameters"
Write-Host "    ProdHost:  $ProdHost"
Write-Host "    ProdUser:  $ProdUser"
Write-Host "    Image:     $FullImageName"

Write-Host "==> Checking SSH connectivity"
Run-RemoteCommand "echo ssh-ok"

# The prod host pulls the image from the registry and brings the stack up.
Write-Host "==> Running remote deploy"
Run-RemoteCommand "sudo -n /opt/siem-source-tracker/deploy_app.sh '$ImageTag'"

Write-Host "==> Deploy finished successfully"
Write-Host "Image: $FullImageName"
