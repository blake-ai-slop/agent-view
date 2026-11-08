# Phần dựng cửa sổ WPF dùng chung (popup, toast, widget, cài đặt, vòng đo). Dot-source chỉ định nghĩa hàm.
if (-not (Test-Path function:Get-AgentViewTheme)) { . (Join-Path $PSScriptRoot 'Theme.ps1') }

function Initialize-AgentViewWpf {
    if (-not ('System.Windows.Media.ArcSegment' -as [type])) {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    }
    if (-not ('System.Windows.Forms.Integration.ElementHost' -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms, WindowsFormsIntegration
    }
}

# WS_EX_NOACTIVATE + WS_EX_TOOLWINDOW (không cướp focus, không có trong Alt+Tab) và trạng thái thông báo của shell.
function Initialize-AgentViewNative {
    if (-not ('AgentView.UiNative' -as [type])) {
        Add-Type -TypeDefinition @'
namespace AgentView {
  public static class UiNative {
    [System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int state);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetWindowLong(System.IntPtr h, int i);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int SetWindowLong(System.IntPtr h, int i, int v);
  }
}
'@
    }
}
function Set-AgentViewNoActivate($Window) {
    try {
        Initialize-AgentViewNative
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle
        [void][AgentView.UiNative]::SetWindowLong($h, -20, ([AgentView.UiNative]::GetWindowLong($h, -20) -bor 0x08000080))
    } catch { }
}

# Trạng thái một cửa sổ mỗi tiến trình, lưu ở AppDomain để handler sự kiện thấy cùng một bản dù gọi từ scope nào.
function Get-AgentViewUiState([string]$Key, [scriptblock]$New) {
    $st = [AppDomain]::CurrentDomain.GetData($Key)
    if ($null -eq $st) { $st = & $New; [AppDomain]::CurrentDomain.SetData($Key, $st) }
    $st
}

function ConvertTo-AgentViewBrush([string]$Hex, [double]$Opacity = 1) {
    $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
    if ($Opacity -lt 1) { $brush.Opacity = $Opacity }
    $brush.Freeze(); $brush
}
function ConvertTo-AgentViewColor([string]$Hex, [byte]$Alpha = 255) {
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    [System.Windows.Media.Color]::FromArgb($Alpha, $c.R, $c.G, $c.B)
}

# Hai màu (mức, đuôi gradient) theo mức 'ok'|'warn'|'crit'|'unk'.
function Get-AgentViewLevelColors([string]$Level, $Theme) {
    if (-not $Theme) { $Theme = Get-AgentViewTheme }
    if (@('ok', 'warn', 'crit', 'unk') -notcontains $Level) { $Level = 'unk' }
    [pscustomobject]@{ Level = $Level; Lv = $Theme[$Level]; Hi = $Theme["$Level-hi"] }
}

function Get-AgentViewVisibility($Visible) { if ($Visible) { 'Visible' } else { 'Collapsed' } }

# Thay token @@khóa-theme@@ trong XAML.
function Expand-AgentViewXaml([string]$Xaml, $Theme) {
    if (-not $Theme) { $Theme = Get-AgentViewTheme }
    [regex]::Replace($Xaml, '@@([a-z0-9-]+)@@', { param($m) $Theme[$m.Groups[1].Value] })
}

# Khung Bezel: Window trong suốt không viền + Border "Shell" viền av-stroke, nền gradient bg-top → bg, bóng đổ.
function Get-AgentViewShellXaml {
    param([string]$Window, [string]$Shell, [string]$Body, [string]$Resources = '', [string]$Transform = '',
        [string]$Gradient = 'StartPoint="0,0" EndPoint="0,1"',
        [string]$Shadow = 'BlurRadius="32" ShadowDepth="12" Direction="270" Opacity="0.55" Color="Black"')
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" $Window>
$Resources
 <Border x:Name="Shell" BorderThickness="1" BorderBrush="@@av-stroke@@" $Shell>
  <Border.Background><LinearGradientBrush $Gradient><GradientStop Color="@@av-bg-top@@" Offset="0"/><GradientStop Color="@@av-bg@@" Offset="1"/></LinearGradientBrush></Border.Background>
  <Border.Effect><DropShadowEffect $Shadow/></Border.Effect>
  $Transform
$Body
 </Border>
</Window>
"@
}

# Parse XAML đã thay token rồi lấy các phần tử có tên vào một hashtable.
function New-AgentViewXamlObject([string]$Xaml, $Theme, [string[]]$Names) {
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-AgentViewXaml $Xaml $Theme))
    $ui = @{}
    foreach ($n in $Names) { $ui[$n] = $root.FindName($n) }
    $root, $ui
}

# Vị trí cửa sổ (đã gồm lề bóng) để mép khung cách góc dưới phải WorkArea Gap px. Metrics: Width/Gap/Shadow*.
function Get-AgentViewCornerPlacement($WorkArea, [double]$WindowHeight, $Metrics) {
    [pscustomobject]@{
        Left = $WorkArea.Right - $Metrics.Gap - $Metrics.Width - $Metrics.ShadowLeft
        Top = $WorkArea.Bottom - $Metrics.Gap + $Metrics.ShadowBottom - $WindowHeight
        Width = $Metrics.Width + $Metrics.ShadowLeft + $Metrics.ShadowRight
    }
}

# Ease: CubicOut | CubicIn | QuinticOut | '' (tuyến tính). From $null ⇒ chạy từ giá trị hiện tại.
function New-AgentViewDoubleAnimation($From, [double]$To, [double]$Ms, [string]$Ease = 'CubicOut', [double]$DelayMs = 0) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    if ($null -ne $From) { $a.From = [double]$From }
    $a.To = $To; $a.Duration = [TimeSpan]::FromMilliseconds($Ms)
    $e = switch ($Ease) {
        'CubicOut' { New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = 'EaseOut' } }
        'CubicIn' { New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = 'EaseIn' } }
        'QuinticOut' { New-Object System.Windows.Media.Animation.QuinticEase -Property @{ EasingMode = 'EaseOut' } }
    }
    if ($e) { $a.EasingFunction = $e }
    if ($DelayMs -gt 0) { $a.BeginTime = [TimeSpan]::FromMilliseconds($DelayMs) }
    $a
}

# Gắn handler và ghi lại để Remove-AgentViewHandlers gỡ hết khi đóng hẳn (handler còn sống sau Close có thể crash PowerShell).
function Add-AgentViewHandler($State, $Target, [string]$Event, [scriptblock]$Handler) {
    $info = $Target.GetType().GetEvent($Event)
    $delegate = $Handler -as $info.EventHandlerType
    $info.AddEventHandler($Target, $delegate)
    $State.Handlers += , @($Target, $info, $delegate)
}
function Remove-AgentViewHandlers($State) {
    foreach ($h in @($State.Handlers)) { $h[1].RemoveEventHandler($h[0], $h[2]) }
    $State.Handlers = @()
}

# Close thật rồi drain Dispatcher khi scope PowerShell định nghĩa handler còn tồn tại.
function Close-AgentViewWindowNow($Window) {
    $Window.Close()
    [void]$Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ContextIdle, [Action]{})
}

# Sau khi ẩn hẳn: nhờ tray dọn bộ nhớ (chỉ có khi chạy trong tray).
function Request-AgentViewUiTrim {
    if (Test-Path function:Request-AgentViewMemoryTrim) { Request-AgentViewMemoryTrim }
}
