function touch {
    [CmdletBinding()]
    param(
        # Positional Parameter 0: The base name of the file.
        [Parameter(Position=0)]
        [string]$Name,

        # Positional Parameter 1: The file extension.
        [Parameter(Position=1)]
        [string]$Extension,

        # Positional Parameter 2: The number of files to create.
        [Parameter(Position=2)]
        [int]$Count,

        # Positional Parameter 3: The number of digits for zero-padding.
        [Parameter(Position=3)]
        [int]$Pad
    )

    # --- Hybrid Logic ---
    # If the first positional argument ($Name) was not provided, switch to interactive mode.
    if (-not $PSBoundParameters.ContainsKey('Name')) {
        Write-Host "Entering interactive mode..." -ForegroundColor Yellow
        
        # Prompt for Name (required)
        do {
            $Name = Read-Host "Enter the base name for the files (e.g., 'report')"
        } until (-not [string]::IsNullOrWhiteSpace($Name))

        # Prompt for Extension (optional)
        $Extension = Read-Host "Enter the file extension (press Enter for 'txt')"
        if ([string]::IsNullOrWhiteSpace($Extension)) { $Extension = 'txt' }

        # Prompt for Count (optional)
        $inputCount = Read-Host "How many files do you want to create? (press Enter for 1)"
        if ($inputCount -match '^\d+$' -and [int]$inputCount -gt 0) {
            $Count = [int]$inputCount
        } else {
            $Count = 1
        }

        # Prompt for Padding (optional)
        $inputPad = Read-Host "How many digits for zero-padding? (press Enter for none)"
        if ($inputPad -match '^\d+$') {
            $Pad = [int]$inputPad
        } else {
            $Pad = 0
        }
    } else {
        # --- Handle defaults for positional arguments if they were not provided ---
        if (-not $PSBoundParameters.ContainsKey('Extension')) { $Extension = 'txt' }
        if (-not $PSBoundParameters.ContainsKey('Count')) { $Count = 1 }
        if (-not $PSBoundParameters.ContainsKey('Pad')) { $Pad = 0 }
    }

    # --- Validation and File Creation ---
    if ($Count -le 0) { $Count = 1 }
    if ($Pad -lt 0) { $Pad = 0 }

    Write-Host "Creating $Count file(s)..." -ForegroundColor Cyan

    1..$Count | ForEach-Object {
        $numberPart = $_
        if ($Pad -gt 0) {
            $numberPart = $_.ToString("D$Pad")
        }
        $fileName = "$Name$numberPart.$Extension"
        New-Item -Path $fileName -ItemType File -Force | Out-Null
    }

    Write-Host "Done. Successfully created $Count file(s) in the current directory." -ForegroundColor Green
}

function prompt {
  $loc = $executionContext.SessionState.Path.CurrentLocation;
  $out = ""
  if ($loc.Provider.Name -eq "FileSystem") {
    $out += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
  }
  $out += "PS $loc$('>' * ($nestedPromptLevel + 1)) ";
  return $out
}

function touch_dummy {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ListFilePath
    )
    if (Test-Path $ListFilePath) {
        Get-Content $ListFilePath | ForEach-Object {
            if ($_ -and $_.Trim() -ne '') {
                New-Item -ItemType File -Name $_ -Force | Out-Null
            }
        }
    } else {
        Write-Error "File not found: $ListFilePath"
    }
}

function winutil {
    irm "https://christitus.com/win" | iex
}

function profile {
    notepad $PROFILE
}

function omp_pull {
    git -C "$env:USERPROFILE\.omp" pull
}

function omp_edit {
    # DEFINE YOUR CONFIG PATH HERE
    # (This should match the path in your 'oh-my-posh init' line)
    $poshConfigPath = "$env:USERPROFILE\.omp\slmlm2009.omp.yaml" 
    
    if (Test-Path $poshConfigPath) {
        notepad $poshConfigPath
    } else {
        Write-Error "Config file not found at: $poshConfigPath"
        Write-Host "Please update the `$poshConfigPath variable in this function." -ForegroundColor Yellow
    }
}

function omp_push {
    param (
        [string]$RepoPath = "$env:USERPROFILE\.omp", # ADJUST THIS PATH
        [string]$Message = "Update config"
    )

    # Save current location to return later
    $originalLocation = Get-Location

    try {
        # Navigate to the repo
        if (Test-Path $RepoPath) {
            Set-Location $RepoPath
        } else {
            Write-Error "Repository path not found: $RepoPath"
            return
        }

        # Check for changes
        if (-not (git status --porcelain)) {
            Write-Warning "No changes to commit."
            return
        }

        # Create timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $fullMessage = "$Message - $timestamp"

        # Git operations
        Write-Host "Staging changes..." -ForegroundColor Cyan
        git add .

        Write-Host "Committing: '$fullMessage'" -ForegroundColor Cyan
        git commit -m "$fullMessage"

        Write-Host "Pushing to remote..." -ForegroundColor Cyan
        git push

        Write-Host "Done!" -ForegroundColor Green
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        # Always return to where you started
        Set-Location $originalLocation
    }
}

oh-my-posh init pwsh --config "C:\Users\slmlm2009\.omp\slmlm2009.omp.yaml" | Invoke-Expression
#oh-my-posh init pwsh --config "https://raw.githubusercontent.com/slmlm2009/mypowershell/refs/heads/main/slmlm2009.omp.yaml" | Invoke-Expression

# =============================================================================
# INITIALIZATION
# =============================================================================
$Script:ErrorActionPreference = 'Stop'

# Initialize Zoxide (Better cd)
# We add '--cmd cd' to replace the standard cd command with zoxide
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& {zoxide init powershell --cmd cd | Out-String})
}

# Import modules
Import-Module PSFzf
Import-Module Terminal-Icons

# Initialize PSFzf (Fuzzy Finder Integration)
if (Get-Module -ListAvailable PSFzf) {
    Import-Module PSFzf

    # 1. Setup Key Bindings (Ctrl+T for files and folders, Ctrl+R for history)
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    
    # 2. Configure Default Command (Use 'fd' if available)
    if (Get-Command fd -ErrorAction SilentlyContinue) {
        # REMOVED: '--type f' so it shows BOTH files and folders
        # Added: '--follow' to follow symlinks, matching your Linux preference
        $env:FZF_DEFAULT_COMMAND = 'fd --hidden --follow --exclude .git --exclude node_modules --exclude target'
        
        # Ctrl+T uses the same command (Files + Folders)
        $env:FZF_CTRL_T_COMMAND  = $env:FZF_DEFAULT_COMMAND
        
        # Alt+C stays strictly directories ('--type d')
        $env:FZF_ALT_C_COMMAND   = 'fd --type d --hidden --follow --exclude .git --exclude node_modules --exclude target'
    } else {
        # Fallback (Files + Folders)
        $env:FZF_DEFAULT_COMMAND = 'Get-ChildItem -Recurse | ForEach-Object { $_.FullName }'
        $env:FZF_CTRL_T_COMMAND  = $env:FZF_DEFAULT_COMMAND
        $env:FZF_ALT_C_COMMAND   = 'Get-ChildItem -Recurse -Directory | ForEach-Object { $_.FullName }'
    }

    # 3. Configure Appearance (Height, Layout, Border)
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border'

    # 4. Configure Previews (Ctrl+T) - Ported to PowerShell syntax
    # We use 'bat' if available, otherwise 'Get-Content' (cat)
    # Note: {} in fzf works the same, but the fallback command syntax "||" works best in cmd/bash. 
    # For PowerShell fzf previews, simple is better.
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        $env:FZF_CTRL_T_OPTS = "--preview 'bat --style=numbers --color=always --line-range :500 {}' --bind 'ctrl-/:toggle-preview'"
    } else {
        $env:FZF_CTRL_T_OPTS = "--preview 'Get-Content {} -TotalCount 100' --bind 'ctrl-/:toggle-preview'"
    }

    # 5. Configure Alt+C Preview (Tree view)
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        $env:FZF_ALT_C_OPTS = "--preview 'eza --tree --level=2 --icons --color=always {} | head -n 50'"
    } else {
        $env:FZF_ALT_C_OPTS = "--preview 'Get-ChildItem -Path {} | Select-Object -First 20'"
    }
}

# =============================================================================
# ALIASES - SYSTEM & NAVIGATION
# =============================================================================
Set-Alias -Name c -Value Clear-Host
Function eprofile { 
    # Opens profile in edit (or change to 'notepad' if using GUI)
    edit $PROFILE 
}

Function sprofile { 
    # Reloads the profile in the current session
    . $PROFILE 
    Write-Host "Profile reloaded!" -ForegroundColor Green 
}

# =============================================================================
# ALIASES - FILE OPERATIONS
# =============================================================================
# Remove built-in read-only aliases so we can overwrite them
# (We use -Force because they are 'AllScope' locked by default)
Remove-Alias -Name ls -Force -ErrorAction SilentlyContinue
Remove-Alias -Name cp -Force -ErrorAction SilentlyContinue
Remove-Alias -Name mv -Force -ErrorAction SilentlyContinue
Remove-Alias -Name rm -Force -ErrorAction SilentlyContinue
Remove-Alias -Name cat -Force -ErrorAction SilentlyContinue

# 1. 'ls' -> 'eza' replacement
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Function ls { eza $args }
    Function ll { eza -lh --sort=modified --reverse --group-directories-first --icons $args }
    Function la { eza -la --icons --group-directories-first $args }
    Function lla { eza -lha --sort=modified --reverse --group-directories-first --icons $args }
    Function tree { eza --tree $args }
} else {
    # Fallback if eza isn't installed
    Function ll { Get-ChildItem -File | Sort-Object LastWriteTime }
    Function la { Get-ChildItem -Force }
}

# 2. Safety Wrappers (Matches your bashrc: cp -i, mv -i, rm -i)
# We use Functions because they can hold parameters like '-Confirm'
Function cp { Copy-Item -Confirm @args }
Function mv { Move-Item -Confirm @args }
Function rm { Remove-Item -Confirm @args }
Set-Alias -Name md -Value mkdir -ErrorAction SilentlyContinue

# =============================================================================
# ALIASES - TEXT PROCESSING
# =============================================================================
# Use ripgrep if available
if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias -Name grep -Value rg -Scope Global -ErrorAction SilentlyContinue
}

# Use bat if available (replacement for cat)
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Function cat { bat $args }
}

# =============================================================================
# ENV VARS & EXTRAS
# =============================================================================

$env:EDITOR = "edit" # Or 'notepad' if you use GUI
