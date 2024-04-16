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

	# Создание списка алиасов с подсчетом совпадений каждого символа ввода в алиасе
	$matches = $Global:DirectoryAliases.Keys | Where-Object {
		$alias = $_.ToLower()
		$inputChars = $normalizedInput.ToCharArray()
		$aliasChars = $alias.ToCharArray()
		$matchingCharsCount = ($inputChars | Where-Object { $aliasChars -contains $_ }).Count
		$matchingCharsCount -gt 1  # Фильтрация алиасов, где более одного совпадающего символа
	}

	# Преобразование отфильтрованных ключей обратно в объекты с путями
	$matchedAliases = $matches | ForEach-Object {
		[PSCustomObject]@{
			Alias = $_
			Path  = $Global:DirectoryAliases[$_]
		}
	}

	if ($matchedAliases.Count -eq 0) {
		Write-Host "No aliases match your input."
	}
 elseif ($matchedAliases.Count -eq 1) {
		$match = $matchedAliases | Select-Object -First 1
		Write-Host "Navigating to alias '$($match.Alias)' at path '$($match.Path)'."
		Set-Location $match.Path
	}
 else {
		Write-Host "Multiple matches found. Please select one:"
		$index = 0
		$keyInfo = $null
		$instructionsLine = [System.Console]::CursorTop + $matchedAliases.Count + 1

		do {
			# Выводим список алиасов
			for ($i = 0; $i -lt $matchedAliases.Count; $i++) {
				if ($i -eq $index) {
					Write-Host "-> $($matchedAliases[$i].Alias) -> $($matchedAliases[$i].Path)" -ForegroundColor Green
				}
				else {
					Write-Host "   $($matchedAliases[$i].Alias) -> $($matchedAliases[$i].Path)" -ForegroundColor Gray
				}
			}

			# Позиционирование сообщения
			Write-Host "`nUse arrow keys to select an alias, press Enter to confirm, or Esc to cancel." -ForegroundColor Cyan

			$keyInfo = [System.Console]::ReadKey($true)
			# Возвращаем курсор наверх для переписывания списка алиасов
			[System.Console]::SetCursorPosition(0, [System.Console]::CursorTop - $matchedAliases.Count - 2)

			switch ($keyInfo.Key) {
				'UpArrow' {
					if ($index -gt 0) { $index-- }
				}
				'DownArrow' {
					if ($index -lt $matchedAliases.Count - 1) { $index++ }
				}
				'Enter' {
					$selectedAlias = $matchedAliases[$index].Alias
					$selectedPath = $matchedAliases[$index].Path
					# Очищаем строки инструкций
					[System.Console]::SetCursorPosition(0, $instructionsLine)
					Write-Host (" " * [System.Console]::WindowWidth)
					Write-Host "Navigating to alias '$selectedAlias' at path '$selectedPath'."
					Set-Location $selectedPath
					return
				}
				'Escape' {
					# Очищаем строки инструкций
					[System.Console]::SetCursorPosition(0, $instructionsLine)
					Write-Host (" " * [System.Console]::WindowWidth)
					Write-Host "Operation cancelled."
					return
				}
			}
		} while ($keyInfo.Key -ne 'Enter' -and $keyInfo.Key -ne 'Escape')
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
	}
 else {
		# Handle predefined commands or suggest similar aliases
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
				}
				else {
					Write-Host "Alias '$Alias' does not exist. Pushed current directory."
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
				_goto_print_similar -aliasInput $Command
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
