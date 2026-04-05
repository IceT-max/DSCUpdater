DSC Software Management
PowerShell 5.1 | ASCII | Pull Server
===========================================================================

STRUTTURA FILE
--------------
DSC-SoftwareManagement\
  cSoftwareManagement\                  Custom DSC Resource (non modificare)
    cSoftwareManagement.psd1
    DSCResources\
      cSoftwareInstall\
        cSoftwareInstall.psm1           Logica principale
        cSoftwareInstall.psd1
        cSoftwareInstall.schema.mof
  SoftwareList.psd1                     Lista software da gestire  <-- modifica qui
  SoftwareConfig.ps1                    Configurazione DSC + lista nodi
  Setup-PullServer.ps1                  Setup Pull Server (1 sola volta)
  Setup-NodeLCM.ps1                     Setup LCM su ogni client
  Deploy-Config.ps1                     Compila e pubblica i MOF


SETUP INIZIALE (nell ordine)
-----------------------------
1. Sul Pull Server:
      .\Setup-PullServer.ps1
      Annota URL e Registration Key stampati a schermo.

2. Su SoftwareConfig.ps1 (macchina admin):
      Inserisci i nomi dei PC nell array $Nodes.

3. Su Setup-NodeLCM.ps1:
      Imposta $PullServerUrl e $RegistrationKey.

4. Dalla macchina admin:
      .\Deploy-Config.ps1

5. Su ogni PC client:
      .\Setup-NodeLCM.ps1


USO QUOTIDIANO
--------------
Per aggiungere o aggiornare un software:
  1. Modifica SoftwareList.psd1
  2. Esegui .\Deploy-Config.ps1
  I PC si aggiornano entro 30 minuti (ciclo LCM automatico).

Per forzare un aggiornamento immediato su un PC:
  Invoke-Command -ComputerName PC-001 -ScriptBlock { Update-DscConfiguration -Wait }


LOGICA DI VERSIONE
------------------
  Non installato              -> installa
  Versione installata < target -> aggiorna
  Versione installata >= target -> non tocca nulla


COMANDI DIAGNOSTICA
-------------------
  # Stato conformita' nodo
  Get-DscConfigurationStatus -CimSession PC-001

  # Software installato su un nodo
  Invoke-Command -ComputerName PC-001 -ScriptBlock {
      Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |
      Select-Object DisplayName, DisplayVersion | Sort-Object DisplayName
  }

  # Stato LCM
  Get-DscLocalConfigurationManager -CimSession PC-001


PORTE FIREWALL
--------------
  Client -> Pull Server : TCP 8080
  Admin  -> Pull Server : TCP 445 (SMB) o 5985 (WinRM)
  Admin  -> Client      : TCP 5985 (WinRM, per diagnostica)
  Client -> FileServer  : TCP 445 (SMB, se InstallerPath e' UNC)
