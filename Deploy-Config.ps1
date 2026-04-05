#Requires -Version 5.1
#Requires -RunAsAdministrator
# Deploy-Config.ps1
# ---------------------------------------------------------------------------
# Esegui ogni volta che modifichi SoftwareList.psd1 o aggiungi nodi.
#
# Operazioni:
#   1. Compila SoftwareConfig.ps1 -> MOF per ogni nodo
#   2. Crea i checksum .mof.checksum
#   3. Copia MOF + checksum nella ConfigurationPath del Pull Server
#   4. Archivia e pubblica il modulo cSoftwareManagement nel Pull Server
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# PARAMETRI
# ---------------------------------------------------------------------------
$PullConfigPath = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Configuration"
$PullModulePath = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Modules"
$ScriptRoot     = $PSScriptRoot
$OutputPath     = Join-Path $ScriptRoot 'Output'
$ResourceModule = Join-Path $ScriptRoot 'cSoftwareManagement'

Write-Host "=== Deploy DSC SoftwareBaseline ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Pulisci output precedente
# ---------------------------------------------------------------------------
Write-Host "[1/4] Pulizia cartella Output..." -ForegroundColor Yellow

if (Test-Path $OutputPath) {
    Remove-Item -Path "$OutputPath\*" -Force -Recurse
} else {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# ---------------------------------------------------------------------------
# 2. Verifica modulo custom nel PSModulePath locale
# ---------------------------------------------------------------------------
Write-Host "[2/4] Verifica modulo cSoftwareManagement..." -ForegroundColor Yellow

$moduleDest = Join-Path "$env:ProgramFiles\WindowsPowerShell\Modules" 'cSoftwareManagement'
if (-not (Test-Path $moduleDest)) {
    Copy-Item -Path $ResourceModule -Destination $moduleDest -Recurse -Force
    Write-Host "  Modulo copiato in PSModulePath."
} else {
    Write-Host "  Modulo gia' presente in PSModulePath."
}

# ---------------------------------------------------------------------------
# 3. Compila la configurazione DSC
# ---------------------------------------------------------------------------
Write-Host "[3/4] Compilazione SoftwareConfig.ps1..." -ForegroundColor Yellow

& "$ScriptRoot\SoftwareConfig.ps1"

$mofFiles = Get-ChildItem -Path $OutputPath -Filter '*.mof' -ErrorAction SilentlyContinue
if ($mofFiles.Count -eq 0) {
    throw "Nessun MOF generato. Controlla SoftwareConfig.ps1."
}
Write-Host "  MOF generati: $($mofFiles.Count)"

# ---------------------------------------------------------------------------
# 4. Checksum + copia sul Pull Server
# ---------------------------------------------------------------------------
Write-Host "[4/4] Pubblicazione sul Pull Server..." -ForegroundColor Yellow

foreach ($mof in $mofFiles) {
    $hash = (Get-FileHash -Path $mof.FullName -Algorithm SHA256).Hash
    $hash | Set-Content -Path "$($mof.FullName).checksum" -Encoding ASCII

    Copy-Item -Path $mof.FullName          -Destination (Join-Path $PullConfigPath $mof.Name)              -Force
    Copy-Item -Path "$($mof.FullName).checksum" -Destination (Join-Path $PullConfigPath "$($mof.Name).checksum") -Force
    Write-Host "  Pubblicato: $($mof.Name)"
}

# Archivia modulo custom per distribuzione ai nodi
$moduleVersion  = (Import-PowerShellDataFile "$ResourceModule\cSoftwareManagement.psd1").ModuleVersion
$moduleArchive  = Join-Path $PullModulePath "cSoftwareManagement_$moduleVersion.zip"

if (-not (Test-Path $moduleArchive)) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($ResourceModule, $moduleArchive)

    $modHash = (Get-FileHash -Path $moduleArchive -Algorithm SHA256).Hash
    $modHash | Set-Content -Path "$moduleArchive.checksum" -Encoding ASCII
    Write-Host "  Modulo archiviato: cSoftwareManagement_$moduleVersion.zip"
} else {
    Write-Host "  Modulo gia' presente (v$moduleVersion)."
}

# ---------------------------------------------------------------------------
# Riepilogo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Deploy completato ===" -ForegroundColor Green
Write-Host "MOF pubblicati : $($mofFiles.Count)"
Write-Host "Config path    : $PullConfigPath"
Write-Host "Modules path   : $PullModulePath"
Write-Host ""
Write-Host "I nodi applicheranno la configurazione al prossimo ciclo LCM (max 30 min)."
Write-Host "Per forzare subito un nodo:"
Write-Host "  Invoke-Command -ComputerName <nodo> -ScriptBlock { Update-DscConfiguration -Wait }"
