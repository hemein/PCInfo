Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# Функция для получения типа памяти по коду SMBIOS
function Get-MemoryType {
    param (
        [int]$SMBIOSMemoryType
    )
    $memoryTypes = @{
        20 = "DDR2"
        24 = "DDR3"
        26 = "DDR4"
        34 = "DDR5"
    }
    if ($memoryTypes.ContainsKey($SMBIOSMemoryType)) {
        return $memoryTypes[$SMBIOSMemoryType]
    } else {
        return "Неизвестный тип ($SMBIOSMemoryType)"
    }
}

# Функция для создания основного окна
function Show-MainForm {
    param (
        [System.Management.Automation.PSCredential]$Credential
    )

    # Создаем форму
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Информация о ПК"
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.StartPosition = "CenterScreen"

    # Задаем фиксированный размер окна
    $form.Size = New-Object System.Drawing.Size(650, 520)
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false

    # Поле для ввода имени компьютера
$labelHostname = New-Object System.Windows.Forms.Label
$labelHostname.Text = "Введите имя компьютера или IP:"
$labelHostname.AutoSize = $false
$labelHostname.Size = New-Object System.Drawing.Size(300,20)
$labelHostname.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
# Центрируем метку по ширине формы (650)
$labelHostname.Location = New-Object System.Drawing.Point(([int]((650 - $labelHostname.Width)/2)),20)

$textBoxHostname = New-Object System.Windows.Forms.TextBox
$textBoxHostname.Size = New-Object System.Drawing.Size(200,20)
# Располагаем текстовое поле под меткой, тоже по центру
$textBoxHostname.Location = New-Object System.Drawing.Point(([int]((650 - $textBoxHostname.Width)/2)),45)

    # Кнопка "Отправить"
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Отправить"
    $button.Size = New-Object System.Drawing.Size(100, 30)
    $button.Location = New-Object System.Drawing.Point(275,75)

    # Добавляем элементы на форму
    [void]$form.Controls.Add($labelHostname)
    [void]$form.Controls.Add($textBoxHostname)
    [void]$form.Controls.Add($button)

    # Панель для скроллинга таблицы (поля ввода и кнопка остаются статичными)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(0, 130)
    $panel.Size = New-Object System.Drawing.Size(650, 380)
    $panel.AutoScroll = $true

    # Таблица с динамической компоновкой
    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.ColumnCount = 2
    $table.RowCount = 0
    $table.AutoSize = $true
    $table.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $table.Dock = [System.Windows.Forms.DockStyle]::Top
    $table.Padding = New-Object System.Windows.Forms.Padding(10)
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 35)))
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 75)))

    $valueLabelMap = @{}
    $fields = @("Имя ПК", "Версия ОС", "Процессор", "Оперативная память", "Установленные диски", "Видеокарта", "ПК без перезагрузки")
    foreach ($field in $fields) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = "${field}:"
        $label.AutoSize = $false
        $label.Dock = [System.Windows.Forms.DockStyle]::Fill
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $valueLabel = New-Object System.Windows.Forms.Label
        $valueLabel.Text = ""
        $valueLabel.AutoSize = $true
        $valueLabel.MaximumSize = New-Object System.Drawing.Size(500, 0)  # Перенос строк
        [void]($rowIdx = $table.RowCount)

        $table.Controls.Add($label, 0, $rowIdx)
        $table.Controls.Add($valueLabel, 1, $rowIdx)
        $null = $table.RowCount++
        $null = $valueLabelMap[$field] = $valueLabel
    }
    [void]$panel.Controls.Add($table)
    [void]$form.Controls.Add($panel)

    # Устанавливаем кнопку "Отправить" как AcceptButton
    $form.AcceptButton = $button

    # Действие при нажатии кнопки
    $button.Add_Click({
        $computerName = $textBoxHostname.Text
        if (-not [string]::IsNullOrWhiteSpace($computerName)) {
            $cimSession = $null
            try {
                # Получаем информацию о системе (CIM, совместимо с PowerShell 5.1 и 7+)
                $sessionOption = New-CimSessionOption -Protocol Dcom
                $cimSession = New-CimSession -ComputerName $computerName -Credential $Credential -SessionOption $sessionOption -ErrorAction Stop

                $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $cimSession -ErrorAction Stop
                $cpuInfo = Get-CimInstance -ClassName Win32_Processor -CimSession $cimSession -ErrorAction Stop
                $memoryInfo = Get-CimInstance -ClassName Win32_PhysicalMemory -CimSession $cimSession -ErrorAction Stop
                $diskInfo = Get-CimInstance -ClassName Win32_DiskDrive -CimSession $cimSession -ErrorAction Stop
                $videoInfo = Get-CimInstance -ClassName Win32_VideoController -CimSession $cimSession -ErrorAction Stop

                # Время без перезагрузки (LastBootUpTime уже приходит как DateTime через CIM)
                $uptime = (Get-Date) - $osInfo.LastBootUpTime

                # Обновляем метки
                $null = $valueLabelMap["Имя ПК"].Text = $osInfo.CSName
                $null = $valueLabelMap["Версия ОС"].Text = $osInfo.Caption
                $null = $valueLabelMap["Процессор"].Text = $cpuInfo.Name
                $null = $valueLabelMap["Оперативная память"].Text = ($memoryInfo | ForEach-Object { "$([math]::Round($_.Capacity / 1GB, 1)) GB $(Get-MemoryType $_.SMBIOSMemoryType)" }) -join ", "
                $null = $valueLabelMap["Установленные диски"].Text = ($diskInfo | ForEach-Object { "$($_.Model) ($([math]::Round($_.Size / 1GB, 1)) GB)" }) -join ", "

                # Проверяем наличие внешней видеокарты (PCI)
                $externalVideo = $videoInfo | Where-Object { $_.PNPDeviceID -like "*PCI*" }
                if ($externalVideo) {
                    $null = $valueLabelMap["Видеокарта"].Text = ($externalVideo | ForEach-Object { $_.Name }) -join ", "
                } else {
                    $null = $valueLabelMap["Видеокарта"].Text = "Внешняя видеокарта не обнаружена"
                }
                $null = $valueLabelMap["ПК без перезагрузки"].Text = "{0} дней, {1} часов, {2} минут" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
            } catch {
                [void][System.Windows.Forms.MessageBox]::Show("Ошибка: Не удалось получить данные.`n$($_.Exception.Message)", "Ошибка", "OK", "Error")
            } finally {
                if ($cimSession) {
                    Remove-CimSession $cimSession
                }
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Ошибка: Введите имя компьютера или IP.", "Ошибка", "OK", "Error")
        }
    })

    # Запуск формы
    $null = $form.ShowDialog()
}

# Запрос учетных данных администратора
$credential = $null
while (-not $credential) {
    $credential = Get-Credential -Message "Введите учетные данные администратора домена"
    if (-not $credential) {
        # Пользователь отменил ввод – завершаем программу
        exit
    }
}

# Отображение основного окна после получения учетных данных
Show-MainForm -Credential $credential