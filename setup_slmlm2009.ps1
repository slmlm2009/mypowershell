<#
.SYNOPSIS
    Setup script for slmlm2009 environment.
    Installs Scoop, Git, CLI tools, PS Modules, Oh My Posh, and symlinks configs.
#>

# 0. Admin Check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires Administrator privileges to create Symbolic Links."
    Break
}

# Get absolute path of the repo root
$RepoPath = $PSScriptRoot
Write-Host "Running setup from: $RepoPath" -ForegroundColor Cyan

# --- Configuration ---
$OmpConfigName = "slmlm2009.omp.yaml"
$OmpTargetDir  = "$HOME\.omp"

# Helper Function to check and create Symlinks
function Set-Symlink {
    param ([string]$SourceFile, [string]$TargetFile)

    if (!(Test-Path $SourceFile)) {
        Write-Warning "Source file missing: $SourceFile. Skipping."
        return
    }
# --- Path Equality Check ---
    # Resolve paths to absolute strings to ensure comparison is accurate
    $absSource = (Resolve-Path $SourceFile).Path
    # For target, we manually construct the expected absolute path to check equality before creation
    $absTarget = [System.IO.Path]::GetFullPath($TargetFile)

    if ($absSource -ieq $absTarget) {
        Write-Host "Source and Target are the same location ($absTarget). No symlink needed." -ForegroundColor Magenta
        return
    }

    # Check if target already exists
	if (Test-Path $TargetFile) {
        $item = Get-Item $TargetFile
        # Check if it's already a link to our repo
		if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $absSource) {
            Write-Host "Link already exists and is correct: $TargetFile" -ForegroundColor Gray
            return
        }
        
		# If it exists but isn't our link, back it up (unless it's a different link, then delete)
		if ($item.LinkType -eq "SymbolicLink") {
			Write-Host "Removing existing different symlink: $TargetFile"
            Remove-Item $TargetFile -Force
        } else {
            $backupName = "$TargetFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Write-Host "Backing up existing file to $backupName"
            Rename-Item -Path $TargetFile -NewName $backupName
        }
    }

	# Create the symlink
    Write-Host "Creating symlink: $TargetFile -> $absSource" -ForegroundColor Yellow
    New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force | Out-Null
}

# ---------------------------------------------------------
# 1. Install Scoop & Git
# ---------------------------------------------------------
Write-Host "`n[1/6] Checking Scoop & Git..." -ForegroundColor Green
if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
}

if ((scoop list git 2>$null) -notmatch "git") {
    Write-Host "Installing Scoop Git..."
    scoop install git
}

# ---------------------------------------------------------
# 2. Add Extras & Install Tools
# ---------------------------------------------------------
Write-Host "`n[2/6] Installing CLI Tools..." -ForegroundColor Green
scoop bucket add extras 2>$null
$tools = @("zoxide", "fzf", "bat", "ripgrep", "fd", "eza")
foreach ($tool in $tools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) { scoop install $tool }
}

# ---------------------------------------------------------
# 3. Install Oh My Posh (Winget)
# ---------------------------------------------------------
Write-Host "`n[3/6] Installing Oh My Posh..." -ForegroundColor Green
if (!(Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements
}

# ---------------------------------------------------------
# 4. Install PowerShell Modules
# ---------------------------------------------------------
Write-Host "`n[4/6] Installing PowerShell Modules (PSFzf, Terminal-Icons)..." -ForegroundColor Green
$modules = @("PSFzf", "Terminal-Icons")
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module"
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
    } else {
        Write-Host "Module $module is already installed." -ForegroundColor Gray
    }
}

# ---------------------------------------------------------
# 5. Backup & Symlink Configurations
# ---------------------------------------------------------
Write-Host "`n[5/6] Configuring Profiles & Symlinks..." -ForegroundColor Green

# A. Windows Terminal
$wtPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState"
$wtResolvedPath = Get-ChildItem -Path $wtPath -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wtResolvedPath) {
    Set-Symlink -SourceFile "$RepoPath\settings.json" -TargetFile "$($wtResolvedPath.FullName)\settings.json"
}

# B. PowerShell Profile
$profileDir = Split-Path -Path $PROFILE
if (!(Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
Set-Symlink -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" -TargetFile $PROFILE

# C. Oh My Posh Config
if (!(Test-Path $OmpTargetDir)) { New-Item -ItemType Directory -Path $OmpTargetDir -Force | Out-Null }
Set-Symlink -SourceFile "$RepoPath\$OmpConfigName" -TargetFile "$OmpTargetDir\$OmpConfigName"

Write-Host "`n[6/6] Setup Complete!" -ForegroundColor Cyan
