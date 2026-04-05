@{
    RootModule        = 'cSoftwareInstall.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-0001-0001-0001-000000000001'
    Author            = 'DSC Admin'
    Description       = 'DSC Resource per installazione e aggiornamento silenzioso di MSI/EXE.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-TargetResource','Test-TargetResource','Set-TargetResource')
}
