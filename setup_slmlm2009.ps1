#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Automated PowerShell environment setup script for Windows hosts
.DESCRIPTION
    This script installs and configures:
    - Scoop package manager with required buckets
    - Git and CLI tools (zoxide, fzf, bat, ripgrep, fd, eza)
    - Oh My Posh prompt theme
    - Creates symlinks to PowerShell profile and Windows Terminal settings
.NOTES
    Author: slmlm2009
    Run this script AFTER cloning the mypowershell repository
    Usage: .\setup_slmlm2009.ps1
#>

# =============================================================================
# CONFIGURATION
# =============================================================================
$ErrorActionPreference = 'Stop'
$RepoPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupFolder = "$env:USERPROFILE\.config_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Paths
$ProfilePath = $PROFILE
$TerminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$OMPConfigPath = "$env:USERPROFILE\.omp_config.yaml"

# Files in repo
$RepoProfileFile = Join-Path $RepoPath "Microsoft.PowerShell_profile.ps1"
$RepoTerminalSettings = Join-Path $RepoPath "settings.json"
$RepoOMPConfig = Join-Path $RepoPath "slmlm2009.omp.yaml"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  slmlm2009 PowerShell Setup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Status {
    param([string]$Message, [string]$Type = 'Info')
    $color = switch ($Type) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'White' }
    }
    Write-Host "[*] $Message" -ForegroundColor $color
}

function Backup-File {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        if (-not (Test-Path $BackupFolder)) {
            New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
        }
        $fileName = Split-Path $FilePath -Leaf
        Copy-Item $FilePath "$BackupFolder\$fileName" -Force
        Write-Status "Backed up: $fileName" 'Success'
    }
}

function Create-Symlink {
    param([string]$Target, [string]$Link)
    
    # Backup existing file
    Backup-File -FilePath $Link
    
    # Remove existing file/link
    if (Test-Path $Link) {
        Remove-Item $Link -Force
    }
    
    # Ensure parent directory exists
    $linkDir = Split-Path $Link -Parent
    if (-not (Test-Path $linkDir)) {
        New-Item -ItemType Directory -Path $linkDir -Force | Out-Null
    }
    
    # Create symlink
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force | Out-Null
        Write-Status "Symlinked: $(Split-Path $Link -Leaf) -> $(Split-Path $Target -Leaf)" 'Success'
    } catch {
        Write-Status "Failed to create symlink for $(Split-Path $Link -Leaf): $_" 'Error'
    }
}

# =============================================================================
# MAIN INSTALLATION
# =============================================================================

# Check administrator privileges
if (-not (Test-Administrator)) {
    Write-Status "This script requires administrator privileges. Please run as Administrator." 'Error'
    exit 1
}

Write-Status "Starting setup..." 'Info'
Write-Status "Repository path: $RepoPath" 'Info'
Write-Status "Backup folder: $BackupFolder" 'Info'
Write-Host ""

# =============================================================================
# 1. INSTALL SCOOP
# =============================================================================
Write-Host "[1/5] Checking Scoop installation..." -ForegroundColor Yellow

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Status "Installing Scoop package manager..." 'Info'
    
    # Set execution policy
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    
    # Install Scoop
    try {
        Invoke-RestMethod get.scoop.sh | Invoke-Expression
        Write-Status "Scoop installed successfully" 'Success'
    } catch {
        Write-Status "Failed to install Scoop: $_" 'Error'
        exit 1
    }
    
    # Refresh environment
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
else {
    Write-Status "Scoop is already installed" 'Success'
}

# =============================================================================
# 2. INSTALL GIT (Required for Scoop buckets)
# =============================================================================
Write-Host ""
Write-Host "[2/5] Checking Git installation..." -ForegroundColor Yellow

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Status "Installing Git..." 'Info'
    scoop install git
    Write-Status "Git installed successfully" 'Success'
else {
    Write-Status "Git is already installed" 'Success'
}

# =============================================================================
# 3. ADD SCOOP BUCKETS AND INSTALL TOOLS
# =============================================================================
Write-Host ""
Write-Host "[3/5] Installing CLI tools via Scoop..." -ForegroundColor Yellow

# Add extras bucket
Write-Status "Adding extras bucket..." 'Info'
scoop bucket add extras 2>$null

# List of tools to install
$tools = @(
    'zoxide',
    'fzf',
    'bat',
    'ripgrep',
    'fd',
    'eza',
    '7zip',
    'sudo'
)

foreach ($tool in $tools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Status "Installing $tool..." 'Info'
        scoop install $tool
    } else {
        Write-Status "$tool is already installed" 'Success'
    }
}

# Install PSFzf module
Write-Status "Installing PSFzf module..." 'Info'
if (-not (Get-Module -ListAvailable PSFzf)) {
    Install-Module -Name PSFzf -Scope CurrentUser -Force -AllowClobber
    Write-Status "PSFzf module installed" 'Success'
else {
    Write-Status "PSFzf module is already installed" 'Success'
}

# Install Terminal-Icons module (optional)
Write-Status "Installing Terminal-Icons module..." 'Info'
if (-not (Get-Module -ListAvailable Terminal-Icons)) {
    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -AllowClobber
    Write-Status "Terminal-Icons module installed" 'Success'
else {
    Write-Status "Terminal-Icons module is already installed" 'Success'
}

# =============================================================================
# 4. INSTALL OH MY POSH
# =============================================================================
Write-Host ""
Write-Host "[4/5] Installing Oh My Posh..." -ForegroundColor Yellow

if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Status "Installing Oh My Posh via winget..." 'Info'
    try {
        winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements
        
        # Refresh environment to pick up oh-my-posh
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Status "Oh My Posh installed successfully" 'Success'
    } catch {
        Write-Status "Failed to install Oh My Posh: $_" 'Error'
    }
else {
    Write-Status "Oh My Posh is already installed" 'Success'
}

# =============================================================================
# 5. CREATE SYMLINKS
# =============================================================================
Write-Host ""
Write-Host "[5/5] Creating symlinks to configuration files..." -ForegroundColor Yellow

# Verify repo files exist
if (-not (Test-Path $RepoProfileFile)) {
    Write-Status "ERROR: PowerShell profile not found in repo: $RepoProfileFile" 'Error'
    exit 1
}

if (-not (Test-Path $RepoOMPConfig)) {
    Write-Status "ERROR: Oh My Posh config not found in repo: $RepoOMPConfig" 'Error'
    exit 1
}

if (-not (Test-Path $RepoTerminalSettings)) {
    Write-Status "WARNING: Windows Terminal settings not found in repo: $RepoTerminalSettings" 'Warning'
    Write-Status "Skipping Terminal settings symlink..." 'Warning'
    $skipTerminalSettings = $true
}

# Create PowerShell profile symlink
Write-Status "Creating PowerShell profile symlink..." 'Info'
Create-Symlink -Target $RepoProfileFile -Link $ProfilePath

# Create Oh My Posh config symlink
Write-Status "Creating Oh My Posh config symlink..." 'Info'
Create-Symlink -Target $RepoOMPConfig -Link $OMPConfigPath

# Create Windows Terminal settings symlink
if (-not $skipTerminalSettings) {
    Write-Status "Creating Windows Terminal settings symlink..." 'Info'
    Create-Symlink -Target $RepoTerminalSettings -Link $TerminalSettingsPath
}

# =============================================================================
# COMPLETION
# =============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Status "Backups saved to: $BackupFolder" 'Info'
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Restart your terminal" -ForegroundColor White
Write-Host "  2. Verify Oh My Posh is loaded" -ForegroundColor White
Write-Host "  3. Run 'sprofile' to reload your profile" -ForegroundColor White
Write-Host ""
Write-Host "Enjoy your Linux-like PowerShell experience!" -ForegroundColor Green
