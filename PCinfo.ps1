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

# Выбранная тема хранится в %APPDATA%\PCInfo\settings.json (пароль и прочие данные не сохраняются)
$script:SettingsPath = Join-Path $env:APPDATA "PCInfo\settings.json"

function Get-SavedTheme {
    try {
        if (Test-Path $script:SettingsPath) {
            $saved = (Get-Content -Raw -Path $script:SettingsPath | ConvertFrom-Json).theme
            if ($saved -eq "dark" -or $saved -eq "light") { return $saved }
        }
    } catch {}
    return "light"
}

function Save-Theme {
    param ([string]$Theme)
    try {
        $dir = Split-Path $script:SettingsPath
        if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        @{ theme = $Theme } | ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8
    } catch {}
}

# Иконка приложения: синий скруглённый квадрат, буква P и "i" (info) с янтарной точкой
function New-AppBitmap {
    param ([int]$Size)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $d = $Size * 0.44
    $bg = New-Object System.Drawing.Drawing2D.GraphicsPath
    $bg.AddArc(0.5, 0.5, $d, $d, 180, 90)
    $bg.AddArc($Size - $d - 0.5, 0.5, $d, $d, 270, 90)
    $bg.AddArc($Size - $d - 0.5, $Size - $d - 0.5, $d, $d, 0, 90)
    $bg.AddArc(0.5, $Size - $d - 0.5, $d, $d, 90, 90)
    $bg.CloseFigure()
    $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)), [System.Drawing.Color]::FromArgb(59, 130, 246), [System.Drawing.Color]::FromArgb(29, 78, 216), 45.0)
    $g.FillPath($gradient, $bg)

    $letter = New-Object System.Drawing.Drawing2D.GraphicsPath
    $letter.AddString("P", (New-Object System.Drawing.FontFamily("Segoe UI")), [int][System.Drawing.FontStyle]::Bold, [single]($Size * 0.62), (New-Object System.Drawing.PointF(0, 0)), [System.Drawing.StringFormat]::GenericTypographic)
    $b = $letter.GetBounds()
    $iWidth = $Size * 0.115
    $gap = $Size * 0.07
    $startX = ($Size - ($b.Width + $gap + $iWidth)) / 2
    $top = ($Size - $b.Height) / 2
    $matrix = New-Object System.Drawing.Drawing2D.Matrix
    $matrix.Translate([single]($startX - $b.X), [single]($top - $b.Y))
    $letter.Transform($matrix)
    $g.FillPath([System.Drawing.Brushes]::White, $letter)

    $iX = $startX + $b.Width + $gap
    $dotGap = $Size * 0.045
    $g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(251, 191, 36))), [single]$iX, [single]$top, [single]$iWidth, [single]$iWidth)
    $stemTop = $top + $iWidth + $dotGap
    $g.FillRectangle([System.Drawing.Brushes]::White, [single]$iX, [single]$stemTop, [single]$iWidth, [single]($top + $b.Height - $stemTop))

    $g.Dispose()
    return $bmp
}

function New-AppIcon {
    $bmp = New-AppBitmap -Size 32
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

# Windows не даёт процессу, который не в фокусе, просто забрать фокус (окно остаётся позади),
# поэтому на момент вызова присоединяем свой поток ввода к потоку активного окна
try {
    Add-Type -Namespace PCInfo -Name Win -MemberDefinition '
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, System.IntPtr processId);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);
        [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();'
} catch {}

function Set-ForegroundForm {
    param ([System.Windows.Forms.Form]$Form)
    # Если exe запущен из ярлыка с режимом "Свернутое", Windows открывает и главное окно свёрнутым
    if ($Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $Form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }
    # Даже если Windows откажет в фокусе, окно на момент вызова окажется поверх остальных
    $Form.TopMost = $true
    $attached = $false
    try {
        $foreground = [PCInfo.Win]::GetForegroundWindow()
        $foregroundThread = [PCInfo.Win]::GetWindowThreadProcessId($foreground, [System.IntPtr]::Zero)
        $currentThread = [PCInfo.Win]::GetCurrentThreadId()
        if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
            $attached = [PCInfo.Win]::AttachThreadInput($currentThread, $foregroundThread, $true)
        }
        [void][PCInfo.Win]::SetForegroundWindow($Form.Handle)
        if ([PCInfo.Win]::GetForegroundWindow() -ne $Form.Handle) {
            # Запасной вариант: синтетическое нажатие Alt даёт процессу право забрать фокус
            [PCInfo.Win]::keybd_event(0x12, 0, 0, [System.UIntPtr]::Zero)
            [PCInfo.Win]::keybd_event(0x12, 0, 2, [System.UIntPtr]::Zero)
            [void][PCInfo.Win]::SetForegroundWindow($Form.Handle)
        }
    } catch {
    } finally {
        if ($attached) { [void][PCInfo.Win]::AttachThreadInput($currentThread, $foregroundThread, $false) }
    }
    $Form.Activate()
    $Form.TopMost = $false
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

    $form.Icon = New-AppIcon

    # Цветовые палитры светлой и тёмной темы; $theme хранит цвета текущей темы
    $themes = @{
        light = @{
            Bg          = [System.Drawing.Color]::White
            Accent      = [System.Drawing.Color]::FromArgb(43, 108, 237)
            AccentHover = [System.Drawing.Color]::FromArgb(29, 89, 209)
            Caption     = [System.Drawing.Color]::FromArgb(60, 64, 67)
            ValueText   = [System.Drawing.Color]::FromArgb(32, 33, 36)
            Divider     = [System.Drawing.Color]::FromArgb(224, 224, 224)
            InputBg     = [System.Drawing.Color]::White
            InputText   = [System.Drawing.Color]::FromArgb(32, 33, 36)
            ToggleBg    = [System.Drawing.Color]::FromArgb(240, 242, 245)
        }
        dark = @{
            Bg          = [System.Drawing.Color]::FromArgb(30, 31, 34)
            Accent      = [System.Drawing.Color]::FromArgb(59, 120, 240)
            AccentHover = [System.Drawing.Color]::FromArgb(86, 142, 250)
            Caption     = [System.Drawing.Color]::FromArgb(176, 180, 186)
            ValueText   = [System.Drawing.Color]::FromArgb(232, 234, 237)
            Divider     = [System.Drawing.Color]::FromArgb(60, 63, 68)
            InputBg     = [System.Drawing.Color]::FromArgb(45, 47, 52)
            InputText   = [System.Drawing.Color]::FromArgb(232, 234, 237)
            ToggleBg    = [System.Drawing.Color]::FromArgb(45, 47, 52)
        }
    }
    $theme = @{}
    $state = @{ Name = "light" }
    $captionLabels = New-Object System.Collections.ArrayList

    # Поле для ввода имени компьютера
$labelHostname = New-Object System.Windows.Forms.Label
$labelHostname.Text = "Введите имя компьютера или IP:"
$labelHostname.AutoSize = $false
$labelHostname.Size = New-Object System.Drawing.Size(300,20)
$labelHostname.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$labelHostname.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
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
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Add_MouseEnter({ $button.BackColor = $theme.AccentHover })
    $button.Add_MouseLeave({ $button.BackColor = $theme.Accent })

    # Тонкая разделительная линия между полем ввода и результатами
    $divider = New-Object System.Windows.Forms.Panel
    $divider.Location = New-Object System.Drawing.Point(0, 118)
    $divider.Size = New-Object System.Drawing.Size(650, 1)
    $divider.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

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
        [void]$captionLabels.Add($label)

        # TextBox вместо Label — чтобы значение можно было выделить и скопировать
        $valueLabel = New-Object System.Windows.Forms.TextBox
        $valueLabel.Multiline = $true
        $valueLabel.ReadOnly = $true
        $valueLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
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

    # Кнопка переключения темы в правом верхнем углу (☀ — включить светлую, ☾ — тёмную)
    $themeButton = New-Object System.Windows.Forms.Button
    $themeButton.Size = New-Object System.Drawing.Size(34, 30)
    $themeButton.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 44), 8)
    $themeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $themeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $themeButton.FlatAppearance.BorderSize = 0
    $themeButton.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 12)
    $themeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $themeButton.TabStop = $false
    [void]$form.Controls.Add($themeButton)
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.SetToolTip($themeButton, "Переключить тему (светлая/тёмная)")

    # Применяет тему ко всем элементам и обновляет иконку на кнопке переключения
    $applyTheme = {
        param([string]$name)
        $state.Name = $name
        foreach ($key in $themes[$name].Keys) { $theme[$key] = $themes[$name][$key] }

        $form.BackColor = $theme.Bg
        $labelHostname.ForeColor = $theme.Caption
        $textBoxHostname.BackColor = $theme.InputBg
        $textBoxHostname.ForeColor = $theme.InputText
        $button.BackColor = $theme.Accent
        $divider.BackColor = $theme.Divider
        $panel.BackColor = $theme.Bg
        $table.BackColor = $theme.Bg
        foreach ($caption in $captionLabels) { $caption.ForeColor = $theme.Caption }
        foreach ($valueBox in $valueLabelMap.Values) {
            $valueBox.BackColor = $theme.Bg
            $valueBox.ForeColor = $theme.ValueText
        }
        $themeButton.BackColor = $theme.ToggleBg
        $themeButton.ForeColor = $theme.Caption
        $themeButton.Text = if ($name -eq "dark") { [string][char]0x2600 } else { [string][char]0x263E }
    }

    $themeButton.Add_Click({
        $newName = if ($state.Name -eq "dark") { "light" } else { "dark" }
        & $applyTheme $newName
        Save-Theme -Theme $newName
    })

    & $applyTheme (Get-SavedTheme)

    # После ввода учётных данных окно должно сразу стать активным (иначе оно может
    # оказаться позади других окон), а курсор — стоять в поле имени компьютера
    $form.ActiveControl = $textBoxHostname
    # Сразу после закрытия диалога учётных данных Windows ещё перераспределяет фокус, поэтому
    # активацию повторяем несколько раз, пока окно не получит фокус
    $activation = @{ Attempts = 0 }
    $activationTimer = New-Object System.Windows.Forms.Timer
    $activationTimer.Interval = 300
    $activationTimer.Add_Tick({
        $activation.Attempts++
        if ($form.ContainsFocus -or $activation.Attempts -gt 8) {
            $activationTimer.Stop()
            return
        }
        Set-ForegroundForm -Form $form
    })
    $form.Add_Shown({
        Set-ForegroundForm -Form $form
        $textBoxHostname.Focus()
        $activationTimer.Start()
    })
    $form.Add_FormClosed({ $activationTimer.Stop() })

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