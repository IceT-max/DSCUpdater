#Requires -Version 5.1
#Requires -RunAsAdministrator
# SoftwareConfig.ps1
# ---------------------------------------------------------------------------
# Configurazione DSC che usa SoftwareList.psd1 per definire lo stato desiderato.
# Output: un file .mof per nodo nella cartella .\Output\
# ---------------------------------------------------------------------------

Import-Module cSoftwareManagement -ErrorAction Stop

# ---------------------------------------------------------------------------
# NODI TARGET - inserisci tutti i PC da gestire
# ---------------------------------------------------------------------------
$Nodes = @(
    'PC-001.dominio.locale',
    'PC-002.dominio.locale',
    'PC-003.dominio.locale'
)

# Carica la lista software
$SoftwareList = Import-PowerShellDataFile -Path "$PSScriptRoot\SoftwareList.psd1"

# ---------------------------------------------------------------------------
# Configurazione DSC
# ---------------------------------------------------------------------------
Configuration SoftwareBaseline {

    param (
        [string[]]$ComputerName = 'localhost'
    )

    Import-DscResource -ModuleName cSoftwareManagement
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node $ComputerName {

        foreach ($sw in $SoftwareList) {

            $resourceId = $sw.Name -replace '[^a-zA-Z0-9]','_'

            cSoftwareInstall "Install_$resourceId" {
                Name          = $sw.Name
                TargetVersion = $sw.TargetVersion
                InstallerPath = $sw.InstallerPath
                InstallerType = if ($sw.InstallerType) { $sw.InstallerType } else { 'MSI'     }
                SilentArgs    = if ($sw.SilentArgs)    { $sw.SilentArgs    } else { ''        }
                Ensure        = if ($sw.Ensure)        { $sw.Ensure        } else { 'Present' }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Compila e genera i MOF
# ---------------------------------------------------------------------------
$outputPath = Join-Path $PSScriptRoot 'Output'

SoftwareBaseline -ComputerName $Nodes -OutputPath $outputPath

Write-Host "MOF generati in: $outputPath"
