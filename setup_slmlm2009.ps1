<#
.SYNOPSIS
    Setup script for slmlm2009 Windows Terminal environment.
    Optimized for SSH sessions, clean status reporting, and robust symlinking.
#>

# 0. Admin Check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Administrator privileges required." -ForegroundColor Red
    Write-Warning "Please right-click PowerShell and 'Run as Administrator'."
    Break
}

# Get absolute path of the repo root
$RepoPath = $PSScriptRoot
Write-Host "`n>>> Starting Deployment from: $RepoPath" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

# --- Configuration ---
$OmpConfigName = "slmlm2009.omp.yaml"
$OmpTargetDir  = "$HOME\.omp"

# Helper Function for Symlinks with Status Reporting
function Set-Symlink {
    param ([string]$SourceFile, [string]$TargetFile, [string]$DisplayName)

    if (!(Test-Path $SourceFile)) {
        Write-Host "  [-] $DisplayName : Source missing ($SourceFile)" -ForegroundColor Yellow
        return
    }

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
        
        if ($item.LinkType -eq "SymbolicLink") {
            Remove-Item $TargetFile -Force
        } else {
            $backup = "$TargetFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Rename-Item -Path $TargetFile -NewName $backup
            Write-Host "  [!] $DisplayName : Backup created (.bak)" -ForegroundColor Magenta
        }
    }

    New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force *>$null
    Write-Host "  [+] $DisplayName : Symlink created successfully" -ForegroundColor Green
}

# ---------------------------------------------------------
# 1. Install Scoop & Git
# ---------------------------------------------------------
Write-Host "`n[1/6] Environment: Scoop & Git" -ForegroundColor Blue
if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing Scoop..." -ForegroundColor White
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression *>$null
    Write-Host "  [+] Scoop installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] Scoop is already installed" -ForegroundColor Gray
}

if (!((scoop list | Out-String) -match "git")) {
    Write-Host "  [..] Installing Scoop Git..." -ForegroundColor White
    scoop install git *>$null
    Write-Host "  [+] Git (Scoop version) installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] Git (Scoop version) is already present" -ForegroundColor Gray
}

# ---------------------------------------------------------
# 2. CLI Tools
# ---------------------------------------------------------
Write-Host "`n[2/6] CLI Tools (Scoop)" -ForegroundColor Blue
if (!(scoop bucket list | Select-String "extras")) {
    Write-Host "  [..] Adding 'extras' bucket..."
    scoop bucket add extras *>$null
}

$tools = @("zoxide", "fzf", "bat", "ripgrep", "fd", "eza")
foreach ($tool in $tools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "  [..] Installing $tool..." -ForegroundColor White
        scoop install $tool *>$null
        Write-Host "  [+] $tool installed" -ForegroundColor Green
    } else {
        Write-Host "  [OK] $tool is already installed" -ForegroundColor Gray
    }
}

# ---------------------------------------------------------
# 3. Prompt: Oh My Posh
# ---------------------------------------------------------
Write-Host "`n[3/6] Prompt: Oh My Posh (Winget)" -ForegroundColor Blue
if (!(Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing Oh My Posh..." -ForegroundColor White
    winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements *>$null
    Write-Host "  [+] Oh My Posh installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] Oh My Posh is already installed" -ForegroundColor Gray
}

# ---------------------------------------------------------
# 4. PowerShell Modules (SSH/Admin Fix)
# ---------------------------------------------------------
Write-Host "`n[4/6] PowerShell Modules (PSGallery)" -ForegroundColor Blue

# THE FIX: Manually create user module path to bypass directory creation permission errors over SSH
$userModulePath = "$HOME\Documents\PowerShell\Modules"
if (!(Test-Path $userModulePath)) { 
    New-Item -ItemType Directory -Path $userModulePath -Force *>$null 
}

if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing NuGet Provider..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force *>$null
}
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted *>$null

$modules = @("PSFzf", "Terminal-Icons")
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "  [..] Installing $module..." -ForegroundColor White
        # -ErrorAction SilentlyContinue handles the non-terminating admin warnings over SSH
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -ErrorAction SilentlyContinue
        
        # Verify installation success
        if (Get-Module -ListAvailable -Name $module) {
            Write-Host "  [+] $module installed successfully" -ForegroundColor Green
        } else {
            Write-Host "  [X] Failed to install $module" -ForegroundColor Red
        }
    } else {
        Write-Host "  [OK] $module is already installed" -ForegroundColor Gray
    }
}

# ---------------------------------------------------------
# 5. Configurations (Symlinks)
# ---------------------------------------------------------
Write-Host "`n[5/6] Configuration Symlinks" -ForegroundColor Blue

# A. Windows Terminal
$wtPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState"
$wtResolvedPath = Get-ChildItem -Path $wtPath -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wtResolvedPath) {
    Set-Symlink -SourceFile "$RepoPath\settings.json" -TargetFile "$($wtResolvedPath.FullName)\settings.json" -DisplayName "Terminal Settings"
}

# B. PowerShell Profile
$profileDir = Split-Path -Path $PROFILE
if (!(Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force *>$null }
Set-Symlink -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" -TargetFile $PROFILE -DisplayName "PowerShell Profile"

# C. Oh My Posh Config
if (!(Test-Path $OmpTargetDir)) { New-Item -ItemType Directory -Path $OmpTargetDir -Force *>$null }
Set-Symlink -SourceFile "$RepoPath\$OmpConfigName" -TargetFile "$OmpTargetDir\$OmpConfigName" -DisplayName "Oh My Posh Config"

# ---------------------------------------------------------
# 6. Conclusion
# ---------------------------------------------------------
Write-Host "`n------------------------------------------------------------"
Write-Host "[6/6] Setup Complete! Restart your session." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------`n"
