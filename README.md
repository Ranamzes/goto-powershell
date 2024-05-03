# PowerShell goto navigation

The PowerShell `goto` function provides an easy way to manage and navigate to your frequently used directories using simple aliases. This function mimics the behavior of the Unix `goto` command, making it easier to switch directories in a more organized manner.

![Example of use](https://raw.githubusercontent.com/Ranamzes/goto-powershell/main/assets/example.gif)

## Features

- **Register Directory Aliases:** Quickly save directory paths with memorable aliases.
- **Navigate with Aliases:** Jump to any registered directory using its alias.
- **List Aliases:** View all currently registered aliases and their paths.
- **Unregister Aliases:** Remove aliases you no longer need.
- **Expand Aliases:** Display the full path of a registered alias.
- **Cleanup Aliases:** Remove aliases pointing to non-existent directories.
- **Push Directory onto Stack:** Save your current directory before moving to another.
- **Pop Directory from Stack:** Return to the most recently saved directory.
- **Update goto:** Automatically check for and apply updates to the goto function.
-
Installation
## Installation

To install the `goto` function in your PowerShell environment, run the following command in your PowerShell terminal. This command will automatically download and configure everything needed:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Ranamzes/goto-powershell/main/InstallGoto.ps1" -OutFile "$env:TEMP\InstallGoto.ps1"; & "$env:TEMP\InstallGoto.ps1"; Remove-Item "$env:TEMP\InstallGoto.ps1"
```

This script will:

- Download the `goto` function script.
- Add a line to your PowerShell profile for automatic loading.
- Clean up the installation script after execution.

## Usage

### Register a New Alias

To save a directory path under a memorable alias:
```powershell
 goto r <alias> <path>
```

### Navigate Using an Alias

To change to a directory associated with an alias:
```powershell
goto <alias>
```

### List All Aliases

To list all registered aliases and their associated paths:
```powershell
goto l
```

### Unregister an Alias

To remove a previously registered alias:
```powershell
goto u <alias>
```

### Expand an Alias

To see the full directory path associated with an alias:
```powershell
goto x <alias>
```

### Cleanup Invalid Aliases

To remove all aliases pointing to non-existent directories:
```powershell
goto c
```

### Push Current Directory and Navigate

To save your current directory and navigate to another:
```powershell
goto p <alias>
```

### Pop to Previous Directory

To return to the directory saved before the last navigation:
```powershell
goto o
```
### Update goto

To check for updates and apply the latest version of the goto function:
```powershell
goto update
```

### Examples

Here are some practical examples to demonstrate how to use the goto function:

- Setting up a workspace:
```powershell
goto r work "C:\Users\UserName\Documents\Work"
goto work
```

- Switching between projects quickly:
```powershell
# Register a project directory and a common resources directory
goto r proj "D:\Projects\CurrentProject"
goto r resources "D:\Resources"

# Navigate to the project
goto proj

# Assume you are now working within the project and need to check something in resources
# Push the current project directory onto the stack and navigate to resources
goto p resources

# After finishing up in the resources directory, pop the stack to return to the project
goto o
```


## Support

If you encounter any issues or have suggestions for improvements, please open an issue on this GitHub repository.

## Contributions

Contributions are welcome! Please feel free to submit pull requests with improvements to the scripts or documentation.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
