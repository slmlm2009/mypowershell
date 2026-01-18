<#
.SYNOPSIS
    Setup script for slmlm2009 Windows Terminal environment
    Installs Scoop, Git, CLI tools, PS Modules, Oh My Posh, and symlinks configs.
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
# --- Path Equality Check ---
    # Resolve paths to absolute strings to ensure comparison is accurate
    $absSource = (Resolve-Path $SourceFile).Path
	# For target, we manually construct the expected absolute path to check equality before creation
    $absTarget = [System.IO.Path]::GetFullPath($TargetFile)

    if ($absSource -ieq $absTarget) {
        Write-Host "  [OK] $DisplayName : Already in correct location" -ForegroundColor Gray
        return
    }
    # Check if target already exists
    if (Test-Path $TargetFile) {
        $item = Get-Item $TargetFile
        # Check if it's already a link to our repo
		if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $absSource) {
            Write-Host "  [OK] $DisplayName : Symlink already correct" -ForegroundColor Gray
            return
        }
        # If it exists but isn't our link, back it up (unless it's a different link, then delete)
        if ($item.LinkType -eq "SymbolicLink") {
			Write-Host "Removing existing different symlink: $TargetFile"
            Remove-Item $TargetFile -Force
        } else {
            $backup = "$TargetFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Rename-Item -Path $TargetFile -NewName $backup
            Write-Host "  [!] $DisplayName : Existing file backed up to .bak" -ForegroundColor Magenta
        }
    }
	# Create the symlink
    Write-Host "Creating symlink: $TargetFile -> $absSource" -ForegroundColor Yellow
    New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force | Out-Null
    Write-Host "  [+] $DisplayName : Symlink created successfully" -ForegroundColor Green
}

# ---------------------------------------------------------
# 1. Install Scoop & Git
# ---------------------------------------------------------
Write-Host "`n[1/6] Environment: Scoop & Git" -ForegroundColor Blue
if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing Scoop..." -ForegroundColor White
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression | Out-Null
    Write-Host "  [+] Scoop installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] Scoop is already installed" -ForegroundColor Gray
}

if ((scoop list git 2>$null) -notmatch "git") {
    Write-Host "  [..] Installing Scoop Git..." -ForegroundColor White
    scoop install git | Out-Null
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
    scoop bucket add extras | Out-Null
}

$tools = @("zoxide", "fzf", "bat", "ripgrep", "fd", "eza")
foreach ($tool in $tools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "  [..] Installing $tool..." -ForegroundColor White
        scoop install $tool | Out-Null
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
    winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements | Out-Null
    Write-Host "  [+] Oh My Posh installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] Oh My Posh is already installed" -ForegroundColor Gray
}

# ---------------------------------------------------------
# 4. PowerShell Modules
# ---------------------------------------------------------
Write-Host "`n[4/6] PowerShell Modules (PSGallery)" -ForegroundColor Blue

# Fix for the "Administrator/NuGet" issue
if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing NuGet Provider..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue

$modules = @("PSFzf", "Terminal-Icons")
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "  [..] Installing $module..." -ForegroundColor White
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber | Out-Null
        Write-Host "  [+] $module installed" -ForegroundColor Green
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
    Set-Symlink -SourceFile "$RepoPath\settings.json" -TargetFile "$($wtResolvedPath.FullName)\settings.json" -DisplayName "Windows Terminal Settings"
}

# B. PowerShell Profile
$profileDir = Split-Path -Path $PROFILE
if (!(Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
Set-Symlink -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" -TargetFile $PROFILE -DisplayName "PowerShell Profile"

# C. Oh My Posh Config
if (!(Test-Path $OmpTargetDir)) { New-Item -ItemType Directory -Path $OmpTargetDir -Force | Out-Null }
Set-Symlink -SourceFile "$RepoPath\$OmpConfigName" -TargetFile "$OmpTargetDir\$OmpConfigName" -DisplayName "Oh My Posh Config"

# ---------------------------------------------------------
# 6. Conclusion
# ---------------------------------------------------------
Write-Host "`n------------------------------------------------------------"
Write-Host "[6/6] Setup Complete! Please restart your Terminal." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------`n"
