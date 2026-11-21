# Cửa sổ cài đặt WPF không modal; dot-source chỉ định nghĩa hàm/chuỗi.
if (-not (Test-Path function:Register-AgentViewStrings)) { . (Join-Path $PSScriptRoot 'I18n.ps1') }
if (-not (Test-Path function:Initialize-AgentViewWpf)) { . (Join-Path $PSScriptRoot 'Ui.ps1') }
if (-not (Test-Path function:Get-AgentViewPaths)) { . (Join-Path $PSScriptRoot 'Cli.ps1') }
if (-not (Test-Path function:Get-AgentViewHistoryEntry)) { . (Join-Path $PSScriptRoot 'History.ps1') }
Register-AgentViewStrings -Module 'settings' -Strings @{
    en=@{
        title='Settings'; language='Language'; auto='Automatic'; english='English'; vietnamese=([Globalization.CultureInfo]::GetCultureInfo('vi').NativeName)
        refresh='Refresh every'; minute1='1 minute'; minute2='2 minutes'; minute5='5 minutes'
        notifications='Quota notifications'; enabled='Enable notifications'; threshold1='First threshold (%)'; threshold2='Second threshold (%)'
        update='Check for updates automatically'; reset='Notify when quota refills'; desktop='Desktop'; widget='Show floating widget'; autostart='Start at sign-in'
        providers='Visible providers'; missing='Not installed'; rescan='Rescan'; save='Save'; cancel='Cancel'
        thresholds_error='Enter whole numbers from 5 to 90. The first threshold must be higher than the second.'
        providers_error='Keep at least one provider visible.'; save_error='Could not save settings. Please try again.'
    }
    vi=@{
        title='Cài đặt'; language='Ngôn ngữ'; auto='Tự động'; english='English'; vietnamese='Tiếng Việt'
        refresh='Làm mới mỗi'; minute1='1 phút'; minute2='2 phút'; minute5='5 phút'
        notifications='Thông báo quota'; enabled='Bật thông báo'; threshold1='Ngưỡng 1 (%)'; threshold2='Ngưỡng 2 (%)'
        update='Tự kiểm tra cập nhật'; reset='Báo khi quota đầy lại'; desktop='Màn hình'; widget='Hiện widget nổi'; autostart='Tự chạy khi đăng nhập'
        providers='Provider hiển thị'; missing='Chưa cài'; rescan='Quét lại'; save='Lưu'; cancel='Hủy'
        thresholds_error='Nhập số nguyên từ 5 đến 90. Ngưỡng 1 phải lớn hơn ngưỡng 2.'
        providers_error='Cần hiển thị ít nhất một provider.'; save_error='Không lưu được cài đặt. Vui lòng thử lại.'
    }
}
function Get-AgentViewSettingsWindowState {
    Get-AgentViewUiState 'agent-view.settings-window' { @{ Window = $null; Ui = @{}; OnSaved = $null; Handlers = @() } }
}
function Get-AgentViewSettingsWindowXaml {
    $resources=@'
 <Window.Resources>
  <Style TargetType="TextBlock"><Setter Property="VerticalAlignment" Value="Center"/></Style>
  <Style TargetType="CheckBox">
   <Setter Property="Margin" Value="0,5,0,5"/><Setter Property="Foreground" Value="@@av-text@@"/>
  </Style>
  <Style TargetType="RadioButton">
   <Setter Property="Margin" Value="0,5,14,5"/><Setter Property="Foreground" Value="@@av-text@@"/>
  </Style>
  <Style TargetType="TextBox">
   <Setter Property="Background" Value="@@av-surface@@"/><Setter Property="Foreground" Value="@@av-text@@"/>
   <Setter Property="BorderBrush" Value="@@av-stroke@@"/><Setter Property="Padding" Value="8,5"/>
   <Setter Property="CaretBrush" Value="@@accent@@"/><Setter Property="Width" Value="64"/>
  </Style>
  <Style TargetType="Button">
   <Setter Property="Foreground" Value="@@av-text@@"/><Setter Property="Background" Value="@@av-surface-hi@@"/>
   <Setter Property="BorderBrush" Value="@@av-stroke@@"/><Setter Property="Padding" Value="20,8"/>
   <Setter Property="Margin" Value="8,0,0,0"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
     <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="BorderBrush" Value="@@accent@@"/></Trigger>
     <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ButtonBorder" Property="BorderBrush" Value="@@accent@@"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Heading" TargetType="TextBlock">
   <Setter Property="Foreground" Value="@@av-text-2@@"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,16,0,5"/>
  </Style>
 </Window.Resources>
'@
    $body=@'
  <ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="24,20,24,22">
   <TextBlock x:Name="TitleBar" Text="@title@" FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="22" FontWeight="SemiBold"/>
   <TextBlock Text="@language@" Style="{StaticResource Heading}"/>
   <WrapPanel>
    <RadioButton x:Name="LangAuto" GroupName="Language" Content="@auto@"/>
    <RadioButton x:Name="LangEn" GroupName="Language" Content="@english@"/>
    <RadioButton x:Name="LangVi" GroupName="Language" Content="@vietnamese@"/>
   </WrapPanel>
   <TextBlock Text="@refresh@" Style="{StaticResource Heading}"/>
   <WrapPanel>
    <RadioButton x:Name="Refresh60" GroupName="Refresh" Content="@minute1@"/>
    <RadioButton x:Name="Refresh120" GroupName="Refresh" Content="@minute2@"/>
    <RadioButton x:Name="Refresh300" GroupName="Refresh" Content="@minute5@"/>
   </WrapPanel>
   <TextBlock Text="@notifications@" Style="{StaticResource Heading}"/>
   <CheckBox x:Name="NotifyEnabled" Content="@enabled@"/>
   <Grid Margin="0,4,0,4">
    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="80"/><ColumnDefinition/><ColumnDefinition Width="64"/></Grid.ColumnDefinitions>
    <TextBlock Text="@threshold1@"/><TextBox x:Name="Threshold1" Grid.Column="1" HorizontalAlignment="Left"/>
    <TextBlock Text="@threshold2@" Grid.Column="2"/><TextBox x:Name="Threshold2" Grid.Column="3"/>
   </Grid>
   <CheckBox x:Name="NotifyReset" Content="@reset@"/>
   <CheckBox x:Name="UpdateCheck" Content="@update@"/>
   <TextBlock Text="@desktop@" Style="{StaticResource Heading}"/>
   <CheckBox x:Name="WidgetEnabled" Content="@widget@"/>
   <CheckBox x:Name="Autostart" Content="@autostart@"/>
   <TextBlock Text="@providers@" Style="{StaticResource Heading}"/>
   <StackPanel x:Name="Providers"/>
   <TextBlock x:Name="ProviderHint" Foreground="@@av-text-2@@" Text="@providers_error@" TextWrapping="Wrap" Margin="0,5,0,0" Visibility="Collapsed"/>
   <TextBlock x:Name="Error" Foreground="@@crit-hi@@" TextWrapping="Wrap" Margin="0,10,0,0" Visibility="Collapsed"/>
   <DockPanel Margin="0,20,0,0">
    <Button x:Name="Rescan" Content="@rescan@" DockPanel.Dock="Left" Margin="0" Visibility="Collapsed"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
     <Button x:Name="Cancel" Content="@cancel@"/>
     <Button x:Name="Save" Content="@save@" Background="@@accent@@" Foreground="@@av-bg@@" IsDefault="True"/>
    </StackPanel>
   </DockPanel>
  </StackPanel>
  </ScrollViewer>
'@
    $x=Get-AgentViewShellXaml -Resources $resources -Body $body -Shell 'Margin="28,16,28,44" CornerRadius="8"' `
        -Window 'Title="@title@" Width="512" SizeToContent="Height" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Foreground="@@av-text@@"'
    $x=Expand-AgentViewXaml $x
    [regex]::Replace($x,'@([a-z0-9_]+)@',{param($m) [Security.SecurityElement]::Escape((Get-AgentViewText ('settings.'+$m.Groups[1].Value)))})
}
# A grouped Family is checked when all its groups are visible and mixed when only some are.
function Sync-AgentViewSettingsFamilyCheck($Entry) {
    $checked = @($Entry.Groups | Where-Object { $_.Box.IsChecked }).Count
    $Entry.Box.IsChecked = if ($checked -eq $Entry.Groups.Count) { $true } elseif ($checked) { $null } else { $false }
}
function Get-AgentViewSettingsVisibleChecks($State) {
    foreach ($entry in $State.Providers) {
        if (-not $entry.Detected) { continue }
        if ($entry.Groups.Count) {
            foreach ($group in $entry.Groups) { if ($group.Box.IsChecked) { $group.Box } }
        } elseif ($entry.Box.IsChecked) { $entry.Box }
    }
}
function Update-AgentViewSettingsProviderChecks($State, $Detected) {
    foreach ($entry in $State.Providers) {
        $entry.Detected = $entry.Id -cin $Detected
        $entry.Missing.Visibility = Get-AgentViewVisibility (-not $entry.Detected)
    }
    $visible = @(Get-AgentViewSettingsVisibleChecks $State)
    foreach ($entry in $State.Providers) {
        $entry.Box.IsEnabled = $entry.Detected -and -not ($visible.Count -eq 1 -and $entry.Box.IsChecked -ne $false)
        foreach ($group in $entry.Groups) {
            $group.Box.IsEnabled = $entry.Detected -and -not ($visible.Count -eq 1 -and $group.Box.IsChecked)
        }
    }
    $State.Ui.ProviderHint.Visibility = Get-AgentViewVisibility ($visible.Count -eq 1)
}
function Initialize-AgentViewSettingsProviders($State, $Settings, $Detected, $Rows, $Paths) {
    # Hidden ids alone do not prove that a group has been seen.
    $labels = @{'antigravity-gemini'='Gemini'; 'antigravity-3p'='Claude/GPT'; 'antigravity-argon'='Argon'}
    $history = Get-AgentViewHistoryEntry (Join-Path $Paths.Root 'history.json')
    $groups = @(
        foreach ($row in @(ConvertTo-QuotaRows $Rows)) {
            if ($row.Group) { $labels[[string]$row.Provider] = $row.Group }
            $row.Provider
        }
        foreach ($key in $history.Series.Keys) { ($key -split '\|', 2)[0] }
    )
    $groups = @($groups | Where-Object { $_ -cmatch '^[a-z0-9]+(-[a-z0-9]+)+$' } | Select-Object -Unique)
    $entries = @(foreach ($provider in Get-AgentViewProviderList $Settings $Detected $groups) {
        $box = New-Object Windows.Controls.CheckBox
        $box.Content = $provider.Name
        $box.Tag = $provider.Family
        $box.IsChecked = -not $provider.Hidden
        $panel = New-Object Windows.Controls.DockPanel
        $missing = New-Object Windows.Controls.TextBlock
        $missing.Text = Get-AgentViewText 'settings.missing'
        $missing.Foreground = ConvertTo-AgentViewBrush (Get-AgentViewTheme)['av-text-2']
        $missing.HorizontalAlignment = 'Right'
        [Windows.Controls.DockPanel]::SetDock($missing, 'Right')
        [void]$panel.Children.Add($missing)
        [void]$panel.Children.Add($box)
        [void]$State.Ui.Providers.Children.Add($panel)

        $children = @(foreach ($group in $provider.Groups) {
            $child = New-Object Windows.Controls.CheckBox
            $child.Content = if ($labels.ContainsKey($group.Id)) { $labels[$group.Id] } else { $group.Id.Substring($provider.Family.Length + 1) }
            $child.Tag = $provider.Family
            $child.Margin = New-Object Windows.Thickness 22,5,0,5
            $child.IsChecked = -not ($provider.Hidden -or $group.Hidden)
            [void]$State.Ui.Providers.Children.Add($child)
            [pscustomobject]@{ Id=$group.Id; Box=$child }
        })
        # Leave the Family controls accessible by id for callers of the settings window.
        $State.Ui[$provider.Family] = $box
        $entry = [pscustomobject]@{ Id=$provider.Family; Box=$box; Groups=$children; Missing=$missing; Detected=$provider.Detected }
        if ($children.Count) { Sync-AgentViewSettingsFamilyCheck $entry }
        $entry
    })
    $State.Providers = $entries
    # Match the tray's fallback when every detected Family or group was hidden by an older settings file.
    $State.UsingVisibilityFallback = -not @(Get-AgentViewSettingsVisibleChecks $State).Count
    if ($State.UsingVisibilityFallback) {
        foreach ($entry in $entries | Where-Object Detected) {
            $entry.Box.IsChecked = $true
            foreach ($group in $entry.Groups) { $group.Box.IsChecked = $true }
        }
    }
    $State.InitialChecks = @{}
    foreach ($entry in $entries) {
        $State.InitialChecks[$entry.Id] = $entry.Box.IsChecked
        foreach ($group in $entry.Groups) { $State.InitialChecks[$group.Id] = $group.Box.IsChecked }
        Add-AgentViewHandler $State $entry.Box 'Click' {
            $st = Get-AgentViewSettingsWindowState
            $entry = $st.Providers | Where-Object Id -CEQ $this.Tag
            foreach ($group in $entry.Groups) { $group.Box.IsChecked = $this.IsChecked }
            Update-AgentViewSettingsProviderChecks $st $st.Detected
        }
        foreach ($group in $entry.Groups) {
            Add-AgentViewHandler $State $group.Box 'Click' {
                $st = Get-AgentViewSettingsWindowState
                Sync-AgentViewSettingsFamilyCheck ($st.Providers | Where-Object Id -CEQ $this.Tag)
                Update-AgentViewSettingsProviderChecks $st $st.Detected
            }
        }
    }
    Update-AgentViewSettingsProviderChecks $State $Detected
}
function Get-AgentViewSettingsHiddenSelection($State, $Hidden) {
    $selection = @{}
    foreach ($entry in $State.Providers) {
        $selection[$entry.Id] = ($entry.Box.IsChecked -eq $false)
        foreach ($group in $entry.Groups) {
            $selection[$group.Id] = (-not $selection[$entry.Id] -and -not $group.Box.IsChecked)
        }
    }
    $changedFamilies = @(foreach ($entry in $State.Providers) {
        if ($State.InitialChecks[$entry.Id] -ne $entry.Box.IsChecked -or
            @($entry.Groups | Where-Object { $State.InitialChecks[$_.Id] -ne $_.Box.IsChecked }).Count) {
            $entry.Id
        }
    })
    $ids = @(foreach ($entry in $State.Providers) {
        if ($entry.Id -cin $changedFamilies -or ($changedFamilies.Count -and $State.UsingVisibilityFallback -and $entry.Detected)) {
            $entry.Id
            foreach ($group in $entry.Groups) { $group.Id }
        }
    })
    foreach ($id in $Hidden) { if ($id -cnotin $ids -or $selection[$id]) { $id } }
    foreach ($id in $ids) { if ($selection[$id] -and $id -cnotin $Hidden) { $id } }
}
function Save-AgentViewSettingsWindow {
    $st=Get-AgentViewSettingsWindowState; $ui=$st.Ui
    $hi=0; $lo=0
    $errorKey=$null
    if (-not [int]::TryParse($ui.Threshold1.Text,[ref]$hi) -or -not [int]::TryParse($ui.Threshold2.Text,[ref]$lo) -or $hi -gt 90 -or $lo -lt 5 -or $hi -le $lo) { $errorKey='thresholds_error' }
    elseif ($st.Detected.Count -and -not @(Get-AgentViewSettingsVisibleChecks $st).Count) { $errorKey='providers_error' }
    if ($errorKey) { $ui.Error.Text=Get-AgentViewText ('settings.'+$errorKey); $ui.Error.Visibility='Visible'; return $false }
    $s=Get-AgentViewSettings
    $s.Language=if ($ui.LangVi.IsChecked) {'vi'} elseif ($ui.LangEn.IsChecked) {'en'} else {'auto'}
    $s.RefreshSeconds=if ($ui.Refresh60.IsChecked) {60} elseif ($ui.Refresh300.IsChecked) {300} else {120}
    $s.UpdateCheck=[bool]$ui.UpdateCheck.IsChecked
    $s.NotifyEnabled=[bool]$ui.NotifyEnabled.IsChecked; $s.NotifyReset=[bool]$ui.NotifyReset.IsChecked
    $s.NotifyThresholds=@($hi,$lo); $s.WidgetEnabled=[bool]$ui.WidgetEnabled.IsChecked
    $s.HiddenProviders=@(Get-AgentViewSettingsHiddenSelection $st $s.HiddenProviders)
    try {
        Set-AgentViewAutostart (Get-AgentViewPaths) ([bool]$ui.Autostart.IsChecked)
        Save-AgentViewSettings $s
    } catch { $ui.Error.Text=Get-AgentViewText 'settings.save_error'; $ui.Error.Visibility='Visible'; return $false }
    $callback=$st.OnSaved
    Close-AgentViewSettingsWindow -Force
    if ($callback) { & $callback $s }
    return $true
}
function Show-AgentViewSettingsWindow {
    param([scriptblock]$OnSaved, [scriptblock]$OnRescan, [object[]]$Rows)
    $st=Get-AgentViewSettingsWindowState
    if ($st.Window) {
        if ($st.Window.WindowState -eq 'Minimized') { $st.Window.WindowState='Normal' }
        [void]$st.Window.Activate()
        return
    }
    Initialize-AgentViewWpf
    $w,$ui=New-AgentViewXamlObject (Get-AgentViewSettingsWindowXaml) $null @('Shell','TitleBar','LangAuto','LangEn','LangVi','Refresh60','Refresh120','Refresh300','NotifyEnabled','Threshold1','Threshold2','NotifyReset','UpdateCheck','WidgetEnabled','Autostart','Providers','ProviderHint','Rescan','Error','Cancel','Save')
    $st.Window=$w; $st.Ui=$ui; $st.OnSaved=$OnSaved; $st.OnRescan=$OnRescan; $st.Handlers=@()
    $w.MaxHeight=[Windows.SystemParameters]::WorkArea.Height
    $s=Get-AgentViewSettings
    $ui.LangAuto.IsChecked=($s.Language -eq 'auto'); $ui.LangEn.IsChecked=($s.Language -eq 'en'); $ui.LangVi.IsChecked=($s.Language -eq 'vi')
    $ui['Refresh'+$s.RefreshSeconds].IsChecked=$true
    $ui.UpdateCheck.IsChecked=$s.UpdateCheck
    $ui.NotifyEnabled.IsChecked=$s.NotifyEnabled; $ui.NotifyReset.IsChecked=$s.NotifyReset
    $ui.Threshold1.Text=[string]$s.NotifyThresholds[0]; $ui.Threshold2.Text=[string]$s.NotifyThresholds[1]
    $ui.WidgetEnabled.IsChecked=$s.WidgetEnabled; $ui.Autostart.IsChecked=Test-AgentViewAutostart (Get-AgentViewPaths)
    $st.Detected = @()
    if (Get-Command Get-AgentViewProviderView -ErrorAction SilentlyContinue) { $st.Detected = @((Get-AgentViewProviderView $s).Detected) }
    Initialize-AgentViewSettingsProviders $st $s $st.Detected $Rows (Get-AgentViewPaths)
    if ($OnRescan) {
        $ui.Rescan.Visibility = 'Visible'
        $st.ScanTimer = New-Object Windows.Threading.DispatcherTimer
        $st.ScanTimer.Interval = [timespan]::FromMilliseconds(500)
        Add-AgentViewHandler $st $st.ScanTimer 'Tick' {
            $st = Get-AgentViewSettingsWindowState
            if (-not (Get-Command Get-AgentViewProviderView -ErrorAction SilentlyContinue)) { return }
            $view = Get-AgentViewProviderView $null
            if ($view.Detected.Count -or $view.NoAgent) {
                $st.Detected = @($view.Detected)
                Update-AgentViewSettingsProviderChecks $st $st.Detected
            }
        }
        Add-AgentViewHandler $st $ui.Rescan 'Click' {
            $st = Get-AgentViewSettingsWindowState
            [void](& $st.OnRescan)
        }
        $st.ScanTimer.Start()
    }
    Add-AgentViewHandler $st $ui.Save 'Click' { [void](Save-AgentViewSettingsWindow) }
    Add-AgentViewHandler $st $ui.Cancel 'Click' { Close-AgentViewSettingsWindow -Force }
    Add-AgentViewHandler $st $ui.TitleBar 'MouseLeftButtonDown' { if ($_.ChangedButton -eq 'Left') { (Get-AgentViewSettingsWindowState).Window.DragMove() } }
    Add-AgentViewHandler $st $w 'PreviewKeyDown' { if ($_.Key -eq 'Escape') { $_.Handled=$true; Close-AgentViewSettingsWindow -Force } }
    Add-AgentViewHandler $st $w 'Closed' {
        $st = Get-AgentViewSettingsWindowState
        if ($st.ScanTimer) { $st.ScanTimer.Stop() }
        Remove-AgentViewHandlers $st
        [AppDomain]::CurrentDomain.SetData('agent-view.settings-window',$null)
    }
    [Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($w)
    $w.Show()
    [void]$w.Activate()
}
function Close-AgentViewSettingsWindow {
    param([switch]$Force)
    $st=Get-AgentViewSettingsWindowState
    if (-not $st.Window) { return }
    if ($st.ScanTimer) { $st.ScanTimer.Stop() }
    Remove-AgentViewHandlers $st
    Close-AgentViewWindowNow $st.Window
    [AppDomain]::CurrentDomain.SetData('agent-view.settings-window',$null)
}
