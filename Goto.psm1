$Global:DirectoryAliases = @{}
$Global:DirectoryStack = @{}

function Initialize-GotoEnvironment {
	$scriptDirectory = "$HOME\PowerShellScripts"
	$scriptPath = Join-Path -Path $scriptDirectory -ChildPath "Goto.psm1"

	# Create the directory if it doesn't exist
	New-Item -ItemType Directory -Path $scriptDirectory -Force | Out-Null

	# Copy the module file to the scripts directory
	Copy-Item -Path $PSScriptRoot\Goto.psm1 -Destination $scriptPath -Force

	# Define the content to be added to the PowerShell profile
	$profileContent = @"

# Auto-generated import for Goto module
Import-Module "$scriptPath"
Import-Aliases
"@

	# Check if the profile already contains a reference to Goto.psm1 and add if not
	if (-Not (Select-String -Path $PROFILE -Pattern "Goto.psm1" -Quiet)) {
		Add-Content -Path $PROFILE -Value $profileContent
		Write-Host "Goto module has been added to your PowerShell profile." -ForegroundColor Green
		Write-Host "Please reload your PowerShell session or run 'Import-Aliases' to start using Goto." -ForegroundColor Yellow
	}
 else {
		Write-Host "Goto module is already registered in your PowerShell profile." -ForegroundColor Cyan
	}
}
function Invoke-VersionCheck {
	$installedModule = Get-InstalledModule -Name Goto -ErrorAction SilentlyContinue
	$onlineModule = Find-Module -Name Goto -ErrorAction SilentlyContinue

	if ($installedModule -and $onlineModule) {
		if ($onlineModule.Version -gt $installedModule.Version) {
			Write-Host "`nNew version $($onlineModule.Version) is available! Your version: $($installedModule.Version)" -ForegroundColor Cyan
			Write-Host "To update, run the following command:" -ForegroundColor Cyan
			Write-Host "  goto update" -ForegroundColor Green
		}
	}
}

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

		Write-Host ""
		$choice = Read-Host "Enter your choice (1-$($matchedAliases.Count))"
		if ([string]::IsNullOrWhiteSpace($choice)) {
			Write-Host "No selection made. No action taken." -ForegroundColor Red
		}
		elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchedAliases.Count) {
			$selectedAlias = $matchedAliases[[int]$choice - 1].Alias
			$spacesToAdd = $maxAliasLength - $selectedAlias.Length
			$spacesToAdd = [Math]::Max(0, $spacesToAdd)
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

	if ($Global:DirectoryAliases.ContainsKey($Command)) {
		$path = $Global:DirectoryAliases[$Command]
		Write-Host "Navigating to alias '$Command' at path '$path'."
		Set-Location $path
	}
	else {
		switch ($Command) {
			'update' {
				try {
					$currentVersion = (Get-InstalledModule -Name Goto).Version
					Update-Module -Name Goto -Force -ErrorAction Stop
					$newVersion = (Get-InstalledModule -Name Goto).Version
					if ($newVersion -gt $currentVersion) {
						Write-Host "Goto has been updated from version $currentVersion to $newVersion!" -ForegroundColor Green
						Initialize-GotoEnvironment
						Write-Host "Please restart your PowerShell session to use the new version." -ForegroundColor Yellow
					}
					else {
						Write-Host "Goto is already at the latest version ($currentVersion)." -ForegroundColor Green
					}
				}
				catch {
					Write-Host "An error occurred while updating Goto: $_" -ForegroundColor Red
				}
			}
			'r' {
				if (-not [string]::IsNullOrWhiteSpace($Alias) -and -not [string]::IsNullOrWhiteSpace($Path)) {
					if (Test-Path $Path) {
						$resolvedPath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
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
					$horizontalLine = ([char]0x2500).ToString() * 2
					$maxAliasLength = ($Global:DirectoryAliases.Keys | Measure-Object -Maximum -Property Length).Maximum + 2
					Write-Host ""
					$Global:DirectoryAliases.GetEnumerator() | Sort-Object Name | ForEach-Object {
						$aliasPadded = $_.Key.PadRight($maxAliasLength)
						Write-Host "  $aliasPadded" -ForegroundColor Green -NoNewline
						Write-Host "$horizontalLine>  " -NoNewline
						Write-Host $_.Value -ForegroundColor Yellow
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
				$keysToRemove = $Global:DirectoryAliases.Keys | Where-Object {
					$path = $Global:DirectoryAliases[$_]
					-not [string]::IsNullOrWhiteSpace($path) -and -not (Test-Path $path)
				}

				if ($keysToRemove.Count -gt 0) {
					foreach ($key in $keysToRemove) {
						Write-Warning "`n    Cleaning up alias '$key' because the path no longer exists." -ForegroundColor Yellow
						$Global:DirectoryAliases.Remove($key)
					}
					Save-Aliases
					Write-Host "`nCleanup complete. Removed aliases with non-existent paths." -ForegroundColor Green
				}
				else {
					Write-Host "`nNo cleanup needed. All aliases point to valid paths." -ForegroundColor Yellow
				}
			}
			'p' {
				$currentPath = (Get-Location).Path
				Push-Location

				if ($Global:DirectoryAliases.ContainsKey($Alias)) {
					$path = $Global:DirectoryAliases[$Alias]
					Write-Host "`nPushed current directory '$currentPath' to stack and moved to alias '$Alias' at path '$path'." -ForegroundColor Green
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
				try {
					Pop-Location
					Write-Host "`nPopped and moved to the top location on the stack." -ForegroundColor Green
				}
				catch {
					Write-Warning "`nDirectory stack is empty or an error occurred." -ForegroundColor Yellow
				}
			}
			default {
				Write-Host "Usage: goto [ r <alias> <path> | u <alias> | l | x <alias> | c | p <alias> | o | <alias>]"
				$null = _goto_print_similar -aliasInput $Command
			}
		}
	}
}


Initialize-GotoEnvironment
Invoke-VersionCheck
Export-ModuleMember -Function goto, Import-Aliases, Initialize-GotoEnvironment

Register-ArgumentCompleter -CommandName 'goto' -ScriptBlock {
	param($commandName, $wordToComplete, $commandAst, $fakeBoundParameters)
	$commands = 'r', 'u', 'l', 'x', 'c', 'p', 'o'  # Register, Unregister, List, eXpand, Cleanup, Push, Pop
	$aliases = $Global:DirectoryAliases.Keys

	if ($wordToComplete -eq 'u' -or $wordToComplete -eq 'x') {
		$aliases | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
			[System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
		}
	}
	else {
		$commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
			[System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Perform $_ operation")
		}
	}
}
