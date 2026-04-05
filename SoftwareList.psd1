# SoftwareList.psd1
# ---------------------------------------------------------------------------
# Elenco del software da gestire su tutti i nodi.
# Modifica questo file e riesegui Deploy-Config.ps1 per aggiornare la policy.
#
# Campi obbligatori : Name, TargetVersion, InstallerPath, InstallerType
# Campi facoltativi : SilentArgs, Ensure (default: Present)
#
# InstallerPath - percorso risolto SUL CLIENT:
#   UNC   : \\fileserver\installers\app.msi
#   HTTP  : https://repo.azienda.it/app.msi
#   Locale: C:\Installers\app.msi  (deve esistere identico su ogni PC)
#
# SilentArgs default:
#   MSI -> /qn /norestart
#   EXE -> /S
# ---------------------------------------------------------------------------

@(
    @{
        Name          = '7-Zip'
        TargetVersion = '24.08.0.0'
        InstallerPath = '\\FILESERVER\DSC-Installers\7z2408-x64.msi'
        InstallerType = 'MSI'
        SilentArgs    = '/qn /norestart'
        Ensure        = 'Present'
    },
    @{
        Name          = 'Notepad++'
        TargetVersion = '8.6.9.0'
        InstallerPath = '\\FILESERVER\DSC-Installers\npp.8.6.9.Installer.x64.exe'
        InstallerType = 'EXE'
        SilentArgs    = '/S'
        Ensure        = 'Present'
    },
    @{
        Name          = 'VLC media player'
        TargetVersion = '3.0.21.0'
        InstallerPath = '\\FILESERVER\DSC-Installers\vlc-3.0.21-win64.msi'
        InstallerType = 'MSI'
        SilentArgs    = '/qn /norestart ALLUSERS=1'
        Ensure        = 'Present'
    }
)
