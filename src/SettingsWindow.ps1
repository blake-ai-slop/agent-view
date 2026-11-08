# Cửa sổ cài đặt WPF không modal; dot-source chỉ định nghĩa hàm/chuỗi.
if (-not (Test-Path function:Register-AgentViewStrings)) { . (Join-Path $PSScriptRoot 'I18n.ps1') }
if (-not (Test-Path function:Initialize-AgentViewWpf)) { . (Join-Path $PSScriptRoot 'Ui.ps1') }
if (-not (Test-Path function:Get-AgentViewPaths)) { . (Join-Path $PSScriptRoot 'Cli.ps1') }
Register-AgentViewStrings -Module 'settings' -Strings @{
    en=@{
        title='Settings'; language='Language'; auto='Automatic'; english='English'; vietnamese=([Globalization.CultureInfo]::GetCultureInfo('vi').NativeName)
        refresh='Refresh every'; minute1='1 minute'; minute2='2 minutes'; minute5='5 minutes'
        notifications='Quota notifications'; enabled='Enable notifications'; threshold1='First threshold (%)'; threshold2='Second threshold (%)'
        update='Check for updates automatically'; reset='Notify when quota refills'; desktop='Desktop'; widget='Show floating widget'; autostart='Start at sign-in'
        providers='Visible providers'; claude='Claude Code'; codex='Codex'; save='Save'; cancel='Cancel'
        thresholds_error='Enter whole numbers from 5 to 90. The first threshold must be higher than the second.'
        providers_error='Keep at least one provider visible.'; save_error='Could not save settings. Please try again.'
    }
    vi=@{
        title='Cài đặt'; language='Ngôn ngữ'; auto='Tự động'; english='English'; vietnamese='Tiếng Việt'
        refresh='Làm mới mỗi'; minute1='1 phút'; minute2='2 phút'; minute5='5 phút'
        notifications='Thông báo quota'; enabled='Bật thông báo'; threshold1='Ngưỡng 1 (%)'; threshold2='Ngưỡng 2 (%)'
        update='Tự kiểm tra cập nhật'; reset='Báo khi quota đầy lại'; desktop='Màn hình'; widget='Hiện widget nổi'; autostart='Tự chạy khi đăng nhập'
        providers='Provider hiển thị'; claude='Claude Code'; codex='Codex'; save='Lưu'; cancel='Hủy'
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
   <WrapPanel>
    <CheckBox x:Name="Claude" Content="@claude@" Margin="0,5,30,5"/>
    <CheckBox x:Name="Codex" Content="@codex@"/>
   </WrapPanel>
   <TextBlock x:Name="Error" Foreground="@@crit-hi@@" TextWrapping="Wrap" Margin="0,10,0,0" Visibility="Collapsed"/>
   <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
    <Button x:Name="Cancel" Content="@cancel@"/>
    <Button x:Name="Save" Content="@save@" Background="@@accent@@" Foreground="@@av-bg@@" IsDefault="True"/>
   </StackPanel>
  </StackPanel>
'@
    $x=Get-AgentViewShellXaml -Resources $resources -Body $body -Shell 'Margin="28,16,28,44" CornerRadius="8"' `
        -Window 'Title="@title@" Width="512" SizeToContent="Height" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Foreground="@@av-text@@"'
    $x=Expand-AgentViewXaml $x
    [regex]::Replace($x,'@([a-z0-9_]+)@',{param($m) [Security.SecurityElement]::Escape((Get-AgentViewText ('settings.'+$m.Groups[1].Value)))})
}
function Save-AgentViewSettingsWindow {
    $st=Get-AgentViewSettingsWindowState; $ui=$st.Ui
    $hi=0; $lo=0
    $errorKey=$null
    if (-not [int]::TryParse($ui.Threshold1.Text,[ref]$hi) -or -not [int]::TryParse($ui.Threshold2.Text,[ref]$lo) -or $hi -gt 90 -or $lo -lt 5 -or $hi -le $lo) { $errorKey='thresholds_error' }
    elseif (-not $ui.Claude.IsChecked -and -not $ui.Codex.IsChecked) { $errorKey='providers_error' }
    if ($errorKey) { $ui.Error.Text=Get-AgentViewText ('settings.'+$errorKey); $ui.Error.Visibility='Visible'; return $false }
    $s=Get-AgentViewSettings
    $s.Language=if ($ui.LangVi.IsChecked) {'vi'} elseif ($ui.LangEn.IsChecked) {'en'} else {'auto'}
    $s.RefreshSeconds=if ($ui.Refresh60.IsChecked) {60} elseif ($ui.Refresh300.IsChecked) {300} else {120}
    $s.UpdateCheck=[bool]$ui.UpdateCheck.IsChecked
    $s.NotifyEnabled=[bool]$ui.NotifyEnabled.IsChecked; $s.NotifyReset=[bool]$ui.NotifyReset.IsChecked
    $s.NotifyThresholds=@($hi,$lo); $s.WidgetEnabled=[bool]$ui.WidgetEnabled.IsChecked
    $s.HiddenProviders=@(if (-not $ui.Claude.IsChecked) {'claude'}; if (-not $ui.Codex.IsChecked) {'codex'})
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
    param([scriptblock]$OnSaved)
    $st=Get-AgentViewSettingsWindowState
    if ($st.Window) {
        if ($st.Window.WindowState -eq 'Minimized') { $st.Window.WindowState='Normal' }
        [void]$st.Window.Activate()
        return
    }
    Initialize-AgentViewWpf
    $w,$ui=New-AgentViewXamlObject (Get-AgentViewSettingsWindowXaml) $null @('Shell','TitleBar','LangAuto','LangEn','LangVi','Refresh60','Refresh120','Refresh300','NotifyEnabled','Threshold1','Threshold2','NotifyReset','UpdateCheck','WidgetEnabled','Autostart','Claude','Codex','Error','Cancel','Save')
    $st.Window=$w; $st.Ui=$ui; $st.OnSaved=$OnSaved; $st.Handlers=@()
    $s=Get-AgentViewSettings
    $ui.LangAuto.IsChecked=($s.Language -eq 'auto'); $ui.LangEn.IsChecked=($s.Language -eq 'en'); $ui.LangVi.IsChecked=($s.Language -eq 'vi')
    $ui['Refresh'+$s.RefreshSeconds].IsChecked=$true
    $ui.UpdateCheck.IsChecked=$s.UpdateCheck
    $ui.NotifyEnabled.IsChecked=$s.NotifyEnabled; $ui.NotifyReset.IsChecked=$s.NotifyReset
    $ui.Threshold1.Text=[string]$s.NotifyThresholds[0]; $ui.Threshold2.Text=[string]$s.NotifyThresholds[1]
    $ui.WidgetEnabled.IsChecked=$s.WidgetEnabled; $ui.Autostart.IsChecked=Test-AgentViewAutostart (Get-AgentViewPaths)
    $ui.Claude.IsChecked=('claude' -notin $s.HiddenProviders); $ui.Codex.IsChecked=('codex' -notin $s.HiddenProviders)
    Add-AgentViewHandler $st $ui.Save 'Click' { [void](Save-AgentViewSettingsWindow) }
    Add-AgentViewHandler $st $ui.Cancel 'Click' { Close-AgentViewSettingsWindow -Force }
    Add-AgentViewHandler $st $ui.TitleBar 'MouseLeftButtonDown' { if ($_.ChangedButton -eq 'Left') { (Get-AgentViewSettingsWindowState).Window.DragMove() } }
    Add-AgentViewHandler $st $w 'PreviewKeyDown' { if ($_.Key -eq 'Escape') { $_.Handled=$true; Close-AgentViewSettingsWindow -Force } }
    Add-AgentViewHandler $st $w 'Closed' { [AppDomain]::CurrentDomain.SetData('agent-view.settings-window',$null) }
    [Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($w)
    $w.Show()
    [void]$w.Activate()
}
function Close-AgentViewSettingsWindow {
    param([switch]$Force)
    $st=Get-AgentViewSettingsWindowState
    if (-not $st.Window) { return }
    Remove-AgentViewHandlers $st
    Close-AgentViewWindowNow $st.Window
    [AppDomain]::CurrentDomain.SetData('agent-view.settings-window',$null)
}
