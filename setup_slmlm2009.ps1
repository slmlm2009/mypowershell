<#
.SYNOPSIS
    Setup for slmlm2009 Windows Terminal environment
#>

#Requires -RunAsAdministrator

# ============================================================
# 0. SESSION PREP
# ============================================================
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Administrator privileges required." -ForegroundColor Red
    Exit 1
}

# Force TLS 1.2 globally for all web operations
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoPath = $PSScriptRoot
Write-Host "`n>>> Starting Deployment from: $RepoPath" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

$OmpConfigName = "slmlm2009.omp.yaml"
$OmpTargetDir  = "$HOME\.omp"

# ============================================================
# HELPER: Nuclear File/Symlink Deletion
# ============================================================
function Remove-ItemNuclear {
    param([string]$Path)
    
    if (!(Test-Path $Path)) { return $true }
    
    try {
        $item = Get-Item -Path $Path -Force -ErrorAction Stop
        $absPath = $item.FullName
        
        # Try native .NET delete first (works for most symlinks)
        if ($item.Attributes -match "ReparsePoint" -or $item.LinkType) {
            $item.Delete()
            Start-Sleep -Milliseconds 100
            if (!(Test-Path $absPath)) { return $true }
        }
        
        # Fallback: Nuclear CMD approach (bypasses PowerShell provider locks)
        if ($item.PSIsContainer) {
            cmd /c "rd /s /q `"$absPath`"" 2>$null
        } else {
            cmd /c "del /f /q /a `"$absPath`"" 2>$null
        }
        
        Start-Sleep -Milliseconds 100
        return (!(Test-Path $absPath))
    }
    catch {
        # Last resort: Force with attrib reset
        cmd /c "attrib -r -s -h `"$Path`"" 2>$null
        cmd /c "del /f /q /a `"$Path`"" 2>$null
        Start-Sleep -Milliseconds 100
        return (!(Test-Path $Path))
    }
}

# ============================================================
# HELPER: Recursive-Safe Symlink Creation
# ============================================================
function Set-SymlinkSafe {
    param(
        [string]$SourceFile,
        [string]$TargetFile,
        [string]$DisplayName
    )
    
    if (!(Test-Path $SourceFile)) {
        Write-Host "  [X] $DisplayName : Source not found" -ForegroundColor Red
        return
    }

    # Resolve absolute paths for comparison
    $absSource = (Resolve-Path $SourceFile).Path
    $absTarget = [System.IO.Path]::GetFullPath($TargetFile)

    # CRITICAL: Prevent recursive symlink (source == target)
    if ($absSource -eq $absTarget) {
        Write-Host "  [OK] $DisplayName : Already in place" -ForegroundColor Gray
        return
    }

    # Check if correct symlink already exists
    if (Test-Path $TargetFile) {
        $item = Get-Item $TargetFile -Force
        if ($item.LinkType -eq "SymbolicLink") {
            $currentTarget = $item.Target
            if ($currentTarget -eq $absSource -or $currentTarget -eq $SourceFile) {
                Write-Host "  [OK] $DisplayName : Symlink valid" -ForegroundColor Gray
                return
            }
        }
        
        # Remove existing (wrong symlink or regular file)
        if (!(Remove-ItemNuclear -Path $absTarget)) {
            Write-Host "  [X] $DisplayName : Failed to remove existing" -ForegroundColor Red
            return
        }
    }

    # Create symlink
    try {
        New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 100
        
        if (Test-Path $TargetFile) {
            Write-Host "  [+] $DisplayName : Symlink created" -ForegroundColor Green
        } else {
            Write-Host "  [X] $DisplayName : Creation failed" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  [X] $DisplayName : $_" -ForegroundColor Red
    }
}

# ============================================================
# 1. ENVIRONMENT: SCOOP & GIT
# ============================================================
Write-Host "`n[1/6] Environment: Scoop & Git" -ForegroundColor Blue

if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing Scoop..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression *>$null
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "  [+] Scoop installed" -ForegroundColor Green
    } else {
        Write-Host "  [X] Scoop installation failed" -ForegroundColor Red
    }
} else {
    Write-Host "  [OK] Scoop ready" -ForegroundColor Gray
}

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing Git..." -ForegroundColor Yellow
    scoop install git *>$null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "  [+] Git installed" -ForegroundColor Green
    } else {
        Write-Host "  [X] Git installation failed" -ForegroundColor Red
    }
} else {
    Write-Host "  [OK] Git ready" -ForegroundColor Gray
}

# ============================================================
# 2. CLI TOOLS (SCOOP)
# ============================================================
Write-Host "`n[2/6] CLI Tools (Scoop)" -ForegroundColor Blue

$buckets = scoop bucket list 2>$null | Out-String
if ($buckets -notmatch "extras") {
    scoop bucket add extras *>$null
}

$tools = @("zoxide", "fzf", "bat", "ripgrep", "fd", "eza")
foreach ($tool in $tools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "  [..] Installing $tool..." -ForegroundColor Yellow
        scoop install $tool *>$null
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            Write-Host "  [+] $tool" -ForegroundColor Green
        } else {
            Write-Host "  [X] $tool failed" -ForegroundColor Red
        }
    } else {
        Write-Host "  [OK] $tool" -ForegroundColor Gray
    }
}

# ============================================================
# 3. OH MY POSH
# ============================================================
Write-Host "`n[3/6] Prompt: Oh My Posh" -ForegroundColor Blue

if (!(Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing Oh My Posh..." -ForegroundColor Yellow
    winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements --silent *>$null 2>&1
    
    # Refresh PATH to detect newly installed binaries
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Host "  [+] Oh My Posh" -ForegroundColor Green
    } else {
        Write-Host "  [X] Oh My Posh failed (may need terminal restart)" -ForegroundColor Red
    }
} else {
    Write-Host "  [OK] Oh My Posh" -ForegroundColor Gray
}

# ============================================================
# 4. POWERSHELL MODULES (SSH-SAFE)
# ============================================================
Write-Host "`n[4/6] PowerShell Modules (PSGallery)" -ForegroundColor Blue

# === STEP 1: Identify and validate user module path ===
$userModPath = ($env:PSModulePath -split ';' | Where-Object { $_ -like "*$HOME*" -and $_ -notlike "*Program Files*" } | Select-Object -First 1)

if ([string]::IsNullOrWhiteSpace($userModPath)) {
    # Fallback to PowerShell 7+ default or legacy path
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $userModPath = "$HOME\Documents\PowerShell\Modules"
    } else {
        $userModPath = "$HOME\Documents\WindowsPowerShell\Modules"
    }
}

# Create if missing
if (!(Test-Path $userModPath)) {
    Write-Host "  [..] Creating module path: $userModPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $userModPath -Force | Out-Null
    Start-Sleep -Seconds 2  # Critical: Let filesystem propagate
}

# Ensure it's in PSModulePath for this session
if ($env:PSModulePath -notlike "*$userModPath*") {
    $env:PSModulePath = "$userModPath;$env:PSModulePath"
}

Write-Host "  [OK] Module path: $userModPath" -ForegroundColor Gray

# === STEP 2: Ensure NuGet and PSGallery trust ===
$nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if (!$nuget -or ($nuget.Version -lt [Version]"2.8.5.201")) {
    Write-Host "  [..] Installing NuGet provider..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -WarningAction SilentlyContinue | Out-Null
}

$psRepo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if ($psRepo.InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -WarningAction SilentlyContinue
}

# === STEP 3: Install modules with SSH-safe fallback ===
$modules = @("PSFzf", "Terminal-Icons")

foreach ($module in $modules) {
    if (Get-Module -ListAvailable -Name $module) {
        Write-Host "  [OK] $module" -ForegroundColor Gray
        continue
    }
    
    Write-Host "  [..] Installing $module..." -ForegroundColor Yellow
    
    # === PRIMARY: Try standard Install-Module ===
    try {
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        
        if (Get-Module -ListAvailable -Name $module) {
            Write-Host "  [+] $module" -ForegroundColor Green
            continue
        }
    }
    catch {
        # Expected in filtered token SSH sessions
    }
    
    # === FALLBACK: Manual Save-Module (bypass temp folder issues) ===
    try {
        Write-Host "  [..] Trying manual save for $module..." -ForegroundColor Yellow
        
        # Double-check path exists (race condition mitigation)
        if (!(Test-Path $userModPath)) {
            New-Item -ItemType Directory -Path $userModPath -Force | Out-Null
            Start-Sleep -Seconds 2
        }
        
        # Save directly to user modules path
        Save-Module -Name $module -Path $userModPath -Force -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 500  # Let module registration complete
        
        if (Get-Module -ListAvailable -Name $module) {
            Write-Host "  [+] $module (manual)" -ForegroundColor Green
        } else {
            Write-Host "  [X] $module failed" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  [X] $module : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================
# 5. CONFIGURATION SYMLINKS
# ============================================================
Write-Host "`n[5/6] Configuration Symlinks" -ForegroundColor Blue

# --- Windows Terminal settings.json ---
$wtPattern = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState"
$wtResolved = Get-ChildItem -Path $wtPattern -ErrorAction SilentlyContinue | Select-Object -First 1

if ($wtResolved) {
    Set-SymlinkSafe -SourceFile "$RepoPath\settings.json" -TargetFile "$($wtResolved.FullName)\settings.json" -DisplayName "Terminal Settings"
} else {
    Write-Host "  [X] Windows Terminal not found" -ForegroundColor Red
}

# --- PowerShell Profile ---
$profileDir = Split-Path -Path $PROFILE
if (!(Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

Set-SymlinkSafe -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" -TargetFile $PROFILE -DisplayName "PS Profile"

# --- Oh My Posh Config ---
if (!(Test-Path $OmpTargetDir)) {
    New-Item -ItemType Directory -Path $OmpTargetDir -Force | Out-Null
}

Set-SymlinkSafe -SourceFile "$RepoPath\$OmpConfigName" -TargetFile "$OmpTargetDir\$OmpConfigName" -DisplayName "OMP Config"

# ============================================================
# 6. COMPLETION
# ============================================================
Write-Host "`n------------------------------------------------------------"
Write-Host "[6/6] Setup Complete!" -ForegroundColor Cyan
Write-Host "`nRECOMMENDED: Restart terminal to load profile and PATH updates.`n" -ForegroundColor Yellow
