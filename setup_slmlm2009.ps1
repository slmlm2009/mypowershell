<#
.SYNOPSIS
    Setup for slmlm2009 Windows Terminal environment.
#>

# 0. Admin & Session Prep
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Administrator privileges required." -ForegroundColor Red
    Break
}

# Force TLS 1.2 for PSGallery (Crucial for SSH sessions)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoPath = $PSScriptRoot
Write-Host "`n>>> Starting Deployment from: $RepoPath" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

$OmpConfigName = "slmlm2009.omp.yaml"
$OmpTargetDir  = "$HOME\.omp"

# Helper Function for Symlinks (Aggressive deletion for SSH)
function Set-Symlink {
    param ([string]$SourceFile, [string]$TargetFile, [string]$DisplayName)
    if (!(Test-Path $SourceFile)) { return }

    $absSource = (Resolve-Path $SourceFile).Path
    $absTarget = [System.IO.Path]::GetFullPath($TargetFile)

    if ($absSource -ieq $absTarget) {
        Write-Host "  [OK] $DisplayName : Already in correct location" -ForegroundColor Gray
        return
    }

    if (Test-Path $TargetFile) {
        $item = Get-Item $TargetFile
        if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $absSource) {
            Write-Host "  [OK] $DisplayName : Symlink already correct" -ForegroundColor Gray
            return
        }
        
        # Access Denied Fix: Use CMD to force delete existing files/links
        Write-Host "  [..] Removing existing $DisplayName..." -ForegroundColor Gray
        if ($item.Attributes -match "Directory") {
            cmd /c "rd /s /q `"$absTarget`"" 2>$null
        } else {
            cmd /c "del /f /q `"$absTarget`"" 2>$null
        }
    }

    # Final attempt to create link
    New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force *>$null
    if (Test-Path $TargetFile) {
        Write-Host "  [+] $DisplayName : Symlink created" -ForegroundColor Green
    } else {
        Write-Host "  [X] $DisplayName : Symlink failed" -ForegroundColor Red
    }
}

# ---------------------------------------------------------
# 1. Environment: Scoop & Git
# ---------------------------------------------------------
Write-Host "`n[1/6] Environment: Scoop & Git" -ForegroundColor Blue
if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression *>$null
}
Write-Host "  [OK] Scoop ready" -ForegroundColor Gray

# Strict Scoop check
$scoopApps = scoop list
if ($scoopApps -notmatch "git") {
    Write-Host "  [..] Installing Scoop Git..."
    scoop install git *>$null
}
Write-Host "  [OK] Git ready" -ForegroundColor Gray

# ---------------------------------------------------------
# 2. CLI Tools
# ---------------------------------------------------------
Write-Host "`n[2/6] CLI Tools (Scoop)" -ForegroundColor Blue
if (!(scoop bucket list | Select-String "extras")) {
    scoop bucket add extras *>$null
}

$tools = @("zoxide", "fzf", "bat", "ripgrep", "fd", "eza")
foreach ($tool in $tools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "  [..] Installing $tool..."
        scoop install $tool *>$null
        Write-Host "  [+] $tool installed" -ForegroundColor Green
    } else {
        Write-Host "  [OK] $tool is already installed" -ForegroundColor Gray
    }
}

# ---------------------------------------------------------
# 3. Prompt: Oh My Posh
# ---------------------------------------------------------
Write-Host "`n[3/6] Prompt: Oh My Posh" -ForegroundColor Blue
if (!(Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements *>$null
    Write-Host "  [+] Oh My Posh installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] Oh My Posh already installed" -ForegroundColor Gray
}

# ---------------------------------------------------------
# 4. PowerShell Modules (Nuclear Fix)
# ---------------------------------------------------------
Write-Host "`n[4/6] PowerShell Modules (PSGallery)" -ForegroundColor Blue

# Ensure Module Path exists
$modPath = "$HOME\Documents\PowerShell\Modules"
if (!(Test-Path $modPath)) { New-Item -ItemType Directory -Path $modPath -Force *>$null }

# Provider and Trust
if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force *>$null
}
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted *>$null

$modules = @("PSFzf", "Terminal-Icons")
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "  [..] Installing $module..." -ForegroundColor White
        # -Scope CurrentUser is sometimes blocked in SSH; we use -Force and -AllowClobber
        try {
            Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -Confirm:$false -ErrorAction Stop
            Write-Host "  [+] $module installed" -ForegroundColor Green
        } catch {
            Write-Host "  [X] Failed to install $module. Attempting workaround..." -ForegroundColor Yellow
            # Alternative for stubborn SSH sessions
            Save-Module -Name $module -Path $modPath -Force *>$null
            Write-Host "  [+] $module saved to user modules" -ForegroundColor Green
        }
    } else {
        Write-Host "  [OK] $module is already installed" -ForegroundColor Gray
    }
}

# ---------------------------------------------------------
# 5. Configuration Symlinks
# ---------------------------------------------------------
Write-Host "`n[5/6] Configuration Symlinks" -ForegroundColor Blue

# Windows Terminal (Only if local appdata exists)
$wtPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState"
$wtResolvedPath = Get-ChildItem -Path $wtPath -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wtResolvedPath) {
    Set-Symlink -SourceFile "$RepoPath\settings.json" -TargetFile "$($wtResolvedPath.FullName)\settings.json" -DisplayName "Terminal Settings"
}

# Profile and OMP
$profileDir = Split-Path -Path $PROFILE
if (!(Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force *>$null }
Set-Symlink -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" -TargetFile $PROFILE -DisplayName "PS Profile"

if (!(Test-Path $OmpTargetDir)) { New-Item -ItemType Directory -Path $OmpTargetDir -Force *>$null }
Set-Symlink -SourceFile "$RepoPath\$OmpConfigName" -TargetFile "$OmpTargetDir\$OmpConfigName" -DisplayName "OMP Config"

Write-Host "`n------------------------------------------------------------"
Write-Host "[6/6] Setup Complete!" -ForegroundColor Cyan
