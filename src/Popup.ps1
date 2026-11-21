if (-not (Test-Path function:Register-AgentViewStrings)) { . (Join-Path $PSScriptRoot 'I18n.ps1') }
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
        'no_agent_title' = 'No agent detected'
        'no_agent_hint' = 'Install an agent to track its quota.'
        'rescan' = 'Rescan'
        'scanning' = 'Scanning…'
        'still_no_agent' = 'Still no agent detected.'
        'looking_for_agents' = 'Looking for agents…'
        'not_detected' = 'Not detected'
        'no_agent_foot' = 'No agent to track'
        'expand_tip' = 'Show reset times'
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
        'no_agent_title' = 'Chưa phát hiện agent nào'
        'no_agent_hint' = 'Cài một agent để theo dõi quota.'
        'rescan' = 'Quét lại'
        'scanning' = 'Đang quét…'
        'still_no_agent' = 'Vẫn chưa phát hiện agent nào.'
        'looking_for_agents' = 'Đang tìm agent…'
        'not_detected' = 'Chưa phát hiện'
        'no_agent_foot' = 'Chưa có agent để theo dõi'
        'expand_tip' = 'Xem giờ đặt lại'
    }
}
# Popup quota kiểu B (danh sách gọn, thiết kế đa provider mục 1B) — WPF trên Windows PowerShell 5.1, sống trong vòng message WinForms của tray.
# Mỗi row một dòng (vòng 28 + logo, tên, 2 thanh mini 5h/tuần); bấm để mở chi tiết (reset, dự báo, lỗi) — mở một row mỗi lúc.
# Dot-source chỉ định nghĩa hàm. Hợp đồng: Show-/Update-/Hide-/Close-AgentViewPopup, Test-AgentViewPopupOpen, Set-AgentViewPopupUpdate.
if (-not (Test-Path function:New-AgentRing)) { . (Join-Path $PSScriptRoot 'Ring.ps1') }
if (-not (Test-Path function:Get-AgentViewHistoryIndex)) { . (Join-Path $PSScriptRoot 'History.ps1') }
if (-not (Test-Path function:Get-AgentViewForecast)) { . (Join-Path $PSScriptRoot 'Forecast.ps1') }

# ---------------------------------------------------------------- hằng số bố cục (khớp Spec 04 + thiết kế mục 1B)
function Get-AgentViewPopupMetrics {
    @{
        Width = 360; Gap = 12                                 # rộng popup; cách mép phải / đỉnh taskbar / đỉnh vùng làm việc
        ShadowLeft = 28; ShadowTop = 16; ShadowRight = 28; ShadowBottom = 44   # lề trong suốt cho DropShadow
        BarWidth = 306                                        # 360 − viền 2 − thân 24 − viền thẻ 2 − padding chi tiết 26
        RowRing = 28; RowStroke = 3; RowIcon = 14; MiniWidth = 56   # dòng gọn: vòng 28, thanh mini 56
        InMs = 200; OutMs = 140; CardMs = 260; CardStaggerMs = 40; OpenMs = 700; UpdateMs = 450; SpinMs = 700; FoldMs = 160
        DeactivateGuardMs = 300                               # bấm icon khay ngay sau khi mất focus = đóng, không mở lại
        FontText = 'Segoe UI Variable Text, Segoe UI'; FontDisplay = 'Segoe UI Variable Display, Segoe UI'
    }
}

# ---------------------------------------------------------------- hàm thuần (test không cần cửa sổ)
function Get-AgentViewPopupPlacement($WorkArea, [double]$WindowHeight) {
    Get-AgentViewCornerPlacement $WorkArea $WindowHeight (Get-AgentViewPopupMetrics)
}

# Chiều cao tối đa của khung (không gồm lề bóng): vùng làm việc trừ Gap trên + dưới.
function Get-AgentViewPopupMaxHeight($WorkArea) {
    [math]::Max(160, [double]$WorkArea.Height - 2 * (Get-AgentViewPopupMetrics).Gap)
}

# Trạng thái provider cho UI (Tray.ps1 · Get-AgentViewProviderView, gọi qua Get-Command để popup/widget chạy được độc lập).
# Settings: tham số, không có thì settings đang dùng của widget/tray. Không ném; thiếu hợp đồng ⇒ chưa quét.
function Get-AgentViewUiProviderView($Settings = $null) {
    $view = $null
    try {
        if (Get-Command Get-AgentViewProviderView -ErrorAction SilentlyContinue) {
            if ($null -eq $Settings -and (Get-Command Get-AgentViewWidgetState -ErrorAction SilentlyContinue)) { $Settings = (Get-AgentViewWidgetState).Settings }
            $view = Get-AgentViewProviderView $Settings
        }
    } catch { $view = $null }
    if ($null -eq $view) { $view = @{ Detected = [string[]]@(); Hidden = [string[]]@(); NoAgent = $false } }
    $view
}

# Row "chưa có dữ liệu" cho từng Family đã phát hiện (theo thứ tự registry), bỏ Family đang ẩn. Không có Family ⇒ không row.
function Get-AgentViewEmptyRows($Families) {
    $want = [string[]]@(@($Families) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    foreach ($p in Get-AgentProviders) {
        if ($want -cnotcontains $p.Family) { continue }
        [pscustomobject]@{ Provider = $p.Family; Family = $p.Family; Group = $null; Name = $p.Name; Ok = $false; Error = (T 'popup.no_data_yet')
            FiveHourUsed = $null; WeekUsed = $null; FiveHourResetsAt = $null; WeekResetsAt = $null; FetchedAt = $null }
    }
}

# Hàng để hiển thị: dàn phẳng chung (Format.ps1); rỗng ⇒ thẻ "chưa có dữ liệu" theo Family phát hiện được (View = Get-AgentViewUiProviderView).
function Get-AgentViewDisplayRows($Rows, $View = $null) {
    $rows = @(ConvertTo-QuotaRows $Rows)
    if (-not $rows.Count) {
        if ($null -eq $View) { $View = Get-AgentViewUiProviderView }
        $families = @(@($View.Detected) | Where-Object { @($View.Hidden) -cnotcontains $_ })
        if (-not $families.Count) { $families = @($View.Detected) }
        $rows = @(Get-AgentViewEmptyRows $families)
    }
    $rows
}

# Xếp row theo Family (giữ thứ tự xuất hiện) để các nhóm cùng Family nằm liền nhau. Trả danh sách @{ Family; Rows }.
function Get-AgentViewFamilyGroups($Rows) {
    $order = New-Object System.Collections.Generic.List[string]
    $map = @{}
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $family = Get-QuotaRowFamily $row
        if (-not $map.ContainsKey($family)) { $map[$family] = New-Object System.Collections.Generic.List[object]; $order.Add($family) }
        $map[$family].Add($row)
    }
    foreach ($f in $order) { [pscustomobject]@{ Family = $f; Rows = $map[$f].ToArray() } }
}

# Tên hiển thị của Family (registry Name; lạ ⇒ chính id).
function Get-AgentViewFamilyName([string]$Family) {
    $p = @(Get-AgentProviders | Where-Object { $_.Family -eq $Family }) | Select-Object -First 1
    if ($p) { return [string]$p.Name }
    return $Family
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

# Mô hình hiển thị một row provider: State 'ok'|'error'|'loading' + chuỗi đã dựng.
# History: mẫu Get-AgentViewHistory (mọi provider) hoặc index Get-AgentViewHistoryIndex ('p|w' ⇒ mẫu) để dự báo; $null ⇒ không có dòng dự báo.
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
        if ($History -is [System.Collections.IDictionary]) {
            $fiveSamples = $History["$provider|5h"]; if ($null -eq $fiveSamples) { $fiveSamples = @() }
            $weekSamples = $History["$provider|week"]; if ($null -eq $weekSamples) { $weekSamples = @() }
        } else {
            $five = New-Object System.Collections.Generic.List[object]; $week = New-Object System.Collections.Generic.List[object]
            foreach ($s in @($History)) {
                if ($null -eq $s -or $s.p -ne $provider) { continue }
                if ($s.w -eq '5h') { $five.Add($s) } elseif ($s.w -eq 'week') { $week.Add($s) }
            }
            $fiveSamples = $five.ToArray(); $weekSamples = $week.ToArray()
        }
    }
    [pscustomobject]@{
        Provider = [string]$Row.Provider; Family = (Get-QuotaRowFamily $Row); Group = $(if ($Row.Group) { [string]$Row.Group } else { $null })
        Name = $name; State = $state; Value = $value; Level = $level
        Sub = $sub
        NumText = $(switch ($state) { 'ok' { [string]$value } 'loading' { '00' } default { '–' } })
        Five = Get-AgentViewWindowModel $Row.FiveHourUsed $Row.FiveHourResetsAt $Now $fiveSamples '5h'
        Week = Get-AgentViewWindowModel $Row.WeekUsed $Row.WeekResetsAt $Now $weekSamples 'week'
        ErrTitle = (T 'popup.cannot_read_quota'); ErrDetail = $detail; Stale = $stale
    }
}

# Chip trạng thái theo mức tệ nhất của các provider đọc được. NoAgent ⇒ 'Chưa phát hiện'.
function Get-AgentViewStatusModel($Rows, [switch]$Loading, [switch]$NoAgent) {
    if ($Loading) { return [pscustomobject]@{ Level = 'unk'; Text = (T 'popup.loading') } }
    if ($NoAgent) { return [pscustomobject]@{ Level = 'unk'; Text = (T 'popup.not_detected') } }
    $vals = @(foreach ($r in $Rows) { if ($r.Ok) { $v = Get-QuotaRemaining $r; if ($null -ne $v) { $v } } })
    $level = 'unk'
    if ($vals.Count) { $level = Get-QuotaLevel (($vals | Measure-Object -Minimum).Minimum) }
    [pscustomobject]@{ Level = $level; Text = (Get-QuotaStatusText $level) }
}

function Get-AgentViewFooterModel($Rows, [switch]$Loading, [datetime]$Now = (Get-Date), [switch]$NoAgent) {
    $hasError = @($Rows | Where-Object { -not $_.Ok }).Count -gt 0
    if ($Loading) { return [pscustomobject]@{ Text = (T 'popup.updating'); Stale = $false } }
    if ($NoAgent) { return [pscustomobject]@{ Text = (T 'popup.no_agent_foot'); Stale = $true } }
    $times = @($Rows | Where-Object { $_.FetchedAt } | ForEach-Object { [datetime]$_.FetchedAt })
    $text = (T 'popup.not_updated_yet')
    if ($times.Count) { $text = (T 'popup.updated') + (Format-QuotaAgo (($times | Measure-Object -Maximum).Maximum) $Now) }
    if ($hasError) { $text += (T 'popup.errors') }
    [pscustomobject]@{ Text = $text; Stale = $hasError }
}

# Row đang mở: giữ lựa chọn nếu row còn; chỉ có một row ⇒ luôn mở (không có gì khác để xem); còn lại ⇒ không row nào mở.
function Get-AgentViewPopupExpandedKey($Current, [string[]]$Order) {
    if (@($Order).Count -eq 1) { return $Order[0] }
    if ($Current -and @($Order) -ccontains [string]$Current) { return [string]$Current }
    return $null
}

# ---------------------------------------------------------------- trạng thái (một popup mỗi tiến trình)
function Get-AgentViewPopupState {
    Get-AgentViewUiState 'agent-view.popup' {
        @{ Window = $null; Rows = @(); Loading = $false; OnRefresh = $null; OnRetry = $null; OnSettings = $null; OnRescan = $null
           UpdateVersion = $null; OnUpdate = $null; Closing = $false; DeactivatedAt = 0; Cards = @{}; Headers = @{}; Order = @(); WorkArea = $null; Handlers = @()
           Expanded = $null; NoAgent = $false; Empty = $null; EmptyNote = $null; RescanPending = $false }
    }
}

# ---------------------------------------------------------------- XAML
function Get-AgentViewPopupXaml {
    $m = Get-AgentViewPopupMetrics
    $w = $m.Width + $m.ShadowLeft + $m.ShadowRight
    $resources = @"
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
  <Style TargetType="ScrollBar">
   <Setter Property="Width" Value="6"/><Setter Property="MinWidth" Value="6"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
    <Track x:Name="PART_Track" IsDirectionReversed="True">
     <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border CornerRadius="3" Background="@@av-stroke@@"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
    </Track>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
 </Window.Resources>
"@
    $body = @"
  <DockPanel>
   <Grid DockPanel.Dock="Top" Margin="16,12,10,8">
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
   <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="16,10,16,12">
    <Ellipse x:Name="LiveDot" Width="6" Height="6" VerticalAlignment="Center"/>
    <TextBlock x:Name="FootText" Margin="8,0,0,0" FontSize="11.5" Foreground="@@av-text-3@@" VerticalAlignment="Center" Typography.NumeralAlignment="Tabular"/>
   </StackPanel>
   <ScrollViewer x:Name="Scroll" Margin="12,4,12,0" Focusable="False" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <ScrollViewer.Template><ControlTemplate TargetType="ScrollViewer">
     <Grid>
      <ScrollContentPresenter CanContentScroll="False"/>
      <ScrollBar x:Name="PART_VerticalScrollBar" HorizontalAlignment="Right" Margin="0,0,-9,0" Opacity="0.85"
                 Value="{TemplateBinding VerticalOffset}" Maximum="{TemplateBinding ScrollableHeight}" ViewportSize="{TemplateBinding ViewportHeight}"
                 Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}"/>
     </Grid>
    </ControlTemplate></ScrollViewer.Template>
    <StackPanel x:Name="Cards"/>
   </ScrollViewer>
  </DockPanel>
"@
    Get-AgentViewShellXaml -Resources $resources -Body $body `
        -Window ('Title="agent-view" ShowInTaskbar="False" Topmost="True" SizeToContent="Height" Width="{0}" ShowActivated="True" UseLayoutRounding="True" FontFamily="{1}" FontSize="12" Foreground="@@av-text@@"' -f $w, $m.FontText) `
        -Shell ('Width="{0}" Margin="{1},{2},{3},{4}" CornerRadius="8" RenderTransformOrigin="1,1"' -f $m.Width, $m.ShadowLeft, $m.ShadowTop, $m.ShadowRight, $m.ShadowBottom) `
        -Gradient 'MappingMode="Absolute" StartPoint="0,0" EndPoint="0,96"' `
        -Transform '<Border.RenderTransform><TransformGroup><ScaleTransform x:Name="ShellScale" ScaleX="1" ScaleY="1"/><TranslateTransform x:Name="ShellShift"/></TransformGroup></Border.RenderTransform>'
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

# Thanh mini của dòng gọn: nhãn 10.5 + % bên phải, thanh cao 4 (thiết kế .mini).
function Get-AgentViewMiniXaml([string]$Prefix, [string]$Label, [int]$Column) {
    @"
<StackPanel x:Name="Mini${Prefix}" Grid.Column="$Column" VerticalAlignment="Center" Margin="7,0,0,0">
 <Grid Margin="0,0,0,3">
  <TextBlock Text="$Label" FontSize="10.5" Foreground="@@av-text-3@@"/>
  <TextBlock x:Name="Mini${Prefix}Value" HorizontalAlignment="Right" FontSize="10.5" FontWeight="SemiBold" Typography.NumeralAlignment="Tabular"/>
 </Grid>
 <Grid Height="4" ClipToBounds="True">
  <Border x:Name="Mini${Prefix}Track" CornerRadius="2" Background="@@av-track@@"/>
  <Border x:Name="Mini${Prefix}Fill" CornerRadius="2" HorizontalAlignment="Left" Width="0"/>
 </Grid>
</StackPanel>
"@
}

# Một row: dòng gọn (Summary, bấm để mở) + phần chi tiết (Detail: 2 thanh đầy đủ có reset/dự báo, hoặc hộp lỗi).
function Get-AgentViewCardXaml {
    $m = Get-AgentViewPopupMetrics
    $five = Get-AgentViewMeterXaml 'Five' (T 'popup.5_hours')
    $week = Get-AgentViewMeterXaml 'Week' (T 'popup.week')
    $miniFive = Get-AgentViewMiniXaml 'Five' '5h' 2
    $miniWeek = Get-AgentViewMiniXaml 'Week' (T 'popup.week') 3
    @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  CornerRadius="8" BorderThickness="1" BorderBrush="@@av-stroke-soft@@" Background="@@av-surface@@"
  TextElement.FontFamily="$($m.FontText)" TextElement.Foreground="@@av-text@@">
 <Border.RenderTransform><TranslateTransform x:Name="Shift"/></Border.RenderTransform>
 <StackPanel>
  <Border x:Name="Summary" CornerRadius="7" Padding="8,6,8,6" MinHeight="48" Cursor="Hand" ToolTip="$(T 'popup.expand_tip')">
   <Border.Style><Style TargetType="Border"><Setter Property="Background" Value="Transparent"/>
    <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="@@av-surface-hi@@"/></Trigger></Style.Triggers>
   </Style></Border.Style>
   <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="$($m.RowRing)"/><ColumnDefinition Width="*"/><ColumnDefinition Width="$($m.MiniWidth + 7)"/><ColumnDefinition Width="$($m.MiniWidth + 7)"/><ColumnDefinition Width="19"/></Grid.ColumnDefinitions>
    <ContentControl x:Name="RingHost" Width="$($m.RowRing)" Height="$($m.RowRing)" VerticalAlignment="Center" Focusable="False"/>
    <StackPanel Grid.Column="1" Margin="8,0,0,0" VerticalAlignment="Center">
     <TextBlock x:Name="NameText" FontSize="12" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
     <TextBlock x:Name="SubText" Margin="0,1,0,0" FontSize="10.5" Foreground="@@av-text-3@@" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
    $miniFive
    $miniWeek
    <Canvas Grid.Column="4" Width="12" Height="12" HorizontalAlignment="Right" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5">
     <Canvas.RenderTransform><RotateTransform x:Name="ChevronRot"/></Canvas.RenderTransform>
     <Path Data="M2.5,4.5 L6,8 L9.5,4.5" Stroke="@@av-text-3@@" StrokeThickness="1.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
    </Canvas>
   </Grid>
  </Border>
  <Border x:Name="Detail" Visibility="Collapsed" BorderThickness="0,1,0,0" BorderBrush="@@av-stroke@@" Padding="12,12,14,14">
   <StackPanel>
    <StackPanel x:Name="Meters">
     $five
     <Border x:Name="MeterGap" Height="10"/>
     $week
    </StackPanel>
    <Border x:Name="ErrBox" Visibility="Collapsed" Background="@@err-bg@@" BorderBrush="@@err-stroke@@" BorderThickness="1" CornerRadius="8" Padding="12,10,10,10">
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
 </StackPanel>
</Border>
"@
}

# Tiêu đề nhóm Family (khi Family có nhiều row, vd. Antigravity): logo 14 + tên.
function Get-AgentViewFamilyHeaderXaml([string]$Name) {
    $m = Get-AgentViewPopupMetrics
    $safe = [Security.SecurityElement]::Escape($Name)
    @"
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Orientation="Horizontal" Margin="4,10,0,6" TextElement.FontFamily="$($m.FontText)">
 <ContentControl x:Name="HeadIcon" Width="14" Height="14" VerticalAlignment="Center" Focusable="False"/>
 <TextBlock Text="$safe" Margin="7,0,0,0" FontSize="11.5" FontWeight="SemiBold" Foreground="@@av-text-2@@" VerticalAlignment="Center"/>
</StackPanel>
"@
}

# Thẻ trạng thái trống: chưa phát hiện agent (danh sách provider hỗ trợ + Quét lại), hoặc đang tìm (chưa quét xong).
function Get-AgentViewEmptyCardXaml {
    $m = Get-AgentViewPopupMetrics
    $names = [Security.SecurityElement]::Escape((@(Get-AgentProviders | ForEach-Object { $_.Name }) -join ' · '))
    @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  CornerRadius="8" BorderThickness="1" BorderBrush="@@av-stroke-soft@@" Background="@@av-surface@@" Padding="12,15,12,15"
  TextElement.FontFamily="$($m.FontText)" TextElement.Foreground="@@av-text@@">
 <StackPanel>
  <TextBlock x:Name="EmptyTitle" FontSize="13" FontWeight="SemiBold" TextWrapping="Wrap"/>
  <TextBlock x:Name="EmptyHint" Margin="0,6,0,0" FontSize="12" Foreground="@@av-text-2@@" TextWrapping="Wrap"/>
  <TextBlock x:Name="EmptyList" Margin="0,6,0,0" FontSize="12" Foreground="@@av-text-2@@" TextWrapping="Wrap" Text="$names"/>
  <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
   <Button x:Name="RescanBtn" Content="$(T 'popup.rescan')"/>
   <TextBlock x:Name="EmptyNote" Margin="10,0,0,0" FontSize="11.5" Foreground="@@av-text-3@@" VerticalAlignment="Center" TextWrapping="Wrap"/>
  </StackPanel>
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
    $window, $ui = New-AgentViewXamlObject (Get-AgentViewPopupXaml) $theme @('Shell', 'ShellScale', 'ShellShift', 'BrandRing', 'StatusDot', 'StatusText', 'RefreshBtn', 'RefreshRot', 'SettingsBtn', 'Scroll', 'Cards', 'LiveDot', 'FootText', 'UpdateChip', 'UpdateChipText')
    $brand = New-AgentRing -Size 16 -Stroke 2.5
    Set-AgentRing -Ring $brand -State ok -Value 76 -DurationMs 0   # dấu thương hiệu tĩnh theo thiết kế
    $ui.BrandRing.Content = $brand
    $st.Window = $window; $st.Ui = $ui; $st.Theme = $theme; $st.Cards = @{}; $st.Headers = @{}; $st.Order = @(); $st.Handlers = @(); $st.Empty = $null
    $st.Shimmer = New-AgentViewShimmerBrush $theme

    Add-AgentViewHandler $st $window 'Deactivated' {
        $s = Get-AgentViewPopupState
        if ($s.Window -and $s.Window.IsVisible -and -not $s.Closing) {
            $s.DeactivatedAt = [Environment]::TickCount
            Hide-AgentViewPopup
        }
    }
    Add-AgentViewHandler $st $window 'KeyDown' {
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $_.Handled = $true; Hide-AgentViewPopup }
    }
    Add-AgentViewHandler $st $window 'Closing' { $_.Cancel = $true; Hide-AgentViewPopup }   # Alt+F4 chỉ ẩn, giữ cửa sổ dùng lại
    Add-AgentViewHandler $st $window 'SizeChanged' {
        $s = Get-AgentViewPopupState
        if ($s.WorkArea) { $s.Window.Top = (Get-AgentViewPopupPlacement $s.WorkArea $s.Window.ActualHeight).Top }
    }
    Add-AgentViewHandler $st $ui.RefreshBtn 'Click' {
        $s = Get-AgentViewPopupState
        $spin = New-AgentViewDoubleAnimation 0 360 (Get-AgentViewPopupMetrics).SpinMs
        $spin.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $s.Ui.RefreshRot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
        if ($s.OnRefresh) { try { & $s.OnRefresh } catch { } }
    }
    Add-AgentViewHandler $st $ui.SettingsBtn 'Click' {
        $cb = (Get-AgentViewPopupState).OnSettings
        if ($cb) { Hide-AgentViewPopup; try { & $cb } catch { } }
    }
    $ui.UpdateChip.Background = ConvertTo-AgentViewBrush $theme['accent'] 0.14
    $ui.UpdateChip.BorderBrush = ConvertTo-AgentViewBrush $theme['accent'] 0.5
    Add-AgentViewHandler $st $ui.UpdateChip 'MouseLeftButtonUp' {
        $_.Handled = $true
        $s = Get-AgentViewPopupState
        $cb = $s.OnUpdate
        if ($cb -and $s.UpdateVersion) { Hide-AgentViewPopup; try { & $cb } catch { } }
    }
    $st.FootTimer = New-Object System.Windows.Threading.DispatcherTimer
    $st.FootTimer.Interval = [TimeSpan]::FromSeconds(20)
    Add-AgentViewHandler $st $st.FootTimer 'Tick' { Update-AgentViewPopupText }
    try { [System.Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($window) } catch { }
    $window
}

# Key = Provider (id row); Family quyết định logo trong vòng 28.
function New-AgentViewCard([string]$Provider, [string]$Family = $null) {
    $st = Get-AgentViewPopupState
    $m = Get-AgentViewPopupMetrics
    $names = @('Shift', 'Summary', 'RingHost', 'NameText', 'SubText', 'ChevronRot', 'Detail', 'Meters', 'ErrBox', 'ErrTitle', 'ErrDetail', 'ErrStale', 'RetryBtn', 'MeterGap') +
        @(foreach ($p in 'Five', 'Week') { foreach ($n in 'Block', 'Line', 'Value', 'Track', 'Fill', 'Ticks', 'Reset', 'Rel', 'Abs', 'Forecast') { "$p$n" }; foreach ($n in '', 'Value', 'Track', 'Fill') { "Mini$p$n" } })
    $root, $c = New-AgentViewXamlObject (Get-AgentViewCardXaml) $st.Theme $names
    $c.Root = $root; $c.Provider = $Provider
    if (-not $Family) { $Family = ($Provider -split '-')[0] }
    $c.Family = $Family
    $c.Ring = New-AgentRing -Size $m.RowRing -Stroke $m.RowStroke -Icon $Family -IconSize $m.RowIcon
    $c.RingHost.Content = $c.Ring
    $c.RetryBtn.Style = $st.Window.Resources['TextBtn']
    $c.RetryBtn.Tag = $Provider
    $c.Summary.Tag = $Provider
    Add-AgentViewHandler $st $c.RetryBtn 'Click' {
        $s = Get-AgentViewPopupState
        if ($s.OnRetry) { try { & $s.OnRetry ([string]$this.Tag) } catch { } }
    }
    Add-AgentViewHandler $st $c.Summary 'MouseLeftButtonUp' {
        $_.Handled = $true
        $s = Get-AgentViewPopupState
        $key = [string]$this.Tag
        if ($s.Expanded -ceq $key -and $s.Order.Count -gt 1) { $key = $null }
        Set-AgentViewPopupExpanded $key -Animate
    }
    $root.Tag = $c
    $c
}

function New-AgentViewFamilyHeader([string]$Family) {
    $st = Get-AgentViewPopupState
    $root, $h = New-AgentViewXamlObject (Get-AgentViewFamilyHeaderXaml (Get-AgentViewFamilyName $Family)) $st.Theme @('HeadIcon')
    $h.Root = $root
    $h.HeadIcon.Content = New-AgentRingIcon $Family 14 $st.Theme
    $h
}

function New-AgentViewEmptyCard {
    $st = Get-AgentViewPopupState
    $root, $e = New-AgentViewXamlObject (Get-AgentViewEmptyCardXaml) $st.Theme @('EmptyTitle', 'EmptyHint', 'EmptyList', 'RescanBtn', 'EmptyNote')
    $e.Root = $root
    $e.RescanBtn.Style = $st.Window.Resources['TextBtn']
    Add-AgentViewHandler $st $e.RescanBtn 'Click' { Invoke-AgentViewPopupRescan }
    $e
}

# Nút "Quét lại": OnRescan nếu tray truyền; không thì gọi Invoke-AgentViewProviderRescan với tray lấy từ closure OnRefresh
# (tray.Begin), cuối cùng xóa cache phát hiện + refresh tay (refresh tay luôn quét lại). Không ném.
function Invoke-AgentViewPopupRescan {
    $st = Get-AgentViewPopupState
    $st.RescanPending = $true
    $st.EmptyNote = (T 'popup.scanning')
    if ($st.Empty) { $st.Empty.EmptyNote.Text = $st.EmptyNote }
    try {
        if ($st.OnRescan) { [void](& $st.OnRescan); return }
        $tray = $null
        if ($st.OnRefresh -and $st.OnRefresh.Module) { try { $tray = $st.OnRefresh.Module.SessionState.PSVariable.GetValue('tray') } catch { $tray = $null } }
        if ($tray -and $tray.State -and (Get-Command Invoke-AgentViewProviderRescan -ErrorAction SilentlyContinue)) { [void](Invoke-AgentViewProviderRescan $tray); return }
        $presence = [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence')
        if ($null -ne $presence) { $presence.Remove('Families') }
        if ($st.OnRefresh) { & $st.OnRefresh }
    } catch { }
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

# Tween độ rộng thanh: 'open' từ 0, 'update' từ hiện tại, 'static' gán ngay.
function Set-AgentViewBarWidth($Fill, [double]$Target, [string]$Mode) {
    $m = Get-AgentViewPopupMetrics
    if ($Mode -eq 'static') { $Fill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $null); $Fill.Width = $Target; return }
    $from = 0.0
    if ($Mode -ne 'open') { $from = $Fill.Width; if ([double]::IsNaN($from)) { $from = 0.0 } }
    $ms = $m.UpdateMs; $ease = 'CubicOut'; if ($Mode -eq 'open') { $ms = $m.OpenMs; $ease = 'QuinticOut' }
    $Fill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, (New-AgentViewDoubleAnimation $from $Target $ms $ease))
}

function New-AgentViewLevelFill([string]$Level) {
    $st = Get-AgentViewPopupState
    $colors = Get-AgentViewLevelColors $Level $st.Theme
    $grad = New-Object System.Windows.Media.LinearGradientBrush ((ConvertTo-AgentViewColor $colors.Lv), (ConvertTo-AgentViewColor $colors.Hi), 0.0)
    $grad.Freeze(); $grad
}

function Set-AgentViewMeter($Card, [string]$Prefix, $Window, [string]$State, [string]$Mode) {
    $st = Get-AgentViewPopupState
    $m = Get-AgentViewPopupMetrics
    $Card["${Prefix}Value"].Text = $Window.ValueText
    $Card["${Prefix}Rel"].Text = [string]$Window.Rel
    $Card["${Prefix}Abs"].Text = [string]$Window.Abs
    Set-AgentViewForecastLine $Card["${Prefix}Forecast"] $Window
    $fill = $Card["${Prefix}Fill"]
    $loading = $State -eq 'loading'
    $Card["${Prefix}Track"].Background = $(if ($loading) { $st.Shimmer.Brush } else { ConvertTo-AgentViewBrush $st.Theme['av-track'] })
    $vis = $(if ($loading) { 'Hidden' } else { 'Visible' }); $fill.Visibility = $vis; $Card["${Prefix}Ticks"].Visibility = $vis
    foreach ($n in 'Line', 'Reset', 'Forecast') { $Card["$Prefix$n"].Opacity = $(if ($loading) { 0.35 } else { 1 }) }
    if ($loading) { return }
    $fill.Background = New-AgentViewLevelFill $Window.Level
    $target = 0.0; if ($State -eq 'ok' -and $null -ne $Window.Remaining) { $target = $m.BarWidth * $Window.Remaining / 100 }
    Set-AgentViewBarWidth $fill $target $Mode
}

# Thanh mini trên dòng gọn: cửa sổ thiếu hoặc row lỗi ⇒ Hidden (giữ cột thẳng hàng như thiết kế).
function Set-AgentViewMiniMeter($Card, [string]$Prefix, $Window, [string]$State, [string]$Mode) {
    $st = Get-AgentViewPopupState
    $m = Get-AgentViewPopupMetrics
    $box = $Card["Mini$Prefix"]
    $show = $Window.Present -and $State -ne 'error'
    $box.Visibility = $(if ($show) { 'Visible' } else { 'Hidden' })
    if (-not $show) { return }
    $loading = $State -eq 'loading'
    $value = $Card["Mini${Prefix}Value"]; $fill = $Card["Mini${Prefix}Fill"]
    $value.Text = $Window.ValueText
    $value.Foreground = ConvertTo-AgentViewBrush $st.Theme[$(if ($loading) { 'av-text-3' } else { (Get-AgentViewLevelColors $Window.Level $st.Theme).Level })]
    $value.Opacity = $(if ($loading) { 0.35 } else { 1 })
    $Card["Mini${Prefix}Track"].Background = $(if ($loading) { $st.Shimmer.Brush } else { ConvertTo-AgentViewBrush $st.Theme['av-track'] })
    $fill.Visibility = $(if ($loading) { 'Hidden' } else { 'Visible' })
    if ($loading) { return }
    $fill.Background = New-AgentViewLevelFill $Window.Level
    Set-AgentViewBarWidth $fill ($m.MiniWidth * [double]$Window.Remaining / 100) $Mode
}

# Áp mô hình lên row. Mode: 'open' (vòng chạy từ 0, 700ms), 'update' (từ giá trị cũ, 450ms), 'static' (không tween).
# DisplayName: tên trên dòng gọn (vd. tên nhóm khi đã có tiêu đề Family); mặc định Model.Name.
function Set-AgentViewCard($Card, $Model, [string]$Mode = 'update', [string]$DisplayName = $null) {
    $st = Get-AgentViewPopupState
    $m = Get-AgentViewPopupMetrics
    $theme = $st.Theme
    $Card.NameText.Text = $(if ($DisplayName) { $DisplayName } else { $Model.Name })
    $Card.SubText.Text = $Model.Sub
    $Card.SubText.Foreground = ConvertTo-AgentViewBrush $theme[$(if ($Model.State -eq 'error') { 'av-text-2' } else { 'av-text-3' })]
    $Card.RetryBtn.Tag = $Model.Provider
    $Card.Summary.Tag = $Model.Provider
    $Card.FiveBlock.Visibility = Get-AgentViewVisibility $Model.Five.Present
    $Card.WeekBlock.Visibility = Get-AgentViewVisibility $Model.Week.Present
    $Card.MeterGap.Visibility = Get-AgentViewVisibility ($Model.Five.Present -and $Model.Week.Present)
    $Card.Meters.Visibility = Get-AgentViewVisibility ($Model.State -ne 'error')
    $Card.ErrBox.Visibility = Get-AgentViewVisibility ($Model.State -eq 'error')
    switch ($Model.State) {
        'ok' {
            $dur = $m.UpdateMs; $from = $null
            if ($Mode -eq 'open') { $dur = $m.OpenMs; $from = 0 }
            if ($Mode -eq 'static') { $dur = 0 }
            Set-AgentRing -Ring $Card.Ring -State ok -Value $Model.Value -DurationMs $dur -From $from
        }
        'loading' { Set-AgentRing -Ring $Card.Ring -State loading }
        default {
            Set-AgentRing -Ring $Card.Ring -State error
            $Card.ErrTitle.Text = $Model.ErrTitle
            $Card.ErrDetail.Text = $Model.ErrDetail
            $Card.ErrDetail.Visibility = Get-AgentViewVisibility $Model.ErrDetail
            $Card.ErrStale.Text = [string]$Model.Stale
            $Card.ErrStale.Visibility = Get-AgentViewVisibility $Model.Stale
        }
    }
    Set-AgentViewMiniMeter $Card 'Five' $Model.Five $Model.State $Mode
    Set-AgentViewMiniMeter $Card 'Week' $Model.Week $Model.State $Mode
    Set-AgentViewMeter $Card 'Five' $Model.Five $Model.State $Mode
    Set-AgentViewMeter $Card 'Week' $Model.Week $Model.State $Mode
}

# Mở đúng một row (Key) và đóng các row khác; -Animate ⇒ chevron xoay + chi tiết mờ dần vào, rồi cuộn row vào tầm nhìn.
function Set-AgentViewPopupExpanded($Key, [switch]$Animate) {
    $st = Get-AgentViewPopupState
    $m = Get-AgentViewPopupMetrics
    $st.Expanded = $(if ($Key) { [string]$Key } else { $null })
    foreach ($k in @($st.Cards.Keys)) {
        $c = $st.Cards[$k]
        $open = ($k -ceq $st.Expanded)
        $angle = $(if ($open) { 180.0 } else { 0.0 })
        $wasOpen = $c.Detail.Visibility -eq 'Visible'
        $c.Detail.Visibility = Get-AgentViewVisibility $open
        if ($Animate -and $open -ne $wasOpen) {
            $c.ChevronRot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, (New-AgentViewDoubleAnimation $null $angle $m.FoldMs))
            if ($open) { $c.Detail.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-AgentViewDoubleAnimation 0 1 $m.FoldMs)) }
        } else {
            $c.ChevronRot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
            $c.ChevronRot.Angle = $angle
        }
    }
    if ($Animate -and $st.Expanded -and $st.Window) {
        [void]$st.Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Loaded, [Action]{
            $s = Get-AgentViewPopupState
            if ($s.Expanded -and $s.Cards.ContainsKey($s.Expanded)) { $s.Cards[$s.Expanded].Root.BringIntoView() }
        })
    }
}

function Set-AgentViewShimmer([bool]$On) {
    $st = Get-AgentViewPopupState
    $sh = $st.Shimmer
    if ($On -eq $sh.Running) { return }
    $prop = [System.Windows.Media.TranslateTransform]::XProperty
    if ($On) {
        $a = New-AgentViewDoubleAnimation -1 1 1200 ''
        $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $sh.Shift.BeginAnimation($prop, $a)
    } else { $sh.Shift.BeginAnimation($prop, $null) }
    $sh.Running = $On
}

# Index history từ cache bộ nhớ (History.ps1; không đọc file nếu file không đổi) cho mỗi lần dựng popup/widget.
# Không ném; lỗi ⇒ index rỗng.
function Get-AgentViewPopupHistory {
    $index = @{}
    try { $index = Get-AgentViewHistoryIndex } catch { }
    if ($null -eq $index) { $index = @{} }
    return $index
}

# Thẻ trống: NoAgent ⇒ hướng dẫn + Quét lại; chưa quét xong ⇒ "Đang tìm agent…".
function Update-AgentViewEmptyCard([bool]$NoAgent) {
    $st = Get-AgentViewPopupState
    if (-not $st.Empty) { $st.Empty = New-AgentViewEmptyCard }
    $e = $st.Empty
    if ($NoAgent) {
        $e.EmptyTitle.Text = (T 'popup.no_agent_title'); $e.EmptyHint.Text = (T 'popup.no_agent_hint')
        $e.EmptyList.Visibility = 'Visible'; $e.RescanBtn.Visibility = 'Visible'
        if ($st.RescanPending -and -not $st.Loading) { $st.RescanPending = $false; $st.EmptyNote = (T 'popup.still_no_agent') }
        elseif ($st.Loading) { $st.EmptyNote = (T 'popup.scanning') }
    } else {
        $e.EmptyTitle.Text = (T 'popup.looking_for_agents'); $e.EmptyHint.Text = (T 'popup.reading_quota')
        $e.EmptyList.Visibility = 'Collapsed'; $e.RescanBtn.Visibility = 'Collapsed'; $st.EmptyNote = $null
    }
    $e.EmptyNote.Text = [string]$st.EmptyNote
    $e.EmptyNote.Visibility = Get-AgentViewVisibility $st.EmptyNote
    $e.Root
}

# Dựng lại nội dung từ $st.Rows. Mode như Set-AgentViewCard.
function Update-AgentViewPopupView([string]$Mode = 'update') {
    $st = Get-AgentViewPopupState
    if (-not $st.Window) { return }
    $theme = $st.Theme
    $view = Get-AgentViewUiProviderView
    $rows = @(Get-AgentViewDisplayRows $st.Rows $view)
    $st.NoAgent = [bool]$view.NoAgent -and $rows.Count -eq 0
    $now = Get-Date
    $history = Get-AgentViewPopupHistory
    $st.Ui.SettingsBtn.Visibility = Get-AgentViewVisibility $st.OnSettings
    Update-AgentViewPopupUpdateChip
    $panel = $st.Ui.Cards
    $panel.Children.Clear()
    $order = @()
    $groups = @(Get-AgentViewFamilyGroups $rows)
    $headersUsed = @()
    foreach ($g in $groups) {
        $grouped = @($g.Rows).Count -gt 1
        if ($grouped) {
            if (-not $st.Headers.ContainsKey($g.Family)) { $st.Headers[$g.Family] = New-AgentViewFamilyHeader $g.Family }
            $head = $st.Headers[$g.Family]
            $head.Root.Margin = New-Object System.Windows.Thickness 4, $(if ($panel.Children.Count -gt 0) { 10 } else { 2 }), 0, 6
            [void]$panel.Children.Add($head.Root); $headersUsed += $g.Family
        }
        foreach ($row in $g.Rows) {
            $key = [string]$row.Provider; if (-not $key) { $key = [string]$row.Name }
            if ($order -contains $key) { continue }
            $order += $key
            if (-not $st.Cards.ContainsKey($key)) { $st.Cards[$key] = New-AgentViewCard $key $g.Family }
            $model = Get-AgentViewCardModel $row -Loading:$st.Loading -Now $now -History $history
            $display = $null; if ($grouped -and $model.Group) { $display = $model.Group }
            $cardMode = $Mode; if (($st.Order -notcontains $key) -and $Mode -eq 'update') { $cardMode = 'open' }
            Set-AgentViewCard $st.Cards[$key] $model $cardMode $display
            $card = $st.Cards[$key]
            $card.Root.Margin = New-Object System.Windows.Thickness 0, $(if ($panel.Children.Count -gt 0 -and -not ($grouped -and $row -eq $g.Rows[0])) { 6 } else { 0 }), 0, 0
            [void]$panel.Children.Add($card.Root)
        }
    }
    foreach ($k in @($st.Headers.Keys)) { if ($headersUsed -notcontains $k) { $st.Headers.Remove($k) } }
    foreach ($k in @($st.Cards.Keys)) { if ($order -notcontains $k) { Suspend-AgentRing $st.Cards[$k].Ring; $st.Cards.Remove($k) } }
    if (-not $order.Count) { [void]$panel.Children.Add((Update-AgentViewEmptyCard $st.NoAgent)) }
    $st.Order = $order
    Set-AgentViewPopupExpanded (Get-AgentViewPopupExpandedKey $st.Expanded ([string[]]$order))
    $status = Get-AgentViewStatusModel $rows -Loading:$st.Loading -NoAgent:$st.NoAgent
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
    $now = Get-Date
    $foot = Get-AgentViewFooterModel $rows -Loading:$st.Loading -Now $now -NoAgent:$st.NoAgent
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

# OnRescan (tùy chọn): nút "Quét lại" của trạng thái trống; thiếu ⇒ Invoke-AgentViewPopupRescan tự tìm tray.
function Show-AgentViewPopup {
    param($Rows, [switch]$Loading, [scriptblock]$OnRefresh, [scriptblock]$OnRetry, [scriptblock]$OnSettings, [string]$UpdateVersion, [scriptblock]$OnUpdate, [scriptblock]$OnRescan)
    $st = Get-AgentViewPopupState
    $st.Rows = $Rows; $st.Loading = [bool]$Loading
    if ($OnRefresh) { $st.OnRefresh = $OnRefresh }
    if ($OnRetry) { $st.OnRetry = $OnRetry }
    if ($OnRescan) { $st.OnRescan = $OnRescan }
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
    $st.EmptyNote = $null; $st.RescanPending = $false
    $ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $st.WorkArea = [System.Windows.SystemParameters]::WorkArea
    $ui.Shell.MaxHeight = Get-AgentViewPopupMaxHeight $st.WorkArea
    Update-AgentViewPopupView 'open'
    $ui.Scroll.ScrollToTop()

    $ui.Shell.Measure((New-Object System.Windows.Size $w.Width, ([double]::PositiveInfinity)))
    $place = Get-AgentViewPopupPlacement $st.WorkArea $ui.Shell.DesiredSize.Height
    $w.Left = $place.Left; $w.Top = $place.Top
    $ui.Shell.Opacity = 0
    $w.Show()
    [void]$w.Activate()

    $ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-AgentViewDoubleAnimation 0 1 $m.InMs))
    Start-AgentViewPopupMotion $ui $true
    for ($i = 0; $i -lt $st.Order.Count; $i++) {
        $card = $st.Cards[$st.Order[$i]]
        $delay = [math]::Min($i, 6) * $m.CardStaggerMs
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

# Khung trượt dọc 12px + thu nhẹ 0.985 (vào: CubicOut InMs; ra: CubicIn OutMs). Độ mờ do người gọi chạy.
function Start-AgentViewPopupMotion($Ui, [bool]$In) {
    $m = Get-AgentViewPopupMetrics
    if ($In) { $ms = $m.InMs; $ease = 'CubicOut'; $y = 12, 0; $k = 0.985, 1 } else { $ms = $m.OutMs; $ease = 'CubicIn'; $y = 0, 12; $k = 1, 0.985 }
    $Ui.ShellShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-AgentViewDoubleAnimation $y[0] $y[1] $ms $ease))
    foreach ($p in [System.Windows.Media.ScaleTransform]::ScaleXProperty, [System.Windows.Media.ScaleTransform]::ScaleYProperty) {
        $Ui.ShellScale.BeginAnimation($p, (New-AgentViewDoubleAnimation $k[0] $k[1] $ms $ease))
    }
}

# Dừng mọi vòng lặp (chân popup, shimmer, vòng đo) để idle CPU ~0.
function Stop-AgentViewPopupLoops($State) {
    $State.FootTimer.Stop()
    Set-AgentViewShimmer $false
    foreach ($card in $State.Cards.Values) { Suspend-AgentRing $card.Ring }
}

function Hide-AgentViewPopup {
    $st = Get-AgentViewPopupState
    if (-not (Test-AgentViewPopupOpen)) { return }
    $st.Closing = $true
    Stop-AgentViewPopupLoops $st
    $fade = New-AgentViewDoubleAnimation 1 0 (Get-AgentViewPopupMetrics).OutMs 'CubicIn'
    $fade.Add_Completed({
        $s = Get-AgentViewPopupState
        if ($s.Closing -and $s.Window) { $s.Window.Hide(); $s.Closing = $false; Request-AgentViewUiTrim }
    })
    Start-AgentViewPopupMotion $st.Ui $false
    $st.Ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
}

# Đóng hẳn (thoát app/test); người dùng đóng thường chỉ ẩn có hoạt ảnh.
function Close-AgentViewPopup {
    param([switch]$Force)
    if (-not $Force) { Hide-AgentViewPopup; return }
    $st = Get-AgentViewPopupState
    if (-not $st.Window) { return }
    $st.Closing = $true
    Stop-AgentViewPopupLoops $st
    Remove-AgentViewHandlers $st
    # Gỡ đồng hồ mờ dần (và Completed của nó) trước khi đóng.
    $st.Ui.Shell.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    Close-AgentViewWindowNow $st.Window
    $st.Window = $null; $st.Cards = @{}; $st.Headers = @{}; $st.Empty = $null; $st.Ui = @{}; $st.Closing = $false; $st.Expanded = $null
}
