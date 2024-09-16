$script:GotoDataPath = Join-Path -Path $env:APPDATA -ChildPath 'PowerShell\Goto'
$script:AliasFilePath = Join-Path -Path $script:GotoDataPath -ChildPath "GotoAliases.xml"
$script:UpdateInfoFile = Join-Path -Path $script:GotoDataPath -ChildPath "UpdateInfo.xml"
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
		$newVersion = $null

		try {
			$onlineModule = Find-Module -Name Goto -ErrorAction Stop
			$newVersion = $onlineModule.Version
		}
		catch {
			Write-Host "Unable to check for updates using Find-Module. Using alternative method." -ForegroundColor Yellow
			try {
				$response = Invoke-RestMethod -Uri "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq 'Goto' and IsLatestVersion" -ErrorAction Stop
				$newVersion = [version]($response.properties.Version)
			}
			catch {
				throw "Failed to check for updates using both methods. Please check your internet connection."
			}
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

function Test-ForUpdates {
	$updateInfo = if (Test-Path $script:UpdateInfoFile) {
		Import-Clixml -Path $script:UpdateInfoFile
	}
 else {
		@{
			LastCheckTime     = (Get-Date).AddDays(-31)
			LatestVersion     = $null
			NotificationCount = 0
		}
	}

	$currentTime = Get-Date
	if (($currentTime - $updateInfo.LastCheckTime).Days -ge 30) {
		$currentVersion = (Get-Module Goto).Version
		try {
			$latestVersion = (Find-Module Goto -Repository PSGallery -ErrorAction Stop).Version
			if ($latestVersion -gt $currentVersion) {
				$updateInfo.LatestVersion = $latestVersion
				$updateInfo.NotificationCount = 0
				Write-Host "New version $latestVersion available. Run 'goto update' to update." -ForegroundColor Yellow
			}
			else {
				$updateInfo.LatestVersion = $null
			}
		}
		catch {
			Write-Verbose "Failed to check for updates: $_"
		}
		$updateInfo.LastCheckTime = $currentTime
	}
	elseif ($updateInfo.LatestVersion -and $updateInfo.LatestVersion -gt (Get-Module Goto).Version) {
		if ($updateInfo.NotificationCount -lt 3) {
			Write-Host "Reminder: New version $($updateInfo.LatestVersion) is available. Run 'goto update' to update." -ForegroundColor Yellow
			$updateInfo.NotificationCount++
		}
	}

	$updateInfo | Export-Clixml -Path $script:UpdateInfoFile
}

function Initialize-GotoEnvironment {
	if (-not (Test-Path -Path $script:GotoDataPath)) {
		New-Item -Path $script:GotoDataPath -ItemType Directory -Force | Out-Null
	}
	Import-Aliases
	if (-not (Test-Path -Path $script:AliasFilePath)) {
		Save-Aliases
	}
	$profileContent = @"

# Import Goto module
Import-Module Goto -DisableNameChecking

# Error handling for WinGet
`$ErrorActionPreference = 'Continue'
try {
    `$null = Get-Command winget -ErrorAction Stop
    Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
} catch {
    Write-Verbose "WinGet not detected. Some features may be unavailable."
}
"@
	if (-not (Test-Path -Path $PROFILE)) {
		New-Item -Path $PROFILE -ItemType File -Force | Out-Null
	}
	$currentProfileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
	if ($currentProfileContent -notmatch [regex]::Escape($profileContent)) {
		Add-Content -Path $PROFILE -Value $profileContent
		Write-Host "Goto module import and WinGet error handling have been added to your PowerShell profile." -ForegroundColor Green
		Write-Host "Please restart your PowerShell session or run '. `$PROFILE' to apply changes." -ForegroundColor Yellow
	}
	Test-ForUpdates
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


function Import-Aliases {
	if (Test-Path $script:AliasFilePath) {
		try {
			$Global:DirectoryAliases = Import-Clixml -Path $script:AliasFilePath
			$Global:DirectoryAliases.GetEnumerator() | ForEach-Object {
				$alias = $_.Key
				$path = $_.Value
				Set-Alias -Name $alias -Value (Get-Command -Name Set-Location) -Force -Scope Global
				Set-Item -Path "Alias:$alias" -Value $path -Force
			}
		}
		catch {
			Write-Warning "Failed to load aliases. Recreating alias file."
			$Global:DirectoryAliases = @{}
			Save-Aliases
		}
	}
	else {
		$Global:DirectoryAliases = @{}
		Save-Aliases
	}
}

function Save-Aliases {
	try {
		$Global:DirectoryAliases | Export-Clixml -Path $script:AliasFilePath -ErrorAction Stop
		Import-Aliases
	}
	catch {
		Write-Warning "Failed to save aliases. Error: $_"
	}
}

function Find-SimilarAlias {
	param (
		[string]$aliasInput
	)
	$normalizedInput = $aliasInput.ToLower()
	$matchingAliases = $Global:DirectoryAliases.Keys | Where-Object {
		$_ -like "*$normalizedInput*" -or $normalizedInput -like "*$_*"
	}

	if ($matchingAliases.Count -eq 1) {
		return $matchingAliases[0]
	}
	elseif ($matchingAliases.Count -gt 1) {
		Write-Host "Did you mean one of these? Type the number to navigate, or press ENTER to cancel:" -ForegroundColor Yellow
		for ($i = 0; $i -lt $matchingAliases.Count; $i++) {
			Write-Host "[$($i+1)]: $($matchingAliases[$i]) -> $($Global:DirectoryAliases[$matchingAliases[$i]])" -ForegroundColor Cyan
		}
		$choice = Read-Host "Enter your choice (1-$($matchingAliases.Count))"
		if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchingAliases.Count) {
			return $matchingAliases[[int]$choice - 1]
		}
	}
	return $null
}

function _goto_print_similar {
	param(
		[string]$aliasInput,
		[string]$action = "navigate"
	)

	$normalizedInput = $aliasInput.ToLower()
	$matchingAliases = $Global:DirectoryAliases.Keys | Where-Object {
		$_ -like "*$normalizedInput*"
	} | Sort-Object

	if ($matchingAliases.Count -gt 1) {
		Write-Host "Did you mean one of these? Type the number to $action, or press ENTER to cancel:" -ForegroundColor Yellow
		Write-Host

		$maxAliasLength = ($matchingAliases | Measure-Object -Property Length -Maximum).Maximum
		$numberWidth = $matchingAliases.Count.ToString().Length

		for ($i = 0; $i -lt $matchingAliases.Count; $i++) {
			$alias = $matchingAliases[$i]
			$path = $Global:DirectoryAliases[$alias]
			$paddedNumber = ($i + 1).ToString().PadLeft($numberWidth)
			$paddedAlias = $alias.PadRight($maxAliasLength)

			Write-Host "[" -NoNewline -ForegroundColor DarkGray
			Write-Host $paddedNumber -NoNewline -ForegroundColor Cyan
			Write-Host "]:" -NoNewline -ForegroundColor DarkGray
			Write-Host " $paddedAlias" -NoNewline -ForegroundColor Green
			Write-Host " -> " -NoNewline -ForegroundColor DarkGray
			Write-Host $path -ForegroundColor Yellow
		}

		Write-Host
		$choice = Read-Host "Enter your choice (1-$($matchingAliases.Count))"
		if ([string]::IsNullOrWhiteSpace($choice)) {
			Write-Host "No selection made. No action taken." -ForegroundColor Red
			return $null
		}
		elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchingAliases.Count) {
			return $matchingAliases[[int]$choice - 1]
		}
		else {
			Write-Host "Invalid selection. No action taken." -ForegroundColor Red
			return $null
		}
	}
	elseif ($matchingAliases.Count -eq 1) {
		return $matchingAliases[0]
	}
	else {
		return $null
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

	if ($Global:DirectoryAliases.ContainsKey($Command)) {
		$path = $Global:DirectoryAliases[$Command]
		Write-Host "Navigating to alias '$Command' at path '$path'." -ForegroundColor Green
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
						$Global:DirectoryAliases[$Alias] = $resolvedPath
						New-Item -Path Function:\ -Name "Global:$Alias" -Value { Set-Location $resolvedPath } | Out-Null
						Write-Host "Alias '$Alias' registered for path '$resolvedPath'." -ForegroundColor Green
						Save-Aliases
					}
					else {
						Write-Host "The specified path does not exist." -ForegroundColor Red
					}
				}
				else {
					Write-Host "Alias name or path not specified. Usage: goto r <alias_name> <path>" -ForegroundColor Yellow
				}
			}
			'u' {
				if (-not $Alias) {
					Write-Host "Usage: goto u <alias>" -ForegroundColor Yellow
					return
				}
				$selectedAlias = _goto_print_similar -aliasInput $Alias -action "unregister"
				if ($selectedAlias) {
					Write-Host "Are you sure you want to unregister the alias '$selectedAlias' which points to '$($Global:DirectoryAliases[$selectedAlias])'? [Y/N]: " -ForegroundColor Yellow -NoNewline
					$confirmation = Read-Host
					if ($confirmation -eq 'Y') {
						$Global:DirectoryAliases.Remove($selectedAlias)
						Remove-Item -Path "Function:$selectedAlias" -ErrorAction SilentlyContinue
						Write-Host "Alias '$selectedAlias' unregistered." -ForegroundColor Green
						Save-Aliases
					}
					else {
						Write-Host "Unregistration cancelled." -ForegroundColor Yellow
					}
				}
				else {
					Write-Host "No matching alias found for '$Alias'." -ForegroundColor Red
				}
			}
			'l' {
				if ($Global:DirectoryAliases.Count -eq 0) {
					Write-Host "No aliases registered." -ForegroundColor Yellow
				}
				else {
					$maxAliasLength = ($Global:DirectoryAliases.Keys | Measure-Object -Maximum -Property Length).Maximum
					$maxPathLength = ($Global:DirectoryAliases.Values | Measure-Object -Maximum -Property Length).Maximum
					Write-Host "`nRegistered Aliases:" -ForegroundColor Cyan
					Write-Host ("-" * (4 + $maxAliasLength + 4 + $maxPathLength)) -ForegroundColor DarkGray
					$Global:DirectoryAliases.GetEnumerator() | Sort-Object Name | ForEach-Object {
						$aliasDisplay = $_.Key.PadRight($maxAliasLength)
						$pathDisplay = $_.Value.PadRight($maxPathLength)
						Write-Host "  " -NoNewline
						Write-Host $aliasDisplay -ForegroundColor Green -NoNewline
						Write-Host " -> " -ForegroundColor DarkGray -NoNewline
						Write-Host $pathDisplay -ForegroundColor Yellow
					}
					Write-Host ("-" * (4 + $maxAliasLength + 4 + $maxPathLength)) -ForegroundColor DarkGray
				}
			}
			'x' {
				if (-not $Alias) {
					Write-Host "Usage: goto x <alias>" -ForegroundColor Yellow
					return
				}
				$selectedAlias = _goto_print_similar -aliasInput $Alias -action "expand"
				if ($selectedAlias) {
					$path = $Global:DirectoryAliases[$selectedAlias]
					Write-Host "Alias: " -ForegroundColor Cyan -NoNewline
					Write-Host "$selectedAlias" -ForegroundColor Green
					Write-Host "Path:  " -ForegroundColor Cyan -NoNewline
					Write-Host "$path" -ForegroundColor Yellow
					if (Test-Path $path) {
						Write-Host "Status:" -ForegroundColor Cyan -NoNewline
						Write-Host " Path exists" -ForegroundColor Green
					}
					else {
						Write-Host "Status:" -ForegroundColor Cyan -NoNewline
						Write-Host " Path does not exist" -ForegroundColor Red
					}
				}
				else {
					Write-Host "No matching alias found for '$Alias'." -ForegroundColor Red
				}
			}
			'c' {
				$invalidAliases = $Global:DirectoryAliases.GetEnumerator() | Where-Object { -not (Test-Path $_.Value) }

				if ($invalidAliases.Count -eq 0) {
					Write-Host "All aliases point to valid paths. No cleanup needed." -ForegroundColor Green
					return
				}

				Write-Host "The following aliases point to non-existent paths:" -ForegroundColor Yellow
				foreach ($invalidAlias in $invalidAliases) {
					Write-Host "  $($invalidAlias.Key) -> $($invalidAlias.Value)" -ForegroundColor Red
				}

				$confirmation = Read-Host "Do you want to remove these aliases? [Y/N]"
				if ($confirmation -eq 'Y') {
					foreach ($invalidAlias in $invalidAliases) {
						$Global:DirectoryAliases.Remove($invalidAlias.Key)
						Remove-Item -Path "Function:$($invalidAlias.Key)" -ErrorAction SilentlyContinue
						Write-Host "Removed alias '$($invalidAlias.Key)'." -ForegroundColor Green
					}
					Save-Aliases
					Write-Host "Cleanup complete. Removed $(($invalidAliases | Measure-Object).Count) invalid aliases." -ForegroundColor Green
				}
				else {
					Write-Host "Cleanup cancelled. No aliases were removed." -ForegroundColor Yellow
				}
			}
			'p' {
				$currentPath = (Get-Location).Path
				Push-Location

				if ($Global:DirectoryAliases.ContainsKey($Alias)) {
					$path = $Global:DirectoryAliases[$Alias]
					Write-Host "Pushed current directory '$currentPath' to stack and moved to alias '$Alias' at path '$path'." -ForegroundColor Green
					Set-Location $path
				}
				else {
					if (-not [string]::IsNullOrWhiteSpace($Alias)) {
						$selectedAlias = _goto_print_similar -aliasInput $Alias
						if ($selectedAlias) {
							$path = $Global:DirectoryAliases[$selectedAlias]
							Write-Host "Pushed current directory '$currentPath' to stack and moved to alias '$selectedAlias' at path '$path'." -ForegroundColor Green
							Set-Location $path
						}
						else {
							Pop-Location
							Write-Host "No matching alias found. Current directory was not changed." -ForegroundColor Yellow
						}
					}
					else {
						Write-Host "Pushed current directory '$currentPath' to stack." -ForegroundColor Yellow
					}
				}
			}
			'o' {
				if ((Get-Location -Stack).Count -eq 0) {
					Write-Host "The location stack is empty." -ForegroundColor Yellow
					return
				}
				$previousPath = (Get-Location).Path
				Pop-Location
				$newPath = (Get-Location).Path
				if ($previousPath -ne $newPath) {
					Write-Host "Popped and moved from '$previousPath' to '$newPath'." -ForegroundColor Green
				}
				else {
					Write-Host "Already at the bottom of the location stack." -ForegroundColor Yellow
				}
			}
			default {
				$selectedAlias = _goto_print_similar -aliasInput $Command
				if ($selectedAlias) {
					$path = $Global:DirectoryAliases[$selectedAlias]
					Write-Host "Navigating to alias '$selectedAlias' at path '$path'." -ForegroundColor Green
					Set-Location $path
				}
				else {
					Write-Host "No matching alias found for '$Command'." -ForegroundColor Red
					Write-Host "Usage: goto [ <alias> | r <alias> <path> | u <alias> | l | x <alias> | c | p <alias> | o | update ]" -ForegroundColor Yellow
				}
			}
		}
	}
}

# Initialization when loading module
Initialize-GotoEnvironment
Start-Job -ScriptBlock {
	Import-Module Goto
	Test-ForUpdates
} | Out-Null

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

$Global:DirectoryAliases.Keys | ForEach-Object { Export-ModuleMember -Function "cd$_" }
