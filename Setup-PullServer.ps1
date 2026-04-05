#Requires -Version 5.1
#Requires -RunAsAdministrator
# Setup-PullServer.ps1
# ---------------------------------------------------------------------------
# Configura il Pull Server DSC su questa macchina (Windows Server).
# Da eseguire UNA SOLA VOLTA sul server che fa da Pull Server.
#
# Pre-requisiti:
#   - Windows Server 2016/2019/2022
#   - Connessione Internet per scaricare xPSDesiredStateConfiguration
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# PARAMETRI
# ---------------------------------------------------------------------------
$PullServerPort     = 8080
$PullServerEndpoint = 'PSDSCPullServer'
$RegistrationKey    = [System.Guid]::NewGuid().ToString()
$CertThumbprint     = 'AllowUnencryptedTraffic'

$ModulePath = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Modules"
$ConfigPath = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Configuration"

Write-Host "=== Setup DSC Pull Server ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Feature Windows
# ---------------------------------------------------------------------------
Write-Host "[1/5] Installazione feature Windows..." -ForegroundColor Yellow

foreach ($feature in @('DSC-Service','Web-Server','Web-Mgmt-Tools','Web-Mgmt-Console')) {
    if (-not (Get-WindowsFeature -Name $feature).Installed) {
        Install-WindowsFeature -Name $feature -IncludeManagementTools | Out-Null
        Write-Host "  Installato: $feature"
    } else {
        Write-Host "  Gia' presente: $feature"
    }
}

# ---------------------------------------------------------------------------
# 2. Modulo xPSDesiredStateConfiguration
# ---------------------------------------------------------------------------
Write-Host "[2/5] Installazione xPSDesiredStateConfiguration..." -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name xPSDesiredStateConfiguration)) {
    Install-Module -Name xPSDesiredStateConfiguration -Force -AllowClobber -Scope AllUsers
    Write-Host "  Modulo installato."
} else {
    Write-Host "  Modulo gia' presente."
}

# ---------------------------------------------------------------------------
# 3. Cartelle e Registration Key
# ---------------------------------------------------------------------------
Write-Host "[3/5] Creazione cartelle e chiave di registrazione..." -ForegroundColor Yellow

foreach ($dir in @($ModulePath, $ConfigPath)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

$keyFile = "$env:PROGRAMFILES\WindowsPowerShell\DscService\RegistrationKeys.txt"
$RegistrationKey | Set-Content -Path $keyFile -Encoding ASCII
Write-Host "  Registration Key: $RegistrationKey"
Write-Host "  Salvata in: $keyFile"

# ---------------------------------------------------------------------------
# 4. Configurazione Pull Server via DSC
# ---------------------------------------------------------------------------
Write-Host "[4/5] Configurazione Pull Server DSC..." -ForegroundColor Yellow

Import-Module xPSDesiredStateConfiguration -ErrorAction Stop

Configuration PullServerSetup {
    Import-DscResource -ModuleName xPSDesiredStateConfiguration
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node localhost {

        WindowsFeature DSCServiceFeature {
            Ensure = 'Present'
            Name   = 'DSC-Service'
        }

        xDscWebService PSDSCPullServer {
            Ensure                   = 'Present'
            EndpointName             = $PullServerEndpoint
            Port                     = $PullServerPort
            PhysicalPath             = "$env:SystemDrive\inetpub\$PullServerEndpoint"
            CertificateThumbPrint    = $CertThumbprint
            ModulePath               = $ModulePath
            ConfigurationPath        = $ConfigPath
            RegistrationKeyPath      = "$env:PROGRAMFILES\WindowsPowerShell\DscService"
            State                    = 'Started'
            UseSecurityBestPractices = $false
            DependsOn                = '[WindowsFeature]DSCServiceFeature'
        }
    }
}

$mofPath = Join-Path $env:TEMP 'PullServerSetup'
PullServerSetup -OutputPath $mofPath | Out-Null
Start-DscConfiguration -Path $mofPath -Wait -Verbose -Force

# ---------------------------------------------------------------------------
# 5. Regola firewall
# ---------------------------------------------------------------------------
Write-Host "[5/5] Regola Windows Firewall..." -ForegroundColor Yellow

New-NetFirewallRule -DisplayName "DSC Pull Server HTTP $PullServerPort" `
    -Direction Inbound -Protocol TCP -LocalPort $PullServerPort `
    -Action Allow -Profile Domain -ErrorAction SilentlyContinue | Out-Null

Write-Host "  Porta $PullServerPort aperta per il profilo Domain."

# ---------------------------------------------------------------------------
# Riepilogo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Pull Server configurato ===" -ForegroundColor Green
Write-Host "URL endpoint    : http://$(hostname):$PullServerPort/$PullServerEndpoint"
Write-Host "Cartella MOF    : $ConfigPath"
Write-Host "Cartella moduli : $ModulePath"
Write-Host "Registration Key: $RegistrationKey"
Write-Host ""
Write-Host "PROSSIMI PASSI:" -ForegroundColor Cyan
Write-Host "  1. Esegui Deploy-Config.ps1 dalla macchina admin"
Write-Host "  2. Esegui Setup-NodeLCM.ps1 su ogni nodo client"
