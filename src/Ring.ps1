# Vòng đo dùng chung (popup, widget) — WPF trên Windows PowerShell 5.1.
# Dot-source chỉ định nghĩa hàm (và nạp Theme.ps1/Format.ps1 cùng thư mục nếu có mà chưa nạp).
# Hợp đồng: New-AgentRing / Set-AgentRing (tray-bezel, widget gọi); Suspend-/Resume-AgentRing để tắt vòng lặp khi ẩn.
if (-not (Get-Command Get-AgentViewTheme -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Theme.ps1')) { . (Join-Path $PSScriptRoot 'Theme.ps1') }
}
if (-not (Get-Command Get-QuotaLevel -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Format.ps1')) { . (Join-Path $PSScriptRoot 'Format.ps1') }
}

function Initialize-AgentViewWpf {
    if (-not ('System.Windows.Media.ArcSegment' -as [type])) {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    }
    if (-not ('System.Windows.Forms.Integration.ElementHost' -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms, WindowsFormsIntegration
    }
}

# ---------------------------------------------------------------- hàm thuần (test không cần WPF)
function Get-AgentRingRadius([double]$Size, [double]$Stroke, [switch]$Ticks) {
    $center = $Size / 2
    $radius = $center - $Stroke / 2
    if ($Ticks) { $radius -= 3 }   # chừa 3 cho vạch khắc
    [pscustomobject]@{ Center = $center; Radius = $radius }
}

# Điểm trên vòng tại p% tính từ 12 giờ theo chiều kim đồng hồ.
function Get-AgentArcPoint([double]$Center, [double]$Radius, [double]$Percent) {
    $a = ($Percent / 100) * 2 * [math]::PI - [math]::PI / 2
    [pscustomobject]@{ X = $Center + $Radius * [math]::Cos($a); Y = $Center + $Radius * [math]::Sin($a) }
}

# Kế hoạch dựng cung: điểm đầu (12 giờ) + danh sách ArcSegment (điểm cuối, IsLargeArc). 100% → 2 nửa vòng.
function Get-AgentArcPlan([double]$Center, [double]$Radius, [double]$Percent) {
    $p = [math]::Max(0, [math]::Min(100, $Percent))
    $start = Get-AgentArcPoint $Center $Radius 0
    $segments = @()
    if ($p -ge 99.999) {
        $segments = @(
            [pscustomobject]@{ Point = (Get-AgentArcPoint $Center $Radius 50); IsLargeArc = $false },
            [pscustomobject]@{ Point = $start; IsLargeArc = $false })
    } elseif ($p -gt 0) {
        $segments = @([pscustomobject]@{ Point = (Get-AgentArcPoint $Center $Radius $p); IsLargeArc = ($p -gt 50) })
    }
    [pscustomobject]@{ Start = $start; Segments = $segments; Visible = ($p -ge 0.5) }
}

# Vạch khắc tại p%: ngoài mép vòng 1, dài 2.5.
function Get-AgentRingTickLine([double]$Center, [double]$Radius, [double]$Stroke, [double]$Percent) {
    $r1 = $Radius + $Stroke / 2 + 1
    $p1 = Get-AgentArcPoint $Center $r1 $Percent
    $p2 = Get-AgentArcPoint $Center ($r1 + 2.5) $Percent
    [pscustomobject]@{ X1 = $p1.X; Y1 = $p1.Y; X2 = $p2.X; Y2 = $p2.Y }
}

# Rãnh nét đứt (lỗi): StrokeDashArray tính theo đơn vị độ dày nét như WPF yêu cầu.
function Get-AgentRingDash([double]$Radius, [double]$Stroke) {
    $circ = 2 * [math]::PI * $Radius
    $segs = [math]::Max(8, [math]::Floor($circ / ($Stroke * 2.2) + 0.5))
    $seg = $circ / $segs
    ,@(($seg * 0.55 / $Stroke), ($seg * 0.45 / $Stroke))
}

# Hai màu (mức, đuôi gradient) theo mức 'ok'|'warn'|'crit'|'unk'.
function Get-AgentViewLevelColors([string]$Level, $Theme) {
    if (-not $Theme) { $Theme = Get-AgentViewTheme }
    if (@('ok', 'warn', 'crit', 'unk') -notcontains $Level) { $Level = 'unk' }
    [pscustomobject]@{ Level = $Level; Lv = $Theme[$Level]; Hi = $Theme["$Level-hi"] }
}

# Kiểu vòng theo trạng thái: màu, rãnh, quầng thở, xoay.
function Get-AgentRingStyle([string]$State, $Value, $Theme) {
    if (-not $Theme) { $Theme = Get-AgentViewTheme }
    $level = 'unk'
    if ($State -eq 'ok' -and $null -ne $Value) { $level = Get-QuotaLevel $Value }
    $colors = Get-AgentViewLevelColors $level $Theme
    $glowMs = 0
    if ($State -eq 'ok' -and $level -eq 'warn') { $glowMs = 1200 }   # nửa chu kỳ 2400ms (AutoReverse)
    if ($State -eq 'ok' -and $level -eq 'crit') { $glowMs = 700 }    # nửa chu kỳ 1400ms
    $track = $Theme['av-track']; if ($State -eq 'error') { $track = '#3A4152' }
    [pscustomobject]@{
        Level = $level; Lv = $colors.Lv; Hi = $colors.Hi; Track = $track
        Dashed = ($State -eq 'error'); Glow = ($glowMs -gt 0); GlowHalfMs = $glowMs
        Spin = ($State -eq 'loading'); TicksVisible = ($State -ne 'loading')
        CenterOpacity = $(if ($State -eq 'error') { 0.55 } else { 1.0 })
    }
}

# ---------------------------------------------------------------- dựng WPF
function ConvertTo-AgentViewBrush([string]$Hex, [double]$Opacity = 1) {
    $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
    if ($Opacity -lt 1) { $brush.Opacity = $Opacity }
    $brush.Freeze(); $brush
}
function ConvertTo-AgentViewColor([string]$Hex, [byte]$Alpha = 255) {
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    [System.Windows.Media.Color]::FromArgb($Alpha, $c.R, $c.G, $c.B)
}

# Biểu tượng tự vẽ (placeholder theo thiết kế SVG, không phải logo chính thức), hệ toạ độ 24×24.
function New-AgentRingIcon([string]$Icon, [double]$IconSize, $Theme) {
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = 24; $canvas.Height = 24
    $round = [System.Windows.Media.PenLineCap]::Round
    if ($Icon -eq 'claude') {
        $brush = ConvertTo-AgentViewBrush $Theme['claude']
        $rays = New-Object System.Windows.Shapes.Path
        $rays.Data = [System.Windows.Media.Geometry]::Parse('M12,3.5 V9 M19.36,7.75 L14.6,10.5 M19.36,16.25 L14.6,13.5 M12,20.5 V15 M4.64,16.25 L9.4,13.5 M4.64,7.75 L9.4,10.5')
        $rays.Stroke = $brush; $rays.StrokeThickness = 2.6; $rays.StrokeStartLineCap = $round; $rays.StrokeEndLineCap = $round
        $dot = New-Object System.Windows.Shapes.Path
        $dot.Data = New-Object System.Windows.Media.EllipseGeometry ((New-Object System.Windows.Point 12, 12), 1.3, 1.3)
        $dot.Fill = $brush
        [void]$canvas.Children.Add($rays); [void]$canvas.Children.Add($dot)
    } elseif ($Icon -eq 'codex') {
        $brush = ConvertTo-AgentViewBrush $Theme['codex']
        $frame = New-Object System.Windows.Shapes.Path
        $frame.Data = New-Object System.Windows.Media.RectangleGeometry ((New-Object System.Windows.Rect 3.5, 4.5, 17, 15), 4.2, 4.2)
        $frame.Stroke = $brush; $frame.StrokeThickness = 1.9
        $prompt = New-Object System.Windows.Shapes.Path
        $prompt.Data = [System.Windows.Media.Geometry]::Parse('M8,10 L10.8,12.2 L8,14.4 M13,14.5 H16.2')
        $prompt.Stroke = $brush; $prompt.StrokeThickness = 1.9
        $prompt.StrokeStartLineCap = $round; $prompt.StrokeEndLineCap = $round; $prompt.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round
        [void]$canvas.Children.Add($frame); [void]$canvas.Children.Add($prompt)
    } else { return $null }
    $box = New-Object System.Windows.Controls.Viewbox
    $box.Width = $IconSize; $box.Height = $IconSize; $box.Child = $canvas
    $box.HorizontalAlignment = 'Center'; $box.VerticalAlignment = 'Center'
    $box
}

function New-AgentRing {
    param([double]$Size = 60, [double]$Stroke = 5, [switch]$Ticks, [string]$Icon = $null, [double]$IconSize = 0)
    Initialize-AgentViewWpf
    $theme = Get-AgentViewTheme
    $geo = Get-AgentRingRadius $Size $Stroke -Ticks:$Ticks
    $c = $geo.Center; $r = $geo.Radius
    $round = [System.Windows.Media.PenLineCap]::Round

    $root = New-Object System.Windows.Controls.Grid
    $root.Width = $Size; $root.Height = $Size; $root.ClipToBounds = $false
    $root.SnapsToDevicePixels = $false

    # Quầng thở: Ellipse RadialGradient phía sau vòng, tràn 30% mỗi phía.
    $glow = New-Object System.Windows.Shapes.Ellipse
    $glow.Width = $Size * 1.6; $glow.Height = $Size * 1.6
    $glow.Margin = New-Object System.Windows.Thickness (-0.3 * $Size)
    $glow.IsHitTestVisible = $false; $glow.Opacity = 0
    $glow.RenderTransformOrigin = New-Object System.Windows.Point 0.5, 0.5
    $glowScale = New-Object System.Windows.Media.ScaleTransform 1, 1
    $glow.RenderTransform = $glowScale

    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = $Size; $canvas.Height = $Size
    $canvas.RenderTransformOrigin = New-Object System.Windows.Point 0.5, 0.5
    $rotate = New-Object System.Windows.Media.RotateTransform 0
    $canvas.RenderTransform = $rotate

    $track = New-Object System.Windows.Shapes.Path
    $track.Data = New-Object System.Windows.Media.EllipseGeometry ((New-Object System.Windows.Point $c, $c), $r, $r)
    $track.StrokeThickness = $Stroke

    $figure = New-Object System.Windows.Media.PathFigure
    $figure.IsClosed = $false; $figure.IsFilled = $false
    $pathGeo = New-Object System.Windows.Media.PathGeometry
    $pathGeo.Figures.Add($figure)
    $arc = New-Object System.Windows.Shapes.Path
    $arc.Data = $pathGeo; $arc.StrokeThickness = $Stroke
    $arc.StrokeStartLineCap = $round; $arc.StrokeEndLineCap = $round

    [void]$canvas.Children.Add($track); [void]$canvas.Children.Add($arc)
    $tickLines = @()
    if ($Ticks) {
        $tickBrush = ConvertTo-AgentViewBrush $theme['av-text-3']
        foreach ($p in 30, 10) {
            $t = Get-AgentRingTickLine $c $r $Stroke $p
            $line = New-Object System.Windows.Shapes.Line
            $line.X1 = $t.X1; $line.Y1 = $t.Y1; $line.X2 = $t.X2; $line.Y2 = $t.Y2
            $line.Stroke = $tickBrush; $line.StrokeThickness = 1.5
            $line.StrokeStartLineCap = $round; $line.StrokeEndLineCap = $round
            [void]$canvas.Children.Add($line); $tickLines += $line
        }
    }

    $centerHost = New-Object System.Windows.Controls.Grid
    $iconEl = $null
    if ($Icon) {
        if ($IconSize -le 0) { $IconSize = [math]::Round($Size * 0.43) }
        $iconEl = New-AgentRingIcon $Icon $IconSize $theme
        if ($iconEl) { [void]$centerHost.Children.Add($iconEl) }
    }

    [void]$root.Children.Add($glow); [void]$root.Children.Add($canvas); [void]$root.Children.Add($centerHost)
    $root.Tag = @{
        Kind = 'AgentRing'; Size = $Size; Stroke = $Stroke; Center = $c; Radius = $r; Theme = $theme
        Root = $root; Glow = $glow; GlowScale = $glowScale; Canvas = $canvas; Rotate = $rotate
        Track = $track; Arc = $arc; Figure = $figure; Ticks = $tickLines; CenterHost = $centerHost; Icon = $iconEl
        State = 'error'; Value = 0.0; Style = $null; Timer = $null; Suspended = $false
    }
    Set-AgentRing -Ring $root -State 'error'
    $root
}

# Dựng lại hình học cung ở giá trị v (0..100).
function Update-AgentRingArc($RingState, [double]$Value) {
    $plan = Get-AgentArcPlan $RingState.Center $RingState.Radius $Value
    $fig = $RingState.Figure
    $fig.StartPoint = New-Object System.Windows.Point $plan.Start.X, $plan.Start.Y
    $fig.Segments.Clear()
    $size = New-Object System.Windows.Size $RingState.Radius, $RingState.Radius
    foreach ($s in $plan.Segments) {
        $seg = New-Object System.Windows.Media.ArcSegment ((New-Object System.Windows.Point $s.Point.X, $s.Point.Y), $size, 0, $s.IsLargeArc, ([System.Windows.Media.SweepDirection]::Clockwise), $true)
        $fig.Segments.Add($seg)
    }
    $RingState.Arc.Opacity = $(if ($plan.Visible) { 1 } else { 0 })
}

function Stop-AgentRingLoops($RingState) {
    $RingState.Glow.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $RingState.GlowScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null)
    $RingState.GlowScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $null)
    $RingState.Glow.Opacity = 0
    $RingState.Rotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $RingState.Rotate.Angle = 0
}

function Start-AgentRingLoops($RingState) {
    $style = $RingState.Style
    if (-not $style -or $RingState.Suspended) { return }
    if ($style.Glow) {
        $ease = New-Object System.Windows.Media.Animation.SineEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
        $dur = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($style.GlowHalfMs))
        $op = New-Object System.Windows.Media.Animation.DoubleAnimation 0.08, 0.34, $dur
        $sc = New-Object System.Windows.Media.Animation.DoubleAnimation 0.9, 1.04, $dur
        foreach ($a in $op, $sc) { $a.AutoReverse = $true; $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever; $a.EasingFunction = $ease }
        $RingState.Glow.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $op)
        $RingState.GlowScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $sc)
        $RingState.GlowScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $sc)
    }
    if ($style.Spin) {
        $spin = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 360, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(1000)))
        $spin.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $RingState.Rotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
    }
}

# Dừng mọi hoạt ảnh lặp (khi cửa sổ chứa vòng ẩn) để idle CPU ~0.
function Suspend-AgentRing($Ring) {
    $s = $Ring.Tag
    $s.Suspended = $true
    Stop-AgentRingLoops $s
}
function Resume-AgentRing($Ring) {
    $s = $Ring.Tag
    if (-not $s.Suspended) { return }
    $s.Suspended = $false
    Start-AgentRingLoops $s
}

function Set-AgentRing {
    param(
        $Ring,
        [ValidateSet('ok', 'error', 'loading')][string]$State,
        $Value = $null,
        [double]$DurationMs = 450,
        $From = $null,
        [scriptblock]$OnTick = $null
    )
    $s = $Ring.Tag
    if ($s.Timer) { $s.Timer.Stop(); $s.Timer = $null }
    if ($State -eq 'ok' -and $null -eq $Value) { $State = 'error' }
    $style = Get-AgentRingStyle $State $Value $s.Theme
    $prev = $s.Style
    $s.State = $State; $s.Style = $style

    $s.Track.Stroke = ConvertTo-AgentViewBrush $style.Track
    if ($style.Dashed) {
        $dash = New-Object System.Windows.Media.DoubleCollection
        foreach ($d in (Get-AgentRingDash $s.Radius $s.Stroke)) { $dash.Add($d) }
        $s.Track.StrokeDashArray = $dash
    } else { $s.Track.StrokeDashArray = $null }

    $grad = New-Object System.Windows.Media.LinearGradientBrush
    $grad.MappingMode = [System.Windows.Media.BrushMappingMode]::Absolute
    $grad.StartPoint = New-Object System.Windows.Point 0, 0
    $grad.EndPoint = New-Object System.Windows.Point $s.Size, $s.Size
    $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop (ConvertTo-AgentViewColor $style.Lv), 0))
    $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop (ConvertTo-AgentViewColor $style.Hi), 1))
    $grad.Freeze()
    $s.Arc.Stroke = $grad

    foreach ($t in $s.Ticks) { $t.Visibility = $(if ($style.TicksVisible) { 'Visible' } else { 'Collapsed' }) }
    $s.CenterHost.Opacity = $style.CenterOpacity

    if ($style.Glow) {
        $glowBrush = New-Object System.Windows.Media.RadialGradientBrush
        $glowBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop (ConvertTo-AgentViewColor $style.Lv), 0))
        $glowBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop (ConvertTo-AgentViewColor $style.Lv 0), 1))
        $glowBrush.Freeze()
        $s.Glow.Fill = $glowBrush
    }
    # Chỉ khởi động lại vòng lặp khi kiểu lặp đổi (tránh giật quầng thở mỗi lần cập nhật).
    $loopChanged = (-not $prev) -or ($prev.GlowHalfMs -ne $style.GlowHalfMs) -or ($prev.Spin -ne $style.Spin)
    if ($loopChanged) { Stop-AgentRingLoops $s; Start-AgentRingLoops $s }

    if ($State -eq 'loading') { Update-AgentRingArc $s 25; return }
    if ($State -eq 'error') { $s.Value = 0.0; Update-AgentRingArc $s 0; return }

    $target = [math]::Max(0, [math]::Min(100, [double]$Value))
    $a = $s.Value; if ($null -ne $From) { $a = [double]$From }
    if ($DurationMs -le 0 -or $a -eq $target) {
        $s.Value = $target; Update-AgentRingArc $s $target
        if ($OnTick) { & $OnTick $target }
        return
    }
    $s.Value = $a; Update-AgentRingArc $s $a
    if ($OnTick) { & $OnTick $a }
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $timer = New-Object System.Windows.Threading.DispatcherTimer ([System.Windows.Threading.DispatcherPriority]::Render)
    $timer.Interval = [TimeSpan]::FromMilliseconds(15)
    $timer.Tag = @{ Ring = $s; A = $a; B = $target; Dur = $DurationMs; Clock = [Diagnostics.Stopwatch]::StartNew(); Ease = $ease; OnTick = $OnTick }
    $timer.Add_Tick({
        $t = $this.Tag
        $k = [math]::Min(1.0, $t.Clock.Elapsed.TotalMilliseconds / $t.Dur)
        $v = $t.A + ($t.B - $t.A) * $t.Ease.Ease($k)
        if ($k -ge 1) { $v = $t.B; $this.Stop(); if ($t.Ring.Timer -eq $this) { $t.Ring.Timer = $null } }
        $t.Ring.Value = $v
        Update-AgentRingArc $t.Ring $v
        if ($t.OnTick) { try { & $t.OnTick $v } catch { } }
    })
    $s.Timer = $timer
    $timer.Start()
}
