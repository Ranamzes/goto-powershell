@{
	RootModule        = 'Goto.psm1'
	ModuleVersion     = '1.5.9'
	GUID              = '504b4162-e8df-5f67-b999-3f46ac2fa586'
	Author            = 'Re•MART'
	Description       = 'PowerShell goto navigation - Easily manage and navigate to your frequently used directories using simple aliases.'
	PowerShellVersion = '5.1'
	FileList          = @('readme.md', 'Goto.psm1')
	FunctionsToExport = @('goto', 'Import-Aliases', 'Initialize-GotoEnvironment')
	PrivateData       = @{
		PSData = @{
			Tags         = @('Navigation', 'Productivity', 'Aliases', 'Directory')
			LicenseUri   = 'https://github.com/Ranamzes/goto-powershell/blob/main/LICENSE'
			ProjectUri   = 'https://github.com/Ranamzes/goto-powershell'
			ReleaseNotes = 'improved find similar'
		}
	}
}
