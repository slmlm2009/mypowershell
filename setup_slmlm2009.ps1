<#
.SYNOPSIS
    Hardened setup for slmlm2009 Windows Terminal environment (SSH-safe v2).
.NOTES
    Fixes for SSH filtered token: module path visibility, profile ownership, error recovery.
#>

#Requires -RunAsAdministrator

# ============================================================
# 0. SESSION PREP
# ============================================================
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Administrator privileges required." -ForegroundColor Red
    Exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoPath = $PSScriptRoot
Write-Host "`n>>> Starting Deployment from: $RepoPath" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

$OmpConfigName = "slmlm2009.omp.yaml"
$OmpTargetDir  = "$HOME\.omp"

# ============================================================
# HELPER: Force File Ownership (SSH-safe)
# ============================================================
function Grant-FileOwnership {
    param([string]$Path)

    if (!(Test-Path $Path)) { return $true }

    try {
        # Take ownership as Administrators group
        takeown /f "$Path" /a 2>$null | Out-Null

        # Grant full control to current user and Administrators
        icacls "$Path" /grant "${env:USERNAME}:F" /grant "Administrators:F" /t /c /q 2>$null | Out-Null

        return $true
    }
    catch {
        return $false
    }
}

# ============================================================
# HELPER: Nuclear File/Symlink Deletion
# ============================================================
function Remove-ItemNuclear {
    param([string]$Path)

    if (!(Test-Path $Path)) { return $true }

    try {
        # Force ownership first
        Grant-FileOwnership -Path $Path | Out-Null

        $item = Get-Item -Path $Path -Force -ErrorAction Stop
        $absPath = $item.FullName

        # Try native .NET delete for symlinks/reparse points
        if ($item.Attributes -match "ReparsePoint" -or $item.LinkType) {
            $item.Delete()
            Start-Sleep -Milliseconds 200
            if (!(Test-Path $absPath)) { return $true }
        }

        # Nuclear CMD approach
        if ($item.PSIsContainer) {
            cmd /c "rd /s /q `"$absPath`"" 2>$null
        } else {
            cmd /c "del /f /q /a `"$absPath`"" 2>$null
        }

        Start-Sleep -Milliseconds 200
        return (!(Test-Path $absPath))
    }
    catch {
        # Last resort with attribute reset
        cmd /c "attrib -r -s -h `"$Path`"" 2>$null
        cmd /c "del /f /q /a `"$Path`"" 2>$null
        Start-Sleep -Milliseconds 200
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

    $absSource = (Resolve-Path $SourceFile).Path
    $absTarget = [System.IO.Path]::GetFullPath($TargetFile)

    # Prevent recursive symlink
    if ($absSource -eq $absTarget) {
        Write-Host "  [OK] $DisplayName : Already in place" -ForegroundColor Gray
        return
    }

    # Check if correct symlink exists
    if (Test-Path $TargetFile) {
        $item = Get-Item $TargetFile -Force
        if ($item.LinkType -eq "SymbolicLink") {
            $currentTarget = $item.Target
            if ($currentTarget -eq $absSource -or $currentTarget -eq $SourceFile) {
                Write-Host "  [OK] $DisplayName : Symlink valid" -ForegroundColor Gray
                return
            }
        }

        # Remove existing
        if (!(Remove-ItemNuclear -Path $absTarget)) {
            Write-Host "  [X] $DisplayName : Failed to remove existing" -ForegroundColor Red
            return
        }
    }

    # Ensure parent directory exists with proper permissions
    $parentDir = Split-Path -Path $TargetFile -Parent
    if (!(Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        Grant-FileOwnership -Path $parentDir | Out-Null
    }

    # Create symlink
    try {
        New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 200

        if (Test-Path $TargetFile) {
            Write-Host "  [+] $DisplayName : Symlink created" -ForegroundColor Green
        } else {
            Write-Host "  [X] $DisplayName : Creation failed" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  [X] $DisplayName : $($_.Exception.Message)" -ForegroundColor Red
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

        # Try install with retry for transient failures
        $installed = $false
        for ($i = 1; $i -le 2; $i++) {
            scoop install $tool *>$null 2>&1
            if (Get-Command $tool -ErrorAction SilentlyContinue) {
                $installed = $true
                break
            }
            Start-Sleep -Seconds 1
        }

        if ($installed) {
            Write-Host "  [+] $tool" -ForegroundColor Green
        } else {
            Write-Host "  [X] $tool (check 'scoop list' manually)" -ForegroundColor Red
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

    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Host "  [+] Oh My Posh" -ForegroundColor Green
    } else {
        Write-Host "  [X] Oh My Posh (may need terminal restart)" -ForegroundColor Red
    }
} else {
    Write-Host "  [OK] Oh My Posh" -ForegroundColor Gray
}

# ============================================================
# 4. POWERSHELL MODULES (SSH-SAFE WITH ABSOLUTE PATHS)
# ============================================================
Write-Host "`n[4/6] PowerShell Modules (PSGallery)" -ForegroundColor Blue

# === Discover user module path ===
$userModPath = ($env:PSModulePath -split ';' | Where-Object { 
    $_ -like "*$HOME*" -and $_ -notlike "*Program Files*" 
} | Select-Object -First 1)

if ([string]::IsNullOrWhiteSpace($userModPath)) {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $userModPath = "$HOME\Documents\PowerShell\Modules"
    } else {
        $userModPath = "$HOME\Documents\WindowsPowerShell\Modules"
    }
}

# Create with explicit filesystem flush
if (!(Test-Path $userModPath)) {
    Write-Host "  [..] Creating module path: $userModPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $userModPath -Force | Out-Null

    # CRITICAL: Force filesystem sync in SSH session
    [System.IO.Directory]::CreateDirectory($userModPath) | Out-Null
    Start-Sleep -Seconds 3

    # Verify creation
    if (!(Test-Path $userModPath)) {
        Write-Host "  [X] Failed to create module directory" -ForegroundColor Red
        Write-Host "------------------------------------------------------------"
        Write-Host "[6/6] Setup Incomplete (Module Path Error)" -ForegroundColor Red
        Exit 1
    }
}

# Grant full permissions to module path
Grant-FileOwnership -Path $userModPath | Out-Null

# Inject into session PSModulePath
if ($env:PSModulePath -notlike "*$userModPath*") {
    $env:PSModulePath = "$userModPath;$env:PSModulePath"
}

Write-Host "  [OK] Module path: $userModPath" -ForegroundColor Gray

# === Ensure NuGet and PSGallery ===
$nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if (!$nuget -or ($nuget.Version -lt [Version]"2.8.5.201")) {
    Write-Host "  [..] Installing NuGet provider..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -WarningAction SilentlyContinue | Out-Null
}

$psRepo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if ($psRepo.InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -WarningAction SilentlyContinue
}

# === Install modules with absolute path resolution ===
$modules = @("PSFzf", "Terminal-Icons")

foreach ($module in $modules) {
    if (Get-Module -ListAvailable -Name $module) {
        Write-Host "  [OK] $module" -ForegroundColor Gray
        continue
    }

    Write-Host "  [..] Installing $module..." -ForegroundColor Yellow

    # PRIMARY: Try Install-Module
    try {
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null

        if (Get-Module -ListAvailable -Name $module) {
            Write-Host "  [+] $module" -ForegroundColor Green
            continue
        }
    }
    catch { }

    # FALLBACK: Manual download with absolute path
    try {
        Write-Host "  [..] Manual save for $module..." -ForegroundColor Yellow

        # Resolve to absolute path and verify it exists
        $absoluteModPath = (Resolve-Path $userModPath -ErrorAction Stop).Path

        if (!(Test-Path $absoluteModPath)) {
            Write-Host "  [X] $module : Module path vanished" -ForegroundColor Red
            continue
        }

        # Download to TEMP first, then move (avoids Save-Module path issues)
        $tempSavePath = "$env:TEMP\PSModules_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempSavePath -Force | Out-Null

        Save-Module -Name $module -Path $tempSavePath -Force -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null

        # Move module folder to final destination
        $moduleFolderTemp = Join-Path $tempSavePath $module
        $moduleFolderFinal = Join-Path $absoluteModPath $module

        if (Test-Path $moduleFolderTemp) {
            if (Test-Path $moduleFolderFinal) {
                Remove-Item -Path $moduleFolderFinal -Recurse -Force
            }
            Move-Item -Path $moduleFolderTemp -Destination $absoluteModPath -Force
            Remove-Item -Path $tempSavePath -Recurse -Force -ErrorAction SilentlyContinue

            Start-Sleep -Milliseconds 500

            if (Get-Module -ListAvailable -Name $module) {
                Write-Host "  [+] $module (manual)" -ForegroundColor Green
            } else {
                Write-Host "  [X] $module : Not detected after save" -ForegroundColor Red
            }
        } else {
            Write-Host "  [X] $module : Save failed" -ForegroundColor Red
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

# --- Windows Terminal ---
$wtPattern = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState"
$wtResolved = Get-ChildItem -Path $wtPattern -ErrorAction SilentlyContinue | Select-Object -First 1

if ($wtResolved) {
    Set-SymlinkSafe -SourceFile "$RepoPath\settings.json" -TargetFile "$($wtResolved.FullName)\settings.json" -DisplayName "Terminal Settings"
} else {
    Write-Host "  [X] Windows Terminal not found" -ForegroundColor Red
}

# --- PowerShell Profile (with ownership fix) ---
$profileDir = Split-Path -Path $PROFILE
if (!(Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Grant-FileOwnership -Path $profileDir | Out-Null
}

# Grant ownership to profile file if it exists
if (Test-Path $PROFILE) {
    Grant-FileOwnership -Path $PROFILE | Out-Null
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
