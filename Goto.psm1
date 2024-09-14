$script:GotoDataPath = Join-Path -Path $env:APPDATA -ChildPath 'PowerShell\Goto'
$script:AliasFilePath = Join-Path -Path $script:GotoDataPath -ChildPath "GotoAliases.ps1"
$script:BackupFilePath = Join-Path -Path $script:GotoDataPath -ChildPath "GotoAliases.bak"



$Global:DirectoryAliases = @{}

function Backup-Aliases {
	if (Test-Path $script:AliasFilePath) {
		Copy-Item -Path $script:AliasFilePath -Destination $script:BackupFilePath -Force
		Write-Host "Aliases backed up to $script:BackupFilePath" -ForegroundColor Green
	}
}

function Restore-AliasesFromBackup {
	if (Test-Path $script:BackupFilePath) {
		Copy-Item -Path $script:BackupFilePath -Destination $script:AliasFilePath -Force
		Write-Host "Aliases restored from backup." -ForegroundColor Green
		Import-Aliases
	}
	else {
		Write-Warning "No backup file found. Unable to restore aliases."
	}
}

function Update-GotoModule {
	try {
		Backup-Aliases

		$currentAliases = $Global:DirectoryAliases.Clone()

		$currentModule = Get-InstalledModule -Name Goto -ErrorAction Stop

		try {
			$onlineModule = Find-Module -Name Goto -ErrorAction Stop
			$newVersion = $onlineModule.Version
		}
		catch {
			Write-Host "Unable to check for updates using Find-Module. Using alternative method." -ForegroundColor Yellow
			$response = Invoke-RestMethod -Uri "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq 'Goto' and IsLatestVersion" -ErrorAction Stop
			$newVersion = [version]($response.properties.Version)
		}

		if ($newVersion -gt $currentModule.Version) {
			Write-Host "Current Goto version: $($currentModule.Version)" -ForegroundColor Cyan
			Write-Host "New version available: $newVersion" -ForegroundColor Green

			Update-Module -Name Goto -Force -ErrorAction Stop

			$updatedModule = Get-InstalledModule -Name Goto
			Write-Host "Goto has been successfully updated to version $($updatedModule.Version)!" -ForegroundColor Green

			$Global:DirectoryAliases = $currentAliases
			Save-Aliases

			Write-Host "Aliases have been restored." -ForegroundColor Green

			Initialize-GotoEnvironment

			Write-Host "Please restart your PowerShell session to use the new version." -ForegroundColor Yellow
		}
		else {
			Write-Host "Goto is already at the latest version ($($currentModule.Version))." -ForegroundColor Green
		}
	}
	catch {
		Write-Host "An error occurred while updating Goto: $_" -ForegroundColor Red
		Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
		Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red

		Restore-AliasesFromBackup
	}
}

function Initialize-GotoEnvironment {
	if (-not (Test-Path -Path $script:GotoDataPath)) {
		New-Item -Path $script:GotoDataPath -ItemType Directory -Force | Out-Null
	}

	if (-not (Test-Path -Path $script:AliasFilePath)) {
		Save-Aliases
	}

	$profileContent = "Import-Module Goto -DisableNameChecking"

	if (-not (Test-Path -Path $PROFILE)) {
		New-Item -Path $PROFILE -ItemType File -Force | Out-Null
	}

	$currentProfileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue

	if ($currentProfileContent -notmatch [regex]::Escape($profileContent)) {
		Add-Content -Path $PROFILE -Value "`n$profileContent"
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
	$aliasContent = @"
# Goto Directory Aliases
`$Global:DirectoryAliases = @{
$((($Global:DirectoryAliases.GetEnumerator() | ForEach-Object { "    '$($_.Key)' = '$($_.Value)'" }) -join "`n"))
}

# Create cd aliases
$(($Global:DirectoryAliases.Keys | ForEach-Object { "Set-Alias -Name cd$_ -Value { Set-Location `$Global:DirectoryAliases['$_'] } -Scope Global" }) -join "`n")
"@

	$aliasContent | Set-Content -Path $script:AliasFilePath
}

function Import-Aliases {
	if (Test-Path $script:AliasFilePath) {
		try {
			. $script:AliasFilePath
			$Global:DirectoryAliases.Keys | ForEach-Object {
				$alias = $_
				$path = $Global:DirectoryAliases[$alias]
				Set-Alias -Name "cd$alias" -Value { Set-Location $path } -Scope Global
			}
		}
		catch {
			Write-Warning "Failed to load aliases from $script:AliasFilePath. Error: $_"
			$Global:DirectoryAliases = @{}
		}
	}
	else {
		$Global:DirectoryAliases = @{}
	}
}

function _goto_print_similar {
	param([string]$aliasInput)

	$normalizedInput = $aliasInput.ToLower()
	$matches = $Global:DirectoryAliases.Keys | Where-Object {
		$_ -like "*$normalizedInput*"
	}

	$matchedAliases = $matches | ForEach-Object {
		[PSCustomObject]@{
			Alias = $_
			Path  = $Global:DirectoryAliases[$_]
		}
	}

	if ($matchedAliases.Count -eq 1) {
		$selectedAlias = $matchedAliases[0].Alias
		$path = $matchedAliases[0].Path
		Write-Host "Navigating to '$selectedAlias' -> '$path'." -ForegroundColor Green
		return $selectedAlias
	}
	elseif ($matchedAliases.Count -gt 1) {
		Write-Host "Did you mean one of these? Type the number to navigate, or press ENTER to cancel:" -ForegroundColor Yellow
		for ($i = 0; $i -lt $matchedAliases.Count; $i++) {
			Write-Host "[$($i+1)]: $($matchedAliases[$i].Alias) -> $($matchedAliases[$i].Path)" -ForegroundColor Cyan
		}
		$choice = Read-Host "Enter your choice (1-$($matchedAliases.Count))"
		if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchedAliases.Count) {
			$selectedAlias = $matchedAliases[[int]$choice - 1].Alias
			$path = $matchedAliases[[int]$choice - 1].Path
			Write-Host "Navigating to '$selectedAlias' -> '$path'." -ForegroundColor Green
			return $selectedAlias
		}
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
				if ($selectedAlias) {
					$path = $Global:DirectoryAliases[$selectedAlias]
					Set-Location $path
				}
				else {
					Write-Host "Usage: goto [ r <alias> <path> | u <alias> | l | x <alias> | c | p <alias> | o | <alias>]"
				}
			}
		}
	}
}

# Initialization when loading module
Initialize-GotoEnvironment
Import-Aliases

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

$Global:DirectoryAliases.Keys | ForEach-Object {
	Export-ModuleMember -Alias "cd$_"
}
