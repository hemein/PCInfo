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

# Задает текст в поле значения и подгоняет высоту под фактическое число строк
# (TextBox, в отличие от Label, не умеет авторазмер по многострочному тексту)
function Set-ValueBoxText {
    param (
        [System.Windows.Forms.TextBox]$TextBox,
        [string]$Text
    )
    $TextBox.Text = $Text
    $proposedSize = New-Object System.Drawing.Size($TextBox.Width, [int]::MaxValue)
    $measured = [System.Windows.Forms.TextRenderer]::MeasureText($TextBox.Text, $TextBox.Font, $proposedSize, [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $TextBox.Height = $measured.Height + 4
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

    # Цветовая палитра
    $colorBg = [System.Drawing.Color]::White
    $colorAccent = [System.Drawing.Color]::FromArgb(43, 108, 237)
    $colorAccentHover = [System.Drawing.Color]::FromArgb(29, 89, 209)
    $colorCaption = [System.Drawing.Color]::FromArgb(60, 64, 67)
    $colorValueText = [System.Drawing.Color]::FromArgb(32, 33, 36)
    $colorDivider = [System.Drawing.Color]::FromArgb(224, 224, 224)
    $form.BackColor = $colorBg

    # Поле для ввода имени компьютера
$labelHostname = New-Object System.Windows.Forms.Label
$labelHostname.Text = "Введите имя компьютера или IP:"
$labelHostname.AutoSize = $false
$labelHostname.Size = New-Object System.Drawing.Size(300,20)
$labelHostname.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$labelHostname.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$labelHostname.ForeColor = $colorCaption
# Центрируем метку по ширине формы (650)
$labelHostname.Location = New-Object System.Drawing.Point(([int]((650 - $labelHostname.Width)/2)),20)

$textBoxHostname = New-Object System.Windows.Forms.TextBox
$textBoxHostname.Size = New-Object System.Drawing.Size(200,20)
$textBoxHostname.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
# Располагаем текстовое поле под меткой, тоже по центру
$textBoxHostname.Location = New-Object System.Drawing.Point(([int]((650 - $textBoxHostname.Width)/2)),45)

    # Кнопка "Отправить"
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Отправить"
    $button.Size = New-Object System.Drawing.Size(120, 32)
    $button.Location = New-Object System.Drawing.Point(265,75)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $colorAccent
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Add_MouseEnter({ $button.BackColor = $colorAccentHover })
    $button.Add_MouseLeave({ $button.BackColor = $colorAccent })

    # Тонкая разделительная линия между полем ввода и результатами
    $divider = New-Object System.Windows.Forms.Panel
    $divider.Location = New-Object System.Drawing.Point(0, 118)
    $divider.Size = New-Object System.Drawing.Size(650, 1)
    $divider.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $divider.BackColor = $colorDivider

    # Добавляем элементы на форму
    [void]$form.Controls.Add($labelHostname)
    [void]$form.Controls.Add($textBoxHostname)
    [void]$form.Controls.Add($button)
    [void]$form.Controls.Add($divider)

    # Панель для скроллинга таблицы (поля ввода и кнопка остаются статичными)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(0, 130)
    # Высота считается от фактической клиентской области формы, а не фиксированным числом:
    # при жестко заданных 380px панель на некоторых системах выходила за нижний край окна
    # (высота заголовка окна варьируется), из-за чего последняя строка таблицы обрезалась
    $panel.Size = New-Object System.Drawing.Size(650, ($form.ClientSize.Height - $panel.Location.Y))
    $panel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $panel.AutoScroll = $true
    $panel.BackColor = $colorBg

    # Таблица с динамической компоновкой
    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.ColumnCount = 2
    $table.RowCount = 0
    $table.AutoSize = $true
    $table.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    # Anchor вместо Dock=Top: ширина подстраивается под панель, высота — под контент,
    # без этого сочетание Dock+AutoSize вызывало паразитный горизонтальный скроллбар,
    # который перекрывал нижнюю часть последней строки
    $table.Location = New-Object System.Drawing.Point(0, 0)
    $table.Width = $panel.ClientSize.Width
    $table.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $table.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 20)
    $table.BackColor = $colorBg
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 35)))
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 75)))

    # TextBox по умолчанию перехватывает прокрутку колесом мыши на себя и не пропускает
    # событие дальше, из-за чего скролл прокрутки в панели переставал работать над полями
    # значений. Здесь вручную прокручиваем панель и гасим встроенную обработку TextBox.
    $panelScrollHandler = {
        param($sender, $e)
        if ($e -is [System.Windows.Forms.HandledMouseEventArgs]) {
            $e.Handled = $true
        }
        $currentY = -$panel.AutoScrollPosition.Y
        $newY = [Math]::Max(0, $currentY - $e.Delta)
        $panel.AutoScrollPosition = New-Object System.Drawing.Point(0, $newY)
    }.GetNewClosure()

    $valueLabelMap = @{}
    $fields = @("Имя ПК", "Версия ОС", "Процессор", "Оперативная память", "Установленные диски", "Видеокарта", "ПК без перезагрузки")
    foreach ($field in $fields) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = "${field}:"
        $label.AutoSize = $false
        $label.Dock = [System.Windows.Forms.DockStyle]::Fill
        $label.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
        $label.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $label.ForeColor = $colorCaption

        # TextBox вместо Label — чтобы значение можно было выделить и скопировать
        $valueLabel = New-Object System.Windows.Forms.TextBox
        $valueLabel.Multiline = $true
        $valueLabel.ReadOnly = $true
        $valueLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
        $valueLabel.BackColor = $colorBg
        $valueLabel.ForeColor = $colorValueText
        $valueLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
        $valueLabel.Width = 480
        Set-ValueBoxText -TextBox $valueLabel -Text ""
        $valueLabel.Add_MouseWheel($panelScrollHandler)
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

                # Обновляем поля
                Set-ValueBoxText -TextBox $valueLabelMap["Имя ПК"] -Text $osInfo.CSName
                Set-ValueBoxText -TextBox $valueLabelMap["Версия ОС"] -Text $osInfo.Caption
                Set-ValueBoxText -TextBox $valueLabelMap["Процессор"] -Text $cpuInfo.Name
                Set-ValueBoxText -TextBox $valueLabelMap["Оперативная память"] -Text (($memoryInfo | ForEach-Object { "$([math]::Round($_.Capacity / 1GB, 1)) GB $(Get-MemoryType $_.SMBIOSMemoryType)" }) -join "`r`n")
                Set-ValueBoxText -TextBox $valueLabelMap["Установленные диски"] -Text (($diskInfo | ForEach-Object { "$($_.Model) ($([math]::Round($_.Size / 1GB, 1)) GB)" }) -join "`r`n")

                # Проверяем наличие внешней видеокарты (PCI)
                $externalVideo = $videoInfo | Where-Object { $_.PNPDeviceID -like "*PCI*" }
                if ($externalVideo) {
                    Set-ValueBoxText -TextBox $valueLabelMap["Видеокарта"] -Text (($externalVideo | ForEach-Object { $_.Name }) -join "`r`n")
                } else {
                    Set-ValueBoxText -TextBox $valueLabelMap["Видеокарта"] -Text "Внешняя видеокарта не обнаружена"
                }
                Set-ValueBoxText -TextBox $valueLabelMap["ПК без перезагрузки"] -Text ("{0} дней, {1} часов, {2} минут" -f $uptime.Days, $uptime.Hours, $uptime.Minutes)

                # Пересчитываем область прокрутки панели под фактическую высоту таблицы
                # (после смены текста лейблы могут перенестись на несколько строк,
                # и Panel.AutoScroll не подхватывает новую высоту без принудительного пересчета)
                $table.PerformLayout()
                $panel.AutoScrollMinSize = New-Object System.Drawing.Size(0, $table.PreferredSize.Height)
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
# Допустимые форматы учетной записи: domain\username или username@domain.ru (UPN)
$usernamePattern = '^([^\\@\s]+\\[^\\@\s]+|[^\\@\s]+@[^\\@\s]+\.[^\\@\s]+)$'
$credential = $null
while (-not $credential) {
    $credential = Get-Credential -Message "Введите учетные данные администратора домена (формат: domain\username или username@domain.ru)"
    if (-not $credential) {
        # Пользователь отменил ввод – завершаем программу
        exit
    }
    if ($credential.UserName -notmatch $usernamePattern) {
        [void][System.Windows.Forms.MessageBox]::Show("Учетная запись должна быть указана в формате domain\username или username@domain.ru", "Ошибка", "OK", "Error")
        $credential = $null
    }
}

# Отображение основного окна после получения учетных данных
Show-MainForm -Credential $credential