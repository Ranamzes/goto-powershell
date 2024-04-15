# Define the URL to the raw version of GotoFunction.ps1 on GitHub
$url = "https://raw.githubusercontent.com/Ranamzes/goto-powershell/main/GotoFunction.ps1"
$scriptDirectory = "$HOME\PowerShellScripts"
$scriptPath = Join-Path -Path $scriptDirectory -ChildPath "GotoFunction.ps1"

# Create the directory if it doesn't exist
New-Item -ItemType Directory -Path $scriptDirectory -Force

# Download the script from GitHub
Invoke-WebRequest -Uri $url -OutFile $scriptPath

# Define the content to be added to the PowerShell profile
$profileContent = @"
# Auto-generated import for Goto function

. `"$scriptPath`"
Import-Aliases
"@

# Check if the profile already contains a reference to GotoFunction.ps1 and add if not
if (-Not (Select-String -Path $PROFILE -Pattern "GotoFunction.ps1" -Quiet)) {
    Add-Content -Path $PROFILE -Value $profileContent
    Write-Host "Goto function has been added to your PowerShell profile. Please reload your PowerShell."
} else {
    Write-Host "Goto function is already registered in your PowerShell profile."
}
