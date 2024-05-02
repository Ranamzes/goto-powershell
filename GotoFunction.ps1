$Global:DirectoryAliases = @{}
$Global:DirectoryStack = @{}

function Save-Aliases {
	$path = Join-Path $env:USERPROFILE "PowerShellScripts\DirectoryAliases.json"
	$Global:DirectoryAliases | ConvertTo-Json | Set-Content -Path $path
}

function Import-Aliases {
	$path = Join-Path $env:USERPROFILE "PowerShellScripts\DirectoryAliases.json"
	if (Test-Path $path) {
		try {
			$jsonContent = Get-Content -Path $path | ConvertFrom-Json
			$Global:DirectoryAliases = @{}
			foreach ($entry in $jsonContent.PSObject.Properties) {
				$Global:DirectoryAliases[$entry.Name] = $entry.Value
			}
		}
		catch {
			Write-Warning "Failed to load aliases from $path due to invalid format."
			$Global:DirectoryAliases = @{}
		}
	}
	else {
		Write-Host "No aliases file found at $path. Starting with an empty aliases list."
		$Global:DirectoryAliases = @{}
	}
}

function _goto_print_similar {
	param([string]$aliasInput)

	$normalizedInput = $aliasInput.ToLower()
	$matches = $Global:DirectoryAliases.Keys | Where-Object {
		$alias = $_.ToLower()
		$inputChars = $normalizedInput.ToCharArray()
		$aliasChars = $alias.ToCharArray()
		$matchingCharsCount = ($inputChars | Where-Object { $aliasChars -contains $_ }).Count
		$matchingCharsCount -gt 1
	}

	$matchedAliases = $matches | ForEach-Object {
		$alias = $_
		$aliasChars = $alias.ToLower().ToCharArray()
		$matchingCharsCount = ($normalizedInput.ToCharArray() | Where-Object { $aliasChars -contains $_ }).Count
		[PSCustomObject]@{
			Alias = $alias
			Path  = $Global:DirectoryAliases[$alias]
			Score = $matchingCharsCount
		}
	} | Sort-Object -Property Score -Descending

	$maxAliasLength = ($matchedAliases | Measure-Object -Property Alias -Maximum).Maximum.Length

	if ($matchedAliases.Count -eq 1) {
		$selectedAlias = $matchedAliases[0].Alias
		$path = $Global:DirectoryAliases[$selectedAlias]
		$spacesToAdd = $maxAliasLength - $selectedAlias.Length
		$spacesToAdd = [Math]::Max(0, $spacesToAdd)
		$aliasDisplay = $selectedAlias + (' ' * $spacesToAdd)
		Write-Host "`nOnly one matching alias found: '$aliasDisplay' -> '$path'. Navigating..." -ForegroundColor Green
		Set-Location $path
		return $selectedAlias
	}
	elseif ($matchedAliases.Count -gt 1) {
		Write-Host "`nDid you mean one of these? Type the number to navigate, or press ENTER to cancel:" -ForegroundColor Yellow
		$index = 1
		foreach ($alias in $matchedAliases) {
			$spacesToAdd = $maxAliasLength - $alias.Alias.Length
			$spacesToAdd = [Math]::Max(0, $spacesToAdd)  # Ensure non-negative value
			$aliasDisplay = $alias.Alias + (' ' * $spacesToAdd)
			Write-Host "[$index]: $aliasDisplay -> $($alias.Path)" -ForegroundColor Cyan
			$index++
		}

		Write-Host "" # Additional indentation before selection
		$choice = Read-Host "Enter your choice (1-$($matchedAliases.Count))"
		if ([string]::IsNullOrWhiteSpace($choice)) {
			Write-Host "No selection made. No action taken." -ForegroundColor Red
		}
		elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchedAliases.Count) {
			$selectedAlias = $matchedAliases[[int]$choice - 1].Alias
			$spacesToAdd = $maxAliasLength - $selectedAlias.Length
			$spacesToAdd = [Math]::Max(0, $spacesToAdd)  # Ensure non-negative value
			$aliasDisplay = $selectedAlias + (' ' * $spacesToAdd)
			$path = $Global:DirectoryAliases[$selectedAlias]
			Write-Host "Navigating to '$aliasDisplay' -> '$path'." -ForegroundColor Green
			Set-Location $path
			return $selectedAlias
		}
		else {
			Write-Host "Invalid selection. No action taken." -ForegroundColor Red
		}
	}
	else {
		Write-Host "No similar aliases found for '$aliasInput'." -ForegroundColor Red
	}
	return $null
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
	}
	else {
		# Handle predefined commands or suggest similar aliases
		switch ($Command) {
			'r' {
				if (-not [string]::IsNullOrWhiteSpace($Alias) -and -not [string]::IsNullOrWhiteSpace($Path)) {
					if (Test-Path $Path) {
				$resolvedPath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
						# Проверка уникальности алиаса
						if ($Global:DirectoryAliases.ContainsKey($Alias)) {
							$currentPath = $Global:DirectoryAliases[$Alias]
							if ($currentPath -ne $resolvedPath) {
								$overwriteConfirmation = Read-Host "`nAlias '$Alias' already exists for path '$currentPath'. Overwrite? [Y/N]"
								if ($overwriteConfirmation -ne 'Y') {
									Write-Host "`nAlias registration cancelled." -ForegroundColor Yellow
									return
								}
							}
						}
				$Global:DirectoryAliases[$Alias] = $resolvedPath
						Write-Host "`nAlias '$Alias' registered for path '$resolvedPath'." -ForegroundColor Green
				Save-Aliases
					}
					else {
						Write-Warning "`nThe specified path does not exist." -ForegroundColor Yellow
					}
				}
				else {
					Write-Warning "`nAlias name or path not specified. Usage: goto r <alias_name> <path>" -ForegroundColor Yellow
				}
			}
			'u' {
				if ($Global:DirectoryAliases.ContainsKey($Alias)) {
					$aliasPath = $Global:DirectoryAliases[$Alias]
					$confirmDeletion = Read-Host "Are you sure you want to unregister the alias '$Alias' which points to '$aliasPath'? [Y/N]"
					if ($confirmDeletion -eq 'Y') {
					$Global:DirectoryAliases.Remove($Alias)
						Write-Host "`nAlias '$Alias' unregistered." -ForegroundColor Green
					Save-Aliases
				}
				else {
						Write-Host "`nAlias unregistration cancelled." -ForegroundColor Yellow
					}
				}
				else {
					Write-Warning "`nAlias '$Alias' does not exist." -ForegroundColor Yellow
				}
			}
			'l' {
				if ($Global:DirectoryAliases.Count -eq 0) {
					Write-Host "`nNo aliases registered."
				}
				else {
					$Global:DirectoryAliases.GetEnumerator() | Sort-Object Name | ForEach-Object {
						Write-Host "$($_.Key) -> $($_.Value)"
					}
				}
			}
			'x' {
				if ($Global:DirectoryAliases.ContainsKey($Alias)) {
					Write-Host "`n$Alias -> $($Global:DirectoryAliases[$Alias])" -ForegroundColor Green
				}
				else {
					Write-Warning "`nAlias $Alias does not exist." -ForegroundColor Yellow
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
				}
				else {
					if (-not [string]::IsNullOrWhiteSpace($Alias)) {
						$selectedAlias = _goto_print_similar -aliasInput $Alias
						Write-Host "`nPushed current directory '$currentPath' to stack and moved to alias." -ForegroundColor Green
					}
					else {
						Write-Host "`nNo alias specified. Pushed current directory '$currentPath' to stack." -ForegroundColor Yellow
					}
				}
			}
			'o' {
				# Pop the location off the stack
				try {
					Pop-Location
					Write-Host "Popped and moved to the top location on the stack."
				}
				catch {
					Write-Warning "Directory stack is empty or an error occurred."
				}
			}
			default {
				Write-Host "Usage: goto [ r <alias> <path> | u <alias> | l | x <alias> | c | p <alias> | o | <alias>]"
				$null = _goto_print_similar -aliasInput $Command
			}
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
	}
	else {
		# If user starts typing any other command, suggest commands
		$commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
			[System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Perform $_ operation")
		}
	}
}
