#Requires -Version 5.1
#Requires -RunAsAdministrator
# Setup-NodeLCM.ps1
# ---------------------------------------------------------------------------
# Configura il Local Configuration Manager (LCM) su questo nodo client
# per puntare al Pull Server DSC.
# Da eseguire SU OGNI NODO CLIENT, non sul Pull Server.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# PARAMETRI - modifica questi valori
# ---------------------------------------------------------------------------
$PullServerUrl   = 'http://PULLSERVER.dominio.locale:8080/PSDSCPullServer'
$RegistrationKey = 'INCOLLA-QUI-LA-REGISTRATION-KEY'
$ConfigurationId = [System.Guid]::NewGuid().ToString()

# Frequenza controllo (in minuti)
$RefreshFrequencyMins      = 30   # ogni quanto il nodo contatta il Pull Server
$ConfigurationModeFreqMins = 30   # ogni quanto applica la configurazione locale

Write-Host "=== Configurazione LCM: $env:COMPUTERNAME ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Configura LCM
# ---------------------------------------------------------------------------
[DSCLocalConfigurationManager()]
Configuration LCMConfig {

    Node localhost {

        Settings {
            RefreshMode                    = 'Pull'
            ConfigurationMode              = 'ApplyAndAutoCorrect'
            ConfigurationID                = $ConfigurationId
            RefreshFrequencyMins           = $RefreshFrequencyMins
            ConfigurationModeFrequencyMins = $ConfigurationModeFreqMins
            RebootNodeIfNeeded             = $false
            ActionAfterReboot              = 'ContinueConfiguration'
            AllowModuleOverwrite           = $true
        }

        ConfigurationRepositoryWeb PullServer {
            ServerURL               = $PullServerUrl
            RegistrationKey         = $RegistrationKey
            ConfigurationNames      = @($env:COMPUTERNAME)
            AllowUnsecureConnection = $true
        }

        ResourceRepositoryWeb PullServerModules {
            ServerURL               = $PullServerUrl
            RegistrationKey         = $RegistrationKey
            AllowUnsecureConnection = $true
        }

        ReportServerWeb PullServerReports {
            ServerURL               = $PullServerUrl
            RegistrationKey         = $RegistrationKey
            AllowUnsecureConnection = $true
        }
    }
}

$mofPath = Join-Path $env:TEMP 'LCMConfig'
LCMConfig -OutputPath $mofPath | Out-Null
Set-DscLocalConfigurationManager -Path $mofPath -Verbose -Force

# ---------------------------------------------------------------------------
# Verifica
# ---------------------------------------------------------------------------
$lcm = Get-DscLocalConfigurationManager

Write-Host ""
Write-Host "=== LCM configurato ===" -ForegroundColor Green
Write-Host "RefreshMode     : $($lcm.RefreshMode)"
Write-Host "ConfigMode      : $($lcm.ConfigurationMode)"
Write-Host "RefreshFreq     : $($lcm.RefreshFrequencyMins) min"
Write-Host "ConfigFreq      : $($lcm.ConfigurationModeFrequencyMins) min"
Write-Host ""
Write-Host "Forza un controllo immediato con:"
Write-Host "  Update-DscConfiguration -Wait -Verbose"
