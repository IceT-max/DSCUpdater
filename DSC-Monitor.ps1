#Requires -Version 5.1
# DSC-Monitor.ps1
# ---------------------------------------------------------------------------
# Form di monitoraggio stato DSC per tutti i nodi definiti in SoftwareConfig.ps1
# Mostra lo stato di ogni nodo e permette di vedere il dettaglio degli errori.
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------
# Costanti colori
# ---------------------------------------------------------------------------
$COL_BG       = [System.Drawing.Color]::FromArgb(30,  30,  30 )
$COL_PANEL    = [System.Drawing.Color]::FromArgb(40,  40,  40 )
$COL_BORDER   = [System.Drawing.Color]::FromArgb(60,  60,  60 )
$COL_TEXT     = [System.Drawing.Color]::FromArgb(220, 220, 220)
$COL_TEXT_DIM = [System.Drawing.Color]::FromArgb(130, 130, 130)
$COL_OK       = [System.Drawing.Color]::FromArgb(60,  180, 90 )
$COL_FAIL     = [System.Drawing.Color]::FromArgb(210, 60,  60 )
$COL_WARN     = [System.Drawing.Color]::FromArgb(210, 160, 40 )
$COL_BTN      = [System.Drawing.Color]::FromArgb(50,  120, 200)
$COL_BTN_HOV  = [System.Drawing.Color]::FromArgb(70,  140, 220)
$COL_GRID_ALT = [System.Drawing.Color]::FromArgb(35,  35,  35 )
$COL_GRID_SEL = [System.Drawing.Color]::FromArgb(50,  80,  130)

$FONT_UI   = New-Object System.Drawing.Font('Segoe UI', 9)
$FONT_MONO = New-Object System.Drawing.Font('Consolas', 9)
$FONT_HEAD = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$FONT_BIG  = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)

# ---------------------------------------------------------------------------
# Helper: legge i nodi da SoftwareConfig.ps1
# ---------------------------------------------------------------------------
function Get-NodesFromConfig {
    param ([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) { return @() }

    $content = Get-Content -Path $ConfigPath -Raw -Encoding Default
    if ($content -match '\$Nodes\s*=\s*@\(([^)]+)\)') {
        $block  = $Matches[1]
        $nodes  = [regex]::Matches($block, "'([^']+)'") |
                  ForEach-Object { $_.Groups[1].Value }
        return $nodes
    }
    return @()
}

# ---------------------------------------------------------------------------
# Helper: controlla stato DSC di un nodo (usato nel BackgroundWorker)
# ---------------------------------------------------------------------------
function Invoke-DscCheck {
    param ([string]$Node)

    $result = @{
        Node        = $Node
        Stato       = 'Sconosciuto'
        DataOra     = ''
        RisorseKO   = 0
        Errore      = ''
        Tag         = 'unknown'
    }

    try {
        $sessOpt = New-CimSessionOption -Protocol Dcom
        $sess    = New-CimSession -ComputerName $Node `
                                  -SessionOption $sessOpt `
                                  -OperationTimeoutSec 15 `
                                  -ErrorAction Stop

        $statuses = Get-DscConfigurationStatus -CimSession $sess -ErrorAction Stop
        Remove-CimSession $sess -ErrorAction SilentlyContinue

        if (-not $statuses) {
            $result.Stato  = 'Nessun dato'
            $result.Tag    = 'unknown'
            return $result
        }

        $last = $statuses | Sort-Object StartDate -Descending | Select-Object -First 1

        $result.DataOra   = if ($last.StartDate) { $last.StartDate.ToString('dd/MM/yyyy HH:mm:ss') } else { '' }
        $result.RisorseKO = @($last.ResourcesNotInDesiredState).Count

        switch ($last.Status) {
            'Success' {
                $result.Stato = 'OK'
                $result.Tag   = 'ok'
            }
            'Failure' {
                $result.Stato = 'ERRORE'
                $result.Tag   = 'fail'
            }
            default {
                $result.Stato = $last.Status
                $result.Tag   = 'unknown'
            }
        }
    }
    catch {
        $result.Stato  = 'Non raggiungibile'
        $result.Errore = $_.Exception.Message
        $result.Tag    = 'unreachable'
    }

    return $result
}

# ---------------------------------------------------------------------------
# Finestra dettaglio errori (Livello 2)
# ---------------------------------------------------------------------------
function Show-DetailForm {
    param ([string]$Node)

    $frmD = New-Object System.Windows.Forms.Form
    $frmD.Text            = "Dettaglio errori DSC - $Node"
    $frmD.Size            = New-Object System.Drawing.Size(820, 520)
    $frmD.StartPosition   = 'CenterParent'
    $frmD.BackColor       = $COL_BG
    $frmD.ForeColor       = $COL_TEXT
    $frmD.Font            = $FONT_UI
    $frmD.FormBorderStyle = 'FixedDialog'
    $frmD.MaximizeBox     = $false

    # Titolo
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "Risorse non conformi su: $Node"
    $lblTitle.Font      = $FONT_BIG
    $lblTitle.ForeColor = $COL_FAIL
    $lblTitle.Location  = New-Object System.Drawing.Point(15, 12)
    $lblTitle.Size      = New-Object System.Drawing.Size(780, 28)
    $frmD.Controls.Add($lblTitle)

    # Pannello stato
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text      = 'Recupero dati in corso...'
    $lblStatus.ForeColor = $COL_TEXT_DIM
    $lblStatus.Location  = New-Object System.Drawing.Point(15, 42)
    $lblStatus.Size      = New-Object System.Drawing.Size(780, 18)
    $frmD.Controls.Add($lblStatus)

    # RichTextBox risultati
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Location    = New-Object System.Drawing.Point(15, 65)
    $rtb.Size        = New-Object System.Drawing.Size(778, 360)
    $rtb.BackColor   = $COL_PANEL
    $rtb.ForeColor   = $COL_TEXT
    $rtb.Font        = $FONT_MONO
    $rtb.ReadOnly    = $true
    $rtb.BorderStyle = 'None'
    $rtb.ScrollBars  = 'Vertical'
    $rtb.Text        = ''
    $frmD.Controls.Add($rtb)

    # Bottone chiudi
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text      = 'Chiudi'
    $btnClose.Size      = New-Object System.Drawing.Size(100, 30)
    $btnClose.Location  = New-Object System.Drawing.Point(695, 440)
    $btnClose.BackColor = $COL_BORDER
    $btnClose.ForeColor = $COL_TEXT
    $btnClose.FlatStyle = 'Flat'
    $btnClose.FlatAppearance.BorderColor = $COL_BORDER
    $btnClose.Add_Click({ $frmD.Close() })
    $frmD.Controls.Add($btnClose)

    $frmD.Show()
    [System.Windows.Forms.Application]::DoEvents()

    # Recupera dati
    try {
        $sessOpt  = New-CimSessionOption -Protocol Dcom
        $sess     = New-CimSession -ComputerName $Node `
                                   -SessionOption $sessOpt `
                                   -OperationTimeoutSec 15 `
                                   -ErrorAction Stop

        $statuses = Get-DscConfigurationStatus -CimSession $sess -ErrorAction Stop
        Remove-CimSession $sess -ErrorAction SilentlyContinue

        $last = $statuses | Sort-Object StartDate -Descending | Select-Object -First 1
        $ko   = @($last.ResourcesNotInDesiredState)

        if ($ko.Count -eq 0) {
            $lblStatus.Text      = 'Nessuna risorsa in errore trovata.'
            $lblStatus.ForeColor = $COL_OK
            $rtb.Text = 'Nessuna risorsa segnalata come non conforme.'
            return
        }

        $lblStatus.Text      = "$($ko.Count) risorsa/e non conforme/i rilevata/e - Ultimo ciclo: $($last.StartDate.ToString('dd/MM/yyyy HH:mm:ss'))"
        $lblStatus.ForeColor = $COL_WARN

        $sb = New-Object System.Text.StringBuilder

        for ($i = 0; $i -lt $ko.Count; $i++) {
            $res = $ko[$i]
            $null = $sb.AppendLine("================================================================")
            $null = $sb.AppendLine("RISORSA $($i + 1) di $($ko.Count)")
            $null = $sb.AppendLine("================================================================")
            $null = $sb.AppendLine("ResourceId      : $($res.ResourceId)")
            $null = $sb.AppendLine("SourceInfo      : $($res.SourceInfo)")
            $null = $sb.AppendLine("ModuleName      : $($res.ModuleName)")
            $null = $sb.AppendLine("DurationSec     : $($res.DurationInSeconds)")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("ERRORE:")

            if ($res.Error) {
                foreach ($line in ($res.Error -split "`n")) {
                    $null = $sb.AppendLine("  $line")
                }
            } else {
                $null = $sb.AppendLine("  (nessun messaggio di errore disponibile)")
            }
            $null = $sb.AppendLine("")
        }

        $rtb.Text = $sb.ToString()
    }
    catch {
        $lblStatus.Text      = "Errore durante il recupero: $_"
        $lblStatus.ForeColor = $COL_FAIL
        $rtb.Text = $_.Exception.Message
    }
}

# ===========================================================================
# FORM PRINCIPALE
# ===========================================================================
$frmMain = New-Object System.Windows.Forms.Form
$frmMain.Text            = 'DSC Monitor - Stato Nodi'
$frmMain.Size            = New-Object System.Drawing.Size(960, 640)
$frmMain.MinimumSize     = New-Object System.Drawing.Size(800, 500)
$frmMain.StartPosition   = 'CenterScreen'
$frmMain.BackColor       = $COL_BG
$frmMain.ForeColor       = $COL_TEXT
$frmMain.Font            = $FONT_UI

# ---------------------------------------------------------------------------
# Panel top - selezione file config
# ---------------------------------------------------------------------------
$pnlTop = New-Object System.Windows.Forms.Panel
$pnlTop.Height    = 58
$pnlTop.Dock      = 'Top'
$pnlTop.BackColor = $COL_PANEL
$frmMain.Controls.Add($pnlTop)

$lblConfig = New-Object System.Windows.Forms.Label
$lblConfig.Text      = 'SoftwareConfig.ps1:'
$lblConfig.Location  = New-Object System.Drawing.Point(12, 18)
$lblConfig.AutoSize  = $true
$lblConfig.ForeColor = $COL_TEXT_DIM
$pnlTop.Controls.Add($lblConfig)

$txtConfig = New-Object System.Windows.Forms.TextBox
$txtConfig.Location  = New-Object System.Drawing.Point(138, 14)
$txtConfig.Size      = New-Object System.Drawing.Size(580, 24)
$txtConfig.BackColor = $COL_BG
$txtConfig.ForeColor = $COL_TEXT
$txtConfig.BorderStyle = 'FixedSingle'
# Precompila con path relativo se esiste
$defaultPath = Join-Path $PSScriptRoot 'SoftwareConfig.ps1'
if (Test-Path $defaultPath) { $txtConfig.Text = $defaultPath }
$pnlTop.Controls.Add($txtConfig)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text      = 'Sfoglia...'
$btnBrowse.Location  = New-Object System.Drawing.Point(726, 13)
$btnBrowse.Size      = New-Object System.Drawing.Size(80, 26)
$btnBrowse.BackColor = $COL_BORDER
$btnBrowse.ForeColor = $COL_TEXT
$btnBrowse.FlatStyle = 'Flat'
$btnBrowse.FlatAppearance.BorderColor = $COL_BORDER
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Seleziona SoftwareConfig.ps1'
    $dlg.Filter = 'Script PowerShell (*.ps1)|*.ps1'
    if ($dlg.ShowDialog() -eq 'OK') {
        $txtConfig.Text = $dlg.FileName
    }
})
$pnlTop.Controls.Add($btnBrowse)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text      = 'Aggiorna Tutti'
$btnRefresh.Location  = New-Object System.Drawing.Point(814, 13)
$btnRefresh.Size      = New-Object System.Drawing.Size(118, 26)
$btnRefresh.BackColor = $COL_BTN
$btnRefresh.ForeColor = [System.Drawing.Color]::White
$btnRefresh.FlatStyle = 'Flat'
$btnRefresh.FlatAppearance.BorderSize  = 0
$btnRefresh.Font = $FONT_HEAD
$pnlTop.Controls.Add($btnRefresh)

# ---------------------------------------------------------------------------
# Status bar in fondo
# ---------------------------------------------------------------------------
$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Height    = 28
$pnlStatus.Dock      = 'Bottom'
$pnlStatus.BackColor = $COL_PANEL

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = 'Pronto. Seleziona il file di configurazione e premi Aggiorna Tutti.'
$lblStatus.Dock      = 'Fill'
$lblStatus.TextAlign = 'MiddleLeft'
$lblStatus.ForeColor = $COL_TEXT_DIM
$lblStatus.Padding   = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$pnlStatus.Controls.Add($lblStatus)
$frmMain.Controls.Add($pnlStatus)

# ---------------------------------------------------------------------------
# DataGridView
# ---------------------------------------------------------------------------
$dgv = New-Object System.Windows.Forms.DataGridView
$dgv.Dock                         = 'Fill'
$dgv.BackgroundColor              = $COL_BG
$dgv.GridColor                    = $COL_BORDER
$dgv.BorderStyle                  = 'None'
$dgv.RowHeadersVisible            = $false
$dgv.AllowUserToAddRows           = $false
$dgv.AllowUserToDeleteRows        = $false
$dgv.AllowUserToResizeRows        = $false
$dgv.ReadOnly                     = $true
$dgv.SelectionMode                = 'FullRowSelect'
$dgv.MultiSelect                  = $false
$dgv.AutoSizeRowsMode             = 'AllCells'
$dgv.ColumnHeadersHeightSizeMode  = 'DisableResizing'
$dgv.ColumnHeadersHeight          = 34
$dgv.RowTemplate.Height           = 36
$dgv.Font                         = $FONT_UI
$dgv.DefaultCellStyle.BackColor   = $COL_BG
$dgv.DefaultCellStyle.ForeColor   = $COL_TEXT
$dgv.DefaultCellStyle.SelectionBackColor = $COL_GRID_SEL
$dgv.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
$dgv.DefaultCellStyle.Padding     = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$dgv.AlternatingRowsDefaultCellStyle.BackColor = $COL_GRID_ALT
$dgv.ColumnHeadersDefaultCellStyle.BackColor   = $COL_PANEL
$dgv.ColumnHeadersDefaultCellStyle.ForeColor   = $COL_TEXT
$dgv.ColumnHeadersDefaultCellStyle.Font        = $FONT_HEAD
$dgv.ColumnHeadersDefaultCellStyle.Padding     = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$dgv.EnableHeadersVisualStyles    = $false

# Colonne
$colNodo = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colNodo.HeaderText = 'Nodo'
$colNodo.Name       = 'Nodo'
$colNodo.Width      = 240
$colNodo.ReadOnly   = $true
$dgv.Columns.Add($colNodo) | Out-Null

$colStato = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colStato.HeaderText = 'Stato'
$colStato.Name       = 'Stato'
$colStato.Width      = 160
$colStato.ReadOnly   = $true
$colStato.DefaultCellStyle.Alignment = 'MiddleCenter'
$colStato.HeaderCell.Style.Alignment = 'MiddleCenter'
$dgv.Columns.Add($colStato) | Out-Null

$colData = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colData.HeaderText = 'Ultimo Controllo DSC'
$colData.Name       = 'DataOra'
$colData.Width      = 180
$colData.ReadOnly   = $true
$colData.DefaultCellStyle.Alignment = 'MiddleCenter'
$colData.HeaderCell.Style.Alignment = 'MiddleCenter'
$dgv.Columns.Add($colData) | Out-Null

$colKO = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colKO.HeaderText = 'Risorse KO'
$colKO.Name       = 'RisorseKO'
$colKO.Width      = 110
$colKO.ReadOnly   = $true
$colKO.DefaultCellStyle.Alignment = 'MiddleCenter'
$colKO.HeaderCell.Style.Alignment = 'MiddleCenter'
$dgv.Columns.Add($colKO) | Out-Null

$colErr = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colErr.HeaderText      = 'Messaggio'
$colErr.Name            = 'Errore'
$colErr.AutoSizeMode    = 'Fill'
$colErr.ReadOnly        = $true
$dgv.Columns.Add($colErr) | Out-Null

$colBtn = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colBtn.HeaderText  = 'Azione'
$colBtn.Name        = 'Azione'
$colBtn.Width       = 110
$colBtn.Text        = 'Dettaglio'
$colBtn.UseColumnTextForButtonValue = $true
$colBtn.DefaultCellStyle.Alignment  = 'MiddleCenter'
$colBtn.DefaultCellStyle.BackColor  = $COL_BORDER
$colBtn.DefaultCellStyle.ForeColor  = $COL_TEXT
$colBtn.HeaderCell.Style.Alignment  = 'MiddleCenter'
$dgv.Columns.Add($colBtn) | Out-Null

$frmMain.Controls.Add($dgv)
# Porta il DataGridView sotto il pannello top
$frmMain.Controls.SetChildIndex($pnlTop, 0)

# ---------------------------------------------------------------------------
# CellFormatting - colora la cella Stato in base al tag
# ---------------------------------------------------------------------------
$dgv.Add_CellFormatting({
    param($s, $e)
    if ($e.ColumnIndex -eq $dgv.Columns['Stato'].Index -and $e.RowIndex -ge 0) {
        $tag = $dgv.Rows[$e.RowIndex].Tag
        switch ($tag) {
            'ok'          { $e.CellStyle.ForeColor = $COL_OK;   $e.CellStyle.Font = $FONT_HEAD }
            'fail'        { $e.CellStyle.ForeColor = $COL_FAIL; $e.CellStyle.Font = $FONT_HEAD }
            'unreachable' { $e.CellStyle.ForeColor = $COL_WARN; $e.CellStyle.Font = $FONT_HEAD }
            'checking'    { $e.CellStyle.ForeColor = $COL_TEXT_DIM }
        }
    }
    # Disabilita visivamente il bottone se non in errore
    if ($e.ColumnIndex -eq $dgv.Columns['Azione'].Index -and $e.RowIndex -ge 0) {
        $tag = $dgv.Rows[$e.RowIndex].Tag
        if ($tag -ne 'fail') {
            $e.CellStyle.BackColor = $COL_BORDER
            $e.CellStyle.ForeColor = $COL_TEXT_DIM
        } else {
            $e.CellStyle.BackColor = $COL_FAIL
            $e.CellStyle.ForeColor = [System.Drawing.Color]::White
        }
    }
})

# ---------------------------------------------------------------------------
# CellClick - gestisce il bottone Dettaglio
# ---------------------------------------------------------------------------
$dgv.Add_CellClick({
    param($s, $e)
    if ($e.RowIndex -lt 0) { return }
    if ($e.ColumnIndex -ne $dgv.Columns['Azione'].Index) { return }

    $row = $dgv.Rows[$e.RowIndex]
    if ($row.Tag -ne 'fail') { return }

    $nodeName = $row.Cells['Nodo'].Value
    Show-DetailForm -Node $nodeName
})

# ---------------------------------------------------------------------------
# Bottone Aggiorna - carica nodi e avvia i check
# ---------------------------------------------------------------------------
$btnRefresh.Add_Click({
    $configPath = $txtConfig.Text.Trim()

    if (-not (Test-Path $configPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "File non trovato:`n$configPath`n`nSeleziona il file SoftwareConfig.ps1 corretto.",
            'File non trovato',
            'OK', 'Warning') | Out-Null
        return
    }

    $nodes = Get-NodesFromConfig -ConfigPath $configPath

    if ($nodes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Nessun nodo trovato in:`n$configPath`n`nVerifica che l array `$Nodes sia definito correttamente.",
            'Nessun nodo',
            'OK', 'Warning') | Out-Null
        return
    }

    # Popola la griglia con i nodi e stato "In controllo..."
    $dgv.Rows.Clear()

    foreach ($node in $nodes) {
        $idx = $dgv.Rows.Add($node, 'In controllo...', '', '', '', '')
        $dgv.Rows[$idx].Tag = 'checking'
    }

    $btnRefresh.Enabled = $false
    $lblStatus.Text     = "Controllo $($nodes.Count) nodi in corso..."
    [System.Windows.Forms.Application]::DoEvents()

    # Controlla ogni nodo in sequenza
    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $node = $nodes[$i]
        $row  = $dgv.Rows[$i]

        $lblStatus.Text = "[$($i + 1)/$($nodes.Count)] Controllo: $node ..."
        [System.Windows.Forms.Application]::DoEvents()

        $res = Invoke-DscCheck -Node $node

        $row.Cells['Nodo'].Value      = $res.Node
        $row.Cells['Stato'].Value     = $res.Stato
        $row.Cells['DataOra'].Value   = $res.DataOra
        $row.Cells['RisorseKO'].Value = if ($res.RisorseKO -gt 0) { $res.RisorseKO } else { '' }
        $row.Cells['Errore'].Value    = $res.Errore
        $row.Tag                      = $res.Tag

        $dgv.InvalidateRow($i)
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Riepilogo finale
    $ok          = @($dgv.Rows | Where-Object { $_.Tag -eq 'ok'          }).Count
    $fail        = @($dgv.Rows | Where-Object { $_.Tag -eq 'fail'        }).Count
    $unreachable = @($dgv.Rows | Where-Object { $_.Tag -eq 'unreachable' }).Count

    $lblStatus.Text = "Completato: $ok OK  |  $fail Errori  |  $unreachable Non raggiungibili  -  Aggiornato: $(Get-Date -Format 'HH:mm:ss')"
    $btnRefresh.Enabled = $true
})

# ---------------------------------------------------------------------------
# Avvio
# ---------------------------------------------------------------------------
[System.Windows.Forms.Application]::Run($frmMain)
