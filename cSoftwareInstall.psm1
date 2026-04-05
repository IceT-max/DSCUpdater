#Requires -Version 5.1
# cSoftwareInstall.psm1
# Custom DSC Resource - installa o aggiorna MSI/EXE silenziosamente.
# Aggiorna SOLO se la versione installata e' inferiore alla versione target.

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Helper: cerca il software nel registro di sistema
# ---------------------------------------------------------------------------
function Get-InstalledSoftwareEntry {
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($regPath in $regPaths) {
        $entry = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and ($_.DisplayName -like "*$Name*") } |
            Sort-Object DisplayVersion -Descending |
            Select-Object -First 1

        if ($entry) {
            return @{
                DisplayName     = $entry.DisplayName
                DisplayVersion  = if ($entry.DisplayVersion) { $entry.DisplayVersion } else { '0.0.0.0' }
                UninstallString = $entry.UninstallString
            }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Helper: confronto versioni robusto
# Restituisce: -1 (a < b) | 0 (a == b) | 1 (a > b)
# ---------------------------------------------------------------------------
function Compare-SoftwareVersion {
    param (
        [string]$VersionA,
        [string]$VersionB
    )

    try {
        $a = [System.Version]$VersionA
        $b = [System.Version]$VersionB
        return $a.CompareTo($b)
    }
    catch {
        if ($VersionA -lt $VersionB) { return -1 }
        if ($VersionA -gt $VersionB) { return  1 }
        return 0
    }
}

# ---------------------------------------------------------------------------
# Helper: scarica installer da URL in cartella temporanea
# ---------------------------------------------------------------------------
function Get-InstallerFromUrl {
    param (
        [Parameter(Mandatory)]
        [string]$Url
    )

    $fileName = [System.IO.Path]::GetFileName(($Url -split '\?')[0])
    $destPath  = Join-Path $env:TEMP "DSC_$fileName"

    Write-Verbose "Download installer: $Url -> $destPath"
    $wc = New-Object System.Net.WebClient
    $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $wc.DownloadFile($Url, $destPath)
    return $destPath
}

# ---------------------------------------------------------------------------
# Helper: avvia installer e attende il completamento
# ---------------------------------------------------------------------------
function Invoke-SilentInstall {
    param (
        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [ValidateSet('MSI','EXE')]
        [string]$InstallerType,

        [string]$SilentArgs
    )

    if ($InstallerType -eq 'MSI') {
        $argString = if ($SilentArgs) { "/i `"$InstallerPath`" $SilentArgs" } `
                     else             { "/i `"$InstallerPath`" /qn /norestart" }
        Write-Verbose "MSI: msiexec.exe $argString"
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argString `
                              -Wait -PassThru -NoNewWindow
    }
    else {
        $argString = if ($SilentArgs) { $SilentArgs } else { '/S' }
        Write-Verbose "EXE: $InstallerPath $argString"
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList $argString `
                              -Wait -PassThru -NoNewWindow
    }

    if ($proc.ExitCode -notin @(0, 3010, 1641)) {
        throw "Installer terminato con codice: $($proc.ExitCode)"
    }
    Write-Verbose "Installazione completata. ExitCode: $($proc.ExitCode)"
}

# ===========================================================================
# GET
# ===========================================================================
function Get-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TargetVersion,

        [Parameter(Mandatory)]
        [string]$InstallerPath
    )

    $entry = Get-InstalledSoftwareEntry -Name $Name

    if ($entry) {
        Write-Verbose "Trovato: $($entry.DisplayName) v$($entry.DisplayVersion)"
        return @{
            Name             = $Name
            TargetVersion    = $TargetVersion
            InstallerPath    = $InstallerPath
            InstalledVersion = $entry.DisplayVersion
            Ensure           = 'Present'
        }
    }
    else {
        Write-Verbose "Software non trovato: $Name"
        return @{
            Name             = $Name
            TargetVersion    = $TargetVersion
            InstallerPath    = $InstallerPath
            InstalledVersion = '0.0.0.0'
            Ensure           = 'Absent'
        }
    }
}

# ===========================================================================
# TEST
# ===========================================================================
function Test-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TargetVersion,

        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [ValidateSet('MSI','EXE')]
        [string]$InstallerType = 'MSI',

        [string]$SilentArgs = '',

        [ValidateSet('Present','Absent')]
        [string]$Ensure = 'Present'
    )

    $current = Get-TargetResource -Name $Name -TargetVersion $TargetVersion `
                                  -InstallerPath $InstallerPath

    if ($Ensure -eq 'Absent') {
        $result = ($current.Ensure -eq 'Absent')
        Write-Verbose "Ensure=Absent. Conforme: $result"
        return $result
    }

    if ($current.Ensure -eq 'Absent') {
        Write-Verbose "Software assente. Richiede installazione."
        return $false
    }

    $cmp = Compare-SoftwareVersion -VersionA $current.InstalledVersion `
                                   -VersionB $TargetVersion

    if ($cmp -lt 0) {
        Write-Verbose "Versione installata ($($current.InstalledVersion)) < target ($TargetVersion). Richiede aggiornamento."
        return $false
    }

    Write-Verbose "Versione installata ($($current.InstalledVersion)) >= target ($TargetVersion). Conforme."
    return $true
}

# ===========================================================================
# SET
# ===========================================================================
function Set-TargetResource {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TargetVersion,

        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [ValidateSet('MSI','EXE')]
        [string]$InstallerType = 'MSI',

        [string]$SilentArgs = '',

        [ValidateSet('Present','Absent')]
        [string]$Ensure = 'Present'
    )

    if ($Ensure -eq 'Absent') {
        Write-Verbose "Rimozione non implementata in questa risorsa."
        return
    }

    $localPath = $InstallerPath
    if ($InstallerPath -match '^https?://') {
        $localPath = Get-InstallerFromUrl -Url $InstallerPath
    }

    if (-not (Test-Path $localPath)) {
        throw "Installer non trovato: $localPath"
    }

    Invoke-SilentInstall -InstallerPath $localPath `
                         -InstallerType $InstallerType `
                         -SilentArgs    $SilentArgs
}

Export-ModuleMember -Function Get-TargetResource, Test-TargetResource, Set-TargetResource
