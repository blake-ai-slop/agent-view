. (Join-Path $PSScriptRoot 'I18n.ps1')
Register-AgentViewStrings -Module 'popup' -Strings @{
    en = @{
        'refresh' = 'Refresh'
        'settings' = 'Settings'
        'left' = '{0} left'
        'remaining' = 'remaining'
        'retry' = 'Retry'

        'no_data_yet' = 'No data yet'
        'weekly_limit_only' = 'Weekly limit only'
        '5_hour_limit_only' = '5-hour limit only'
        'tightest_limit' = 'Tightest limit: {0}'
        'reading_quota' = 'Reading quota…'
        'no_fresh_data' = 'No fresh data'
        'last_known_left' = 'Last known: {0}% left'
        'no_data_available' = 'No data available.'
        'cannot_read_quota' = 'Cannot read quota'
        'loading' = 'Loading…'
        'updating' = 'Updating…'
        'not_updated_yet' = 'Not updated yet'
        'updated' = 'Updated '
        'errors' = ' · errors'
        '5_hours' = '5 hours'
        'week' = 'Week'
        'update_chip' = 'v{0} ↑'
        'update_tip' = 'Update available: v{0}'
    }
    vi = @{
        'refresh' = 'Làm mới'
        'settings' = 'Cài đặt'
        'left' = 'còn {0}'
        'remaining' = 'còn lại'
        'retry' = 'Thử lại'

        'no_data_yet' = 'Chưa có dữ liệu'
        'weekly_limit_only' = 'Chỉ giới hạn tuần'
        '5_hour_limit_only' = 'Chỉ giới hạn 5 giờ'
        'tightest_limit' = 'Giới hạn sát nhất: {0}'
        'reading_quota' = 'Đang đọc quota…'
        'no_fresh_data' = 'Không có số liệu mới'
        'last_known_left' = 'Số liệu cuối: còn {0}%'
        'no_data_available' = 'Không có số liệu.'
        'cannot_read_quota' = 'Không đọc được quota'
        'loading' = 'Đang tải…'
        'updating' = 'Đang cập nhật…'
        'not_updated_yet' = 'Chưa cập nhật'
        'updated' = 'Cập nhật '
        'errors' = ' · có lỗi'
        '5_hours' = '5 giờ'
        'week' = 'Tuần'
        'update_chip' = 'v{0} ↑'
        'update_tip' = 'Có bản mới: v{0}'
    }
}
# Popup quota (thiết kế Bezel mục 02) — WPF trên Windows PowerShell 5.1, sống trong vòng message WinForms của tray.
# Dot-source chỉ định nghĩa hàm. Hợp đồng: Show-/Update-/Hide-AgentViewPopup, Test-AgentViewPopupOpen.
. (Join-Path $PSScriptRoot 'Ring.ps1')
. (Join-Path $PSScriptRoot 'Format.ps1')
. (Join-Path $PSScriptRoot 'History.ps1')
. (Join-Path $PSScriptRoot 'Forecast.ps1')

# ---------------------------------------------------------------- hằng số bố cục (khớp Spec 04)
function Get-AgentViewPopupMetrics {
    @{
        Width = 360; Gap = 12                                 # rộng popup; cách mép phải / đỉnh taskbar
        ShadowLeft = 28; ShadowTop = 16; ShadowRight = 28; ShadowBottom = 44   # lề trong suốt cho DropShadow
        BarWidth = 306                                        # 360 − viền 2 − thân 24 − viền thẻ 2 − padding thẻ 26
        InMs = 200; OutMs = 140; CardMs = 260; CardStaggerMs = 60; OpenMs = 700; UpdateMs = 450; SpinMs = 700
        DeactivateGuardMs = 300                               # bấm icon khay ngay sau khi mất focus = đóng, không mở lại
        FontText = 'Segoe UI Variable Text, Segoe UI'; FontDisplay = 'Segoe UI Variable Display, Segoe UI'
    }
}

# ---------------------------------------------------------------- hàm thuần (test không cần cửa sổ)
# Vị trí cửa sổ (đã gồm lề bóng) để mép popup cách góc dưới phải WorkArea 12px.
function Get-AgentViewPopupPlacement($WorkArea, [double]$WindowHeight) {
    $m = Get-AgentViewPopupMetrics
    [pscustomobject]@{
        Left = $WorkArea.Right - $m.Gap - $m.Width - $m.ShadowLeft
        Top = $WorkArea.Bottom - $m.Gap + $m.ShadowBottom - $WindowHeight
        Width = $m.Width + $m.ShadowLeft + $m.ShadowRight
    }
}

# Empty-state display rows are separate from collection normalization.
function Get-AgentViewEmptyRows {
    foreach ($p in @(@('claude', 'Claude Code'), @('codex', 'Codex'))) {
        [pscustomobject]@{ Provider = $p[0]; Name = $p[1]; Ok = $false; Error = (T 'popup.no_data_yet'); FiveHourUsed = $null; WeekUsed = $null; FiveHourResetsAt = $null; WeekResetsAt = $null; FetchedAt = $null }
    }
}

# Samples: mẫu history đúng provider+cửa sổ; $null ⇒ không dự báo (ForecastKind 'unknown').
function Get-AgentViewWindowModel($Used, $ResetsAt, [datetime]$Now, $Samples = $null, [string]$Window = '5h') {
    $rem = $null
    if ($null -ne $Used) { $rem = [int][math]::Max(0, [math]::Min(100, 100 - [double]$Used)) }
    $level = Get-QuotaLevel $rem
    $rel = $null; $abs = $null
    if ($null -ne $Used -and $null -ne $ResetsAt) {
        $rel = Format-QuotaResetRelative ([datetime]$ResetsAt) $Now
        $a = Format-QuotaResetAbsolute ([datetime]$ResetsAt) $Now
        if ($a) { $abs = '· ' + $a }
    }
    $fKind = 'unknown'; $fText = $null; $fAt = $null
    if ($null -ne $Used -and $null -ne $Samples) {
        $f = Get-AgentViewForecast -Samples $Samples -Used $Used -ResetsAt $ResetsAt -Window $Window -Now $Now
        $fKind = $f.Kind; $fAt = $f.At
        if ($fKind -ne 'unknown') { $fText = Format-AgentViewForecast $f $Now }
    }
    [pscustomobject]@{
        Present = ($null -ne $Used); Remaining = $rem; Level = $level
        ValueText = $(if ($null -eq $rem) { '–' } else { "$rem%" })
        Rel = $rel; Abs = $abs
        ForecastKind = $fKind; ForecastText = $fText; ForecastAt = $fAt
    }
}

# Mô hình hiển thị một thẻ provider: State 'ok'|'error'|'loading' + chuỗi đã dựng.
# History: mẫu Get-AgentViewHistory (mọi provider) để dự báo; $null ⇒ không có dòng dự báo.
function Get-AgentViewCardModel($Row, [switch]$Loading, [datetime]$Now = (Get-Date), $History = $null) {
    $name = $Row.Name; if (-not $name) { $name = [string]$Row.Provider }
    $value = Get-QuotaRemaining $Row
    $state = 'ok'
    if ($Loading) { $state = 'loading' }
    elseif (-not $Row.Ok -or $null -eq $value) { $state = 'error' }
    $level = 'unk'; if ($state -eq 'ok') { $level = Get-QuotaLevel $value }
    $sub = ''
    switch ($state) {
        'ok' { $w = Get-QuotaTightestWindow $Row; if ($null -eq $Row.FiveHourUsed) { $sub = (T 'popup.weekly_limit_only') } elseif ($null -eq $Row.WeekUsed) { $sub = (T 'popup.5_hour_limit_only') } elseif ($w) { $sub = (T 'popup.tightest_limit' -Args @($w)) } }
        'loading' { $sub = (T 'popup.reading_quota') }
        'error' { $sub = (T 'popup.no_fresh_data') }
    }
    $stale = $null
    if ($state -eq 'error' -and $null -ne $value) {
        $stale = (T 'popup.last_known_left' -Args @($value))
        if ($Row.FetchedAt) { $stale += ' · ' + (Format-QuotaAgo ([datetime]$Row.FetchedAt) $Now) }
    }
    $detail = [string]$Row.Error
    if (-not $detail -and $state -eq 'error') { $detail = (T 'popup.no_data_available') }
    $fiveSamples = $null; $weekSamples = $null
    if ($null -ne $History -and $Row.Ok -eq $true) {
        $provider = [string]$Row.Provider
        $fiveSamples = @(@($History) | Where-Object { $null -ne $_ -and $_.p -eq $provider -and $_.w -eq '5h' })
        $weekSamples = @(@($History) | Where-Object { $null -ne $_ -and $_.p -eq $provider -and $_.w -eq 'week' })
    }
    [pscustomobject]@{
        Provider = [string]$Row.Provider; Name = $name; State = $state; Value = $value; Level = $level
        Sub = $sub
        NumText = $(switch ($state) { 'ok' { [string]$value } 'loading' { '00' } default { '–' } })
        Five = Get-AgentViewWindowModel $Row.FiveHourUsed $Row.FiveHourResetsAt $Now $fiveSamples '5h'
        Week = Get-AgentViewWindowModel $Row.WeekUsed $Row.WeekResetsAt $Now $weekSamples 'week'
        ErrTitle = (T 'popup.cannot_read_quota'); ErrDetail = $detail; Stale = $stale
    }
}

# Chip trạng thái theo mức tệ nhất của các provider đọc được.
function Get-AgentViewStatusModel($Rows, [switch]$Loading) {
    if ($Loading) { return [pscustomobject]@{ Level = 'unk'; Text = (T 'popup.loading') } }
    $vals = @(foreach ($r in $Rows) { if ($r.Ok) { $v = Get-QuotaRemaining $r; if ($null -ne $v) { $v } } })
    $level = 'unk'
    if ($vals.Count) { $level = Get-QuotaLevel (($vals | Measure-Object -Minimum).Minimum) }
    [pscustomobject]@{ Level = $level; Text = (Get-QuotaStatusText $level) }
}

function Get-AgentViewFooterModel($Rows, [switch]$Loading, [datetime]$Now = (Get-Date)) {
    $hasError = @($Rows | Where-Object { -not $_.Ok }).Count -gt 0
    if ($Loading) { return [pscustomobject]@{ Text = (T 'popup.updating'); Stale = $false } }
    $times = @($Rows | Where-Object { $_.FetchedAt } | ForEach-Object { [datetime]$_.FetchedAt })
    $text = (T 'popup.not_updated_yet')
    if ($times.Count) { $text = (T 'popup.updated') + (Format-QuotaAgo (($times | Measure-Object -Maximum).Maximum) $Now) }
    if ($hasError) { $text += (T 'popup.errors') }
    [pscustomobject]@{ Text = $text; Stale = $hasError }
}

function Expand-AgentViewXaml([string]$Xaml, $Theme) {
    [regex]::Replace($Xaml, '@@([a-z0-9-]+)@@', { param($m) $Theme[$m.Groups[1].Value] })
}

# ---------------------------------------------------------------- trạng thái (một popup mỗi tiến trình)
# Lưu ở AppDomain để handler sự kiện thấy cùng một bản dù được gọi từ scope/closure nào.
function Get-AgentViewPopupState {
    $st = [AppDomain]::CurrentDomain.GetData('agent-view.popup')
    if ($null -eq $st) {
        $st = @{ Window = $null; Rows = @(); Loading = $false; OnRefresh = $null; OnRetry = $null; OnSettings = $null
                 UpdateVersion = $null; OnUpdate = $null; Closing = $false; DeactivatedAt = 0; Cards = @{}; WorkArea = $null }
        [AppDomain]::CurrentDomain.SetData('agent-view.popup', $st)
    }
    $st
}

# ---------------------------------------------------------------- XAML

function Get-AgentViewPopupXaml {
    $m = Get-AgentViewPopupMetrics
    $w = $m.Width + $m.ShadowLeft + $m.ShadowRight
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Title="agent-view" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" Topmost="True"
  ResizeMode="NoResize" SizeToContent="Height" Width="$w" ShowActivated="True" UseLayoutRounding="True"
  FontFamily="$($m.FontText)" FontSize="12" Foreground="@@av-text@@">
 <Window.Resources>
  <Style x:Key="IconBtn" TargetType="Button">
   <Setter Property="Width" Value="32"/><Setter Property="Height" Value="32"/>
   <Setter Property="Foreground" Value="@@av-text-2@@"/><Setter Property="Background" Value="Transparent"/>
   <Setter Property="Focusable" Value="False"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
     <ContentPresenter x:Name="cp" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5"/>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="@@av-surface-hi@@"/><Setter Property="Foreground" Value="@@av-text@@"/></Trigger>
     <Trigger Property="IsPressed" Value="True"><Setter TargetName="cp" Property="RenderTransform"><Setter.Value><ScaleTransform ScaleX="0.9" ScaleY="0.9"/></Setter.Value></Setter></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="TextBtn" TargetType="Button">
   <Setter Property="Height" Value="28"/><Setter Property="Padding" Value="12,0"/><Setter Property="FontSize" Value="12"/>
   <Setter Property="Foreground" Value="@@av-text@@"/><Setter Property="Background" Value="@@av-surface-hi@@"/>
   <Setter Property="BorderBrush" Value="@@av-stroke@@"/><Setter Property="Focusable" Value="False"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
     <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#2A3040"/><Setter TargetName="bd" Property="BorderBrush" Value="#394052"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
 </Window.Resources>
 <Border x:Name="Shell" Width="$($m.Width)" Margin="$($m.ShadowLeft),$($m.ShadowTop),$($m.ShadowRight),$($m.ShadowBottom)" CornerRadius="8" BorderThickness="1" BorderBrush="@@av-stroke@@" RenderTransformOrigin="1,1">
  <Border.Background><LinearGradientBrush MappingMode="Absolute" StartPoint="0,0" EndPoint="0,96"><GradientStop Color="@@av-bg-top@@" Offset="0"/><GradientStop Color="@@av-bg@@" Offset="1"/></LinearGradientBrush></Border.Background>
  <Border.Effect><DropShadowEffect BlurRadius="32" ShadowDepth="12" Direction="270" Opacity="0.55" Color="Black"/></Border.Effect>
  <Border.RenderTransform><TransformGroup><ScaleTransform x:Name="ShellScale" ScaleX="1" ScaleY="1"/><TranslateTransform x:Name="ShellShift"/></TransformGroup></Border.RenderTransform>
  <StackPanel>
   <Grid Margin="16,12,10,8">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
     <ContentControl x:Name="BrandRing" Width="16" Height="16" VerticalAlignment="Center" Focusable="False"/>
     <TextBlock Text="agent-view" Margin="8,0,0,0" FontFamily="$($m.FontDisplay)" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
    </StackPanel>
    <Border Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center" CornerRadius="999" Padding="7,2,9,2" Background="@@av-surface@@" BorderBrush="@@av-stroke-soft@@" BorderThickness="1">
     <StackPanel Orientation="Horizontal">
      <Ellipse x:Name="StatusDot" Width="7" Height="7" VerticalAlignment="Center"/>
      <TextBlock x:Name="StatusText" Margin="6,0,0,0" FontSize="11.5" Foreground="@@av-text-2@@" VerticalAlignment="Center"/>
     </StackPanel>
    </Border>
    <Border x:Name="UpdateChip" Grid.Column="2" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="8,0,0,0" Visibility="Collapsed" Cursor="Hand"
            CornerRadius="999" Padding="7,1,7,2" BorderThickness="1">
     <TextBlock x:Name="UpdateChipText" FontSize="11" FontWeight="SemiBold" Foreground="@@accent@@" VerticalAlignment="Center" Typography.NumeralAlignment="Tabular"/>
    </Border>
    <Button x:Name="RefreshBtn" Grid.Column="3" Margin="10,0,0,0" Style="{StaticResource IconBtn}" ToolTip="$(T 'popup.refresh')">
     <Canvas Width="16" Height="16" RenderTransformOrigin="0.5,0.5">
      <Canvas.RenderTransform><RotateTransform x:Name="RefreshRot"/></Canvas.RenderTransform>
      <Path Data="M13.5,8 A5.5,5.5 0 1 1 11.9,4.1 M13.5,2.5 V5.5 H10.5" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"
            Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
     </Canvas>
    </Button>
    <Button x:Name="SettingsBtn" Grid.Column="4" Margin="10,0,0,0" Style="{StaticResource IconBtn}" ToolTip="$(T 'popup.settings')">
     <Canvas Width="16" Height="16">
      <Path StrokeThickness="1.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"
            Data="M10.2,8 A2.2,2.2 0 1 1 5.8,8 A2.2,2.2 0 1 1 10.2,8 M8,1.8 V3.4 M8,12.6 V14.2 M14.2,8 H12.6 M3.4,8 H1.8 M12.4,3.6 L11.3,4.7 M4.7,11.3 L3.6,12.4 M12.4,12.4 L11.3,11.3 M4.7,4.7 L3.6,3.6"/>
     </Canvas>
    </Button>
   </Grid>
   <StackPanel x:Name="Cards" Margin="12,4,12,0"/>
   <StackPanel Orientation="Horizontal" Margin="16,10,16,12">
    <Ellipse x:Name="LiveDot" Width="6" Height="6" VerticalAlignment="Center"/>
    <TextBlock x:Name="FootText" Margin="8,0,0,0" FontSize="11.5" Foreground="@@av-text-3@@" VerticalAlignment="Center" Typography.NumeralAlignment="Tabular"/>
   </StackPanel>
  </StackPanel>
 </Border>
</Window>
"@
}

function Get-AgentViewMeterXaml([string]$Prefix, [string]$Label) {
    $m = Get-AgentViewPopupMetrics
    $t30 = $m.BarWidth * 0.3; $t10 = $m.BarWidth * 0.1
    $valueRun = "<Run x:Name=`"${Prefix}Value`" FontWeight=`"SemiBold`" Foreground=`"@@av-text@@`"/>"
    @"
<StackPanel x:Name="${Prefix}Block">
 <Grid Margin="0,0,0,5">
  <TextBlock Text="$Label" FontSize="12" Foreground="@@av-text-2@@"/>
  <TextBlock x:Name="${Prefix}Line" HorizontalAlignment="Right" FontSize="12" Foreground="@@av-text-2@@" Typography.NumeralAlignment="Tabular">$(T 'popup.left' -Args @($valueRun))</TextBlock>
 </Grid>
 <Grid Height="6" ClipToBounds="True">
  <Border x:Name="${Prefix}Track" CornerRadius="3" Background="@@av-track@@"/>
  <Border x:Name="${Prefix}Fill" CornerRadius="3" HorizontalAlignment="Left" Width="0"/>
  <Canvas x:Name="${Prefix}Ticks" IsHitTestVisible="False">
   <Rectangle Canvas.Left="$t30" Width="1" Height="6" Fill="@@av-bg@@" Opacity="0.9"/>
   <Rectangle Canvas.Left="$t10" Width="1" Height="6" Fill="@@av-bg@@" Opacity="0.9"/>
  </Canvas>
 </Grid>
 <StackPanel x:Name="${Prefix}Reset" Orientation="Horizontal" Margin="0,5,0,0">
  <Viewbox Width="11" Height="11" VerticalAlignment="Center"><Canvas Width="12" Height="12">
   <Path Data="M2,6 A4,4 0 1 0 3.2,3.15 M2,1.8 V4.2 H4.4" Stroke="@@av-text-3@@" StrokeThickness="1.3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
  </Canvas></Viewbox>
  <TextBlock x:Name="${Prefix}Rel" Margin="5,0,0,0" FontSize="11.5" Foreground="@@av-text-2@@" Typography.NumeralAlignment="Tabular" VerticalAlignment="Center"/>
  <TextBlock x:Name="${Prefix}Abs" Margin="5,0,0,0" FontSize="11.5" Foreground="@@av-text-3@@" Typography.NumeralAlignment="Tabular" VerticalAlignment="Center"/>
 </StackPanel>
 <TextBlock x:Name="${Prefix}Forecast" Visibility="Collapsed" Margin="16,3,0,0" FontSize="11.5" Foreground="@@av-text-3@@" Typography.NumeralAlignment="Tabular" TextTrimming="CharacterEllipsis"/>
</StackPanel>
"@
}

function Get-AgentViewCardXaml {
    $m = Get-AgentViewPopupMetrics
    $five = Get-AgentViewMeterXaml 'Five' (T 'popup.5_hours')
    $week = Get-AgentViewMeterXaml 'Week' (T 'popup.week')
    @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  CornerRadius="10" BorderThickness="1" BorderBrush="@@av-stroke-soft@@" Background="@@av-surface@@" Padding="12,12,14,12"
  TextElement.FontFamily="$($m.FontText)" TextElement.Foreground="@@av-text@@">
 <Border.RenderTransform><TranslateTransform x:Name="Shift"/></Border.RenderTransform>
 <StackPanel>
  <Grid>
   <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <ContentControl x:Name="RingHost" Width="60" Height="60" VerticalAlignment="Center" Focusable="False"/>
   <StackPanel Grid.Column="1" Margin="12,0,12,0" VerticalAlignment="Center">
    <TextBlock x:Name="NameText" FontSize="14" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
    <TextBlock x:Name="SubText" Margin="0,2,0,0" FontSize="11.5" Foreground="@@av-text-3@@" TextTrimming="CharacterEllipsis"/>
   </StackPanel>
   <StackPanel Grid.Column="2" VerticalAlignment="Center">
    <Border x:Name="NumWrap" CornerRadius="6" HorizontalAlignment="Right">
     <TextBlock FontFamily="$($m.FontDisplay)" FontWeight="SemiBold" Typography.NumeralAlignment="Tabular" LineStackingStrategy="BlockLineHeight" LineHeight="30"><Run x:Name="BigNum" FontSize="30"/><Run x:Name="BigPct" Text="%" FontSize="15"/></TextBlock>
    </Border>
    <TextBlock Text="$(T 'popup.remaining')" HorizontalAlignment="Right" Margin="0,4,0,0" FontSize="11" Foreground="@@av-text-3@@"/>
   </StackPanel>
  </Grid>
  <StackPanel x:Name="Meters" Margin="0,12,0,0">
   $five
   <Border x:Name="MeterGap" Height="10"/>
   $week
  </StackPanel>
  <Border x:Name="ErrBox" Visibility="Collapsed" Margin="0,12,0,0" Background="@@err-bg@@" BorderBrush="@@err-stroke@@" BorderThickness="1" CornerRadius="8" Padding="12,10,10,10">
   <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <Border Width="20" Height="20" CornerRadius="10" Background="@@crit@@" VerticalAlignment="Top" Margin="0,1,0,0">
     <TextBlock Text="!" FontFamily="$($m.FontDisplay)" FontWeight="Bold" FontSize="13" Foreground="#1A0B0C" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <StackPanel Grid.Column="1" Margin="10,0,10,0">
     <TextBlock x:Name="ErrTitle" FontSize="13" FontWeight="SemiBold" TextWrapping="Wrap"/>
     <TextBlock x:Name="ErrDetail" Margin="0,2,0,0" FontSize="12" Foreground="@@av-text-2@@" TextWrapping="Wrap"/>
     <TextBlock x:Name="ErrStale" Margin="0,2,0,0" FontSize="11.5" Foreground="@@av-text-3@@" TextWrapping="Wrap" Typography.NumeralAlignment="Tabular"/>
    </StackPanel>
    <Button x:Name="RetryBtn" Grid.Column="2" Content="$(T 'popup.retry')" VerticalAlignment="Top"/>
   </Grid>
  </Border>
 </StackPanel>
</Border>
"@
}

# ---------------------------------------------------------------- dựng cửa sổ
function New-AgentViewShimmerBrush($Theme) {
    $b = New-Object System.Windows.Media.LinearGradientBrush
    $b.StartPoint = New-Object System.Windows.Point 0, 0
    $b.EndPoint = New-Object System.Windows.Point 2, 0        # ảnh gradient rộng 200%
    $b.GradientStops.Add((New-Object System.Windows.Media.GradientStop (ConvertTo-AgentViewColor $Theme['av-track']), 0))
    $b.GradientStops.Add((New-Object System.Windows.Media.GradientStop (ConvertTo-AgentViewColor '#343B4D'), 0.5))
    $b.GradientStops.Add((New-Object System.Windows.Media.GradientStop (ConvertTo-AgentViewColor $Theme['av-track']), 1))
    $shift = New-Object System.Windows.Media.TranslateTransform -1, 0
    $b.RelativeTransform = $shift
    @{ Brush = $b; Shift = $shift; Running = $false }
}

function New-AgentViewPopupWindow {
    Initialize-AgentViewWpf
    $st = Get-AgentViewPopupState
    $theme = Get-AgentViewTheme
    $window = [System.Windows.Markup.XamlReader]::Parse((Expand-AgentViewXaml (Get-AgentViewPopupXaml) $theme))
    $ui = @{}
    foreach ($n in 'Shell', 'ShellScale', 'ShellShift', 'BrandRing', 'StatusDot', 'StatusText', 'RefreshBtn', 'RefreshRot', 'SettingsBtn', 'Cards', 'LiveDot', 'FootText', 'UpdateChip', 'UpdateChipText') {
        $ui[$n] = $window.FindName($n)
    }
    $brand = New-AgentRing -Size 16 -Stroke 2.5
    Set-AgentRing -Ring $brand -State ok -Value 76 -DurationMs 0   # dấu thương hiệu tĩnh theo thiết kế
    $ui.BrandRing.Content = $brand
    $st.Window = $window; $st.Ui = $ui; $st.Theme = $theme; $st.Cards = @{}; $st.Order = @()
    $st.Shimmer = New-AgentViewShimmerBrush $theme

    $st.DeactivatedHandler = [EventHandler]{
        $s = Get-AgentViewPopupState
        if ($s.Window -and $s.Window.IsVisible -and -not $s.Closing) {
            $s.DeactivatedAt = [Environment]::TickCount
            Hide-AgentViewPopup
        }
    }
    $window.Add_Deactivated($st.DeactivatedHandler)
    $window.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $_.Handled = $true; Hide-AgentViewPopup }
    })
    $st.ClosingHandler = [System.ComponentModel.CancelEventHandler]{ $_.Cancel = $true; Hide-AgentViewPopup }
    $window.Add_Closing($st.ClosingHandler)   # Alt+F4 chỉ ẩn, giữ cửa sổ dùng lại
    $st.SizeChangedHandler = [System.Windows.SizeChangedEventHandler]{
        $s = Get-AgentViewPopupState
        if ($s.WorkArea) { $s.Window.Top = (Get-AgentViewPopupPlacement $s.WorkArea $s.Window.ActualHeight).Top }
    }
    $window.Add_SizeChanged($st.SizeChangedHandler)
    $ui.RefreshBtn.Add_Click({
        $s = Get-AgentViewPopupState
        $m = Get-AgentViewPopupMetrics
        $spin = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 360, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($m.SpinMs)))
        $ease = New-Object System.Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'; $spin.EasingFunction = $ease
        $spin.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $s.Ui.RefreshRot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
        if ($s.OnRefresh) { try { & $s.OnRefresh } catch { } }
    })
    $ui.SettingsBtn.Add_Click({
        $s = Get-AgentViewPopupState
        $cb = $s.OnSettings
        if ($cb) { Hide-AgentViewPopup; try { & $cb } catch { } }
    })
    $st.UpdateChipHandler = [System.Windows.Input.MouseButtonEventHandler]{
        $_.Handled = $true
        $s = Get-AgentViewPopupState
        $cb = $s.OnUpdate
        if ($cb -and $s.UpdateVersion) { Hide-AgentViewPopup; try { & $cb } catch { } }
    }
    $ui.UpdateChip.Background = ConvertTo-AgentViewBrush $theme['accent'] 0.14
    $ui.UpdateChip.BorderBrush = ConvertTo-AgentViewBrush $theme['accent'] 0.5
    $ui.UpdateChip.Add_MouseLeftButtonUp($st.UpdateChipHandler)
    $footTimer = New-Object System.Windows.Threading.DispatcherTimer
    $footTimer.Interval = [TimeSpan]::FromSeconds(20)
    $footTimer.Add_Tick({ Update-AgentViewPopupText })
    $st.FootTimer = $footTimer
    try { [System.Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($window) } catch { }
    $window
}

function New-AgentViewCard([string]$Provider) {
    $st = Get-AgentViewPopupState
    $root = [System.Windows.Markup.XamlReader]::Parse((Expand-AgentViewXaml (Get-AgentViewCardXaml) $st.Theme))
    $c = @{ Root = $root; Provider = $Provider }
    foreach ($n in 'Shift', 'RingHost', 'NameText', 'SubText', 'NumWrap', 'BigNum', 'BigPct', 'Meters', 'ErrBox', 'ErrTitle', 'ErrDetail', 'ErrStale', 'RetryBtn',
                   'FiveBlock', 'WeekBlock', 'MeterGap', 'FiveLine', 'FiveValue', 'FiveTrack', 'FiveFill', 'FiveTicks', 'FiveReset', 'FiveRel', 'FiveAbs', 'FiveForecast',
                   'WeekLine', 'WeekValue', 'WeekTrack', 'WeekFill', 'WeekTicks', 'WeekReset', 'WeekRel', 'WeekAbs', 'WeekForecast') {
        $c[$n] = $root.FindName($n)
    }
    $icon = $null; if (@('claude', 'codex') -contains $Provider) { $icon = $Provider }
    $c.Ring = New-AgentRing -Size 60 -Stroke 5 -Ticks -Icon $icon -IconSize 26
    $c.RingHost.Content = $c.Ring
    $c.RetryBtn.Style = $st.Window.Resources['TextBtn']
    $c.RetryBtn.Tag = $Provider
    $c.RetryBtn.Add_Click({
        $s = Get-AgentViewPopupState
        if ($s.OnRetry) { try { & $s.OnRetry ([string]$this.Tag) } catch { } }
    })
    $root.Tag = $c
    $c
}

function New-AgentViewDoubleAnimation([double]$From, [double]$To, [double]$Ms, [string]$Ease = 'CubicOut', [double]$DelayMs = 0) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation $From, $To, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($Ms)))
    switch ($Ease) {
        'CubicOut' { $e = New-Object System.Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseOut' }
        'CubicIn' { $e = New-Object System.Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseIn' }
        'QuinticOut' { $e = New-Object System.Windows.Media.Animation.QuinticEase; $e.EasingMode = 'EaseOut' }
    }
    $a.EasingFunction = $e
    if ($DelayMs -gt 0) { $a.BeginTime = [TimeSpan]::FromMilliseconds($DelayMs) }
    $a
}

# Màu dòng dự báo: 'runout' ⇒ crit nếu cửa sổ đã crit, ngược lại warn; 'enough' ⇒ chữ phụ; 'unknown' ⇒ ẩn.
function Get-AgentViewForecastColorKey($Window) {
    switch ($Window.ForecastKind) {
        'runout' { if ($Window.Level -eq 'crit') { return 'crit' }; return 'warn' }
        'enough' { return 'av-text-3' }
    }
    return $null
}

function Set-AgentViewForecastLine($Block, $Window) {
    $key = Get-AgentViewForecastColorKey $Window
    if (-not $key -or -not $Window.ForecastText) { $Block.Text = ''; $Block.Visibility = 'Collapsed'; return }
    $st = Get-AgentViewPopupState
    $Block.Text = [string]$Window.ForecastText
    $Block.Foreground = ConvertTo-AgentViewBrush $st.Theme[$key]
    $Block.Visibility = 'Visible'
}

function Set-AgentViewMeter($Card, [string]$Prefix, $Window, [string]$State, [string]$Mode) {
    $st = Get-AgentViewPopupState
    $m = Get-AgentViewPopupMetrics
    $Card["${Prefix}Value"].Text = $Window.ValueText
    $Card["${Prefix}Rel"].Text = [string]$Window.Rel
    $Card["${Prefix}Abs"].Text = [string]$Window.Abs
    Set-AgentViewForecastLine $Card["${Prefix}Forecast"] $Window
    $fill = $Card["${Prefix}Fill"]
    if ($State -eq 'loading') {
        $Card["${Prefix}Track"].Background = $st.Shimmer.Brush
        $fill.Visibility = 'Hidden'; $Card["${Prefix}Ticks"].Visibility = 'Hidden'
        $Card["${Prefix}Line"].Opacity = 0.35; $Card["${Prefix}Reset"].Opacity = 0.35; $Card["${Prefix}Forecast"].Opacity = 0.35
        return
    }
    $Card["${Prefix}Track"].Background = ConvertTo-AgentViewBrush $st.Theme['av-track']
    $fill.Visibility = 'Visible'; $Card["${Prefix}Ticks"].Visibility = 'Visible'
    $Card["${Prefix}Line"].Opacity = 1; $Card["${Prefix}Reset"].Opacity = 1; $Card["${Prefix}Forecast"].Opacity = 1
    $colors = Get-AgentViewLevelColors $Window.Level $st.Theme
    $grad = New-Object System.Windows.Media.LinearGradientBrush ((ConvertTo-AgentViewColor $colors.Lv), (ConvertTo-AgentViewColor $colors.Hi), 0.0)
    $grad.Freeze(); $fill.Background = $grad
    $target = 0.0; if ($State -eq 'ok' -and $null -ne $Window.Remaining) { $target = $m.BarWidth * $Window.Remaining / 100 }
    $from = 0.0
    if ($Mode -ne 'open') { $from = $fill.Width; if ([double]::IsNaN($from)) { $from = 0.0 } }
    if ($Mode -eq 'static') { $fill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $null); $fill.Width = $target; return }
    $ms = $m.UpdateMs; $ease = 'CubicOut'; if ($Mode -eq 'open') { $ms = $m.OpenMs; $ease = 'QuinticOut' }
    $fill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, (New-AgentViewDoubleAnimation $from $target $ms $ease))
}

# Áp mô hình lên thẻ. Mode: 'open' (vòng + số chạy từ 0, 700ms), 'update' (từ giá trị cũ, 450ms), 'static' (không tween).
function Set-AgentViewCard($Card, $Model, [string]$Mode = 'update') {
    $st = Get-AgentViewPopupState
    $m = Get-AgentViewPopupMetrics
    $theme = $st.Theme
    $colors = Get-AgentViewLevelColors $Model.Level $theme
    $Card.NameText.Text = $Model.Name
    $Card.SubText.Text = $Model.Sub
    $Card.RetryBtn.Tag = $Model.Provider
    $num = $Card.BigNum
    $Card.FiveBlock.Visibility = $(if ($Model.Five.Present) { 'Visible' } else { 'Collapsed' })
    $Card.WeekBlock.Visibility = $(if ($Model.Week.Present) { 'Visible' } else { 'Collapsed' })
    $Card.MeterGap.Visibility = $(if ($Model.Five.Present -and $Model.Week.Present) { 'Visible' } else { 'Collapsed' })
    $Card.Meters.Visibility = $(if ($Model.State -eq 'error') { 'Collapsed' } else { 'Visible' })
    $Card.ErrBox.Visibility = $(if ($Model.State -eq 'error') { 'Visible' } else { 'Collapsed' })
    switch ($Model.State) {
        'ok' {
            $Card.NumWrap.Background = $null
            $num.Foreground = ConvertTo-AgentViewBrush $colors.Lv
            $Card.BigPct.Foreground = ConvertTo-AgentViewBrush $colors.Lv 0.85
            $dur = $m.UpdateMs; $from = $null
            if ($Mode -eq 'open') { $dur = $m.OpenMs; $from = 0 }
            if ($Mode -eq 'static') { $dur = 0 }
            $tick = { param($v) $num.Text = [string][int][math]::Round($v, [MidpointRounding]::AwayFromZero) }.GetNewClosure()
            Set-AgentRing -Ring $Card.Ring -State ok -Value $Model.Value -DurationMs $dur -From $from -OnTick $tick
        }
        'loading' {
            $Card.NumWrap.Background = $st.Shimmer.Brush
            $num.Text = $Model.NumText
            $num.Foreground = [System.Windows.Media.Brushes]::Transparent
            $Card.BigPct.Foreground = [System.Windows.Media.Brushes]::Transparent
            Set-AgentRing -Ring $Card.Ring -State loading
        }
        default {
            $Card.NumWrap.Background = $null
            $num.Text = $Model.NumText
            $num.Foreground = ConvertTo-AgentViewBrush $theme['av-text-3']
            $Card.BigPct.Foreground = ConvertTo-AgentViewBrush $colors.Lv 0.85
            Set-AgentRing -Ring $Card.Ring -State error
            $Card.ErrTitle.Text = $Model.ErrTitle
            $Card.ErrDetail.Text = $Model.ErrDetail
            $Card.ErrDetail.Visibility = $(if ($Model.ErrDetail) { 'Visible' } else { 'Collapsed' })
            $Card.ErrStale.Text = [string]$Model.Stale
            $Card.ErrStale.Visibility = $(if ($Model.Stale) { 'Visible' } else { 'Collapsed' })
        }
    }
    Set-AgentViewMeter $Card 'Five' $Model.Five $Model.State $Mode
    Set-AgentViewMeter $Card 'Week' $Model.Week $Model.State $Mode
}

function Set-AgentViewShimmer([bool]$On) {
    $st = Get-AgentViewPopupState
    $sh = $st.Shimmer
    if ($On -eq $sh.Running) { return }
    $prop = [System.Windows.Media.TranslateTransform]::XProperty
    if ($On) {
        $a = New-Object System.Windows.Media.Animation.DoubleAnimation -1, 1, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(1200)))
        $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $sh.Shift.BeginAnimation($prop, $a)
    } else { $sh.Shift.BeginAnimation($prop, $null) }
    $sh.Running = $On
}

# Đọc history MỘT lần cho mỗi lần dựng popup/widget (không ném; lỗi ⇒ mảng rỗng).
function Get-AgentViewPopupHistory {
    $samples = @()
    try { $samples = @(Get-AgentViewHistory) } catch { }
    return ,$samples
}

# Dựng lại nội dung từ $st.Rows. Mode như Set-AgentViewCard.
function Update-AgentViewPopupView([string]$Mode = 'update') {
    $st = Get-AgentViewPopupState
    if (-not $st.Window) { return }
    $theme = $st.Theme
    $rows = @(ConvertTo-QuotaRows $st.Rows)
    if (-not $rows.Count) { $rows = @(Get-AgentViewEmptyRows) }
    $now = Get-Date
    $history = Get-AgentViewPopupHistory
    $st.Ui.SettingsBtn.Visibility = $(if ($st.OnSettings) { 'Visible' } else { 'Collapsed' })
    Update-AgentViewPopupUpdateChip
    $order = @()
    foreach ($row in $rows) {
        $key = [string]$row.Provider; if (-not $key) { $key = [string]$row.Name }
        if ($order -contains $key) { continue }
        $order += $key
        if (-not $st.Cards.ContainsKey($key)) { $st.Cards[$key] = New-AgentViewCard $key }
        $cardMode = $Mode; if (($st.Order -notcontains $key) -and $Mode -eq 'update') { $cardMode = 'open' }
        Set-AgentViewCard $st.Cards[$key] (Get-AgentViewCardModel $row -Loading:$st.Loading -Now $now -History $history) $cardMode
    }
    $panel = $st.Ui.Cards
    $panel.Children.Clear()
    for ($i = 0; $i -lt $order.Count; $i++) {
        $card = $st.Cards[$order[$i]]
        $card.Root.Margin = New-Object System.Windows.Thickness 0, $(if ($i -gt 0) { 8 } else { 0 }), 0, 0
        [void]$panel.Children.Add($card.Root)
    }
    foreach ($k in @($st.Cards.Keys)) { if ($order -notcontains $k) { Suspend-AgentRing $st.Cards[$k].Ring; $st.Cards.Remove($k) } }
    $st.Order = $order
    $status = Get-AgentViewStatusModel $rows -Loading:$st.Loading
    $st.Ui.StatusDot.Fill = ConvertTo-AgentViewBrush (Get-AgentViewLevelColors $status.Level $theme).Lv
    $st.Ui.StatusText.Text = $status.Text
    Update-AgentViewPopupText
    if (Test-AgentViewPopupOpen) { Set-AgentViewShimmer ([bool]$st.Loading) }
}

# Chỉ làm mới chữ phụ thuộc thời gian (chân popup, dòng reset) — gọi mỗi 20s khi đang mở.
function Update-AgentViewPopupText {
    $st = Get-AgentViewPopupState
    if (-not $st.Window) { return }
    $rows = @(ConvertTo-QuotaRows $st.Rows)
    if (-not $rows.Count) { $rows = @(Get-AgentViewEmptyRows) }
    $now = Get-Date
    $foot = Get-AgentViewFooterModel $rows -Loading:$st.Loading -Now $now
    $st.Ui.FootText.Text = $foot.Text
    $st.Ui.LiveDot.Fill = ConvertTo-AgentViewBrush $(if ($foot.Stale) { $st.Theme['warn'] } else { $st.Theme['ok'] })
    foreach ($row in $rows) {
        $card = $st.Cards[[string]$row.Provider]; if (-not $card) { continue }
        $model = Get-AgentViewCardModel $row -Loading:$st.Loading -Now $now
        foreach ($p in 'Five', 'Week') {
            $card["${p}Rel"].Text = [string]$model.$p.Rel; $card["${p}Abs"].Text = [string]$model.$p.Abs
        }
        if ($model.State -eq 'error') { $card.ErrStale.Text = [string]$model.Stale }
    }
}

# Chip 'v{0} ↑' góc header: chỉ hiện khi có cả phiên bản mới và OnUpdate.
function Update-AgentViewPopupUpdateChip {
    $st = Get-AgentViewPopupState
    if (-not $st.Window) { return }
    $v = [string]$st.UpdateVersion
    if ($v -and $st.OnUpdate) {
        $st.Ui.UpdateChipText.Text = (T 'popup.update_chip' -Args @($v))
        $st.Ui.UpdateChip.ToolTip = (T 'popup.update_tip' -Args @($v))
        $st.Ui.UpdateChip.Visibility = 'Visible'
    } else { $st.Ui.UpdateChip.Visibility = 'Collapsed' }
}
# Tray đổi trạng thái cập nhật lúc popup đang mở/đóng. Thiếu Version/OnUpdate ⇒ chip ẩn.
function Set-AgentViewPopupUpdate {
    param([string]$Version, [scriptblock]$OnUpdate)
    $st = Get-AgentViewPopupState
    $st.UpdateVersion = $(if ($Version) { $Version } else { $null }); $st.OnUpdate = $OnUpdate
    Update-AgentViewPopupUpdateChip
}

# ---------------------------------------------------------------- API công khai
function Test-AgentViewPopupOpen {
    $st = Get-AgentViewPopupState
    [bool]($st.Window -and $st.Window.IsVisible -and -not $st.Closing)
}

function Show-AgentViewPopup {
    param($Rows, [switch]$Loading, [scriptblock]$OnRefresh, [scriptblock]$OnRetry, [scriptblock]$OnSettings, [string]$UpdateVersion, [scriptblock]$OnUpdate)
    $st = Get-AgentViewPopupState
    $st.Rows = $Rows; $st.Loading = [bool]$Loading
    if ($OnRefresh) { $st.OnRefresh = $OnRefresh }
    if ($OnRetry) { $st.OnRetry = $OnRetry }
    $st.OnSettings = $OnSettings      # thiếu ⇒ nút ⚙ ẩn
    $st.UpdateVersion = $(if ($UpdateVersion) { $UpdateVersion } else { $null }); $st.OnUpdate = $OnUpdate   # thiếu ⇒ chip ẩn
    if (Test-AgentViewPopupOpen) { Hide-AgentViewPopup; return }
    $m = Get-AgentViewPopupMetrics
    # Bấm icon khay khi popup đang mở: popup mất focus (Deactivated) trước khi click tới → coi là đóng.
    if ($st.DeactivatedAt -and ([Environment]::TickCount - $st.DeactivatedAt) -lt $m.DeactivateGuardMs) { $st.DeactivatedAt = 0; return }
    $st.DeactivatedAt = 0
    if (-not $st.Window) { [void](New-AgentViewPopupWindow) }
    $w = $st.Window; $ui = $st.Ui
    $st.Closing = $false
    $ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    Update-AgentViewPopupView 'open'

    $st.WorkArea = [System.Windows.SystemParameters]::WorkArea
    $ui.Shell.Measure((New-Object System.Windows.Size $w.Width, ([double]::PositiveInfinity)))
    $place = Get-AgentViewPopupPlacement $st.WorkArea $ui.Shell.DesiredSize.Height
    $w.Left = $place.Left; $w.Top = $place.Top
    $ui.Shell.Opacity = 0
    $w.Show()
    [void]$w.Activate()

    $in = $m.InMs
    $ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-AgentViewDoubleAnimation 0 1 $in))
    $ui.ShellShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-AgentViewDoubleAnimation 12 0 $in))
    $ui.ShellScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, (New-AgentViewDoubleAnimation 0.985 1 $in))
    $ui.ShellScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, (New-AgentViewDoubleAnimation 0.985 1 $in))
    for ($i = 0; $i -lt $st.Order.Count; $i++) {
        $card = $st.Cards[$st.Order[$i]]
        $delay = $i * $m.CardStaggerMs
        $card.Root.Opacity = 0; $card.Shift.Y = 6
        $card.Root.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-AgentViewDoubleAnimation 0 1 $m.CardMs 'CubicOut' $delay))
        $card.Shift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-AgentViewDoubleAnimation 6 0 $m.CardMs 'CubicOut' $delay))
    }
    foreach ($k in $st.Order) { Resume-AgentRing $st.Cards[$k].Ring }
    Set-AgentViewShimmer ([bool]$st.Loading)
    $st.FootTimer.Start()
}

function Update-AgentViewPopup {
    param($Rows, [switch]$Loading)
    $st = Get-AgentViewPopupState
    $st.Rows = $Rows; $st.Loading = [bool]$Loading
    if (Test-AgentViewPopupOpen) { Update-AgentViewPopupView 'update' }
}

function Hide-AgentViewPopup {
    $st = Get-AgentViewPopupState
    if (-not (Test-AgentViewPopupOpen)) { return }
    $m = Get-AgentViewPopupMetrics
    $st.Closing = $true
    $ui = $st.Ui
    # Dừng mọi vòng lặp ngay khi bắt đầu ẩn (idle CPU ~0).
    $st.FootTimer.Stop()
    Set-AgentViewShimmer $false
    foreach ($k in @($st.Cards.Keys)) { Suspend-AgentRing $st.Cards[$k].Ring }
    $out = $m.OutMs
    $fade = New-AgentViewDoubleAnimation 1 0 $out 'CubicIn'
    $fade.Add_Completed({
        $s = Get-AgentViewPopupState
        if ($s.Closing -and $s.Window) { $s.Window.Hide(); $s.Closing = $false }
    })
    $ui.ShellShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-AgentViewDoubleAnimation 0 12 $out 'CubicIn'))
    $ui.ShellScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, (New-AgentViewDoubleAnimation 1 0.985 $out 'CubicIn'))
    $ui.ShellScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, (New-AgentViewDoubleAnimation 1 0.985 $out 'CubicIn'))
    $ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
}

# Permanent disposal for shutdown/tests; normal user close continues to animate and hide.
function Close-AgentViewPopup {
    param([switch]$Force)
    if (-not $Force) { Hide-AgentViewPopup; return }
    $st = Get-AgentViewPopupState
    if (-not $st.Window) { return }
    $w = $st.Window
    $st.Closing = $true
    $st.FootTimer.Stop()
    Set-AgentViewShimmer $false
    foreach ($card in $st.Cards.Values) { Suspend-AgentRing $card.Ring }
    $w.Remove_Deactivated($st.DeactivatedHandler)
    $w.Remove_Closing($st.ClosingHandler)
    $w.Remove_SizeChanged($st.SizeChangedHandler)
    if ($st.UpdateChipHandler) { $st.Ui.UpdateChip.Remove_MouseLeftButtonUp($st.UpdateChipHandler); $st.UpdateChipHandler = $null }
    # Remove the fade clock (and its Completed callback) before closing.
    $st.Ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $w.Close()
    # Drain queued layout/close work while the defining PowerShell scope still exists.
    $w.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ContextIdle, [Action]{})
    $st.Window = $null
    $st.Cards = @{}
    $st.Ui = @{}
    $st.Closing = $false
}
