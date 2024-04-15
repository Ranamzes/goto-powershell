$Global:DirectoryAliases = @{}
$Global:DirectoryStack = @{}

function Save-Aliases {
	$path = Join-Path $env:USERPROFILE "PowerShellScripts\DirectoryAliases.xml"
	$Global:DirectoryAliases | Export-Clixml -Path $path
	Write-Host "Aliases saved to $path"
}

function Load-Aliases {
	$path = Join-Path $env:USERPROFILE "PowerShellScripts\DirectoryAliases.xml"
	if (Test-Path $path) {
		$Global:DirectoryAliases = Import-Clixml -Path $path
	}
 else {
		Write-Host "No aliases file found at $path. Starting with an empty aliases list."
		$Global:DirectoryAliases = @{}
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
			$Global:DirectoryStack += (Get-Location).Path
			Set-Location $Global:DirectoryAliases[$Alias]
			Write-Host "Pushed current directory and moved to $Alias."
		}
		'o' {
			if ($Global:DirectoryStack.Count -gt 0) {
				$popLocation = $Global:DirectoryStack[-1]
				$Global:DirectoryStack = $Global:DirectoryStack[0..($Global:DirectoryStack.Count - 2)]
				Set-Location $popLocation
				Write-Host "Popped and moved to $popLocation."
			}
			else {
				Write-Warning "Directory stack is empty."
			}
		}
		default {
			Write-Host "Usage: goto [-r <alias> <path> | -u <alias> | -l | -x <alias> | -c | -p <alias> | -o | <alias>]"
			_goto_print_similar $Command
		}
	}
}
