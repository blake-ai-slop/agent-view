. (Join-Path $PSScriptRoot 'I18n.ps1')
Register-AgentViewStrings -Module 'toast' -Strings @{
    en = @{ 'more' = '+{0} more'; 'close' = 'Close'; 'now' = '· just now' }
    vi = @{ 'more' = '+{0} thông báo khác'; 'close' = 'Đóng'; 'now' = '· vừa xong' }
}
# Toast thông báo kiểu agent-view (thay balloon NotifyIcon) — theo thiết kế Bezel đã chốt.
# Dot-source chỉ định nghĩa hàm (và đăng ký chuỗi). Một toast mỗi tiến trình, sống trên thread STA của tray.
# Hợp đồng: Show-AgentViewToast -Items @(@{Provider;Window;Kind(low|reset|update);Remaining;Title;Text}) [-Warning] [-OnClick {}],
#           Hide-AgentViewToast, Close-AgentViewToast -Force, Test-AgentViewToastOpen, Test-AgentViewUserBusy.
. (Join-Path $PSScriptRoot 'Ring.ps1')

function Get-AgentViewToastMetrics {
    @{
        Width = 344; Gap = 12; MaxRows = 4; Ring = 40; RingRadius = 16; RingStroke = 4
        ShadowLeft = 24; ShadowTop = 14; ShadowRight = 24; ShadowBottom = 36
        InMs = 220; OutMs = 200; InShift = 14; OutShift = 8; HideMs = 8000; MinResumeMs = 1500
        FontText = 'Segoe UI Variable Text, Segoe UI'
    }
}

# ---------------------------------------------------------------- hàm thuần
# Vị trí cửa sổ (gồm lề bóng) để mép toast cách góc dưới phải WorkArea 12px.
function Get-AgentViewToastPlacement($WorkArea, [double]$WindowHeight) {
    $m = Get-AgentViewToastMetrics
    [pscustomobject]@{
        Left = $WorkArea.Right - $m.Gap - $m.Width - $m.ShadowLeft
        Top = $WorkArea.Bottom - $m.Gap + $m.ShadowBottom - $WindowHeight
        Width = $m.Width + $m.ShadowLeft + $m.ShadowRight
    }
}

# Hàng hiển thị: tối đa MaxRows, phần thừa ⇒ More = N. 'reset' ⇒ vòng đầy, ✓, màu ok.
function Get-AgentViewToastModel($Items, [switch]$Warning) {
    $m = Get-AgentViewToastMetrics
    $list = @(@($Items) | Where-Object { $null -ne $_ })
    $rows = @(foreach ($it in @($list | Select-Object -First $m.MaxRows)) {
        $rem = $null; if ($null -ne $it.Remaining) { $rem = [int][math]::Max(0, [math]::Min(100, [double]$it.Remaining)) }
        $full = ($it.Kind -eq 'reset')
        $update = ($it.Kind -eq 'update')   # cập nhật ⇒ mũi tên lên màu accent, không %
        $level = if ($update) { 'update' } elseif ($full) { 'ok' } else { Get-QuotaLevel $rem }
        $value = if ($full) { 100 } elseif ($null -ne $rem -and -not $update) { $rem } else { 0 }
        $center = if ($update) { [string][char]0x2191 } elseif ($full) { [string][char]0x2713 } elseif ($null -ne $rem) { "$rem%" } else { '–' }
        if ($update) { $rem = $null }
        [pscustomobject]@{ Provider = [string]$it.Provider; Title = [string]$it.Title; Text = [string]$it.Text; Remaining = $rem
            Level = $level; Value = $value; Center = $center; Full = $full; Kind = [string]$it.Kind }
    })
    $more = [math]::Max(0, $list.Count - $m.MaxRows)
    [pscustomobject]@{
        Rows = $rows; More = $more
        MoreText = $(if ($more) { T 'toast.more' -Args @($more) } else { $null })
        Warning = [bool]$Warning
    }
}

# Màu ô provider: claude/codex theo theme, provider lạ ⇒ accent.
function Get-AgentViewToastProviderColor([string]$Provider, $Theme) {
    if (-not $Theme) { $Theme = Get-AgentViewTheme }
    if (@('claude', 'codex') -contains $Provider) { return $Theme[$Provider] }
    return $Theme['accent']
}

# ---------------------------------------------------------------- người dùng bận
function Initialize-AgentViewToastNative {
    if (-not ('AgentView.ToastNative' -as [type])) {
        Add-Type -TypeDefinition @'
namespace AgentView {
  public static class ToastNative {
    [System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int state);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetWindowLong(System.IntPtr h, int i);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int SetWindowLong(System.IntPtr h, int i, int v);
  }
}
'@
    }
}
# Bận = toàn màn hình/trình chiếu/quiet time/khóa máy (mọi trạng thái khác QUNS_ACCEPTS_NOTIFICATIONS=5). Lỗi ⇒ không bận.
function Test-AgentViewUserBusy {
    try {
        Initialize-AgentViewToastNative
        $state = 0
        $hr = [AgentView.ToastNative]::SHQueryUserNotificationState([ref]$state)
        if ($hr -ne 0) { return $false }
        return ($state -ne 5)
    } catch { return $false }
}

# ---------------------------------------------------------------- trạng thái (một toast mỗi tiến trình)
function Get-AgentViewToastState {
    $st = [AppDomain]::CurrentDomain.GetData('agent-view.toast')
    if ($null -eq $st) {
        $st = @{ Window = $null; Ui = @{}; OnClick = $null; Closing = $false; Timer = $null; WorkArea = $null; Model = $null; Handlers = @{}
                 LeftMs = 0; Clock = $null }
        [AppDomain]::CurrentDomain.SetData('agent-view.toast', $st)
    }
    $st
}

function Get-AgentViewToastXaml {
    $m = Get-AgentViewToastMetrics
    $w = $m.Width + $m.ShadowLeft + $m.ShadowRight
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Title="agent-view" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" Topmost="True"
  ShowActivated="False" Focusable="False" ResizeMode="NoResize" SizeToContent="Height" Width="$w" UseLayoutRounding="True"
  FontFamily="$($m.FontText)" FontSize="12" Foreground="@@av-text@@">
 <Border x:Name="Shell" Width="$($m.Width)" Margin="$($m.ShadowLeft),$($m.ShadowTop),$($m.ShadowRight),$($m.ShadowBottom)" CornerRadius="12" BorderThickness="1" BorderBrush="@@av-stroke@@" Padding="12,10,12,12" Cursor="Hand">
  <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="@@av-bg-top@@" Offset="0"/><GradientStop Color="@@av-bg@@" Offset="1"/></LinearGradientBrush></Border.Background>
  <Border.Effect><DropShadowEffect BlurRadius="40" ShadowDepth="18" Direction="270" Opacity="0.55" Color="Black"/></Border.Effect>
  <Border.RenderTransform><TranslateTransform x:Name="ShellShift"/></Border.RenderTransform>
  <StackPanel>
   <Grid Height="22">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <Grid VerticalAlignment="Center" Width="13" Height="13">
     <Ellipse x:Name="DotHalo" Width="13" Height="13" Fill="@@crit@@" Opacity="0.18" Visibility="Collapsed"/>
     <Ellipse x:Name="Dot" Width="7" Height="7" Fill="@@accent@@"/>
    </Grid>
    <TextBlock Grid.Column="1" Text="agent-view" Margin="4,0,0,0" FontSize="11.5" FontWeight="SemiBold" Foreground="@@av-text-2@@" VerticalAlignment="Center"/>
    <TextBlock x:Name="NowText" Grid.Column="2" Margin="5,0,0,0" FontSize="11.5" Foreground="@@av-text-3@@" VerticalAlignment="Center"/>
    <Button x:Name="CloseBtn" Grid.Column="4" Width="22" Height="22" Focusable="False" Cursor="Hand" ToolTip="$(T 'toast.close')">
     <Button.Template><ControlTemplate TargetType="Button">
      <Border x:Name="bd" Background="Transparent" CornerRadius="6">
       <Path x:Name="glyph" Data="M3.5,3.5 L9.5,9.5 M9.5,3.5 L3.5,9.5" Width="13" Height="13" Stroke="@@av-text-3@@" StrokeThickness="1.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="@@av-surface-hi@@"/><Setter TargetName="glyph" Property="Stroke" Value="@@av-text@@"/></Trigger></ControlTemplate.Triggers>
     </ControlTemplate></Button.Template>
    </Button>
   </Grid>
   <StackPanel x:Name="Rows" Margin="0,8,0,0"/>
   <TextBlock x:Name="MoreText" Visibility="Collapsed" Margin="51,2,0,2" FontSize="12" Foreground="@@av-text-3@@"/>
   <Border Height="2" Margin="0,8,0,0" CornerRadius="1" Background="@@av-stroke-soft@@" ClipToBounds="True">
    <Border x:Name="Bar" CornerRadius="1" Background="@@av-text-3@@" RenderTransformOrigin="0,0.5">
     <Border.RenderTransform><ScaleTransform x:Name="BarScale" ScaleX="1" ScaleY="1"/></Border.RenderTransform>
    </Border>
   </Border>
  </StackPanel>
 </Border>
</Window>
"@
}

function Expand-AgentViewToastXaml([string]$Xaml, $Theme) {
    [regex]::Replace($Xaml, '@@([a-z0-9-]+)@@', { param($x) $Theme[$x.Groups[1].Value] })
}

# Biểu tượng cập nhật 40px: vòng accent mờ + mũi tên lên accent (thay vòng %, cùng kích thước).
function New-AgentViewToastUpdateIcon($Theme) {
    $m = Get-AgentViewToastMetrics
    $size = $m.Ring; $c = $size / 2; $r = $m.RingRadius
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = $size; $canvas.Height = $size; $canvas.VerticalAlignment = 'Center'
    $disc = New-Object System.Windows.Shapes.Path
    $disc.Data = New-Object System.Windows.Media.EllipseGeometry ((New-Object System.Windows.Point $c, $c), $r, $r)
    $disc.Fill = ConvertTo-AgentViewBrush $Theme['accent'] 0.14
    $disc.Stroke = ConvertTo-AgentViewBrush $Theme['accent'] 0.55; $disc.StrokeThickness = 2
    [void]$canvas.Children.Add($disc)
    $arrow = New-Object System.Windows.Shapes.Path
    $arrow.Data = [System.Windows.Media.Geometry]::Parse(("M{0},{1} L{0},{2} M{3},{4} L{0},{1} L{5},{4}" -f $c, ($c - 7), ($c + 7), ($c - 6), ($c - 1), ($c + 6)))
    $arrow.Stroke = ConvertTo-AgentViewBrush $Theme['accent']; $arrow.StrokeThickness = 2.4
    $arrow.StrokeStartLineCap = 'Round'; $arrow.StrokeEndLineCap = 'Round'; $arrow.StrokeLineJoin = 'Round'
    [void]$canvas.Children.Add($arrow)
    $canvas
}

# Vòng 40px (rãnh av-track, cung màu mức, đầu tròn) + chữ giữa (% hoặc ✓). Hình học từ Ring.ps1. Kind 'update' ⇒ mũi tên.
function New-AgentViewToastRing($Row, $Theme) {
    if ($Row.Kind -eq 'update') { return (New-AgentViewToastUpdateIcon $Theme) }
    $m = Get-AgentViewToastMetrics
    $size = $m.Ring; $c = $size / 2; $r = $m.RingRadius
    $color = ConvertTo-AgentViewBrush (Get-AgentViewLevelColors $Row.Level $Theme).Lv
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width = $size; $grid.Height = $size; $grid.VerticalAlignment = 'Center'
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = $size; $canvas.Height = $size
    $track = New-Object System.Windows.Shapes.Path
    $track.Data = New-Object System.Windows.Media.EllipseGeometry ((New-Object System.Windows.Point $c, $c), $r, $r)
    $track.Stroke = ConvertTo-AgentViewBrush $Theme['av-track']; $track.StrokeThickness = $m.RingStroke
    [void]$canvas.Children.Add($track)
    $plan = Get-AgentArcPlan $c $r $Row.Value
    if ($plan.Visible) {
        $fig = New-Object System.Windows.Media.PathFigure
        $fig.IsClosed = $false; $fig.IsFilled = $false
        $fig.StartPoint = New-Object System.Windows.Point $plan.Start.X, $plan.Start.Y
        foreach ($s in $plan.Segments) {
            $fig.Segments.Add((New-Object System.Windows.Media.ArcSegment ((New-Object System.Windows.Point $s.Point.X, $s.Point.Y), (New-Object System.Windows.Size $r, $r), 0, $s.IsLargeArc, ([System.Windows.Media.SweepDirection]::Clockwise), $true)))
        }
        $geo = New-Object System.Windows.Media.PathGeometry; $geo.Figures.Add($fig)
        $arc = New-Object System.Windows.Shapes.Path
        $arc.Data = $geo; $arc.Stroke = $color; $arc.StrokeThickness = $m.RingStroke
        $arc.StrokeStartLineCap = 'Round'; $arc.StrokeEndLineCap = 'Round'
        [void]$canvas.Children.Add($arc)
    }
    [void]$grid.Children.Add($canvas)
    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.Text = $Row.Center; $txt.Foreground = $color; $txt.FontWeight = [System.Windows.FontWeights]::Bold
    $txt.FontSize = $(if ($Row.Full) { 14 } else { 11 })
    $txt.HorizontalAlignment = 'Center'; $txt.VerticalAlignment = 'Center'
    [System.Windows.Documents.Typography]::SetNumeralAlignment($txt, [System.Windows.FontNumeralAlignment]::Tabular)
    [void]$grid.Children.Add($txt)
    $grid
}

function New-AgentViewToastWindow {
    Initialize-AgentViewWpf
    $st = Get-AgentViewToastState
    $theme = Get-AgentViewTheme
    $window = [System.Windows.Markup.XamlReader]::Parse((Expand-AgentViewToastXaml (Get-AgentViewToastXaml) $theme))
    $ui = @{}
    foreach ($n in 'Shell', 'ShellShift', 'Dot', 'DotHalo', 'NowText', 'CloseBtn', 'Rows', 'MoreText', 'Bar', 'BarScale') { $ui[$n] = $window.FindName($n) }
    $st.Window = $window; $st.Ui = $ui; $st.Theme = $theme; $st.Handlers = @{}

    # Không nhận focus kể cả khi bấm (WS_EX_NOACTIVATE), không hiện trong Alt+Tab (WS_EX_TOOLWINDOW).
    $st.Handlers.Source = [EventHandler]{
        try {
            Initialize-AgentViewToastNative
            $h = (New-Object System.Windows.Interop.WindowInteropHelper ($this)).Handle
            $ex = [AgentView.ToastNative]::GetWindowLong($h, -20)
            [void][AgentView.ToastNative]::SetWindowLong($h, -20, ($ex -bor 0x08000000 -bor 0x80))
        } catch { }
    }
    $window.Add_SourceInitialized($st.Handlers.Source)
    $st.Handlers.Size = [System.Windows.SizeChangedEventHandler]{
        $s = Get-AgentViewToastState
        if ($s.WorkArea -and $s.Window) { $s.Window.Top = (Get-AgentViewToastPlacement $s.WorkArea $s.Window.ActualHeight).Top }
    }
    $window.Add_SizeChanged($st.Handlers.Size)
    $st.Handlers.Enter = [System.Windows.Input.MouseEventHandler]{
        $s = Get-AgentViewToastState
        if ($s.Closing) {   # đang mờ đi ⇒ giữ lại
            $s.Closing = $false
            $s.Ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null); $s.Ui.Shell.Opacity = 1
            $s.Ui.ShellShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null); $s.Ui.ShellShift.Y = 0
            $s.LeftMs = (Get-AgentViewToastMetrics).HideMs
            $s.Ui.BarScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null); $s.Ui.BarScale.ScaleX = 1
            $s.Timer.Stop(); $s.Clock = $null
        } else { Suspend-AgentViewToastCountdown }
        $s.Hover = $true
        if (-not $s.Model.Warning) { $s.Ui.Shell.BorderBrush = ConvertTo-AgentViewBrush '#3A4256' }   # cảnh báo giữ viền crit
    }
    $ui.Shell.Add_MouseEnter($st.Handlers.Enter)
    $st.Handlers.Leave = [System.Windows.Input.MouseEventHandler]{
        $s = Get-AgentViewToastState
        $s.Hover = $false
        Set-AgentViewToastBorder
        if (Test-AgentViewToastOpen) { Start-AgentViewToastCountdown }
    }
    $ui.Shell.Add_MouseLeave($st.Handlers.Leave)
    $st.Handlers.Body = [System.Windows.Input.MouseButtonEventHandler]{
        $s = Get-AgentViewToastState
        $cb = $s.OnClick
        if ($cb) { try { & $cb } catch { } }
        Hide-AgentViewToast
    }
    $ui.Shell.Add_MouseLeftButtonUp($st.Handlers.Body)
    $st.Handlers.Close = [System.Windows.RoutedEventHandler]{ $_.Handled = $true; Hide-AgentViewToast }
    $ui.CloseBtn.Add_Click($st.Handlers.Close)

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $st.Handlers.Tick = [EventHandler]{ $this.Stop(); Hide-AgentViewToast }
    $timer.Add_Tick($st.Handlers.Tick)
    $st.Timer = $timer
    $window
}

# Viền theo trạng thái: cảnh báo ⇒ crit 55%; thường ⇒ av-stroke.
function Set-AgentViewToastBorder {
    $st = Get-AgentViewToastState
    if (-not $st.Window) { return }
    if ($st.Model -and $st.Model.Warning) { $st.Ui.Shell.BorderBrush = ConvertTo-AgentViewBrush $st.Theme['crit'] 0.55 }
    else { $st.Ui.Shell.BorderBrush = ConvertTo-AgentViewBrush $st.Theme['av-stroke'] }
}

# Đếm ngược: còn LeftMs ⇒ thanh thu từ tỉ lệ hiện tại về 0, timer bắn khi hết. Rê chuột dừng, rời chuột chạy tiếp.
function Start-AgentViewToastCountdown {
    $st = Get-AgentViewToastState
    $m = Get-AgentViewToastMetrics
    $left = [math]::Max($m.MinResumeMs, [double]$st.LeftMs)
    $from = [math]::Min(1.0, $left / $m.HideMs)
    $st.Timer.Stop()
    $st.Timer.Interval = [TimeSpan]::FromMilliseconds($left)
    $st.LeftMs = $left
    $st.Clock = [Diagnostics.Stopwatch]::StartNew()
    $bar = New-Object System.Windows.Media.Animation.DoubleAnimation $from, 0, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($left)))
    $st.Ui.BarScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $bar)
    $st.Timer.Start()
}
function Suspend-AgentViewToastCountdown {
    $st = Get-AgentViewToastState
    $m = Get-AgentViewToastMetrics
    $st.Timer.Stop()
    if ($st.Clock) { $st.LeftMs = [math]::Max(0, $st.LeftMs - $st.Clock.Elapsed.TotalMilliseconds); $st.Clock = $null }
    $st.Ui.BarScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null)
    $st.Ui.BarScale.ScaleX = [math]::Min(1.0, $st.LeftMs / $m.HideMs)
}

function Set-AgentViewToastContent($Model) {
    $st = Get-AgentViewToastState
    $ui = $st.Ui; $theme = $st.Theme
    $st.Model = $Model
    $ui.NowText.Text = (T 'toast.now')
    $ui.Rows.Children.Clear()
    $ui.Dot.Fill = ConvertTo-AgentViewBrush $(if ($Model.Warning) { $theme['crit'] } else { $theme['accent'] })
    $ui.DotHalo.Visibility = $(if ($Model.Warning) { 'Visible' } else { 'Collapsed' })
    $ui.Bar.Background = $(if ($Model.Warning) { ConvertTo-AgentViewBrush $theme['crit'] 0.7 } else { ConvertTo-AgentViewBrush $theme['av-text-3'] })
    Set-AgentViewToastBorder
    $i = 0
    foreach ($row in $Model.Rows) {
        $item = New-Object System.Windows.Controls.Border
        $item.Padding = New-Object System.Windows.Thickness 0, 6, 0, 6
        if ($i -gt 0) { $item.BorderThickness = New-Object System.Windows.Thickness 0, 1, 0, 0; $item.BorderBrush = ConvertTo-AgentViewBrush $theme['av-stroke-soft'] }
        $grid = New-Object System.Windows.Controls.Grid
        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength 40
        [void]$grid.ColumnDefinitions.Add($c0)
        [void]$grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        [void]$grid.Children.Add((New-AgentViewToastRing $row $theme))

        $texts = New-Object System.Windows.Controls.StackPanel
        $texts.Margin = New-Object System.Windows.Thickness 11, 0, 0, 0
        $texts.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($texts, 1)
        $line = New-Object System.Windows.Controls.DockPanel
        $pv = New-Object System.Windows.Controls.Border
        $pv.Width = 6; $pv.Height = 6; $pv.CornerRadius = New-Object System.Windows.CornerRadius 2
        $pv.Background = ConvertTo-AgentViewBrush (Get-AgentViewToastProviderColor $row.Provider $theme)
        $pv.Margin = New-Object System.Windows.Thickness 0, 1, 6, 0; $pv.VerticalAlignment = 'Center'
        [void]$line.Children.Add($pv)
        $title = New-Object System.Windows.Controls.TextBlock
        $title.Text = $row.Title; $title.FontSize = 13.5; $title.FontWeight = [System.Windows.FontWeights]::SemiBold; $title.TextTrimming = 'CharacterEllipsis'
        [void]$line.Children.Add($title)
        $sub = New-Object System.Windows.Controls.TextBlock
        $sub.Text = $row.Text; $sub.FontSize = 12; $sub.TextTrimming = 'CharacterEllipsis'; $sub.Margin = New-Object System.Windows.Thickness 0, 2, 0, 0
        $sub.Foreground = ConvertTo-AgentViewBrush $theme['av-text-2']
        [System.Windows.Documents.Typography]::SetNumeralAlignment($sub, [System.Windows.FontNumeralAlignment]::Tabular)
        if (-not $row.Text) { $sub.Visibility = 'Collapsed' }
        [void]$texts.Children.Add($line); [void]$texts.Children.Add($sub)
        [void]$grid.Children.Add($texts)
        $item.Child = $grid
        [void]$ui.Rows.Children.Add($item)
        $i++
    }
    $ui.MoreText.Text = [string]$Model.MoreText
    $ui.MoreText.Visibility = $(if ($Model.More) { 'Visible' } else { 'Collapsed' })
}

function New-AgentViewToastAnimation([double]$From, [double]$To, [double]$Ms, [string]$Mode) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation $From, $To, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($Ms)))
    $e = New-Object System.Windows.Media.Animation.CubicEase; $e.EasingMode = $Mode
    $a.EasingFunction = $e
    $a
}

# ---------------------------------------------------------------- API công khai
function Test-AgentViewToastOpen {
    $st = Get-AgentViewToastState
    [bool]($st.Window -and $st.Window.IsVisible -and -not $st.Closing)
}

# Đang hiện ⇒ thay nội dung + đếm lại 8 giây (vẫn 1 cửa sổ). Không cướp focus.
function Show-AgentViewToast {
    param([object[]]$Items, [switch]$Warning, [scriptblock]$OnClick)
    $model = Get-AgentViewToastModel $Items -Warning:$Warning
    if (-not $model.Rows.Count) { return }
    $st = Get-AgentViewToastState
    if (-not $st.Window) { [void](New-AgentViewToastWindow) }
    $m = Get-AgentViewToastMetrics
    $w = $st.Window; $ui = $st.Ui
    $st.OnClick = $OnClick
    Set-AgentViewToastContent $model
    $st.WorkArea = [System.Windows.SystemParameters]::WorkArea
    $ui.Shell.Measure((New-Object System.Windows.Size $m.Width, ([double]::PositiveInfinity)))
    $height = $ui.Shell.DesiredSize.Height   # DesiredSize đã gồm Margin (lề bóng)
    $place = Get-AgentViewToastPlacement $st.WorkArea $height
    $w.Left = $place.Left; $w.Top = $place.Top
    $wasOpen = Test-AgentViewToastOpen
    $wasVisible = $w.IsVisible
    $st.Closing = $false
    if (-not $wasOpen) {
        $from = 0.0; if ($wasVisible) { $from = $ui.Shell.Opacity }   # đang mờ đi ⇒ hiện lại từ độ mờ hiện tại
        $ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $ui.ShellShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
        $ui.Shell.Opacity = $from
        if (-not $wasVisible) { $w.Show() }
        $ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-AgentViewToastAnimation $from 1 $m.InMs 'EaseOut'))
        $ui.ShellShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-AgentViewToastAnimation $m.InShift 0 $m.InMs 'EaseOut'))
    }
    $st.LeftMs = $m.HideMs; $st.Clock = $null
    if ($ui.Shell.IsMouseOver) { $st.Timer.Stop(); $ui.BarScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null); $ui.BarScale.ScaleX = 1 }
    else { Start-AgentViewToastCountdown }
}

function Hide-AgentViewToast {
    $st = Get-AgentViewToastState
    if (-not (Test-AgentViewToastOpen)) { return }
    $m = Get-AgentViewToastMetrics
    $st.Closing = $true
    $st.Timer.Stop(); $st.Clock = $null
    $fade = New-AgentViewToastAnimation 1 0 $m.OutMs 'EaseIn'
    $fade.Add_Completed({
        $s = Get-AgentViewToastState
        if ($s.Closing -and $s.Window) { $s.Window.Hide(); $s.Closing = $false; if (Get-Command Request-AgentViewMemoryTrim -ErrorAction SilentlyContinue) { Request-AgentViewMemoryTrim } }
    })
    $st.Ui.ShellShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-AgentViewToastAnimation 0 $m.OutShift $m.OutMs 'EaseIn'))
    $st.Ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
}

# Đóng hẳn (thoát app/test): gỡ handler, dừng timer/hoạt ảnh, Close thật, drain Dispatcher.
function Close-AgentViewToast {
    param([switch]$Force)
    if (-not $Force) { Hide-AgentViewToast; return }
    $st = Get-AgentViewToastState
    if (-not $st.Window) { return }
    $w = $st.Window; $ui = $st.Ui; $h = $st.Handlers
    $st.Closing = $true
    if ($st.Timer) { $st.Timer.Stop(); if ($h.Tick) { $st.Timer.Remove_Tick($h.Tick) } }
    if ($h.Source) { $w.Remove_SourceInitialized($h.Source) }
    if ($h.Size) { $w.Remove_SizeChanged($h.Size) }
    if ($h.Enter) { $ui.Shell.Remove_MouseEnter($h.Enter) }
    if ($h.Leave) { $ui.Shell.Remove_MouseLeave($h.Leave) }
    if ($h.Body) { $ui.Shell.Remove_MouseLeftButtonUp($h.Body) }
    if ($h.Close) { $ui.CloseBtn.Remove_Click($h.Close) }
    $ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $ui.ShellShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $ui.BarScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null)
    $w.Close()
    $w.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ContextIdle, [Action]{})
    $st.Window = $null; $st.Ui = @{}; $st.Timer = $null; $st.Handlers = @{}; $st.OnClick = $null; $st.Model = $null
    $st.Closing = $false; $st.Clock = $null; $st.Hover = $false
}
