$Global:DirectoryAliases = @{}
$Global:DirectoryStack = @{}

function Save-Aliases {
    $path = Join-Path $env:USERPROFILE "PowerShellScripts\DirectoryAliases.json"
    $Global:DirectoryAliases | ConvertTo-Json | Set-Content -Path $path
    Write-Host "Aliases saved to $path"
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
        Write-Host "No aliases file found at $path. Starting with an empty aliases list."
        $Global:DirectoryAliases = @{}
    }
}

function _goto_print_similar {
    param([string]$input)
    $similar = $Global:DirectoryAliases.Keys | Where-Object { $_ -like "*$input*" }

    if ($similar) {
        $selection = $similar | Out-GridView -Title "Did you mean one of these? Select to navigate." -PassThru
        if ($selection) {
            $path = $Global:DirectoryAliases[$selection]
            Write-Host "Navigating to alias '$selection' at path '$path'."
            Set-Location $path
        } else {
            Write-Host "No selection made. No action taken."
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
				Push-Location
				Set-Location $Global:DirectoryAliases[$Alias]
				Write-Host "Pushed current directory and moved to $Alias."
		}
		'o' {
				if ((Get-LocationStack).Count -gt 0) {
						Pop-Location
				} else {
						Write-Warning "Directory stack is empty."
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
