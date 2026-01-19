<#
.SYNOPSIS
    Setup script for slmlm2009 Windows Terminal environment.

.DESCRIPTION
    Transforms a stock Windows terminal into a modern CLI environment by:
    - Installing Scoop package manager and essential CLI tools
    - Setting up Oh My Posh for a beautiful prompt
    - Creating symbolic links to configuration files from your dotfiles repo

.PARAMETER Interactive
    Prompts the user to select which components to install/configure.

.PARAMETER SkipTools
    Skips installation of CLI tools (zoxide, fzf, bat, etc.)

.PARAMETER SkipSymlinks
    Skips creation of configuration symlinks and backups of existing files.

.PARAMETER DryRun
    Shows what would be done without making any changes.

.PARAMETER Force
    Skips all confirmation prompts.

.EXAMPLE
    .\setup.ps1
    Runs the full setup with defaults.

.EXAMPLE
    .\setup.ps1 -Interactive
    Prompts for each component.

.EXAMPLE
    .\setup.ps1 -DryRun
    Shows what would be installed/configured without making changes.
#>

[CmdletBinding()]
param(
    [switch]$Interactive,
    [switch]$SkipTools,
    [switch]$SkipSymlinks,
    [switch]$DryRun,
    [switch]$Force
)

#region ==================== CONFIGURATION ====================

$script:Config = @{
    OmpConfigName = "slmlm2009.omp.yaml"
    OmpTargetDir  = "$HOME\.omp"
    
    # Define all CLI tools with metadata
    CliTools = @(
        @{ Name = "zoxide";  Command = "zoxide"; Description = "Smarter cd command" }
        @{ Name = "fzf";     Command = "fzf";    Description = "Fuzzy finder" }
        @{ Name = "bat";     Command = "bat";    Description = "cat with syntax highlighting" }
        @{ Name = "ripgrep"; Command = "rg";     Description = "Fast grep alternative" }
        @{ Name = "fd";      Command = "fd";     Description = "Fast find alternative" }
        @{ Name = "eza";     Command = "eza";    Description = "Modern ls replacement" }
    )
    
    # Symlink configurations
    Symlinks = @{
        PowerShellProfile = @{
            Name        = "PowerShell Profile"
            SourceFile  = "Microsoft.PowerShell_profile.ps1"
            TargetFile  = $PROFILE
            Description = "Custom PowerShell profile with aliases and functions"
        }
        WindowsTerminal = @{
            Name        = "Windows Terminal"
            SourceFile  = "settings.json"
            TargetFile  = $null  # Resolved dynamically
            Description = "Windows Terminal appearance and keybindings"
        }
        OhMyPosh = @{
            Name        = "Oh My Posh Theme"
            SourceFile  = "slmlm2009.omp.yaml"
            TargetFile  = "$HOME\.omp\slmlm2009.omp.yaml"
            Description = "Custom prompt theme configuration"
        }
    }
}

$script:RepoPath = $PSScriptRoot
$script:Stats = @{ Created = 0; Skipped = 0; Backed = 0; Failed = 0 }

#endregion

#region ==================== HELPER FUNCTIONS ====================

function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    
    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
}

function Write-Step {
    param(
        [string]$Number,
        [string]$Total,
        [string]$Title
    )
    Write-Host "`n[$Number/$Total] $Title" -ForegroundColor Blue
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Write-Status {
    param(
        [ValidateSet("OK", "New", "Skip", "Warn", "Error", "Info", "DryRun")]
        [string]$Type,
        [string]$Item,
        [string]$Message
    )
    
    $symbols = @{
        OK     = @{ Symbol = "[OK]";  Color = "Gray" }
        New    = @{ Symbol = "[+]";   Color = "Green" }
        Skip   = @{ Symbol = "[-]";   Color = "Yellow" }
        Warn   = @{ Symbol = "[!]";   Color = "Magenta" }
        Error  = @{ Symbol = "[X]";   Color = "Red" }
        Info   = @{ Symbol = "[..]";  Color = "White" }
        DryRun = @{ Symbol = "[?]";   Color = "Cyan" }
    }
    
    $s = $symbols[$Type]
    $display = if ($Message) { "$Item : $Message" } else { $Item }
    Write-Host "  $($s.Symbol) $display" -ForegroundColor $s.Color
}

function Test-AdminPrivileges {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-SessionPath {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + 
                [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
}

function Show-InteractiveMenu {
    param(
        [string]$Title,
        [hashtable[]]$Options,  # Array of @{ Key; Name; Description; Default }
        [switch]$MultiSelect
    )
    
    Write-Host "`n$Title" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor DarkGray
    
    $selected = @{}
    foreach ($opt in $Options) {
        $selected[$opt.Key] = $opt.Default
    }
    
    if ($MultiSelect) {
        Write-Host "Enter numbers to toggle selection, 'a' for all, 'n' for none, Enter to confirm:" -ForegroundColor DarkGray
    }
    
    $done = $false
    while (!$done) {
        Write-Host ""
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $opt = $Options[$i]
            $marker = if ($selected[$opt.Key]) { "[X]" } else { "[ ]" }
            $color = if ($selected[$opt.Key]) { "Green" } else { "Gray" }
            Write-Host "  $($i + 1). $marker $($opt.Name)" -ForegroundColor $color
            if ($opt.Description) {
                Write-Host "         $($opt.Description)" -ForegroundColor DarkGray
            }
        }
        
        if (!$MultiSelect) {
            $done = $true
            $choice = Read-Host "`nSelect an option (1-$($Options.Count))"
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $Options.Count) {
                return @($Options[$idx].Key)
            }
        } else {
            $input = Read-Host "`nChoice"
            switch ($input.ToLower()) {
                ""  { $done = $true }
                "a" { foreach ($k in $selected.Keys.Clone()) { $selected[$k] = $true } }
                "n" { foreach ($k in $selected.Keys.Clone()) { $selected[$k] = $false } }
                default {
                    $nums = $input -split "[,\s]+" | Where-Object { $_ -match "^\d+$" }
                    foreach ($n in $nums) {
                        $idx = [int]$n - 1
                        if ($idx -ge 0 -and $idx -lt $Options.Count) {
                            $key = $Options[$idx].Key
                            $selected[$key] = !$selected[$key]
                        }
                    }
                }
            }
        }
    }
    
    return ($selected.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key })
}

function Set-Symlink {
    param(
        [string]$SourceFile,
        [string]$TargetFile,
        [string]$DisplayName
    )
    
    if (!$DisplayName) {
        $DisplayName = Split-Path $TargetFile -Leaf
    }
    
    # Validate source exists
    if (!(Test-Path $SourceFile)) {
        Write-Status -Type Skip -Item $DisplayName -Message "Source missing ($SourceFile)"
        $script:Stats.Failed++
        return $false
    }
    
    # Resolve absolute paths
    $absSource = (Resolve-Path $SourceFile).Path
    $absTarget = [System.IO.Path]::GetFullPath($TargetFile)
    
    # Self-reference check
    if ($absSource -ieq $absTarget) {
        Write-Status -Type OK -Item $DisplayName -Message "Already in correct location"
        $script:Stats.Skipped++
        return $true
    }
    
    # Dry run mode
    if ($DryRun) {
        Write-Status -Type DryRun -Item $DisplayName -Message "Would create symlink -> $absSource"
        return $true
    }
    
    # Handle existing target
    if (Test-Path $TargetFile) {
        $item = Get-Item $TargetFile -Force
        
        # Check if already a correct symlink
        if ($item.LinkType -eq "SymbolicLink") {
            # Get symlink target (use LinkTarget for PS 6+, fallback to Target)
            $existingTarget = if ($item.PSObject.Properties.Name -contains 'LinkTarget') {
                $item.LinkTarget
            } else {
                $item.Target
            }
            
            # Handle array return
            if ($existingTarget -is [Array]) {
                $existingTarget = $existingTarget[0]
            }
            
            # Resolve to absolute path
            try {
                if ([System.IO.Path]::IsPathRooted($existingTarget)) {
                    # Already absolute - just normalize
                    $existingTarget = [System.IO.Path]::GetFullPath($existingTarget)
                } else {
                    # Relative path - combine with parent directory
                    $existingTarget = [System.IO.Path]::GetFullPath(
                        [System.IO.Path]::Combine((Split-Path $TargetFile), $existingTarget)
                    )
                }
            } catch {
                # Fallback if path resolution fails
                $existingTarget = $existingTarget
            }
            
            if ($existingTarget -ieq $absSource) {
                Write-Status -Type OK -Item $DisplayName -Message "Symlink already correct"
                $script:Stats.Skipped++
                return $true
            }
            
            # Wrong symlink - remove it
            Remove-Item $TargetFile -Force
        } else {
            # Regular file - backup
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backup = "$TargetFile.bak_$timestamp"
            Rename-Item -Path $TargetFile -NewName $backup
            Write-Status -Type Warn -Item $DisplayName -Message "Backed up existing file"
            $script:Stats.Backed++
        }
    }
    
    # Ensure parent directory exists
    $parentDir = Split-Path $TargetFile -Parent
    if (!(Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    # Create symlink
    try {
        New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force -ErrorAction Stop | Out-Null
        Write-Status -Type New -Item $DisplayName -Message "Symlink created"
        $script:Stats.Created++
        return $true
    } catch {
        Write-Status -Type Error -Item $DisplayName -Message "Failed: $($_.Exception.Message)"
        $script:Stats.Failed++
        return $false
    }
}
    
    # Ensure parent directory exists
    $parentDir = Split-Path $TargetFile -Parent
    if (!(Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    # Create symlink
    try {
        New-Item -ItemType SymbolicLink -Path $TargetFile -Target $absSource -Force -ErrorAction Stop | Out-Null
        Write-Status -Type New -Item $DisplayName -Message "Symlink created"
        $script:Stats.Created++
        return $true
    } catch {
        Write-Status -Type Error -Item $DisplayName -Message "Failed: $($_.Exception.Message)"
        $script:Stats.Failed++
        return $false
    }

function Install-ScoopPackage {
    param(
        [string]$Name,
        [string]$Command,
        [string]$Description
    )
    
    if (Get-Command $Command -ErrorAction SilentlyContinue) {
        Write-Status -Type OK -Item $Name -Message "Already installed"
        return $true
    }
    
    if ($DryRun) {
        Write-Status -Type DryRun -Item $Name -Message "Would install ($Description)"
        return $true
    }
    
    Write-Status -Type Info -Item $Name -Message "Installing..."
    
    $output = scoop install $Name 2>&1
    $success = $LASTEXITCODE -eq 0
    
    # Refresh PATH
    Update-SessionPath
    
    if ($success -or (Get-Command $Command -ErrorAction SilentlyContinue)) {
        Write-Status -Type New -Item $Name -Message "Installed successfully"
        return $true
    } else {
        Write-Status -Type Error -Item $Name -Message "Installation failed"
        return $false
    }
}

function Get-WindowsTerminalPath {
    $patterns = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_*\LocalState"
    )
    
    foreach ($pattern in $patterns) {
        $path = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($path) {
            return $path.FullName
        }
    }
    
    return $null
}

function Test-RepoFiles {
    $required = @(
        @{ File = "Microsoft.PowerShell_profile.ps1"; Optional = $false }
        @{ File = "settings.json"; Optional = $true }
        @{ File = $Config.OmpConfigName; Optional = $true }
    )
    
    $valid = $true
    foreach ($item in $required) {
        $path = Join-Path $RepoPath $item.File
        if (!(Test-Path $path)) {
            if ($item.Optional) {
                Write-Status -Type Warn -Item $item.File -Message "Not found in repo (optional)"
            } else {
                Write-Status -Type Error -Item $item.File -Message "REQUIRED file not found in repo!"
                $valid = $false
            }
        }
    }
    
    return $valid
}

#endregion

#region ==================== INSTALLATION FUNCTIONS ====================

function Install-Scoop {
    Write-Host "  Checking Scoop package manager..."
    
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Status -Type OK -Item "Scoop" -Message "Already installed"
        return $true
    }
    
    if ($DryRun) {
        Write-Status -Type DryRun -Item "Scoop" -Message "Would install"
        return $true
    }
    
    Write-Status -Type Info -Item "Scoop" -Message "Installing..."
    
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        Update-SessionPath
        
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Status -Type New -Item "Scoop" -Message "Installed successfully"
            return $true
        }
    } catch {
        Write-Status -Type Error -Item "Scoop" -Message "Installation failed: $($_.Exception.Message)"
    }
    
    return $false
}

function Install-ScoopGit {
    Write-Host "  Checking Git..."
    
    # Check if Scoop's git is installed (parse table output)
    $scoopList = scoop list *>&1 | Out-String
    $hasGit = $scoopList -match '(?m)^git\s+'
    
    if ($hasGit) {
        Write-Status -Type OK -Item "Git (Scoop)" -Message "Already installed"
        return $true
    }
    
    # Check for system Git
    $systemGit = Get-Command git -ErrorAction SilentlyContinue
    if ($systemGit -and $systemGit.Source -notlike "*scoop*") {
        Write-Status -Type OK -Item "Git (System)" -Message "Using system Git"
        return $true
    }
    
    if ($DryRun) {
        Write-Status -Type DryRun -Item "Git" -Message "Would install via Scoop"
        return $true
    }
    
    Write-Status -Type Info -Item "Git" -Message "Installing..."
    scoop install git 2>&1 | Out-Null
    Update-SessionPath
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Status -Type New -Item "Git" -Message "Installed successfully"
        return $true
    }
    
    Write-Status -Type Error -Item "Git" -Message "Installation failed"
    return $false
}

function Install-OhMyPosh {
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Status -Type OK -Item "Oh My Posh" -Message "Already installed"
        return $true
    }
    
    if ($DryRun) {
        Write-Status -Type DryRun -Item "Oh My Posh" -Message "Would install via winget"
        return $true
    }
    
    Write-Status -Type Info -Item "Oh My Posh" -Message "Installing..."
    
    $result = winget install JanDeDobbeleer.OhMyPosh --source winget `
              --accept-package-agreements --accept-source-agreements 2>&1
    
    Update-SessionPath
    
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Status -Type New -Item "Oh My Posh" -Message "Installed successfully"
        return $true
    }
    
    Write-Status -Type Error -Item "Oh My Posh" -Message "Installation may require terminal restart"
    return $false
}

function Install-CliTools {
    param([string[]]$ToolsToInstall = $null)
    
    # Add extras bucket if needed
    $buckets = scoop bucket list 2>$null
    if ($buckets -notmatch "extras") {
        if (!$DryRun) {
            scoop bucket add extras 2>&1 | Out-Null
        }
    }
    
    $tools = $Config.CliTools
    if ($ToolsToInstall) {
        $tools = $tools | Where-Object { $_.Name -in $ToolsToInstall }
    }
    
    foreach ($tool in $tools) {
        Install-ScoopPackage -Name $tool.Name -Command $tool.Command -Description $tool.Description
    }
}

#endregion

#region ==================== MAIN EXECUTION ====================

# Clear screen and show banner
Clear-Host
Write-Banner "DOTFILES SETUP SCRIPT"

# Dry run warning
if ($DryRun) {
    Write-Host "`n  *** DRY RUN MODE - No changes will be made ***" -ForegroundColor Yellow
}

# Admin check
Write-Host "`nChecking prerequisites..." -ForegroundColor White

if (!(Test-AdminPrivileges)) {
    Write-Host ""
    Write-Host "  ERROR: Administrator privileges required!" -ForegroundColor Red
    Write-Host "  Symlinks on Windows require elevation." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Please run:" -ForegroundColor White
    Write-Host "    Start-Process pwsh -Verb RunAs -ArgumentList '-File', '$($MyInvocation.MyCommand.Path)'" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}
Write-Status -Type OK -Item "Administrator" -Message "Running with elevation"

# Show repo path
Write-Host ""
Write-Host "  Repository: $RepoPath" -ForegroundColor DarkGray

# Validate repo files
Write-Host ""
if (!(Test-RepoFiles)) {
    Write-Host "`n  Cannot continue without required files." -ForegroundColor Red
    exit 1
}

# Interactive mode - component selection
$installScoop = $true
$installTools = !$SkipTools
$installOmp = $true
$createSymlinks = !$SkipSymlinks
$selectedSymlinks = @("PowerShellProfile", "WindowsTerminal", "OhMyPosh")
$selectedTools = $Config.CliTools | ForEach-Object { $_.Name }

if ($Interactive) {
    Write-Host ""
    
    # Main component selection
    $mainOptions = @(
        @{ Key = "Scoop";    Name = "Package Manager (Scoop + Git)"; Description = "Required for CLI tools"; Default = $true }
        @{ Key = "Tools";    Name = "CLI Tools";                     Description = "zoxide, fzf, bat, ripgrep, fd, eza"; Default = !$SkipTools }
        @{ Key = "OMP";      Name = "Oh My Posh";                    Description = "Beautiful prompt engine"; Default = $true }
        @{ Key = "Symlinks"; Name = "Configuration Symlinks";        Description = "Link configs to your repo (backup of existing configs will be created)"; Default = !$SkipSymlinks }
    )
    
    $selected = Show-InteractiveMenu -Title "Select components to install/configure:" -Options $mainOptions -MultiSelect
    
    $installScoop = "Scoop" -in $selected
    $installTools = "Tools" -in $selected
    $installOmp = "OMP" -in $selected
    $createSymlinks = "Symlinks" -in $selected
    
    # Tool selection
    if ($installTools) {
        Write-Host ""
        $toolOptions = $Config.CliTools | ForEach-Object {
            @{ Key = $_.Name; Name = $_.Name; Description = $_.Description; Default = $true }
        }
        $selectedTools = Show-InteractiveMenu -Title "Select CLI tools to install:" -Options $toolOptions -MultiSelect
    }
    
    # Symlink selection
    if ($createSymlinks) {
        Write-Host ""
        $symlinkOptions = @(
            @{ Key = "PowerShellProfile"; Name = "PowerShell Profile"; Description = "Custom aliases, functions, and prompt"; Default = $true }
            @{ Key = "WindowsTerminal";   Name = "Windows Terminal";   Description = "Appearance, fonts, and keybindings"; Default = $true }
            @{ Key = "OhMyPosh";          Name = "Oh My Posh Theme";   Description = "Prompt theme configuration"; Default = $true }
        )
        $selectedSymlinks = Show-InteractiveMenu -Title "Select configuration files to symlink (existing files will be backed up):" -Options $symlinkOptions -MultiSelect
    }
    
    # Confirmation
    if (!$Force) {
        Write-Host "`nReady to proceed with selected options?" -ForegroundColor Yellow
        $confirm = Read-Host "Press Enter to continue, or Ctrl+C to cancel"
    }
}

# Calculate total steps
$totalSteps = 0
if ($installScoop) { $totalSteps++ }
if ($installTools) { $totalSteps++ }
if ($installOmp) { $totalSteps++ }
if ($createSymlinks) { $totalSteps++ }
$currentStep = 0

# ---------------------------------------------------------
# STEP 1: Scoop & Git
# ---------------------------------------------------------
if ($installScoop) {
    $currentStep++
    Write-Step -Number $currentStep -Total $totalSteps -Title "Package Manager: Scoop & Git"
    
    if (Install-Scoop) {
        Install-ScoopGit
    }
}

# ---------------------------------------------------------
# STEP 2: CLI Tools
# ---------------------------------------------------------
if ($installTools) {
    $currentStep++
    Write-Step -Number $currentStep -Total $totalSteps -Title "CLI Tools (Scoop)"
    
    if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Status -Type Error -Item "CLI Tools" -Message "Scoop not available - skipping"
    } else {
        Install-CliTools -ToolsToInstall $selectedTools
    }
}

# ---------------------------------------------------------
# STEP 3: Oh My Posh
# ---------------------------------------------------------
if ($installOmp) {
    $currentStep++
    Write-Step -Number $currentStep -Total $totalSteps -Title "Prompt Engine: Oh My Posh"
    
    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Status -Type Error -Item "Oh My Posh" -Message "Winget not available"
    } else {
        Install-OhMyPosh
    }
}

# ---------------------------------------------------------
# STEP 4: Configuration Symlinks
# ---------------------------------------------------------
if ($createSymlinks) {
    $currentStep++
    Write-Step -Number $currentStep -Total $totalSteps -Title "Configuration Symlinks & Backups"
    
    # PowerShell Profile
    if ("PowerShellProfile" -in $selectedSymlinks) {
        Write-Host "  PowerShell Profile:" -ForegroundColor White
        $profileDir = Split-Path -Path $PROFILE
        if (!(Test-Path $profileDir)) { 
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null 
        }
        Set-Symlink -SourceFile "$RepoPath\Microsoft.PowerShell_profile.ps1" `
                    -TargetFile $PROFILE `
                    -DisplayName "Microsoft.PowerShell_profile.ps1"
    }
    
    # Windows Terminal
    if ("WindowsTerminal" -in $selectedSymlinks) {
        Write-Host "`n  Windows Terminal:" -ForegroundColor White
        $wtPath = Get-WindowsTerminalPath
        if ($wtPath) {
            Set-Symlink -SourceFile "$RepoPath\settings.json" `
                        -TargetFile "$wtPath\settings.json" `
                        -DisplayName "settings.json"
        } else {
            Write-Status -Type Skip -Item "settings.json" -Message "Windows Terminal not found"
        }
    }
    
    # Oh My Posh Theme
    if ("OhMyPosh" -in $selectedSymlinks) {
        Write-Host "`n  Oh My Posh Theme:" -ForegroundColor White
        $ompDir = $Config.OmpTargetDir
        if (!(Test-Path $ompDir)) { 
            New-Item -ItemType Directory -Path $ompDir -Force | Out-Null 
        }
        Set-Symlink -SourceFile "$RepoPath\$($Config.OmpConfigName)" `
                    -TargetFile "$ompDir\$($Config.OmpConfigName)" `
                    -DisplayName $Config.OmpConfigName
    }
}

# ---------------------------------------------------------
# FINAL SUMMARY
# ---------------------------------------------------------
Write-Banner "SETUP COMPLETE"

# Statistics
Write-Host ""
Write-Host "  Symlink Statistics:" -ForegroundColor White
Write-Host "    Created:  $($Stats.Created)" -ForegroundColor Green
Write-Host "    Skipped:  $($Stats.Skipped)" -ForegroundColor Gray
Write-Host "    Backed:   $($Stats.Backed)" -ForegroundColor Magenta
if ($Stats.Failed -gt 0) {
    Write-Host "    Failed:   $($Stats.Failed)" -ForegroundColor Red
}

# Post-install notes
Write-Host ""
Write-Host "  Next Steps:" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray

$hasPostSteps = $false

# Check for PSFzf and Terminal-Icons
$needsModules = @()
if (!(Get-Module -ListAvailable -Name PSFzf)) { $needsModules += "PSFzf" }
if (!(Get-Module -ListAvailable -Name Terminal-Icons)) { $needsModules += "Terminal-Icons" }

if ($needsModules.Count -gt 0) {
    $hasPostSteps = $true
    Write-Host ""
    Write-Host "  1. Install recommended PowerShell modules:" -ForegroundColor White
    Write-Host "     Install-Module $($needsModules -join ', ') -Scope CurrentUser" -ForegroundColor Cyan
}

# Font reminder
$hasPostSteps = $true
Write-Host ""
Write-Host "  2. Install a Nerd Font for Oh My Posh icons:" -ForegroundColor White
Write-Host "     oh-my-posh font install" -ForegroundColor Cyan

# Restart reminder
Write-Host ""
Write-Host "  3. Restart your terminal to apply all changes" -ForegroundColor White

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

#endregion
