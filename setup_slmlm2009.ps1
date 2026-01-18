<#
.SYNOPSIS
    Hardened dotfiles/bootstrap script for Windows Terminal
    Can be executed from an elevated SSH session with a filtered admin token.
.DESCRIPTION
    - Avoids recursive/self symlinks
    - Uses CMD-level deletion to bypass PS provider/ACL weirdness
    - Forces TLS 1.2 for PSGallery
    - Discovers the *effective* CurrentUser PSModulePath
    - Falls back to Save-Module when Install-Module is blocked
    - Suppresses installer noise and reports final state cleanly
#>

# ------------------------------------------------------------
# 0. Session & Security Prep
# ------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal]
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "[X] Administrator privileges required" -ForegroundColor Red
    return
}

# Force TLS 1.2 (PSGallery + WinHTTP in SSH sessions)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoPath = $PSScriptRoot
Write-Host "\n>>> Deploying from $RepoPath" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

# ------------------------------------------------------------
# Utility: Status Output
# ------------------------------------------------------------
function Write-OK($msg) { Write-Host "  [OK] $msg" -ForegroundColor DarkGray }
function Write-Add($msg){ Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-Err($msg){ Write-Host "  [X] $msg" -ForegroundColor Red }
function Write-Do ($msg){ Write-Host "  [..] $msg" -ForegroundColor Yellow }

# ------------------------------------------------------------
# Utility: Nuclear Delete (bypass PS provider locks)
# ------------------------------------------------------------
function Remove-Nuclear {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return }

    $full = [System.IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force

    if ($item.PSIsContainer) {
        cmd /c "rd /s /q \"$full\"" 2>$null
    } else {
        cmd /c "del /f /q \"$full\"" 2>$null
    }
}

# ------------------------------------------------------------
# Utility: Safe Symlink Creation
# ------------------------------------------------------------
function Set-Symlink {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Name
    )

    if (-not (Test-Path $Source)) { return }

    $absSource = (Resolve-Path $Source).Path
    $absTarget = [System.IO.Path]::GetFullPath($Target)

    # Prevent recursive/self links
    if ($absSource -ieq $absTarget) {
        Write-OK "$Name already in correct location"
        return
    }

    if (Test-Path $absTarget) {
        try {
            $existing = Get-Item $absTarget -Force
            if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $absSource) {
                Write-OK "$Name symlink already correct"
                return
            }
        } catch {}

        Remove-Nuclear $absTarget
    }

    New-Item -ItemType SymbolicLink -Path $absTarget -Target $absSource -Force *>$null

    if (Test-Path $absTarget) { Write-Add "$Name linked" }
    else { Write-Err "$Name link failed" }
}

# ------------------------------------------------------------
# 1. Environment: Scoop & Git
# ------------------------------------------------------------
Write-Host "\n[1/6] Environment" -ForegroundColor Blue

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Invoke-RestMethod https://get.scoop.sh | Invoke-Expression *>$null
}
Write-OK "Scoop ready"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Do "Installing Git"
    scoop install git *>$null
}
Write-OK "Git ready"

# ------------------------------------------------------------
# 2. CLI Tools (Scoop)
# ------------------------------------------------------------
Write-Host "\n[2/6] CLI Tools" -ForegroundColor Blue

if (-not (scoop bucket list | Select-String extras)) {
    scoop bucket add extras *>$null
}

$tools = "zoxide","fzf","bat","ripgrep","fd","eza"
foreach ($t in $tools) {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        Write-Do "Installing $t"
        scoop install $t *>$null
        Write-Add "$t installed"
    } else {
        Write-OK "$t present"
    }
}

# ------------------------------------------------------------
# 3. Prompt: Oh My Posh
# ------------------------------------------------------------
Write-Host "\n[3/6] Oh My Posh" -ForegroundColor Blue

if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    winget install JanDeDobbeleer.OhMyPosh --accept-package-agreements --accept-source-agreements *>$null
    Write-Add "Oh My Posh installed"
} else {
    Write-OK "Oh My Posh present"
}

# ------------------------------------------------------------
# 4. PowerShell Modules (Filtered Token Safe)
# ------------------------------------------------------------
Write-Host "\n[4/6] PowerShell Modules" -ForegroundColor Blue

# Determine *effective* CurrentUser module path
$userModuleRoot = ($env:PSModulePath -split ';' |
    Where-Object { $_ -match [regex]::Escape($HOME) } |
    Select-Object -First 1)

if (-not $userModuleRoot) {
    $userModuleRoot = "$HOME\Documents\PowerShell\Modules"
}

if (-not (Test-Path $userModuleRoot)) {
    New-Item -ItemType Directory -Path $userModuleRoot -Force *>$null
}

# PSGallery prep
if (-not (Get-PackageProvider NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider NuGet -Force *>$null
}
Set-PSRepository PSGallery -InstallationPolicy Trusted *>$null

$modules = "PSFzf","Terminal-Icons"
foreach ($m in $modules) {
    if (Get-Module -ListAvailable $m) {
        Write-OK "$m present"
        continue
    }

    Write-Do "Installing $m"
    try {
        Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Add "$m installed"
    } catch {
        Write-Do "Save-Module fallback for $m"
        Save-Module $m -Path $userModuleRoot -Force -ErrorAction SilentlyContinue

        if (Get-Module -ListAvailable $m) {
            Write-Add "$m saved"
        } else {
            Write-Err "$m failed"
        }
    }
}

# ------------------------------------------------------------
# 5. Configuration Symlinks
# ------------------------------------------------------------
Write-Host "\n[5/6] Symlinks" -ForegroundColor Blue

# Windows Terminal
$wt = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.WindowsTerminal_*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wt) {
    Set-Symlink "$RepoPath\settings.json" "$($wt.FullName)\LocalState\settings.json" "Windows Terminal"
}

# PowerShell Profile
$profileDir = Split-Path $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force *>$null
}
Set-Symlink "$RepoPath\Microsoft.PowerShell_profile.ps1" $PROFILE "PowerShell Profile"

# Oh My Posh config
$ompDir = "$HOME\.omp"
if (-not (Test-Path $ompDir)) {
    New-Item -ItemType Directory -Path $ompDir -Force *>$null
}
Set-Symlink "$RepoPath\slmlm2009.omp.yaml" "$ompDir\slmlm2009.omp.yaml" "OMP Config"

Write-Host "\n------------------------------------------------------------"
Write-Host "[6/6] Setup Complete" -ForegroundColor Cyan
