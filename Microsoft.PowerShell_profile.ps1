# =============================================================================
# OPTIMIZED POWERSHELL PROFILE
# Note: RUN THE 'refresh' FUNCTION EVERYTIME YOU UPDATE FZF OR ZOXIDE!
# =============================================================================
$Script:ErrorActionPreference = 'Stop'
$env:EDITOR = "edit" 

# --- PATHS & CACHE ---
$cacheDir = "$env:USERPROFILE\.cache\powershell"

# 1. Load Zoxide (Cached)
if (Test-Path "$cacheDir\zoxide.ps1") {
    . "$cacheDir\zoxide.ps1"
} elseif (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& {zoxide init powershell --cmd cd | Out-String})
}

# 2. Load Oh My Posh (Cached)
if (Test-Path "$cacheDir\omp.ps1") {
    . "$cacheDir\omp.ps1"
} else {
    oh-my-posh init pwsh --config "$env:USERPROFILE\.omp\slmlm2009.omp.yaml" | Invoke-Expression
}

# 3. Import PSFzf
if (Get-Module -ListAvailable PSFzf) { 
    Import-Module PSFzf 
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# =============================================================================
# FUNCTIONS
# =============================================================================

function touch {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$Name,
        [Parameter(Position=1)][string]$Extension,
        [Parameter(Position=2)][int]$Count,
        [Parameter(Position=3)][int]$Pad
    )

    if (-not $PSBoundParameters.ContainsKey('Name')) {
        Write-Host "Entering interactive mode..." -ForegroundColor Yellow
        do { $Name = Read-Host "Base name (e.g. 'report')" } until (-not [string]::IsNullOrWhiteSpace($Name))
        
        $Extension = Read-Host "Extension (Enter for 'txt')"
        if ([string]::IsNullOrWhiteSpace($Extension)) { $Extension = 'txt' }
        
        $inputCount = Read-Host "Count (Enter for 1)"
        $Count = if ($inputCount -match '^\d+$' -and [int]$inputCount -gt 0) { [int]$inputCount } else { 1 }
        
        $inputPad = Read-Host "Padding (Enter for 0)"
        $Pad = if ($inputPad -match '^\d+$') { [int]$inputPad } else { 0 }
    } else {
        if (-not $PSBoundParameters.ContainsKey('Extension')) { $Extension = 'txt' }
        if (-not $PSBoundParameters.ContainsKey('Count')) { $Count = 1 }
        if (-not $PSBoundParameters.ContainsKey('Pad')) { $Pad = 0 }
    }

    if ($Count -le 0) { $Count = 1 }
    if ($Pad -lt 0) { $Pad = 0 }

    Write-Host "Creating $Count file(s)..." -ForegroundColor Cyan
    1..$Count | ForEach-Object {
        $num = if ($Pad -gt 0) { $_.ToString("D$Pad") } else { $_ }
        New-Item -Path "$Name$num.$Extension" -ItemType File -Force | Out-Null
    }
    Write-Host "Done." -ForegroundColor Green
}

function touch_dummy {
    param ([Parameter(Mandatory=$true)][string]$ListFilePath)
    if (Test-Path $ListFilePath) {
        Get-Content $ListFilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            New-Item -ItemType File -Name $_.Trim() -Force | Out-Null
        }
    } else { Write-Error "File not found: $ListFilePath" }
}

function winutil { irm "https://christitus.com/win" | iex }
function profile { notepad $PROFILE }
function eprofile { edit $PROFILE }
function sprofile { . $PROFILE; Write-Host "Profile reloaded!" -ForegroundColor Green }

# OMP Functions
function omp_pull { git -C "$env:USERPROFILE\.omp" pull }
function omp_edit {
    $p = "$env:USERPROFILE\.omp\slmlm2009.omp.yaml"
    if (Test-Path $p) { notepad $p } else { Write-Error "Config not found: $p" }
}
function omp_push {
    param ([string]$RepoPath = "$env:USERPROFILE\.omp", [string]$Message = "Update config")
    $orig = Get-Location
    try {
        if (!(Test-Path $RepoPath)) { throw "Repo not found: $RepoPath" }
        Set-Location $RepoPath
        if (-not (git status --porcelain)) { Write-Warning "No changes."; return }
        
        git add .
        git commit -m "$Message - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        git push
        Write-Host "Done!" -ForegroundColor Green
    }
    catch { Write-Error $_ }
    finally { Set-Location $orig }
}

# Cache Refresh Helper !!RUN THIS FUNCTION EVERYTIME YOU UPDATE FZF OR ZOXIDE!!
function refresh {
    $cacheDir = "$env:USERPROFILE\.cache\powershell"
    if (!(Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
    
    Write-Host "Caching Zoxide..." -NoNewline
    zoxide init powershell --cmd cd > "$cacheDir\zoxide.ps1"
    Write-Host "Done." -ForegroundColor Green
    
    Write-Host "Caching Oh My Posh..." -NoNewline
    oh-my-posh init pwsh --config "$env:USERPROFILE\.omp\slmlm2009.omp.yaml" --print > "$cacheDir\omp.ps1"
    Write-Host "Done." -ForegroundColor Green
}

# =============================================================================
# FZF CONFIGURATION
# =============================================================================
if (Get-Command fd -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = 'fd --hidden --follow --exclude .git --exclude node_modules --exclude target'
    $env:FZF_CTRL_T_COMMAND  = $env:FZF_DEFAULT_COMMAND
    $env:FZF_ALT_C_COMMAND   = 'fd --type d --hidden --follow --exclude .git --exclude node_modules --exclude target'
} else {
    $env:FZF_DEFAULT_COMMAND = 'Get-ChildItem -Recurse | ForEach-Object { $_.FullName }'
    $env:FZF_CTRL_T_COMMAND  = $env:FZF_DEFAULT_COMMAND
    $env:FZF_ALT_C_COMMAND   = 'Get-ChildItem -Recurse -Directory | ForEach-Object { $_.FullName }'
}

$env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border'

if (Get-Command bat -ErrorAction SilentlyContinue) {
    $env:FZF_CTRL_T_OPTS = "--preview 'bat --style=numbers --color=always --line-range :500 {}' --bind 'ctrl-/:toggle-preview'"
} else {
    $env:FZF_CTRL_T_OPTS = "--preview 'Get-Content {} -TotalCount 100' --bind 'ctrl-/:toggle-preview'"
}

if (Get-Command eza -ErrorAction SilentlyContinue) {
    $env:FZF_ALT_C_OPTS = "--preview 'eza --tree --level=2 --icons --color=always {} | head -n 50'"
} else {
    $env:FZF_ALT_C_OPTS = "--preview 'Get-ChildItem -Path {} | Select-Object -First 20'"
}

# =============================================================================
# ALIASES
# =============================================================================
Set-Alias -Name c -Value Clear-Host
Set-Alias -Name md -Value mkdir -ErrorAction SilentlyContinue

# Tool-specific aliases
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Alias -Name ls -Force -ErrorAction SilentlyContinue
    Function ls { eza $args }
    Function ll { eza -lh --sort=modified --reverse --group-directories-first --icons $args }
    Function la { eza -la --icons --group-directories-first $args }
    Function lla { eza -lha --sort=modified --reverse --group-directories-first --icons $args }
    Function tree { eza --tree $args }
} else {
    Function ll { Get-ChildItem -File | Sort-Object LastWriteTime }
    Function la { Get-ChildItem -Force }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    Remove-Alias -Name cat -Force -ErrorAction SilentlyContinue
    Function cat { bat $args }
}

if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias -Name grep -Value rg -Scope Global -Force
}

# Safety Wrappers
'cp','mv','rm' | ForEach-Object { Remove-Alias -Name $_ -Force -ErrorAction SilentlyContinue }
Function cp { Copy-Item -Confirm @args }
Function mv { Move-Item -Confirm @args }
Function rm { Remove-Item -Confirm @args }
