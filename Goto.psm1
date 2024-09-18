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
		$updateInfo = Test-ForUpdates

		if ($updateInfo) {
			Write-Host "Current Goto version: $($updateInfo.CurrentVersion)" -ForegroundColor Cyan
			Write-Host "New version available: $($updateInfo.NewVersion)" -ForegroundColor Green

			$confirmation = Read-Host "Do you want to update now? (Y/N)"
			if ($confirmation -eq 'Y') {
				try {
					Update-Module -Name Goto -Force -ErrorAction Stop
					$updatedModule = Get-InstalledModule -Name Goto

					if ($updatedModule.Version -gt $currentModule.Version) {
						Write-Host "Goto has been successfully updated to version $($updatedModule.Version)!" -ForegroundColor Green

						$Global:DirectoryAliases = $currentAliases
						Save-Aliases
						Write-Host "Aliases have been restored." -ForegroundColor Green

						Initialize-GotoEnvironment
						Write-Host "Please restart your PowerShell session to use the new version." -ForegroundColor Yellow
					}
					else {
						throw "Update failed: Version did not change"
					}
				}
				catch {
					Write-Host "Error during Update-Module. Trying alternative update method..." -ForegroundColor Yellow

					# Alternative update method
					try {
						Uninstall-Module -Name Goto -AllVersions -Force -ErrorAction Stop
						Install-Module -Name Goto -Force -AllowClobber -ErrorAction Stop

						$updatedModule = Get-InstalledModule -Name Goto
						if ($updatedModule.Version -gt $currentModule.Version) {
							Write-Host "Goto has been successfully updated to version $($updatedModule.Version)!" -ForegroundColor Green

							$Global:DirectoryAliases = $currentAliases
							Save-Aliases
							Write-Host "Aliases have been restored." -ForegroundColor Green

							Initialize-GotoEnvironment
							Write-Host "Please restart your PowerShell session to use the new version." -ForegroundColor Yellow
						}
						else {
							throw "Alternative update failed: Version did not change"
						}
					}
					catch {
						throw "Both update methods failed. Error: $_"
					}
				}
			}
			else {
				Write-Host "Update cancelled." -ForegroundColor Yellow
			}
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
	$currentModule = Get-InstalledModule -Name Goto -ErrorAction SilentlyContinue
	if (-not $currentModule) {
		return $null
	}

	try {
		$onlineModule = Find-Module -Name Goto -Repository PSGallery -ErrorAction Stop
		$newVersion = $onlineModule.Version
	}
	catch {
		Write-Warning "Unable to check for updates. Please check your internet connection and try again later."
		return $null
	}

	if ($newVersion -gt $currentModule.Version) {
		return @{
			CurrentVersion = $currentModule.Version
			NewVersion     = $newVersion
		}
	}

	return $null
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

	# Asynchronous verification of updates every 30 days
	$lastCheckFile = Join-Path $script:GotoDataPath "LastUpdateCheck.txt"
	$lastCheck = if (Test-Path $lastCheckFile) { Get-Content $lastCheckFile } else { "1970-01-01" }
	if ((Get-Date) -gt ([DateTime]::Parse($lastCheck).AddDays(30))) {
		Start-Job -ScriptBlock {
			Import-Module Goto
			$updateInfo = Test-ForUpdates
			if ($updateInfo) {
				Write-Host "New version $($updateInfo.NewVersion) of Goto is available. Your version: $($updateInfo.CurrentVersion). Run 'goto -Update' to update." -ForegroundColor Yellow
			}
			Get-Date -Format "yyyy-MM-dd" | Set-Content $using:lastCheckFile
		} | Out-Null
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

function _goto_print_similar {
		param(
				[string]$aliasInput,
				[string]$action = "navigate to",
				[switch]$SuppressNavigation
		)

		$normalizedInput = $aliasInput.ToLower()

		function Get-MatchScore {
				param (
						[string]$alias,
						[string]$searchTerm
				)
				$alias = $alias.ToLower()
				$score = 0
				$matchedChars = 0

				foreach ($char in $searchTerm.ToCharArray()) {
						if ($alias.Contains($char)) {
								$matchedChars++
								$score += 10
						} else {
								return 0
						}
				}

				if ($matchedChars -eq $searchTerm.Length) {
						$score += 100

						$lastIndex = -1
						$orderBonus = 0
						foreach ($char in $searchTerm.ToCharArray()) {
								$index = $alias.IndexOf($char, $lastIndex + 1)
								if ($index -gt $lastIndex) {
										$orderBonus += 10
										$lastIndex = $index
								}
						}
						$score += $orderBonus

						if ($alias.StartsWith($searchTerm)) {
								$score += 200
						}

						return $score
				}
				return 0
		}

		$matchedAliases = @()

		foreach ($entry in $Global:DirectoryAliases.GetEnumerator()) {
				$alias = $entry.Key
				$path = $entry.Value
				$score = Get-MatchScore -alias $alias -searchTerm $normalizedInput
				if ($score -gt 0) {
						$matchedAliases += [PSCustomObject]@{
								Alias = $alias
								Path = $path
								Score = $score
						}
				}
		}

		$matchedAliases = @($matchedAliases | Sort-Object -Property Score -Descending)

		if ($matchedAliases.Count -eq 1) {
				$selectedAlias = $matchedAliases[0].Alias
				$path = $matchedAliases[0].Path
				if (-not $SuppressNavigation) {
						if (Test-Path $path) {
								Write-Host "Navigating to '$selectedAlias' -> '$path'." -ForegroundColor Green
								Set-Location $path
						} else {
								Write-Host "The path '$path' for alias '$selectedAlias' does not exist." -ForegroundColor Red
						}
				}
				return $selectedAlias
		}
		elseif ($matchedAliases.Count -gt 1) {
				Write-Host "Did you mean one of these? Type the number to $action, or press ENTER to cancel:" -ForegroundColor Yellow
				Write-Host ""

				$maxAliasLength = ($matchedAliases | ForEach-Object { $_.Alias.Length } | Measure-Object -Maximum).Maximum
				$numberWidth = $matchedAliases.Count.ToString().Length

				for ($i = 0; $i -lt $matchedAliases.Count; $i++) {
						$alias = $matchedAliases[$i].Alias
						$path = $matchedAliases[$i].Path
						$paddedAlias = $alias.PadRight($maxAliasLength)
						$paddedNumber = ($i + 1).ToString().PadLeft($numberWidth)

						Write-Host "[" -NoNewline -ForegroundColor DarkGray
						Write-Host $paddedNumber -NoNewline -ForegroundColor Cyan
						Write-Host "]:" -NoNewline -ForegroundColor DarkGray
						Write-Host " $paddedAlias" -NoNewline -ForegroundColor Green
						Write-Host " -> " -NoNewline -ForegroundColor DarkGray
						Write-Host $path -ForegroundColor Yellow
				}

				Write-Host ""
				$choice = Read-Host "Enter your choice (1-$($matchedAliases.Count))"
				if ([string]::IsNullOrEmpty($choice)) {
						Write-Host "Operation cancelled. No action taken." -ForegroundColor Yellow
						return $null
				}
				elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchedAliases.Count) {
						$selectedAlias = $matchedAliases[[int]$choice - 1].Alias
						$path = $matchedAliases[[int]$choice - 1].Path
						if (Test-Path $path) {
								Write-Host "Navigating to '$selectedAlias' -> '$path'." -ForegroundColor Green
								Set-Location $path
						} else {
								Write-Host "The path '$path' for alias '$selectedAlias' does not exist." -ForegroundColor Red
						}
						return $selectedAlias
				}
				else {
						Write-Host "Invalid selection. No action taken." -ForegroundColor Red
						return $null
				}
		}
		else {
				return "NO_MATCH"
		}
}


function goto {
	[CmdletBinding(DefaultParameterSetName = 'Navigate')]
	param(
		[Parameter(ParameterSetName = 'Navigate', Position = 0)]
		[Parameter(ParameterSetName = 'Unregister', Position = 1)]
		[Parameter(ParameterSetName = 'Expand', Position = 1)]
		[Parameter(ParameterSetName = 'Push', Position = 1)]
		[Parameter(ParameterSetName = 'Register', Position = 1)]
		[string]$Alias,

		[Parameter(ParameterSetName = 'Register', Mandatory = $true)]
		[Alias('r')]
		[switch]$Register,

		[Parameter(ParameterSetName = 'Unregister', Mandatory = $true)]
		[Alias('u')]
		[switch]$Unregister,

		[Parameter(ParameterSetName = 'Push', Mandatory = $true)]
		[Alias('p')]
		[switch]$Push,

		[Parameter(ParameterSetName = 'Pop', Mandatory = $true)]
		[Alias('o')]
		[switch]$Pop,

		[Parameter(ParameterSetName = 'List', Mandatory = $true)]
		[Alias('l')]
		[switch]$List,

		[Parameter(ParameterSetName = 'Expand', Mandatory = $true)]
		[Alias('x')]
		[switch]$Expand,

		[Parameter(ParameterSetName = 'Cleanup', Mandatory = $true)]
		[Alias('c')]
		[switch]$Cleanup,

		[Parameter(ParameterSetName = 'Help', Mandatory = $true)]
		[Alias('h')]
		[switch]$Help,

		[Parameter(ParameterSetName = 'Update', Mandatory = $true)]
		[switch]$Update,

		[Parameter(ParameterSetName = 'Version', Mandatory = $true)]
		[Alias('v')]
		[switch]$Version,

		[Parameter(ParameterSetName = 'Register', Position = 2)]
		[Parameter(ParameterSetName = 'Navigate', Position = 1)]
		[string]$Path
	)

	switch ($PSCmdlet.ParameterSetName) {
		'Register' {
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
				Write-Host "Alias name or path not specified. Usage: goto -r <alias_name> <path>" -ForegroundColor Yellow
			}
		}
		'Unregister' {
			if (-not $Alias) {
				Write-Host "Usage: goto u <alias>" -ForegroundColor Yellow
				return
			}

			if ($Global:DirectoryAliases.ContainsKey($Alias)) {
				$selectedAlias = $Alias
			}
			else {
				$selectedAlias = _goto_print_similar -aliasInput $Alias -action "unregister" -SuppressNavigation
			}

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
		}
		'List' {
			try {
				if ($Global:DirectoryAliases.Count -eq 0) {
					Write-Host "No aliases registered." -ForegroundColor Yellow
					return
				}
				$maxAliasLength = ($Global:DirectoryAliases.Keys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
				$maxPathLength = ($Global:DirectoryAliases.Values | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
				Write-Host "`nRegistered Aliases:" -ForegroundColor Cyan
				$separatorLine = "-" * (4 + $maxAliasLength + 4 + $maxPathLength)
				Write-Host $separatorLine -ForegroundColor DarkGray
				$Global:DirectoryAliases.GetEnumerator() | Sort-Object Name | ForEach-Object {
					$aliasDisplay = $_.Key.PadRight($maxAliasLength)
					$pathDisplay = $_.Value.PadRight($maxPathLength)
					Write-Host "  " -NoNewline
					Write-Host $aliasDisplay -NoNewline -ForegroundColor Green
					Write-Host " -> " -NoNewline -ForegroundColor DarkGray
					Write-Host $pathDisplay -ForegroundColor Yellow
				}
				Write-Host $separatorLine -ForegroundColor DarkGray
			}
			catch {
				Write-Host "An error occurred while listing aliases. Please try again or contact support if the issue persists." -ForegroundColor Red
			}
		}
		'Expand' {
			if (-not $Alias) {
				Write-Host "Usage: goto x <alias>" -ForegroundColor Yellow
				return
			}

			if ($Global:DirectoryAliases.ContainsKey($Alias)) {
				$selectedAlias = $Alias
				$path = $Global:DirectoryAliases[$Alias]
			}
			else {
				$selectedAlias = _goto_print_similar -aliasInput $Alias -action "expand" -SuppressNavigation
			}

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
		'Cleanup' {
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
		'Help' {
			function Show-Help {
				$gotoAsciiArt = @"
_____/\\\\\\\\\\\\___________________________________________
 ___/\\\//////////____________________________________________
  __/\\\_______________________________/\\\____________________
   _\/\\\____/\\\\\\\_____/\\\\\_____/\\\\\\\\\\\_____/\\\\\____
    _\/\\\___\/////\\\___/\\\///\\\__\////\\\////____/\\\///\\\__
     _\/\\\_______\/\\\__/\\\__\//\\\____\/\\\_______/\\\__\//\\\_
      _\/\\\_______\/\\\_\//\\\__/\\\_____\/\\\_/\\__\//\\\__/\\\__
       _\//\\\\\\\\\\\\/___\///\\\\\/______\//\\\\\____\///\\\\\/___
        __\////////////_______\/////_________\/////_______\/////_____
"@
				$lines = $gotoAsciiArt -split "`n"

				function Write-ColoredChar {
					param($char, $color)
					if ($char -eq '_') {
						Write-Host $char -ForegroundColor DarkGray -NoNewline
					}
					else {
						Write-Host $char -ForegroundColor $color -NoNewline
					}
				}

				$colors = @{
					DR = [System.ConsoleColor]::DarkMagenta
					R  = [System.ConsoleColor]::Red
					DG = [System.ConsoleColor]::DarkGreen
					G  = [System.ConsoleColor]::Green
					DY = [System.ConsoleColor]::DarkYellow
					Y  = [System.ConsoleColor]::Yellow
					DC = [System.ConsoleColor]::DarkBlue
					C  = [System.ConsoleColor]::Cyan
				}

				$colorPatterns = @(
					@("DR", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R"),
					@("DR", "R", "R", "R", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR"),
					@("DR", "R", "R", "R", "DG", "G", "G", "G"),
					@("DR", "DR", "R", "R", "R", "DR", "R", "R", "R", "R", "R", "R", "R", "DY", "Y", "Y", "Y", "Y", "Y", "DG", "G", "G", "G", "G", "G", "G", "G", "G", "G", "G", "G", "DC", "C", "C", "C", "C", "C"),
					@("DR", "DR", "R", "R", "R", "DR", "DR", "DR", "DR", "DR", "DR", "R", "R", "R", "DY", "Y", "Y", "Y", "DY", "DY", "DY", "Y", "Y", "Y", "DG", "DG", "DG", "DG", "DG", "G", "G", "G", "DG", "DG", "DG", "DG", "DC", "C", "C", "C", "DC", "DC", "DC", "C", "C", "C"),
					@("DR", "DR", "R", "R", "R", "DR", "DR", "R", "R", "R", "DY", "Y", "Y", "Y", "DY", "DY", "DY", "Y", "Y", "Y", "DG", "DG", "G", "G", "G", "DC", "C", "C", "C", "DC", "DC", "DC", "C", "C", "C"),
					@("DR", "DR", "R", "R", "R", "DR", "DR", "R", "R", "R", "DY", "DY", "DY", "Y", "Y", "Y", "DY", "Y", "Y", "Y", "DG", "DG", "G", "G", "G", "DG", "G", "G", "DC", "DC", "DC", "C", "C", "C", "DC", "C", "C", "C"),
					@("DR", "DR", "DR", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "DR", "DY", "DY", "DY", "DY", "Y", "Y", "Y", "Y", "Y", "DY", "DG", "DG", "DG", "G", "G", "G", "G", "G", "DC", "DC", "DC", "DC", "C", "C", "C", "C", "C", "DC"),
					@("DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DR", "DY", "DY", "DY", "DY", "DY", "DY", "DG", "DG", "DG", "DG", "DG", "DG", "DC", "DC", "DC", "DC", "DC", "DC")
				)

				for ($i = 0; $i -lt $lines.Count; $i++) {
					$line = $lines[$i]
					$pattern = $colorPatterns[$i]
					$colorIndex = 0

					foreach ($char in $line.ToCharArray()) {
						if ($char -eq '_') {
							Write-ColoredChar $char "DarkGray"
						}
						elseif ($char -in '/', '\', '*') {
							Write-ColoredChar $char $colors[$pattern[$colorIndex]]
							$colorIndex = ($colorIndex + 1) % $pattern.Count
						}
						else {
							Write-Host $char -NoNewline
						}
					}
					Write-Host ""
				}

				Write-Host "`nUsage: " -ForegroundColor Cyan -NoNewline
				Write-Host "goto [<option>] <alias> [<directory>]`n" -ForegroundColor White

				Write-Host "Default usage:" -ForegroundColor Cyan
				Write-Host "  goto <alias> " -ForegroundColor Yellow -NoNewline
				Write-Host "- changes to the directory registered for the given alias`n" -ForegroundColor White

				Write-Host "Partial Alias Matching:" -ForegroundColor Cyan
				Write-Host "  You can use partial aliases. For example, if you have an alias 'documents'," -ForegroundColor White
				Write-Host "  you can use 'goto doc' to match it. If multiple aliases match, you'll be" -ForegroundColor White
				Write-Host "  prompted to choose the correct one.`n" -ForegroundColor White

				Write-Host "OPTIONS:" -ForegroundColor Cyan
				$options = @(
					@{Option = "-r, -Register"; Desc = "registers an alias"; Usage = "goto -r|-Register <alias> <directory>" },
					@{Option = "-u, -Unregister"; Desc = "unregisters an alias"; Usage = "goto -u|-Unregister <alias>" },
					@{Option = "-p, -Push"; Desc = "pushes the current directory onto the stack, then performs goto"; Usage = "goto -p|-Push <alias>" },
					@{Option = "-o, -Pop"; Desc = "pops the top directory from the stack, then changes to that directory"; Usage = "goto -o|-Pop" },
					@{Option = "-l, -List"; Desc = "lists aliases"; Usage = "goto -l|-List" },
					@{Option = "-x, -Expand"; Desc = "expands an alias"; Usage = "goto -x|-Expand <alias>" },
					@{Option = "-c, -Cleanup"; Desc = "cleans up non existent directory aliases"; Usage = "goto -c|-Cleanup" },
					@{Option = "-h, -Help"; Desc = "prints this help"; Usage = "goto -h|-Help" },
					@{Option = "-v, -Version"; Desc = "displays the version of the goto module"; Usage = "goto -v|-Version" },
					@{Option = "-Update"; Desc = "updates the goto module"; Usage = "goto -Update" }
				)

				foreach ($opt in $options) {
					Write-Host "  $($opt.Option)" -ForegroundColor Green
					Write-Host "    $($opt.Desc)" -ForegroundColor White
					Write-Host "    Usage: " -ForegroundColor DarkGray -NoNewline
					Write-Host "$($opt.Usage)`n" -ForegroundColor Yellow
				}
			}
			Show-Help
		}

		'Push' {
			$currentPath = (Get-Location).Path
			Push-Location

			if ($Global:DirectoryAliases.ContainsKey($Alias)) {
				$path = $Global:DirectoryAliases[$Alias]
				Write-Host "Pushed current directory '$currentPath' to stack and moved to alias '$Alias' at path '$path'." -ForegroundColor Green
				Set-Location $path
			}
			else {
				if (-not [string]::IsNullOrWhiteSpace($Alias)) {
					$selectedAlias = _goto_print_similar -aliasInput $Alias -SuppressNavigation
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
		'Pop' {
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
		'Version' {
			$moduleInfo = Get-Module Goto
			$moduleVersion = $moduleInfo.Version.ToString()
			Write-Host "goto version $moduleVersion"
		}
		'Update' {
			Update-GotoModule
		}
		'Navigate' {
			if (-not $Alias) {
				Show-Help
				return
			}
			if ($Global:DirectoryAliases.ContainsKey($Alias)) {
				$path = $Global:DirectoryAliases[$Alias]
				if (Test-Path $path) {
					Write-Host "Navigating to '$Alias' -> '$path'." -ForegroundColor Green
					Set-Location $path
				}
				else {
					Write-Host "The path '$path' for alias '$Alias' does not exist." -ForegroundColor Red
				}
			}
			else {
				$result = _goto_print_similar -aliasInput $Alias
				if ($result -eq "NO_MATCH") {
					Write-Host "No matching alias found for '$Alias'." -ForegroundColor Red
				}
			}
		}
	}
}

# Initialization when loading module
Initialize-GotoEnvironment

# Asynchronous verification of updates
$updateCheckJob = Start-Job -ScriptBlock {
	param($GotoDataPath, $UpdateInfoFile)

	Import-Module Goto

	if (Test-Path $UpdateInfoFile) {
		$updateInfo = Import-Clixml -Path $UpdateInfoFile
		if (($null -eq $updateInfo.LastCheckTime) -or ((Get-Date) - $updateInfo.LastCheckTime).Days -ge 30) {
			Test-ForUpdates
		}
	}
	else {
		Test-ForUpdates
	}
} -ArgumentList $script:GotoDataPath, $script:UpdateInfoFile

# Register the ending event of the Job
Register-ObjectEvent -InputObject $updateCheckJob -EventName StateChanged -Action {
	if ($Event.SourceEventArgs.JobStateInfo.State -eq "Completed") {
		$result = Receive-Job -Job $Event.SourceJob
		if ($result) {
			Write-Host $result -ForegroundColor Yellow
		}
		Unregister-Event -SourceIdentifier $Event.SourceIdentifier
		Remove-Job -Job $Event.SourceJob
	}
} | Out-Null

# Export of functions
Export-ModuleMember -Function goto, Import-Aliases, Initialize-GotoEnvironment, Update-GotoModule, Save-Aliases

Register-ArgumentCompleter -CommandName 'goto' -ScriptBlock {
	param($commandName, $wordToComplete, $commandAst, $fakeBoundParameters)

	$commands = @{
		'r'      = 'Register'
		'u'      = 'Unregister'
		'l'      = 'List'
		'x'      = 'Expand'
		'c'      = 'Cleanup'
		'p'      = 'Push'
		'o'      = 'Pop'
		'v'      = 'Version'
		'h'      = 'Help'
		'Update' = 'Update'
	}

	$aliases = $Global:DirectoryAliases.Keys

	if ($wordToComplete.StartsWith('-')) {
		$commands.GetEnumerator() | Where-Object { $_.Key -like "$($wordToComplete.TrimStart('-'))*" -or $_.Value -like "$($wordToComplete.TrimStart('-'))*" } | ForEach-Object {
			[System.Management.Automation.CompletionResult]::new("-$($_.Value)", "-$($_.Value)", 'ParameterName', "Perform $($_.Value) operation")
		}
	}
	elseif ($fakeBoundParameters.ContainsKey('Unregister') -or $fakeBoundParameters.ContainsKey('u') -or
		$fakeBoundParameters.ContainsKey('Expand') -or $fakeBoundParameters.ContainsKey('x') -or
		$fakeBoundParameters.ContainsKey('Push') -or $fakeBoundParameters.ContainsKey('p')) {
		$aliases | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
			[System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
		}
	}
	else {
		$aliases | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
			[System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
		}
	}
}

#Export of CD functions for each Alias
$Global:DirectoryAliases.Keys | ForEach-Object {
	$aliasName = $_
	$aliasPath = $Global:DirectoryAliases[$aliasName]
	New-Item -Path Function:\ -Name "Global:cd$aliasName" -Value { Set-Location $aliasPath }.GetNewClosure() | Out-Null
	Export-ModuleMember -Function "cd$aliasName"
}
