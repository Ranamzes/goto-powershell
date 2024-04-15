$Global:DirectoryAliases = @{}
$Global:DirectoryStack = @{}

function Save-Aliases {
    $path = Join-Path $env:USERPROFILE "PowerShellScripts\DirectoryAliases.json"
    $Global:DirectoryAliases | ConvertTo-Json | Set-Content -Path $path
}

function Import-Aliases {
    $path = Join-Path $env:USERPROFILE "PowerShellScripts\DirectoryAliases.json"
    if (Test-Path $path) {
        $jsonContent = Get-Content -Path $path | ConvertFrom-Json
        $Global:DirectoryAliases = @{}
        foreach ($entry in $jsonContent.PSObject.Properties) {
            $Global:DirectoryAliases[$entry.Name] = $entry.Value
        }
    } else {
        $Global:DirectoryAliases = @{}
    }
}

function _goto_print_similar {
    param([string]$input)
    # Filter aliases to strictly include only those that contain the input string
    $similar = $Global:DirectoryAliases.Keys | Where-Object { $_ -like "*$input*" }

    if ($similar.Count -eq 1) {
        # If only one similar alias, navigate directly
        $selectedAlias = $similar[0]
        $path = $Global:DirectoryAliases[$selectedAlias]
        Write-Host "Only one matching alias found: '$selectedAlias'. Navigating to '$path'."
        Set-Location $path
    }
    elseif ($similar.Count -gt 1) {
        Write-Host "Did you mean one of these? Type the number to navigate, or press ENTER to cancel:"
        # Display options, requiring user interaction to choose
        $index = 1
        foreach ($alias in $similar) {
            Write-Host "[$index]: $alias"
            $index++
        }

        # Ask user for choice
        $choice = Read-Host "Enter your choice (1-$($similar.Count))"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Host "No selection made. No action taken."
        }
        elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $similar.Count) {
            $selectedAlias = $similar[[int]$choice - 1]
            $path = $Global:DirectoryAliases[$selectedAlias]
            Write-Host "Navigating to alias '$selectedAlias' at path '$path'."
            Set-Location $path
        }
        else {
            Write-Host "Invalid selection. No action taken."
        }
    } else {
        Write-Host "No similar aliases found."
    }
}

function goto {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Command,

		[Parameter(Mandatory = $false, Position = 1)]
		[string]$Alias,

		[Parameter(Mandatory = $false, Position = 2)]
		[string]$Path
	)

	# Check if the command is an alias directly
	if ($Global:DirectoryAliases.ContainsKey($Command)) {
		$path = $Global:DirectoryAliases[$Command]
		Write-Host "Navigating to alias '$Command' at path '$path'."
		Set-Location $path
		return
	}

	# Handle predefined commands
	switch ($Command) {
		'r' {
			# Resolve the path to an absolute path
			$resolvedPath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
			$Global:DirectoryAliases[$Alias] = $resolvedPath
			Write-Host "Alias $Alias registered for path $resolvedPath."
			Save-Aliases
		}
		'u' {
			if ($Global:DirectoryAliases.ContainsKey($Alias)) {
				$Global:DirectoryAliases.Remove($Alias)
				Write-Host "Alias $Alias unregistered."
				Save-Aliases
			}
			else {
				Write-Warning "Alias $Alias does not exist."
			}
		}
		'l' {
			if ($Global:DirectoryAliases.Count -eq 0) {
				Write-Host "No aliases registered."
			}
			else {
				$Global:DirectoryAliases.GetEnumerator() | Sort-Object Name | ForEach-Object {
					Write-Host "$($_.Key) -> $($_.Value)"
				}
			}
		}
		'x' {
			if ($Global:DirectoryAliases.ContainsKey($Alias)) {
				Write-Host "$Alias -> $($Global:DirectoryAliases[$Alias])"
			}
			else {
				Write-Warning "Alias $Alias does not exist."
			}
		}
		'c' {
			$keysToRemove = $Global:DirectoryAliases.Keys | Where-Object { -Not (Test-Path $Global:DirectoryAliases[$_]) }
			foreach ($key in $keysToRemove) {
				Write-Warning "Cleaning up alias $key because the path no longer exists."
				$Global:DirectoryAliases.Remove($key)
			}
			Save-Aliases
		}
		'p' {
				# Push the current location onto the stack
				Push-Location
				if ($Global:DirectoryAliases.ContainsKey($Alias)) {
						$path = $Global:DirectoryAliases[$Alias]
						Write-Host "Pushed current directory and moved to '$Alias' at path '$path'."
						Set-Location $path
				} else {
						Write-Host "Alias '$Alias' does not exist. Pushed current directory."
				}
		}
		'o' {
				# Pop the location off the stack
				try {
						Pop-Location
						Write-Host "Popped and moved to the top location on the stack."
				} catch {
						Write-Warning "Directory stack is empty or an error occurred."
				}
		}
		default {
			Write-Host "Usage: goto [-r <alias> <path> | -u <alias> | -l | -x <alias> | -c | -p <alias> | -o | <alias>]"
			_goto_print_similar $Command
		}
	}
}

Register-ArgumentCompleter -CommandName 'goto' -ScriptBlock {
    param($commandName, $wordToComplete, $commandAst, $fakeBoundParameters)
    # Single-letter commands
    $commands = 'r', 'u', 'l', 'x', 'c', 'p', 'o'  # Register, Unregister, List, eXpand, Cleanup, Push, Pop
    $aliases = $Global:DirectoryAliases.Keys

    if ($wordToComplete -eq 'u' -or $wordToComplete -eq 'x') {
        # If user starts typing 'u' for unregister or 'x' for expand, suggest aliases
        $aliases | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    } else {
        # If user starts typing any other command, suggest commands
        $commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Perform $_ operation")
        }
    }
}
