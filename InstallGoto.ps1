# Define the URL to the raw version of GotoFunction.ps1 on GitHub
$url = "https://raw.githubusercontent.com/ranamzes/goto-powershell/GotoFunction.ps1"
$scriptPath = "$HOME\PowerShellScripts\GotoFunction.ps1"

# Create the directory if it doesn't exist
New-Item -ItemType Directory -Path "$HOME\PowerShellScripts" -Force

# Download the script from GitHub
Invoke-WebRequest -Uri $url -OutFile $scriptPath

# Add the script to the user's PowerShell profile
$profileContent = @"
# Auto-generated import for Goto function
. '$scriptPath'
"@

if (-Not (Select-String -Path $PROFILE -Pattern "GotoFunction.ps1" -Quiet)) {
	$profileContent | Out-File -FilePath $PROFILE -Append -Encoding UTF8
	Write-Host "Goto function has been added to your PowerShell profile."
}
else {
	Write-Host "Goto function is already registered in your PowerShell profile."
}
