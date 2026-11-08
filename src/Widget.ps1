if (-not (Test-Path function:Register-AgentViewStrings)) { . (Join-Path $PSScriptRoot 'I18n.ps1') }
Register-AgentViewStrings -Module 'widget' -Strings @{
    en = @{
        'title' = 'agent-view widget'
        'five' = '5h {0}'
        'week' = 'Week {0}'
        'runout' = 'out ~{0}'
    }
    vi = @{
        'title' = 'agent-view widget'
        'five' = '5h {0}'
        'week' = 'Tuần {0}'
        'runout' = 'hết ~{0}'
    }
}
# Widget Bezel nổi bám cạnh màn hình, tạo lười trên thread STA của tray. Dot-source chỉ định nghĩa hàm.
if (-not (Test-Path function:New-AgentRing)) { . (Join-Path $PSScriptRoot 'Ring.ps1') }
if (-not (Test-Path function:Get-AgentViewSettings)) { . (Join-Path $PSScriptRoot 'Settings.ps1') }
if (-not (Test-Path function:Get-AgentViewCardModel)) { . (Join-Path $PSScriptRoot 'Popup.ps1') }

function Get-AgentViewWidgetDetailText($Model, [datetime]$Now = (Get-Date)) {
    $parts = @()
    if ($null -ne $Model.Five.Remaining) { $parts += (T 'widget.five' -Args @($Model.Five.ValueText)) }
    if ($null -ne $Model.Week.Remaining) { $parts += (T 'widget.week' -Args @($Model.Week.ValueText)) }
    $text = $parts -join ' · '
    $primary = $Model.Five; $fallback = $Model.Week
    if ($null -eq $primary.Remaining -or ($null -ne $fallback.Remaining -and $fallback.Remaining -lt $primary.Remaining)) {
        $primary = $Model.Week; $fallback = $Model.Five
    }
    $reset = $primary.Rel; if (-not $reset) { $reset = $fallback.Rel }
    if ($reset) { $text += " · ↺ $reset" }
    # Dự báo chỉ cho cửa sổ sát nhất và chỉ khi sẽ hết trước reset.
    if ($primary.ForecastKind -eq 'runout' -and $null -ne $primary.ForecastAt) {
        $at = [datetime]$primary.ForecastAt
        $when = $(if ($at.Date -eq $Now.Date) { $at.ToString('HH:mm') } else { Format-QuotaResetAbsolute $at $Now })
        $text += ' · ' + (T 'widget.runout' -Args @($when))
    }
    $text
}

function Get-AgentViewWidgetEdge($Area, [double]$X, [double]$Y) {
    $d = @{ left = [math]::Abs($X - $Area.Left); right = [math]::Abs($Area.Right - $X); top = [math]::Abs($Y - $Area.Top) }
    @('right', 'left', 'top') | Sort-Object { $d[$_] } | Select-Object -First 1
}

# Area: WorkingArea theo pixel thiết bị, Scale: DPI ⇒ kết quả theo đơn vị WPF. Offset dọc cạnh, kẹp trong vùng.
function Get-AgentViewWidgetPlacement($Area, [string]$Edge, $Offset, [double]$Width, [double]$Height, [double]$Scale = 1) {
    $l = $Area.Left / $Scale; $t = $Area.Top / $Scale; $r = $Area.Right / $Scale; $b = $Area.Bottom / $Scale
    $length = $b - $t - $Height - 24; if ($Edge -eq 'top') { $length = $r - $l - $Width - 24 }
    if ($null -eq $Offset) { $Offset = $length / 2 }
    $o = [math]::Max(0, [math]::Min([math]::Max(0, $length), [double]$Offset))
    $x = $r - $Width - 12; $y = $t + 12 + $o
    if ($Edge -eq 'left') { $x = $l + 12 }
    if ($Edge -eq 'top') { $x = $l + 12 + $o; $y = $t + 12 }
    [pscustomobject]@{ Left = $x; Top = $y; Offset = $o }
}

function Get-AgentViewWidgetState {
    Get-AgentViewUiState 'agent-view.widget' {
        @{ Window = $null; Cards = @(); Settings = (Get-AgentViewSettings); Screen = $null; Scale = 1; DockTimer = $null; CloseTimer = $null; OnOpenPopup = $null }
    }
}

function Test-AgentViewWidgetVisible { $s = Get-AgentViewWidgetState; return ($null -ne $s.Window -and $s.Window.IsVisible) }

# Đặt cửa sổ theo cạnh/offset đã lưu (lề bóng của Shell: 28 hai bên, 20 trên, 40 dưới). -Animate ⇒ trượt 240ms.
function Set-AgentViewWidgetDock([switch]$Animate) {
    $s = Get-AgentViewWidgetState; $w = $s.Window
    $edge = $s.Settings.WidgetEdge; $top = $edge -eq 'top'
    $s.List.Orientation = $(if ($top) { 'Horizontal' } else { 'Vertical' })
    $grip = $w.FindName('Grip')
    if ($top) { $grip.Height = [double]::NaN; $grip.Width = 10; $grip.VerticalAlignment = 'Center' } else { $grip.Height = 10; $grip.Width = [double]::NaN }
    $alignment = switch ($edge) { right { 'Right' } left { 'Left' } top { 'Center' } }
    foreach ($c in $s.Cards) {
        if ($c.Edge -ne $edge) {
            $c.Detail.BeginAnimation([Windows.FrameworkElement]::MaxWidthProperty, $null)
            $c.Detail.BeginAnimation([Windows.FrameworkElement]::MaxHeightProperty, $null)
            if ($top) { $c.Detail.MaxWidth = 230; $c.Detail.MaxHeight = 0 } else { $c.Detail.MaxWidth = 0; $c.Detail.MaxHeight = [double]::PositiveInfinity }
            $c.Edge = $edge
        }
        $c.Panel.Orientation = $(if ($top) { 'Vertical' } else { 'Horizontal' })
        $c.Panel.Margin = $(if ($top) { '4,0,4,0' } else { '0,4,0,4' })
        $c.Panel.FlowDirection = $(if ($edge -eq 'right') { 'RightToLeft' } else { 'LeftToRight' })
        $c.Detail.FlowDirection = 'LeftToRight'
        $c.Name.TextAlignment = $alignment
        $c.Line.TextAlignment = $alignment
        $c.Compact.Orientation = $(if ($top) { 'Horizontal' } else { 'Vertical' })
        $c.Compact.Width = $(if ($top) { [double]::NaN } else { 48 })
        $c.Label.VerticalAlignment = 'Center'
        $c.Label.Margin = $(if ($top) { '7,0,4,0' } else { '0,3,0,0' })
    }
    $w.UpdateLayout()
    $p = Get-AgentViewWidgetPlacement $s.Screen.WorkingArea $edge $s.Settings.WidgetOffset ($w.ActualWidth - 56) ($w.ActualHeight - 60) $s.Scale
    $x = $p.Left - 28; $y = $p.Top - 20
    if ($s.DockTimer) { $s.DockTimer.Stop(); $s.DockTimer = $null }
    if (-not $Animate) { $w.Left = $x; $w.Top = $y; return }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [timespan]::FromMilliseconds(15)
    $timer.Tag = @{ W = $w; X = $w.Left; Y = $w.Top; TX = $x; TY = $y; Clock = [Diagnostics.Stopwatch]::StartNew() }
    $timer.Add_Tick({
        $v = $this.Tag
        $k = [math]::Min(1, $v.Clock.Elapsed.TotalMilliseconds / 240); $e = 1 - [math]::Pow(1 - $k, 3)
        $v.W.Left = $v.X + ($v.TX - $v.X) * $e; $v.W.Top = $v.Y + ($v.TY - $v.Y) * $e
        if ($k -ge 1) { $this.Stop(); $this.Tag = $null }
    })
    $s.DockTimer = $timer; $timer.Start()
}

# Rê chuột ⇒ mở phần chi tiết (rộng tới 230, hoặc cao tới 44 khi bám cạnh trên).
function Set-AgentViewWidgetExpanded([bool]$Expanded) {
    $s = Get-AgentViewWidgetState
    $top = $s.Settings.WidgetEdge -eq 'top'
    $property = [Windows.FrameworkElement]::MaxWidthProperty; $target = 230
    if ($top) { $property = [Windows.FrameworkElement]::MaxHeightProperty; $target = 44 }
    if (-not $Expanded) { $target = 0 }
    $ms = $(if ($Expanded) { 220 } else { 160 })
    foreach ($c in $s.Cards) {
        $c.Detail.Margin = $(if (-not $Expanded) { '0' } elseif ($top) { '0,6,0,0' } else { '6,0,8,0' })
        $c.Detail.BeginAnimation($property, (New-AgentViewDoubleAnimation $null $target $ms))
        $c.Detail.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-AgentViewDoubleAnimation $null ([double][int]$Expanded) 160 ''))
    }
}

function New-AgentViewWidgetWindow {
    Initialize-AgentViewWpf
    $s = Get-AgentViewWidgetState
    $xaml = Get-AgentViewShellXaml `
        -Window ('Title="{0}" ShowInTaskbar="False" ShowActivated="False" Topmost="True" SizeToContent="WidthAndHeight" FontFamily="Segoe UI" Foreground="@@av-text@@"' -f (T 'widget.title')) `
        -Shell 'Margin="28,20,28,40" Padding="8" CornerRadius="14"' -Shadow 'BlurRadius="28" ShadowDepth="10" Opacity="0.5"' `
        -Body '<StackPanel x:Name="List"><TextBlock x:Name="Grip" Text="⠿" Foreground="@@av-text-3@@" HorizontalAlignment="Center" Cursor="SizeAll" Height="14"/></StackPanel>'
    $w, $ui = New-AgentViewXamlObject $xaml $null @('List', 'Grip')
    $s.Window = $w; $s.List = $ui.List
    [Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($w)
    $w.Add_SourceInitialized({ Set-AgentViewNoActivate $this })
    $ui.Grip.Add_MouseLeftButtonDown({
        $s = Get-AgentViewWidgetState; Set-AgentViewWidgetExpanded $false
        $shadow = $s.Window.FindName('Shell').Effect
        $shadow.BlurRadius = 40; $shadow.ShadowDepth = 18; $shadow.Opacity = 0.6
        try { $s.Window.DragMove() } finally { $shadow.BlurRadius = 28; $shadow.ShadowDepth = 10; $shadow.Opacity = 0.5 }
        $pt = [Windows.Forms.Cursor]::Position; $s.Screen = [Windows.Forms.Screen]::FromPoint($pt)
        $s.Scale = [Windows.PresentationSource]::FromVisual($s.Window).CompositionTarget.TransformToDevice.M11
        $s.Settings.WidgetEdge = Get-AgentViewWidgetEdge $s.Screen.WorkingArea $pt.X $pt.Y
        $s.Settings.WidgetScreen = $s.Screen.DeviceName
        $offset = ($s.Window.Top + 20) - $s.Screen.WorkingArea.Top / $s.Scale - 12
        if ($s.Settings.WidgetEdge -eq 'top') { $offset = ($s.Window.Left + 28) - $s.Screen.WorkingArea.Left / $s.Scale - 12 }
        $s.Settings.WidgetOffset = $offset; Set-AgentViewWidgetDock -Animate
        $p = Get-AgentViewWidgetPlacement $s.Screen.WorkingArea $s.Settings.WidgetEdge $offset ($s.Window.ActualWidth - 56) ($s.Window.ActualHeight - 60) $s.Scale
        $s.Settings.WidgetOffset = $p.Offset; Save-AgentViewSettings $s.Settings
    })
    $s.CloseTimer = New-Object Windows.Threading.DispatcherTimer; $s.CloseTimer.Interval = [timespan]::FromMilliseconds(150)
    $s.CloseTimer.Add_Tick({ $this.Stop(); Set-AgentViewWidgetExpanded $false })
    $w.Add_MouseEnter({ $s = Get-AgentViewWidgetState; $s.CloseTimer.Stop(); Set-AgentViewWidgetExpanded $true })
    $w.Add_MouseLeave({ (Get-AgentViewWidgetState).CloseTimer.Start() })
    $w.Add_SizeChanged({ $s = Get-AgentViewWidgetState; if ($s.Screen) { Set-AgentViewWidgetDock } })
}

# Một thẻ mỗi provider: vòng 40px + nhãn % (thu gọn), tên + dòng chi tiết (mở khi rê chuột).
function New-AgentViewWidgetCard($Row, $Theme) {
    $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = '0,4,0,4'
    $compact = New-Object Windows.Controls.StackPanel; $compact.Width = 48; $compact.FlowDirection = 'LeftToRight'
    $ring = New-AgentRing -Size 40 -Stroke 4 -Icon $Row.Provider -IconSize 18
    $ring.HorizontalAlignment = 'Center'; [void]$compact.Children.Add($ring)
    $label = New-Object Windows.Controls.TextBlock; $label.FontSize = 12; $label.FontWeight = 'SemiBold'; $label.HorizontalAlignment = 'Center'
    [void]$compact.Children.Add($label)
    $detail = New-Object Windows.Controls.StackPanel; $detail.VerticalAlignment = 'Center'; $detail.MaxWidth = 0; $detail.Opacity = 0; $detail.ClipToBounds = $true
    $name = New-Object Windows.Controls.TextBlock; $name.TextTrimming = 'CharacterEllipsis'; $name.FontSize = 12.5; $name.FontWeight = 'SemiBold'
    $line = New-Object Windows.Controls.TextBlock; $line.TextTrimming = 'CharacterEllipsis'; $line.FontSize = 11.5; $line.Foreground = ConvertTo-AgentViewBrush $Theme['av-text-2']
    [void]$detail.Children.Add($name); [void]$detail.Children.Add($line)
    [void]$panel.Children.Add($compact); [void]$panel.Children.Add($detail)
    $panel.Add_MouseLeftButtonUp({ $s = Get-AgentViewWidgetState; if ($s.OnOpenPopup) { & $s.OnOpenPopup } })
    @{ Panel = $panel; Compact = $compact; Detail = $detail; Name = $name; Line = $line; Label = $label; Ring = $ring }
}

function Update-AgentViewWidget {
    param($Rows, [switch]$Loading)
    $s = Get-AgentViewWidgetState; if (-not (Test-AgentViewWidgetVisible)) { return }
    $theme = Get-AgentViewTheme
    $rowsFlat = @(Get-AgentViewDisplayRows $Rows)
    if ($s.Cards.Count -ne $rowsFlat.Count) {
        foreach ($c in $s.Cards) { Suspend-AgentRing $c.Ring }
        while ($s.List.Children.Count -gt 1) { $s.List.Children.RemoveAt(1) }
        $s.Cards = @(foreach ($r in $rowsFlat) { $c = New-AgentViewWidgetCard $r $theme; [void]$s.List.Children.Add($c.Panel); $c })
    }
    $history = Get-AgentViewPopupHistory; $now = Get-Date
    for ($i = 0; $i -lt $rowsFlat.Count; $i++) {
        $c = $s.Cards[$i]; $m = Get-AgentViewCardModel $rowsFlat[$i] -Loading:$Loading -Now $now -History $history
        $c.Name.Text = $m.Name
        $c.Line.Text = $(if ($m.State -eq 'ok') { Get-AgentViewWidgetDetailText $m $now } else { $m.ErrDetail })
        $c.Label.Text = $(if ($Loading) { '…' } elseif ($m.State -eq 'error') { '?' } else { "$($m.Value)%" })
        $c.Label.Foreground = ConvertTo-AgentViewBrush $theme[$m.Level]
        $label = $c.Label
        $tick = { param($v) $label.Text = ([string][int][math]::Round($v)) + '%' }.GetNewClosure()
        Set-AgentRing -Ring $c.Ring -State $m.State -Value $m.Value -DurationMs 450 -OnTick $tick
    }
    Set-AgentViewWidgetDock
}

function Show-AgentViewWidget {
    param($Rows, [switch]$Loading, [scriptblock]$OnOpenPopup)
    $s = Get-AgentViewWidgetState; if ($OnOpenPopup) { $s.OnOpenPopup = $OnOpenPopup }
    if (-not $s.Window) { New-AgentViewWidgetWindow }
    $s.Screen = @([Windows.Forms.Screen]::AllScreens | Where-Object DeviceName -eq $s.Settings.WidgetScreen) | Select-Object -First 1
    if (-not $s.Screen) { $s.Screen = [Windows.Forms.Screen]::PrimaryScreen; $s.Settings.WidgetOffset = $null }
    $s.Window.Show(); $s.Scale = [Windows.PresentationSource]::FromVisual($s.Window).CompositionTarget.TransformToDevice.M11
    Update-AgentViewWidget -Rows $Rows -Loading:$Loading
    foreach ($c in $s.Cards) { Resume-AgentRing $c.Ring }
}

function Hide-AgentViewWidget {
    $s = Get-AgentViewWidgetState
    if ($s.CloseTimer) { $s.CloseTimer.Stop() }; if ($s.DockTimer) { $s.DockTimer.Stop() }
    foreach ($c in $s.Cards) { Suspend-AgentRing $c.Ring; if ($c.Ring.Tag.Timer) { $c.Ring.Tag.Timer.Stop(); $c.Ring.Tag.Timer = $null } }
    if ($s.Window) { $s.Window.Close(); $s.Window = $null; $s.Cards = @() }
}
