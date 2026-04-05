@echo off
setlocal EnableDelayedExpansion

:: ===========================================================================
:: setup.bat
:: Installa DSC-SoftwareManagement nelle cartelle previste.
:: Eseguire come Amministratore.
:: ===========================================================================

:: ---------------------------------------------------------------------------
:: Verifica privilegi amministratore
:: ---------------------------------------------------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  [ERRORE] Questo script deve essere eseguito come Amministratore.
    echo  Tasto destro su setup.bat -^> "Esegui come amministratore"
    echo.
    pause
    exit /b 1
)

:: ---------------------------------------------------------------------------
:: Cartella sorgente (dove si trova questo bat)
:: ---------------------------------------------------------------------------
set "SRC=%~dp0"
:: Rimuove eventuale backslash finale
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

:: ---------------------------------------------------------------------------
:: Destinazioni
:: ---------------------------------------------------------------------------
set "DEST_PROJECT=C:\DSC\DSC-SoftwareManagement"
set "DEST_MODULE=%ProgramFiles%\WindowsPowerShell\Modules\cSoftwareManagement"
set "DEST_DSCMOD=%ProgramFiles%\WindowsPowerShell\DscService\Modules"

:: ---------------------------------------------------------------------------
:: Banner
:: ---------------------------------------------------------------------------
echo.
echo  ===========================================================
echo   DSC Software Management - Setup
echo  ===========================================================
echo.
echo  Sorgente  : %SRC%
echo  Progetto  : %DEST_PROJECT%
echo  Modulo PS : %DEST_MODULE%
echo.
echo  Premi un tasto per continuare o CTRL+C per annullare.
pause >nul
echo.

:: ---------------------------------------------------------------------------
:: 1. Cartella progetto principale
:: ---------------------------------------------------------------------------
echo  [1/5] Creazione cartella progetto...

if not exist "%DEST_PROJECT%" (
    mkdir "%DEST_PROJECT%"
    echo       Creata: %DEST_PROJECT%
) else (
    echo       Gia' presente: %DEST_PROJECT%
)

:: Sottocartella Output
if not exist "%DEST_PROJECT%\Output" (
    mkdir "%DEST_PROJECT%\Output"
    echo       Creata: %DEST_PROJECT%\Output
)

:: ---------------------------------------------------------------------------
:: 2. Copia script principali
:: ---------------------------------------------------------------------------
echo.
echo  [2/5] Copia script nella cartella progetto...

set "FILES=SoftwareList.psd1 SoftwareConfig.ps1 Setup-PullServer.ps1 Setup-NodeLCM.ps1 Deploy-Config.ps1 DSC-Monitor.ps1 README.txt ISTRUZIONI.txt"

for %%F in (%FILES%) do (
    if exist "%SRC%\%%F" (
        copy /Y "%SRC%\%%F" "%DEST_PROJECT%\%%F" >nul
        echo       Copiato: %%F
    ) else (
        echo       [AVVISO] Non trovato: %%F
    )
)

:: ---------------------------------------------------------------------------
:: 3. Copia modulo DSC custom nella cartella progetto
:: ---------------------------------------------------------------------------
echo.
echo  [3/5] Copia modulo cSoftwareManagement nella cartella progetto...

set "MOD_SRC=%SRC%\cSoftwareManagement"
set "MOD_DEST_PROJ=%DEST_PROJECT%\cSoftwareManagement"

if not exist "%MOD_SRC%" (
    echo       [ERRORE] Cartella modulo non trovata: %MOD_SRC%
    echo       Verifica che la struttura del pacchetto sia integra.
    goto :STEP4
)

:: Crea struttura cartelle modulo
if not exist "%MOD_DEST_PROJ%"                                              mkdir "%MOD_DEST_PROJ%"
if not exist "%MOD_DEST_PROJ%\DSCResources"                                 mkdir "%MOD_DEST_PROJ%\DSCResources"
if not exist "%MOD_DEST_PROJ%\DSCResources\cSoftwareInstall"               mkdir "%MOD_DEST_PROJ%\DSCResources\cSoftwareInstall"

:: Copia file modulo
copy /Y "%MOD_SRC%\cSoftwareManagement.psd1"                                          "%MOD_DEST_PROJ%\cSoftwareManagement.psd1" >nul
copy /Y "%MOD_SRC%\DSCResources\cSoftwareInstall\cSoftwareInstall.psm1"   "%MOD_DEST_PROJ%\DSCResources\cSoftwareInstall\cSoftwareInstall.psm1" >nul
copy /Y "%MOD_SRC%\DSCResources\cSoftwareInstall\cSoftwareInstall.psd1"   "%MOD_DEST_PROJ%\DSCResources\cSoftwareInstall\cSoftwareInstall.psd1" >nul
copy /Y "%MOD_SRC%\DSCResources\cSoftwareInstall\cSoftwareInstall.schema.mof" "%MOD_DEST_PROJ%\DSCResources\cSoftwareInstall\cSoftwareInstall.schema.mof" >nul

echo       Modulo copiato nella cartella progetto.

:: ---------------------------------------------------------------------------
:STEP4
:: 4. Installa modulo nel PSModulePath globale
:: ---------------------------------------------------------------------------
echo.
echo  [4/5] Installazione modulo nel PSModulePath di sistema...

if not exist "%MOD_SRC%" (
    echo       [SALTATO] Modulo sorgente non trovato.
    goto :STEP5
)

if not exist "%DEST_MODULE%"                                                mkdir "%DEST_MODULE%"
if not exist "%DEST_MODULE%\DSCResources"                                   mkdir "%DEST_MODULE%\DSCResources"
if not exist "%DEST_MODULE%\DSCResources\cSoftwareInstall"                 mkdir "%DEST_MODULE%\DSCResources\cSoftwareInstall"

copy /Y "%MOD_SRC%\cSoftwareManagement.psd1"                                          "%DEST_MODULE%\cSoftwareManagement.psd1" >nul
copy /Y "%MOD_SRC%\DSCResources\cSoftwareInstall\cSoftwareInstall.psm1"   "%DEST_MODULE%\DSCResources\cSoftwareInstall\cSoftwareInstall.psm1" >nul
copy /Y "%MOD_SRC%\DSCResources\cSoftwareInstall\cSoftwareInstall.psd1"   "%DEST_MODULE%\DSCResources\cSoftwareInstall\cSoftwareInstall.psd1" >nul
copy /Y "%MOD_SRC%\DSCResources\cSoftwareInstall\cSoftwareInstall.schema.mof" "%DEST_MODULE%\DSCResources\cSoftwareInstall\cSoftwareInstall.schema.mof" >nul

echo       Modulo installato in: %DEST_MODULE%

:: ---------------------------------------------------------------------------
:STEP5
:: 5. Crea cartelle servizio DSC (se questo e' il Pull Server)
:: ---------------------------------------------------------------------------
echo.
echo  [5/5] Verifica cartelle servizio DSC...

if not exist "%DEST_DSCMOD%" (
    mkdir "%DEST_DSCMOD%"
    echo       Creata: %DEST_DSCMOD%
) else (
    echo       Gia' presente: %DEST_DSCMOD%
)

set "DEST_DSCCONF=%ProgramFiles%\WindowsPowerShell\DscService\Configuration"
if not exist "%DEST_DSCCONF%" (
    mkdir "%DEST_DSCCONF%"
    echo       Creata: %DEST_DSCCONF%
) else (
    echo       Gia' presente: %DEST_DSCCONF%
)

:: ---------------------------------------------------------------------------
:: Riepilogo
:: ---------------------------------------------------------------------------
echo.
echo  ===========================================================
echo   Setup completato.
echo  ===========================================================
echo.
echo   Cartella progetto : %DEST_PROJECT%
echo   Modulo PS         : %DEST_MODULE%
echo.
echo   PROSSIMI PASSI:
echo.
echo   1. Modifica %DEST_PROJECT%\SoftwareList.psd1
echo      Inserisci il software da gestire.
echo.
echo   2. Modifica %DEST_PROJECT%\SoftwareConfig.ps1
echo      Inserisci i nomi dei nodi nell array Nodes.
echo.
echo   3. Sul Pull Server esegui come Admin:
echo      powershell -ExecutionPolicy Bypass -File "%DEST_PROJECT%\Setup-PullServer.ps1"
echo.
echo   4. Dalla macchina admin esegui come Admin:
echo      powershell -ExecutionPolicy Bypass -File "%DEST_PROJECT%\Deploy-Config.ps1"
echo.
echo   5. Su ogni nodo client esegui come Admin:
echo      powershell -ExecutionPolicy Bypass -File "%DEST_PROJECT%\Setup-NodeLCM.ps1"
echo.
echo   6. Per monitorare i nodi:
echo      powershell -ExecutionPolicy Bypass -File "%DEST_PROJECT%\DSC-Monitor.ps1"
echo.
pause
endlocal
