$script:PowerShellDataPath = [System.IO.Path]::Combine([Environment]::GetFolderPath('ApplicationData'), 'PowerShell')
$script:GotoDataPath = Join-Path -Path $script:PowerShellDataPath -ChildPath 'Goto'
$script:AliasFilePath = Join-Path -Path $script:GotoDataPath -ChildPath "GotoAliases.ps1"

$Global:DirectoryAliases = @{}

function Update-GotoModule {
	try {
		$currentVersion = (Get-InstalledModule -Name Goto -ErrorAction Stop).Version
		Write-Host "Current Goto version: $currentVersion" -ForegroundColor Cyan

		Update-Module -Name Goto -Force -ErrorAction Stop
		$newVersion = (Get-InstalledModule -Name Goto -ErrorAction Stop).Version
		Write-Host "Updated Goto to version: $newVersion" -ForegroundColor Green

		if ($newVersion -gt $currentVersion) {
			Write-Host "Goto has been successfully updated!" -ForegroundColor Green

			Import-Aliases
			Write-Host "Aliases have been restored from $script:AliasFilePath" -ForegroundColor Green

			Initialize-GotoEnvironment

			Write-Host "Please restart your PowerShell session to use the new version." -ForegroundColor Yellow
		}
		else {
			Write-Host "Goto is already at the latest version ($currentVersion)." -ForegroundColor Green
		}
	}
	catch {
		Write-Host "An error occurred while updating Goto: $_" -ForegroundColor Red
		Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
		Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
	}
}

function Initialize-GotoEnvironment {
	if (-not (Test-Path -Path $script:GotoDataPath)) {
		New-Item -Path $script:GotoDataPath -ItemType Directory -Force | Out-Null
	}

	if (-not (Test-Path -Path $script:AliasFilePath)) {
		@"
# Goto Directory Aliases
`$Global:DirectoryAliases = @{}

# Create functions for cd aliases

# Create cd aliases
"@ | Set-Content -Path $script:AliasFilePath
	}

	$profileContent = @"

# Auto-generated import for Goto module
Import-Module Goto
if (Test-Path '$script:AliasFilePath') {
    . '$script:AliasFilePath'
}
"@

	if (-not (Test-Path -Path $PROFILE)) {
		New-Item -Path $PROFILE -ItemType File -Force | Out-Null
	}

	$currentProfileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue

	if ($currentProfileContent -notmatch [regex]::Escape($profileContent)) {
		Add-Content -Path $PROFILE -Value "`n$profileContent"
		Write-Host "Goto module and aliases import has been added to your PowerShell profile." -ForegroundColor Green
		Write-Host "Please restart your PowerShell session or run '. `$PROFILE' to apply changes." -ForegroundColor Yellow
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
	$aliasDefinitions = $Global:DirectoryAliases.GetEnumerator() | ForEach-Object {
		"    '$($_.Key)' = '$($_.Value)'"
	}
	$aliasFunctions = $Global:DirectoryAliases.GetEnumerator() | ForEach-Object {
		"function Global:cdFunc_$($_.Key) { Set-Location `$Global:DirectoryAliases['$($_.Key)'] }"
	}
	$aliasCommands = $Global:DirectoryAliases.Keys | ForEach-Object {
		"Set-Alias -Name 'cd$_' -Value 'Global:cdFunc_$_' -Scope Global"
	}

	$aliasContent = @"
# Goto Directory Aliases
`$Global:DirectoryAliases = @{
$($aliasDefinitions -join "`n")
}

# Create functions for cd aliases
$($aliasFunctions -join "`n")

# Create cd aliases
$($aliasCommands -join "`n")
"@

	$aliasContent | Set-Content -Path $script:AliasFilePath
	Write-Host "Aliases saved to $script:AliasFilePath" -ForegroundColor Green
}

function Import-Aliases {
	if (Test-Path $script:AliasFilePath) {
		try {
			. $script:AliasFilePath
			$Global:DirectoryAliases.Keys | ForEach-Object {
				if (Test-Path Function::Global:cdFunc_$_) {
					Set-Alias -Name "cd$_" -Value "Global:cdFunc_$_" -Scope Global
				}
			}
		}
		catch {
			Write-Warning "Failed to load aliases from $script:AliasFilePath. Error: $_"
			$Global:DirectoryAliases = @{}
		}
	}
	else {
		$Global:DirectoryAliases = @{}
		Save-Aliases
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

	if ($Global:DirectoryAliases.ContainsKey($Command)) {
		$path = $Global:DirectoryAliases[$Command]
		Write-Host "Navigating to alias '$Command' at path '$path'."
		Set-Location $path
	}
	else {
		switch ($Command) {
			'update' {
				Update-GotoModule
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
				$selectedAlias = _goto_print_similar -aliasInput $Command
				if ($selectedAlias -eq $null) {
					Write-Host "Usage: goto [ r <alias> <path> | u <alias> | l | x <alias> | c | p <alias> | o | <alias>]"
				}
			}
		}
	}
}

# Initialization when loading module
Initialize-GotoEnvironment
Import-Aliases
Invoke-VersionCheck

# Export of functions
Export-ModuleMember -Function goto, Import-Aliases, Initialize-GotoEnvironment, Update-GotoModule, Save-Aliases

Register-ArgumentCompleter -CommandName 'goto' -ScriptBlock {
	param($commandName, $wordToComplete, $commandAst, $fakeBoundParameters)
	$commands = 'r', 'u', 'l', 'x', 'c', 'p', 'o', 'update'  # Register, Unregister, List, eXpand, Cleanup, Push, Pop, Update
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
