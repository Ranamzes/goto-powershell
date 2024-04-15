# PowerShell Goto Function

The PowerShell `goto` function provides an easy way to manage and navigate to your frequently used directories using simple aliases. This function mimics the behavior of the Unix `goto` command, making it easier to switch directories in a more organized manner.

## Features

- **Register Directory Aliases:** Quickly save directory paths with memorable aliases.
- **Navigate with Aliases:** Jump to any registered directory using its alias.
- **List Aliases:** View all currently registered aliases and their paths.
- **Unregister Aliases:** Remove aliases you no longer need.
- **Expand Aliases:** Display the full path of a registered alias.
- **Cleanup Aliases:** Remove aliases pointing to non-existent directories.

## Installation

To install the `goto` function in your PowerShell environment, run the following command in your PowerShell terminal. This command will automatically download and configure everything needed:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Ranamzes/goto-powershell/InstallGoto.ps1" -OutFile "$env:TEMP\InstallGoto.ps1"; & "$env:TEMP\InstallGoto.ps1"; Remove-Item "$env:TEMP\InstallGoto.ps1"
```

This script will:

- Download the `goto` function script.
- Add a line to your PowerShell profile for automatic loading.
- Clean up the installation script after execution.

## Usage

### Register a New Alias

To save a directory path under a memorable alias:
`powershell Goto -r <alias> <path>`

### Navigate Using an Alias

To change to a directory associated with an alias:
`powershell Goto <alias>`

### List All Aliases

To list all registered aliases and their associated paths:
`powershell Goto -l`

### Unregister an Alias

To remove a previously registered alias:
`powershell Goto -u <alias>`

### Expand an Alias

To see the full directory path associated with an alias:
`powershell Goto -x <alias>`

### Cleanup Invalid Aliases

To remove all aliases pointing to non-existent directories:
`powershell Goto -c`

## Support

If you encounter any issues or have suggestions for improvements, please open an issue on this GitHub repository.

## Contributions

Contributions are welcome! Please feel free to submit pull requests with improvements to the scripts or documentation.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
