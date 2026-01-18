<#
.SYNOPSIS
    Setup script for slmlm2009 Windows Terminal environment.
#>

# 0. Admin Check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Administrator privileges required." -ForegroundColor Red
    Write-Warning "Please right-click PowerShell and 'Run as Administrator'."
    Break
}

$RepoPath = $PSScriptRoot
Write-Host "`n>>> Starting Deployment from: $RepoPath" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

$OmpConfigName = "slmlm2009.omp.yaml"
$OmpTargetDir  = "$HOME\.omp"

# Helper Function for Symlinks (With Clean Output)
function Set-Symlink {
    param ([string]$SourceFile, [string]$TargetFile)

    # Use the filename as the display name for cleaner output
    $DisplayName = Split-Path $TargetFile -Leaf

    if (!(Test-Path $SourceFile)) {
        Write-Host "  [-] $DisplayName : Source missing ($SourceFile)" -ForegroundColor Yellow
        return
    }

    $absSource = (Resolve-Path $SourceFile).Path
    $absTarget = [System.IO.Path]::GetFullPath($TargetFile)

    # 1. Self-Reference Check
    if ($absSource -ieq $absTarget) {
        Write-Host "  [OK] $DisplayName : Already in correct location" -ForegroundColor Gray
        return
    }

    # 2. Existing Target Check
    if (Test-Path $TargetFile) {
        $item = Get-Item $TargetFile
        
        # Check if it's already a correct symlink
        if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $absSource) {
            Write-Host "  [OK] $DisplayName : Symlink already correct" -ForegroundColor Gray
            return
        }
        
        # Backup existing file/link
        if ($item.LinkType -eq "SymbolicLink") {
            Remove-Item $TargetFile -Force
        } else {
            $backup = "$TargetFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Rename-Item -Path $TargetFile -NewName $backup
            Write-Host "  [!] $DisplayName : Backup created (.bak)" -ForegroundColor Magenta
        }
    }

    # 3. Create Link
    New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force | Out-Null
    Write-Host "  [+] $DisplayName : Symlink created" -ForegroundColor Green
}

# ---------------------------------------------------------
# 1. Scoop & Git
# ---------------------------------------------------------
Write-Host "`n[1/4] Environment: Scoop & Git" -ForegroundColor Blue

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
    Write-Host "  [OK] Git (Scoop version) is present" -ForegroundColor Gray
}

# ---------------------------------------------------------
# 2. CLI Tools
# ---------------------------------------------------------
Write-Host "`n[2/4] CLI Tools (Scoop)" -ForegroundColor Blue

if (!(scoop bucket list | Select-String "extras")) {
    scoop bucket add extras | Out-Null
}

$tools = @("zoxide", "fzf", "bat", "ripgrep", "fd", "eza")

foreach ($tool in $tools) {
    # FIX: ripgrep installs as 'ripgrep' but runs as 'rg'
    $cmdCheck = if ($tool -eq "ripgrep") { "rg" } else { $tool }

    if (!(Get-Command $cmdCheck -ErrorAction SilentlyContinue)) {
        Write-Host "  [..] Installing $tool..." -ForegroundColor White
        scoop install $tool | Out-Null
        Write-Host "  [+] $tool installed" -ForegroundColor Green
    } else {
        Write-Host "  [OK] $tool is already installed" -ForegroundColor Gray
    }
}

# ---------------------------------------------------------
# 3. Oh My Posh
# ---------------------------------------------------------
Write-Host "`n[3/4] Prompt: Oh My Posh" -ForegroundColor Blue

if (!(Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing Oh My Posh..." -ForegroundColor White
    winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements | Out-Null
    Write-Host "  [+] Oh My Posh installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] Oh My Posh is already installed" -ForegroundColor Gray
}

# ---------------------------------------------------------
# 4. Configuration Symlinks
# ---------------------------------------------------------
Write-Host "`n[4/4] Configuration Symlinks" -ForegroundColor Blue

# A. Windows Terminal
$wtPath = "$env:LOCAL
