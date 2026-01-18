<#
.SYNOPSIS
    Setup for slmlm2009 Windows Terminal environment (SSH-safe v3).
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
# HELPER: Hierarchical Directory Creation
# ============================================================
function New-DirectoryHierarchical {
    param([string]$Path)

    $absPath = [System.IO.Path]::GetFullPath($Path)
    if (Test-Path $absPath) { return $absPath }

    # Method 1: CMD mkdir (bypasses PowerShell provider)
    cmd /c "mkdir `"$absPath`"" 2>$null
    Start-Sleep -Milliseconds 500
    if (Test-Path $absPath) { return $absPath }

    # Method 2: PowerShell New-Item
    try {
        New-Item -ItemType Directory -Path $absPath -Force -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 500
        if (Test-Path $absPath) { return $absPath }
    }
    catch { }

    # Method 3: Parent-by-parent
    $parts = $absPath.Split('\\') | Where-Object { $_ }
    $currentPath = ""

    foreach ($part in $parts) {
        if ($currentPath -eq "") {
            $currentPath = $part
        } else {
            $currentPath = Join-Path $currentPath $part
        }

        if (!(Test-Path $currentPath)) {
            try {
                cmd /c "mkdir `"$currentPath`"" 2>$null
                Start-Sleep -Milliseconds 200
            }
            catch { }
        }
    }

    Start-Sleep -Seconds 1

    if (Test-Path $absPath) {
        return $absPath
    }

    return $null
}

# ============================================================
# HELPER: Force File Ownership
# ============================================================
function Grant-FileOwnership {
    param([string]$Path)

    if (!(Test-Path $Path)) { return $true }

    try {
        takeown /f "$Path" /a 2>$null | Out-Null
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
        Grant-FileOwnership -Path $Path | Out-Null

        $item = Get-Item -Path $Path -Force -ErrorAction Stop
        $absPath = $item.FullName

        if ($item.Attributes -match "ReparsePoint" -or $item.LinkType) {
            $item.Delete()
            Start-Sleep -Milliseconds 200
            if (!(Test-Path $absPath)) { return $true }
        }

        if ($item.PSIsContainer) {
            cmd /c "rd /s /q `"$absPath`"" 2>$null
        } else {
            cmd /c "del /f /q /a `"$absPath`"" 2>$null
        }

        Start-Sleep -Milliseconds 200
        return (!(Test-Path $absPath))
    }
    catch {
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

    if ($absSource -eq $absTarget) {
        Write-Host "  [OK] $DisplayName : Already in place" -ForegroundColor Gray
        return
    }

    if (Test-Path $TargetFile) {
        $item = Get-Item $TargetFile -Force
        if ($item.LinkType -eq "SymbolicLink") {
            $currentTarget = $item.Target
            if ($currentTarget -eq $absSource -or $currentTarget -eq $SourceFile) {
                Write-Host "  [OK] $DisplayName : Symlink valid" -ForegroundColor Gray
                return
            }
        }

        if (!(Remove-ItemNuclear -Path $absTarget)) {
            Write-Host "  [X] $DisplayName : Failed to remove existing" -ForegroundColor Red
            return $false
        }
    }

    $parentDir = Split-Path -Path $TargetFile -Parent
    if (!(Test-Path $parentDir)) {
        $created = New-DirectoryHierarchical -Path $parentDir
        if (!$created) {
            Write-Host "  [X] $DisplayName : Cannot create parent directory" -ForegroundColor Red
            return $false
        }
        Grant-FileOwnership -Path $created | Out-Null
    }

    try {
        New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 200

        if (Test-Path $TargetFile) {
            Write-Host "  [+] $DisplayName : Symlink created" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [X] $DisplayName : Creation failed" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "  [X] $DisplayName : $($_.Exception.Message)" -ForegroundColor Red
        return $false
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

# Map tool names to their actual executable names
$toolMap = @{
    "zoxide"   = "zoxide"
    "fzf"      = "fzf"
    "bat"      = "bat"
    "ripgrep"  = "rg"      # ripgrep binary is 'rg'
    "fd"       = "fd"
    "eza"      = "eza"
}

foreach ($toolPackage in $toolMap.Keys) {
    $toolExe = $toolMap[$toolPackage]

    if (!(Get-Command $toolExe -ErrorAction SilentlyContinue)) {
        Write-Host "  [..] Installing $toolPackage..." -ForegroundColor Yellow

        $installed = $false
        for ($i = 1; $i -le 2; $i++) {
            scoop install $toolPackage *>$null 2>&1
            Start-Sleep -Milliseconds 500

            if (Get-Command $toolExe -ErrorAction SilentlyContinue) {
                $installed = $true
                break
            }
        }

        if ($installed) {
            Write-Host "  [+] $toolPackage" -ForegroundColor Green
        } else {
            Write-Host "  [X] $toolPackage (verify with 'scoop list')" -ForegroundColor Red
        }
    } else {
        Write-Host "  [OK] $toolPackage" -ForegroundColor Gray
    }
}

# ============================================================
# 3. OH MY POSH
# ============================================================
Write-Host "`n[3/6] Prompt: Oh My Posh" -ForegroundColor Blue

if (!(Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host "  [..] Installing Oh My Posh..." -ForegroundColor Yellow
    winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements --silent *>$null 2>&1

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
# 4. POWERSHELL MODULES (MULTI-PATH FALLBACK)
# ============================================================
Write-Host "`n[4/6] PowerShell Modules (PSGallery)" -ForegroundColor Blue

# === Define fallback paths ===
$modulePaths = @(
    "$HOME\Documents\PowerShell\Modules",
    "$HOME\Documents\WindowsPowerShell\Modules",
    "$env:LOCALAPPDATA\PowerShell\Modules",
    "$env:APPDATA\PowerShell\Modules"
)

$userModPath = $null

foreach ($testPath in $modulePaths) {
    $result = New-DirectoryHierarchical -Path $testPath

    if ($result -and (Test-Path $result)) {
        $userModPath = $result
        Write-Host "  [+] Module path: $userModPath" -ForegroundColor Green
        break
    }
}

if (!$userModPath) {
    Write-Host "  [!] Using TEMP module path" -ForegroundColor Yellow
    $userModPath = "$env:TEMP\PSModules"
    $result = New-DirectoryHierarchical -Path $userModPath
    if (!$result) {
        Write-Host "  [X] Critical: Cannot create any module path" -ForegroundColor Red
        Write-Host "------------------------------------------------------------"
        Write-Host "[6/6] Setup Failed (Module Path Error)" -ForegroundColor Red
        Exit 1
    }
}

Grant-FileOwnership -Path $userModPath | Out-Null

if ($env:PSModulePath -notlike "*$userModPath*") {
    $env:PSModulePath = "$userModPath;$env:PSModulePath"
}

# === Ensure NuGet and PSGallery ===
$nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if (!$nuget -or ($nuget.Version -lt [Version]"2.8.5.201")) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -WarningAction SilentlyContinue | Out-Null
}

$psRepo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if ($psRepo.InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -WarningAction SilentlyContinue
}

# === Install modules with verification ===
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

    # FALLBACK: TEMP staging + move
    try {
        $tempSavePath = "$env:TEMP\PSModules_$(Get-Random)"
        cmd /c "mkdir `"$tempSavePath`"" 2>$null
        Start-Sleep -Milliseconds 500

        if (!(Test-Path $tempSavePath)) {
            Write-Host "  [X] $module : Cannot create temp directory" -ForegroundColor Red
            continue
        }

        Save-Module -Name $module -Path $tempSavePath -Force -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null

        $moduleFolderTemp = Join-Path $tempSavePath $module
        $moduleFolderFinal = Join-Path $userModPath $module

        if (Test-Path $moduleFolderTemp) {
            if (Test-Path $moduleFolderFinal) {
                Remove-Item -Path $moduleFolderFinal -Recurse -Force -ErrorAction SilentlyContinue
            }

            Move-Item -Path $moduleFolderTemp -Destination $userModPath -Force
            Remove-Item -Path $tempSavePath -Recurse -Force -ErrorAction SilentlyContinue

            Start-Sleep -Milliseconds 500

            # Verify module is actually loadable
            if (Get-Module -ListAvailable -Name $module) {
                try {
                    Import-Module $module -ErrorAction Stop -WarningAction SilentlyContinue
                    Write-Host "  [+] $module (verified)" -ForegroundColor Green
                }
                catch {
                    Write-Host "  [+] $module (installed, import may need restart)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [X] $module : Not detected after staging" -ForegroundColor Red
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

# --- PowerShell Profile (with fallback location) ---
$profileDir = Split-Path -Path $PROFILE
$profileDirCreated = New-DirectoryHierarchical -Path $profileDir

if (!$profileDirCreated) {
    Write-Host "  [!] Documents tree locked, using AppData profile location" -ForegroundColor Yellow

    # Fallback: Use same directory as modules if Documents is inaccessible
    $fallbackProfile = Join-Path $userModPath "Microsoft.PowerShell_profile.ps1"

    # Add to PSModulePath search so profile is still found
    if ($env:PSModulePath -notlike "*$userModPath*") {
        $env:PSModulePath = "$userModPath;$env:PSModulePath"
    }

    $success = Set-SymlinkSafe -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" -TargetFile $fallbackProfile -DisplayName "PS Profile (Fallback)"

    if ($success) {
        Write-Host "  [!] NOTE: Profile at non-standard location: $fallbackProfile" -ForegroundColor Yellow
        Write-Host "  [!] Add to `$PROFILE via: . `"$fallbackProfile`"" -ForegroundColor Yellow
    }
} else {
    if (Test-Path $PROFILE) {
        Grant-FileOwnership -Path $PROFILE | Out-Null
    }

    $success = Set-SymlinkSafe -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" -TargetFile $PROFILE -DisplayName "PS Profile"

    # If standard location still fails, try fallback
    if (!$success) {
        Write-Host "  [!] Trying fallback profile location..." -ForegroundColor Yellow
        $fallbackProfile = Join-Path $userModPath "Microsoft.PowerShell_profile.ps1"

        $fbSuccess = Set-SymlinkSafe -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" -TargetFile $fallbackProfile -DisplayName "PS Profile (Fallback)"

        if ($fbSuccess) {
            Write-Host "  [!] Profile at: $fallbackProfile" -ForegroundColor Yellow
            Write-Host "  [!] To use, add to your `$PROFILE: . `"$fallbackProfile`"" -ForegroundColor Yellow
        }
    }
}

# --- Oh My Posh Config ---
$ompDirCreated = New-DirectoryHierarchical -Path $OmpTargetDir
if (!$ompDirCreated) {
    Write-Host "  [X] Cannot create OMP directory" -ForegroundColor Red
} else {
    Set-SymlinkSafe -SourceFile "$RepoPath\$OmpConfigName" -TargetFile "$OmpTargetDir\$OmpConfigName" -DisplayName "OMP Config"
}

# ============================================================
# 6. COMPLETION
# ============================================================
Write-Host "`n------------------------------------------------------------"
Write-Host "[6/6] Setup Complete!" -ForegroundColor Cyan
Write-Host "`nRECOMMENDED: Restart terminal to load profile and PATH updates.`n" -ForegroundColor Yellow
