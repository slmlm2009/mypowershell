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
oh-my-posh init pwsh --config "https://raw.githubusercontent.com/slmlm2009/mypowershell/refs/heads/main/slmlm2009.omp.yaml" | Invoke-Expression