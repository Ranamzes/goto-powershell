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
	if (($currentTime - $updateInfo.LastCheckTime).Days -ge 7) {
		$currentVersion = (Get-Module Goto).Version
		try {
			$latestVersion = (Find-Module Goto -Repository PSGallery -ErrorAction Stop).Version
			if ($latestVersion -gt $currentVersion) {
				$updateInfo.LatestVersion = $latestVersion
				$updateInfo.NotificationCount = 0
				Write-Host "New version $latestVersion available. Run 'goto update' to update." -ForegroundColor Yellow
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
Import-Module Goto -DisableNameChecking

# Error handling for WinGet
`$ErrorActionPreference = 'Continue'
try {
    `$null = Get-Command winget -ErrorAction Stop
    Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
}
catch {
    Write-Verbose "WinGet not detected. Some features may be unavailable."
}
"@

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


function Import-Aliases {
	if (Test-Path $script:AliasFilePath) {
		try {
			$Global:DirectoryAliases = Import-Clixml -Path $script:AliasFilePath
			$Global:DirectoryAliases.GetEnumerator() | ForEach-Object {
				$alias = $_.Key
				$path = $_.Value
				Set-Item -Path Function:Global:$("cd$alias") -Value { Set-Location $using:path }.GetNewClosure()
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
	param([string]$aliasInput)

	$normalizedInput = $aliasInput.ToLower()
	$matchingAliases = $Global:DirectoryAliases.Keys | Where-Object {
		$alias = $_.ToLower()
		$inputChars = $normalizedInput.ToCharArray()
		$aliasChars = $alias.ToCharArray()
		$matchingCharsCount = ($inputChars | Where-Object { $aliasChars -contains $_ }).Count
		$matchingCharsCount -gt 1
	}

	$matchedAliases = $matchingAliases | ForEach-Object {
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
		for ($i = 0; $i -lt $matchedAliases.Count; $i++) {
			$alias = $matchedAliases[$i]
			$spacesToAdd = $maxAliasLength - $alias.Alias.Length
			$spacesToAdd = [Math]::Max(0, $spacesToAdd)
			$aliasDisplay = $alias.Alias + (' ' * $spacesToAdd)
			Write-Host "[$($i+1)]: $aliasDisplay -> $($alias.Path)" -ForegroundColor Cyan
		}

		Write-Host "" # Additional indentation before selection
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
				Update-GotoModule
			}
			'r' {
				if (-not [string]::IsNullOrWhiteSpace($Alias) -and -not [string]::IsNullOrWhiteSpace($Path)) {
					if (Test-Path $Path) {
						$resolvedPath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
						$Global:DirectoryAliases[$Alias] = $resolvedPath
						Write-Host "Alias '$Alias' registered for path '$resolvedPath'." -ForegroundColor Green
						Save-Aliases
					}
					else {
						Write-Warning "The specified path does not exist."
					}
				}
				else {
					Write-Warning "Alias name or path not specified. Usage: goto r <alias_name> <path>"
				}
			}
			'u' {
				if ($Global:DirectoryAliases.ContainsKey($Alias)) {
					$Global:DirectoryAliases.Remove($Alias)
					Write-Host "Alias '$Alias' unregistered." -ForegroundColor Green
					Save-Aliases
				}
				else {
					Write-Warning "Alias '$Alias' does not exist."
				}
			}
			'l' {
				if ($Global:DirectoryAliases.Count -eq 0) {
					Write-Host "No aliases registered."
				}
				else {
					$Global:DirectoryAliases.GetEnumerator() | Sort-Object Name | Format-Table -AutoSize @{
						Label      = "Alias"
						Expression = { $_.Key }
					}, @{
						Label      = "Path"
						Expression = { $_.Value }
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
				try {
					$previousPath = (Get-Location).Path
					Pop-Location
					$newPath = (Get-Location).Path
					Write-Host "Popped and moved from '$previousPath' to '$newPath'." -ForegroundColor Green
				}
				catch {
					Write-Warning "Directory stack is empty or an error occurred."
				}
			}
			default {
				_goto_print_similar -aliasInput $Command
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
