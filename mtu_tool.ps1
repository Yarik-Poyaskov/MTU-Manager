Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "MTU Manager"
$form.Size = "460,620"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.TopMost = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = "1. Выберите адаптер (имя | текущий MTU):"; $label.Location = "10,10"; $label.AutoSize = $true
$form.Controls.Add($label)

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = "10,35"; $listBox.Size = "420,100"
$listBox.Font = New-Object System.Drawing.Font("Courier New", 9)
$form.Controls.Add($listBox)

$labelMtu = New-Object System.Windows.Forms.Label
$labelMtu.Text = "2. Новое значение MTU:"; $labelMtu.Location = "10,148"; $labelMtu.AutoSize = $true
$form.Controls.Add($labelMtu)

$inputMtu = New-Object System.Windows.Forms.TextBox
$inputMtu.Location = "10,168"; $inputMtu.Size = "100,22"; $inputMtu.Text = "1400"
$form.Controls.Add($inputMtu)

# --- ПОЛЕ ДЛЯ ХОСТА ---
$labelHost = New-Object System.Windows.Forms.Label
$labelHost.Text = "3. Хост для проверки MTU (ping):"; $labelHost.Location = "10,200"; $labelHost.AutoSize = $true
$form.Controls.Add($labelHost)

$inputHost = New-Object System.Windows.Forms.TextBox
$inputHost.Location = "10,220"; $inputHost.Size = "200,22"; $inputHost.Text = "8.8.8.8"
$form.Controls.Add($inputHost)

$labelHostHint = New-Object System.Windows.Forms.Label
$labelHostHint.Text = "(по умолчанию: 8.8.8.8)"; $labelHostHint.Location = "220,223"; $labelHostHint.AutoSize = $true
$labelHostHint.ForeColor = "Gray"
$form.Controls.Add($labelHostHint)
# -----------------------

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = "10,252"; $statusLabel.Size = "420,18"
$statusLabel.ForeColor = "DarkBlue"; $statusLabel.Text = ""
$form.Controls.Add($statusLabel)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "ПРИМЕНИТЬ MTU"
$btnApply.Location = "10,276"; $btnApply.Size = "420,32"
$btnApply.BackColor = "LightGreen"
$form.Controls.Add($btnApply)

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text = "Тест Ping (проверить текущий MTU)"
$btnTest.Location = "10,314"; $btnTest.Size = "420,32"
$form.Controls.Add($btnTest)

$btnFind = New-Object System.Windows.Forms.Button
$btnFind.Text = "🔍 Найти максимальный MTU (авто)"
$btnFind.Location = "10,352"; $btnFind.Size = "420,32"
$btnFind.BackColor = "LightBlue"
$form.Controls.Add($btnFind)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = "10,390"; $progressBar.Size = "420,14"
$progressBar.Minimum = 0; $progressBar.Maximum = 100
$progressBar.Visible = $false
$form.Controls.Add($progressBar)

$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Text = "Лог поиска MTU:"; $labelLog.Location = "10,412"; $labelLog.AutoSize = $true
$labelLog.Visible = $false
$form.Controls.Add($labelLog)

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = "10,430"; $logBox.Size = "420,140"
$logBox.Font = New-Object System.Drawing.Font("Courier New", 8)
$logBox.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
$logBox.ForeColor = [System.Drawing.Color]::LightGreen
$logBox.ReadOnly = $true
$logBox.Visible = $false
$form.Controls.Add($logBox)

function Write-Log {
    param([string]$text, [string]$color = "LightGreen")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.SelectionLength = 0
    switch ($color) {
        "Yellow" { $logBox.SelectionColor = [System.Drawing.Color]::Yellow }
        "Red"    { $logBox.SelectionColor = [System.Drawing.Color]::Tomato }
        "Cyan"   { $logBox.SelectionColor = [System.Drawing.Color]::Cyan }
        "Gray"   { $logBox.SelectionColor = [System.Drawing.Color]::Gray }
        default  { $logBox.SelectionColor = [System.Drawing.Color]::LightGreen }
    }
    $logBox.AppendText("$text`n")
    $logBox.ScrollToCaret()
}

function Get-TargetHost {
    $h = $inputHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($h)) { return "8.8.8.8" }
    return $h
}

$script:adapterNames = @()
$script:currentJob   = $null
$script:currentTimer = $null

function Refresh-Adapters {
    $listBox.Items.Clear()
    $script:adapterNames = @()
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $realName = $_.Name
        $script:adapterNames += $realName
        try {
            $mtuVal = (Get-NetIPInterface -InterfaceAlias $realName -AddressFamily IPv4 -ErrorAction Stop).NlMtu
        } catch { $mtuVal = "?" }
        $line = "{0,-28}  MTU: {1}" -f $realName, $mtuVal
        [void]$listBox.Items.Add($line)
    }
}
Refresh-Adapters

function Get-SelectedAdapterName {
    $idx = $listBox.SelectedIndex
    if ($idx -lt 0) { return $null }
    return $script:adapterNames[$idx]
}

function Set-ButtonsEnabled($state) {
    $btnApply.Enabled = $state
    $btnTest.Enabled  = $state
    $btnFind.Enabled  = $state
}

# --- ПРИМЕНИТЬ ---
$btnApply.Add_Click({
    $sel = Get-SelectedAdapterName
    $mtu = $inputMtu.Text.Trim()
    if (-not $sel) { $statusLabel.ForeColor="Red"; $statusLabel.Text="⚠ Выберите адаптер!"; return }
    if ($mtu -notmatch '^\d+$' -or [int]$mtu -lt 576 -or [int]$mtu -gt 9000) {
        $statusLabel.ForeColor="Red"; $statusLabel.Text="⚠ MTU должен быть числом 576–9000"; return
    }
    Set-ButtonsEnabled $false
    $statusLabel.ForeColor = "DarkBlue"
    $statusLabel.Text = "⏳ Применяю MTU=$mtu на '$sel'..."
    $form.Refresh()

    $script:currentJob = Start-Job -ScriptBlock {
        param([string]$adapterName, [string]$mtuValue)
        $log = @()
        $found = Get-NetAdapter | Where-Object { $_.Name -eq $adapterName }
        if (-not $found) {
            $all = (Get-NetAdapter | Select-Object -ExpandProperty Name) -join ", "
            return "НЕ НАЙДЕН. Доступные: $all"
        }
        $out = & netsh interface ipv4 set subinterface "$adapterName" mtu=$mtuValue store=persistent 2>&1
        $log += "netsh: $($out -join ' ')"
        try { Disable-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction Stop; $log += "Disable: OK" }
        catch { $log += "Disable ERROR: $($_.Exception.Message)" }
        Start-Sleep -Seconds 3
        try { Enable-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction Stop; $log += "Enable: OK" }
        catch { $log += "Enable ERROR: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
        return ($log -join " | ")
    } -ArgumentList $sel, $mtu

    $script:currentTimer = New-Object System.Windows.Forms.Timer
    $script:currentTimer.Interval = 500
    $script:currentTimer.Add_Tick({
        $job = $script:currentJob
        if ($null -eq $job) { return }
        if ($job.State -in @("Completed","Failed","Stopped")) {
            $script:currentTimer.Stop(); $script:currentTimer.Dispose(); $script:currentTimer = $null
            $output = Receive-Job -Job $job
            Remove-Job -Job $job -Force; $script:currentJob = $null
            if ($output -match "ERROR|НЕ НАЙДЕН") { $statusLabel.ForeColor="Red"; $statusLabel.Text="❌ $output" }
            else { $statusLabel.ForeColor="DarkGreen"; $statusLabel.Text="✅ $output" }
            Set-ButtonsEnabled $true
            Refresh-Adapters
        }
    })
    $script:currentTimer.Start()
})

# --- ТЕСТ ТЕКУЩЕГО MTU ---
$btnTest.Add_Click({
    $mtu     = [int]$inputMtu.Text.Trim()
    $bufSize = $mtu - 28
    $target  = Get-TargetHost
    $statusLabel.ForeColor = "DarkBlue"
    $statusLabel.Text = "⏳ Пингую $target с буфером $bufSize (MTU $mtu)..."
    $form.Refresh()
    if (Test-Connection -ComputerName $target -Count 2 -BufferSize $bufSize -Quiet) {
        $statusLabel.ForeColor = "DarkGreen"; $statusLabel.Text = "✅ Пакеты MTU=$mtu проходят! (хост: $target)"
    } else {
        $statusLabel.ForeColor = "Red"; $statusLabel.Text = "❌ Пакеты MTU=$mtu НЕ проходят (хост: $target)"
    }
})

# --- НАЙТИ МАКСИМАЛЬНЫЙ MTU ---
$btnFind.Add_Click({
    $target = Get-TargetHost
    Set-ButtonsEnabled $false
    $progressBar.Visible = $true
    $progressBar.Value   = 0
    $labelLog.Visible    = $true
    $logBox.Visible      = $true
    $logBox.Clear()
    $statusLabel.ForeColor = "DarkBlue"
    $statusLabel.Text = "⏳ Ищу максимальный MTU..."
    Write-Log "=== Старт поиска максимального MTU ===" "Cyan"
    Write-Log "Диапазон: 576 – 1500, цель: $target" "Gray"
    Write-Log "Флаг DF (Don't Fragment) = включён" "Gray"
    Write-Log "─────────────────────────────────────" "Gray"
    $form.Refresh()

    $script:currentJob = Start-Job -ScriptBlock {
        param([string]$targetHost)

        function Test-MTUSize([int]$mtu) {
            $buf = $mtu - 28
            if ($buf -lt 1) { return $false }
            $result = & ping.exe -n 2 -f -l $buf $targetHost 2>&1
            $failed = $result | Where-Object { $_ -match "fragment|timed out|unreachable|недост|фрагм|истекло|100%" }
            $ok     = $result | Where-Object { $_ -match "TTL=|bytes=" }
            return ($failed.Count -eq 0 -and $ok.Count -gt 0)
        }

        Write-Output "LOG:CYAN:Проверка верхней границы MTU=1500..."
        if (Test-MTUSize 1500) {
            Write-Output "LOG:GREEN:MTU=1500 ✅ — максимум достигнут сразу"
            Write-Output "RESULT:1500"
            return
        }
        Write-Output "LOG:YELLOW:MTU=1500 ❌ — начинаю бинарный поиск"

        Write-Output "LOG:CYAN:Проверка нижней границы MTU=576..."
        if (-not (Test-MTUSize 576)) {
            Write-Output "LOG:RED:MTU=576 ❌ — нет ответа от $targetHost"
            Write-Output "RESULT:NOPING"
            return
        }
        Write-Output "LOG:GREEN:MTU=576 ✅ — связь есть, ищу максимум"
        Write-Output "LOG:GRAY:─────────────────────────────────────"

        $low  = 576
        $high = 1499
        $best = 576
        $step = 0

        while ($low -le $high) {
            $mid      = [int](($low + $high) / 2)
            $step++
            $progress = [int](100 - (($high - $low) / (1500 - 576)) * 100)
            Write-Output "PROGRESS:$progress"
            Write-Output "LOG:CYAN:Шаг $step — тестирую MTU=$mid (buf=$($mid-28))..."

            if (Test-MTUSize $mid) {
                $best = $mid
                $low  = $mid + 1
                Write-Output "LOG:GREEN:  MTU=$mid ✅  → ищу выше  [диапазон: $($mid+1)..$high]"
            } else {
                $high = $mid - 1
                Write-Output "LOG:YELLOW:  MTU=$mid ❌  → ищу ниже  [диапазон: $low..$($mid-1)]"
            }
        }

        Write-Output "LOG:GRAY:─────────────────────────────────────"
        Write-Output "LOG:GREEN:Готово! Максимальный MTU = $best"
        Write-Output "RESULT:$best"
    } -ArgumentList $target

    $script:currentTimer = New-Object System.Windows.Forms.Timer
    $script:currentTimer.Interval = 300

    $script:currentTimer.Add_Tick({
        $job = $script:currentJob
        if ($null -eq $job) { return }

        $lines = Receive-Job -Job $job -Keep
        foreach ($line in $lines) {
            if ($line -match "^PROGRESS:(\d+)$") {
                $progressBar.Value = [Math]::Min([int]$Matches[1], 100)
            }
            elseif ($line -match "^LOG:(GREEN|YELLOW|RED|CYAN|GRAY):(.+)$") {
                $col  = $Matches[1]
                $text = $Matches[2]
                if (-not $logBox.Text.Contains($text)) {
                    Write-Log $text $col
                }
            }
        }

        if ($job.State -in @("Completed","Failed","Stopped")) {
            $script:currentTimer.Stop(); $script:currentTimer.Dispose(); $script:currentTimer = $null

            $allLines = Receive-Job -Job $job
            Remove-Job -Job $job -Force; $script:currentJob = $null

            $progressBar.Value = 100

            $resultLine = $allLines | Where-Object { $_ -match "^RESULT:" } | Select-Object -Last 1

            if ($resultLine -match "RESULT:NOPING") {
                $target2 = $inputHost.Text.Trim(); if ([string]::IsNullOrWhiteSpace($target2)) { $target2 = "8.8.8.8" }
                $statusLabel.ForeColor = "Red"
                $statusLabel.Text = "❌ Нет ответа от $target2 — проверь адрес или соединение"
            } elseif ($resultLine -match "RESULT:(\d+)") {
                $found = [int]$Matches[1]
                $inputMtu.Text = "$found"
                $statusLabel.ForeColor = "DarkGreen"
                $statusLabel.Text = "✅ Максимальный MTU: $found  —  подставлен в поле выше"
            } else {
                $statusLabel.ForeColor = "Red"
                $statusLabel.Text = "❌ Не удалось определить MTU"
            }

            Set-ButtonsEnabled $true
        }
    })
    $script:currentTimer.Start()
})

$form.Add_FormClosing({
    if ($script:currentTimer) { $script:currentTimer.Stop(); $script:currentTimer.Dispose() }
    if ($script:currentJob)   { Remove-Job -Job $script:currentJob -Force }
})

[void]$form.ShowDialog()