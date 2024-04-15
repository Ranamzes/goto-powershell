@"
`$$Global:DirectoryAliases = @{}

function goto {
    param(
        [Parameter(Mandatory=`$$false, Position=0)]
        [string]`$$Command = "",

        [Parameter(Mandatory=`$$false, Position=1)]
        [string]`$$Alias,

        [Parameter(Mandatory=`$$false, Position=2)]
        [string]`$$Path
    )

    switch (`$$Command) {
        "-r" {
            `$$Global:DirectoryAliases[`$$Alias] = `$$Path
            Write-Host "Alias '`$$Alias' registered for path '`$$Path'."
        }
        "-u" {
            if (`$$Global:DirectoryAliases.ContainsKey(`$$Alias)) {
                `$$Global:DirectoryAliases.Remove(`$$Alias)
                Write-Host "Alias '`$$Alias' unregistered."
            } else {
                Write-Warning "Alias '`$$Alias' does not exist."
            }
        }
        "-l" {
            `$$Global:DirectoryAliases.GetEnumerator() | Sort-Object Name | ForEach-Object {
                Write-Host "`$($_.Key) -> `$($_.Value)"
            }
        }
        "-x" {
            if (`$$Global:DirectoryAliases.ContainsKey(`$$Alias)) {
                Write-Host "`$$Alias -> `$(`$$Global:DirectoryAliases[`$$Alias])"
            } else {
                Write-Warning "Alias '`$$Alias' does not exist."
            }
        }
        "-c" {
            `$$Global:DirectoryAliases.Keys | Where-Object { -Not (Test-Path `$$Global:DirectoryAliases[`$_]) } | ForEach-Object {
                Write-Warning "Cleaning up alias `$$_ because the path no longer exists."
                `$$Global:DirectoryAliases.Remove(`$_)
            }
        }
        "-p" {
            $Global:DirectoryStack += (Get-Location).Path
            Set-Location $Global:DirectoryAliases[$Alias]
            Write-Host "Pushed current directory and moved to '$Alias'."
        }
        "-o" {
            if ($Global:DirectoryStack.Count -gt 0) {
                $popLocation = $Global:DirectoryStack[-1]
                $Global:DirectoryStack = $Global:DirectoryStack[0..($Global:DirectoryStack.Count-2)]
                Set-Location $popLocation
                Write-Host "Popped and moved to '$popLocation'."
            } else {
                Write-Warning "Directory stack is empty."
            }
        }
        default {
            if (`$$Global:DirectoryAliases.ContainsKey(`$$Command)) {
                Set-Location `$$Global:DirectoryAliases[`$$Command]
            } elseif (`$$Command) {
                Write-Warning "Alias '`$$Command' does not exist."
            } else {
                Write-Host "Usage: goto [-r <alias> <path> | -u <alias> | -l | -x <alias> | -c | -p <alias> | -o | <alias>]"
            }
        }
    }
}
"@ | Out-File -FilePath $scriptPath -Encoding UTF8
