. (Join-Path $PSScriptRoot 'I18n.ps1')
Register-AgentViewStrings -Module 'tray' -Strings @{
    en = @{
        'quota_value' = '{0} {1}%'
        'quota_error' = '{0}: {1}'
        'refresh' = 'Refresh'
        'floating_widget' = 'Floating widget'
        'start_at_sign_in' = 'Start at sign-in'
        'quit' = 'Quit'
        'updating_quota' = 'Updating quota'
        'missing_quota_ps1' = 'Missing Quota.ps1'
        'cannot_read_quota' = 'Cannot read quota'
        'settings' = 'Settings…'
    }
    vi = @{
        'quota_value' = '{0} {1}%'
        'quota_error' = '{0} : {1}'
        'refresh' = 'Làm mới'
        'floating_widget' = 'Widget nổi'
        'start_at_sign_in' = 'Tự chạy khi đăng nhập'
        'quit' = 'Thoát'
        'updating_quota' = 'Đang cập nhật quota'
        'missing_quota_ps1' = 'Thiếu Quota.ps1'
        'cannot_read_quota' = 'Không đọc được quota'
        'settings' = 'Cài đặt…'
    }
}
. (Join-Path $PSScriptRoot 'Theme.ps1')
. (Join-Path $PSScriptRoot 'Format.ps1')
. (Join-Path $PSScriptRoot 'History.ps1')
. (Join-Path $PSScriptRoot 'Forecast.ps1')
. (Join-Path $PSScriptRoot 'Notify.ps1')
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,PresentationFramework,PresentationCore,WindowsBase,WindowsFormsIntegration
. (Join-Path $PSScriptRoot 'Popup.ps1')
. (Join-Path $PSScriptRoot 'Widget.ps1')
. (Join-Path $PSScriptRoot 'SettingsWindow.ps1')
function Format-QuotaTooltip($Rows) {
    $parts = foreach ($row in $Rows) {
        $name = $row.Name
        if ($row.Provider -eq 'claude') { $name = 'Claude' }
        $remaining = Get-QuotaRemaining $row
        if ($row.Ok -and $null -ne $remaining) { T 'tray.quota_value' -Args @($name, $remaining) } else { T 'tray.quota_error' -Args @($name, $row.Error) }
    }
    $text = 'agent-view' + "`n" + ($parts -join "`n")
    if ($text.Length -le 63) { return $text }
    $text = $parts -join ' · '
    if ($text.Length -gt 63) { $text = $text.Substring(0, 62); if ([char]::IsHighSurrogate($text[$text.Length-1])) { $text = $text.Substring(0,$text.Length-1) }; $text += '…' }
    return $text
}
function Get-AgentViewStartupPath {
    Join-Path ([Environment]::GetFolderPath('Startup')) 'agent-view.lnk'
}
function Set-AgentViewStartup([bool]$Enabled) {
    $path = Get-AgentViewStartupPath
    if (-not $Enabled) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue; return }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = '"' + (Join-Path $PSScriptRoot 'launch.vbs') + '"'
    $shortcut.Save()
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}
function Get-QuotaIconLayout([int]$Size, $Remaining, [switch]$Loading) {
    $spec = switch ($Size) { 16 { @(2,10,9,6.5) } 20 { @(2,12,11,8) } 24 { @(2.5,14,13,10) } default { @(3,19,17,13) } }
    $label = '?'; $index = 2
    if ($null -ne $Remaining) { $label = [string][int]$Remaining; $index = $label.Length }
    $fontSize = $spec[[math]::Min(3,$index)]
    if ($Remaining -eq 100 -and $Size -le 20) { $label = '✓' }
    if ($Loading) { $label = '' }
    [pscustomobject]@{Size=$Size;Stroke=$spec[0];FontSize=$fontSize;Label=$label;RoundCaps=($Size -ge 24)}
}
function Get-QuotaTrayRemaining($Rows) {
    $values = @($Rows | Where-Object { $_.Ok } | ForEach-Object { Get-QuotaRemaining $_ } | Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    return [int]($values | Measure-Object -Minimum).Minimum
}
function New-QuotaIconBitmap($Rows, [int]$Size = 16, [switch]$Loading, [int]$Frame = 0) {
    $remaining = Get-QuotaTrayRemaining $Rows
    $level = Get-QuotaLevel $remaining
    $theme = Get-AgentViewTheme
    $layout = Get-QuotaIconLayout $Size $remaining -Loading:$Loading
    $bitmap = New-Object Drawing.Bitmap $Size,$Size
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $resources = New-Object 'System.Collections.Generic.List[System.IDisposable]'
    try {
        $graphics.SmoothingMode = 'AntiAlias'; $graphics.TextRenderingHint = 'AntiAliasGridFit'
        $graphics.Clear([Drawing.Color]::Transparent)
        $disc = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($theme['tray-disc'])); $resources.Add($disc)
        $graphics.FillEllipse($disc,0,0,$Size,$Size)
        $trackColor = $theme['tray-track']; if ($null -eq $remaining -or $Loading) { $trackColor = '#5A6274' }
        $track = New-Object Drawing.Pen ([Drawing.ColorTranslator]::FromHtml($trackColor)),([single]$layout.Stroke); $resources.Add($track)
        $inset = [single]($layout.Stroke/2); $diameter = [single]($Size-$layout.Stroke)
        $graphics.DrawEllipse($track,$inset,$inset,$diameter,$diameter)
        if ($Loading -or ($null -ne $remaining -and $remaining -gt 0)) {
            $color = $theme[$level]; $alpha = 255; $start = -90; $sweep = 3.6*$remaining
            if ($Loading) { $color=$theme['unk-hi']; $start += ($Frame%8)*45; $sweep=90 }
            elseif ($level -eq 'crit') { $alpha = [int](255*@(1,.75,.45,.75)[$Frame%4]) }
            $arc = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($alpha,[Drawing.ColorTranslator]::FromHtml($color))),([single]$layout.Stroke); $resources.Add($arc)
            if ($layout.RoundCaps) { $arc.StartCap='Round'; $arc.EndCap='Round' }
            $graphics.DrawArc($arc,$inset,$inset,$diameter,$diameter,[single]$start,[single]$sweep)
        }
        if ($layout.Label -eq '✓') {
            $pen = New-Object Drawing.Pen ([Drawing.ColorTranslator]::FromHtml('#F4F6FA')),([single]($Size*.1125)); $resources.Add($pen)
            $pen.StartCap='Round'; $pen.EndCap='Round'; $pen.LineJoin='Round'
            $graphics.DrawLines($pen,[Drawing.PointF[]]@((New-Object Drawing.PointF ($Size*.31),($Size*.52)),(New-Object Drawing.PointF ($Size*.45),($Size*.65)),(New-Object Drawing.PointF ($Size*.70),($Size*.37))))
        } elseif ($layout.Label) {
            $font = New-Object Drawing.Font 'Segoe UI',([single]$layout.FontSize),([Drawing.FontStyle]::Bold),([Drawing.GraphicsUnit]::Pixel); $resources.Add($font)
            $color = '#F4F6FA'; if ($null -eq $remaining) { $color='#B8BFCC' }
            $brush = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($color)); $resources.Add($brush)
            $format = [Drawing.StringFormat]::GenericTypographic.Clone(); $resources.Add($format); $format.Alignment='Center'
            # GDI+ line box includes ascent/descent padding; place it manually around the centre.
            $height = $font.GetHeight($graphics)
            $graphics.DrawString($layout.Label,$font,$brush,[single]($Size/2),[single](($Size-$height)/2-.3),$format)
        }
        # Bitmap is one disposable value, not a list of quota rows.
        return ,$bitmap
    } catch { $bitmap.Dispose(); throw }
    finally { foreach ($resource in $resources) { $resource.Dispose() }; $graphics.Dispose() }
}
function New-QuotaIcon($Rows, [switch]$Loading, [int]$Frame = 0) {
    $size = [Windows.Forms.SystemInformation]::SmallIconSize.Width
    $bitmap = New-QuotaIconBitmap $Rows -Size $size -Loading:$Loading -Frame $Frame
    $handle = [IntPtr]::Zero
    try {
        $handle=$bitmap.GetHicon(); $borrowed=[Drawing.Icon]::FromHandle($handle)
        try { return $borrowed.Clone() } finally { $borrowed.Dispose() }
    } finally {
        if ($handle -ne [IntPtr]::Zero) { [void][AgentView.Native]::DestroyIcon($handle) }
        $bitmap.Dispose()
    }
}
function Initialize-AgentViewTrayNative {
    if (-not ('AgentView.Native' -as [type])) { Add-Type 'namespace AgentView { public static class Native { [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h); } }' }
}
# Đọc một trường settings (pscustomobject hoặc hashtable); thiếu/null ⇒ mặc định. Settings.ps1 có thể chưa có trường mới.
function Get-AgentViewSettingValue($Settings, [string]$Name, $Default) {
    if ($null -eq $Settings) { return $Default }
    $v = $null
    if ($Settings -is [System.Collections.IDictionary]) { if ($Settings.Contains($Name)) { $v = $Settings[$Name] } }
    elseif ($Settings.PSObject.Properties[$Name]) { $v = $Settings.$Name }
    if ($null -eq $v) { return $Default }
    return $v
}
# Chu kỳ refresh: 60/120/300 giây; giá trị khác hoặc thiếu ⇒ 120.
function Get-AgentViewRefreshSeconds($Settings) {
    $v = Get-AgentViewSettingValue $Settings 'RefreshSeconds' 120
    try { $i = [int]$v } catch { return 120 }
    if (@(60, 120, 300) -contains $i) { return $i }
    return 120
}
function Test-AgentViewRefreshDue($State, [datetime]$Now = (Get-Date)) {
    $seconds = 120; if ($State.RefreshSeconds) { $seconds = [int]$State.RefreshSeconds }
    return (($Now - $State.Last).TotalSeconds -ge $seconds)
}
# Bỏ provider bị ẩn khỏi phần hiển thị (icon/tooltip/popup/widget). Phát từng row; caller bọc @().
function Select-AgentViewVisibleRows($Rows, $Settings) {
    $hidden = @(@(Get-AgentViewSettingValue $Settings 'HiddenProviders' @()) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    foreach ($row in @(ConvertTo-QuotaRows $Rows)) {
        if ($hidden -contains [string]$row.Provider) { continue }
        $row
    }
}
# Gộp các thông báo của một lần refresh thành MỘT balloon. Warning nếu có mốc ≤ ngưỡng thấp nhất.
function Get-AgentViewBalloon($Notifications, $Settings) {
    $list = @(@($Notifications) | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return $null }
    $thresholds = @(Get-AgentViewNotifyThresholds $Settings)
    $warning = $false
    if ($thresholds.Count) {
        $low = ($thresholds | Measure-Object -Minimum).Minimum
        $warning = @($list | Where-Object { $_.Kind -eq 'low' -and $null -ne $_.Remaining -and $_.Remaining -le $low }).Count -gt 0
    }
    if ($list.Count -eq 1) { $title = [string]$list[0].Title; $text = [string]$list[0].Text }
    else {
        $title = 'agent-view'
        $text = (@($list | ForEach-Object { if ($_.Kind -eq 'low') { '{0} · {1}' -f $_.Title, $_.Text } else { [string]$_.Text } })) -join "`n"
    }
    if (-not $text) { $text = $title }
    if ($title.Length -gt 63) { $title = $title.Substring(0, 62) + '…' }
    if ($text.Length -gt 255) { $text = $text.Substring(0, 254) + '…' }
    $icon = [Windows.Forms.ToolTipIcon]::Info; if ($warning) { $icon = [Windows.Forms.ToolTipIcon]::Warning }
    [pscustomobject]@{ Title = $title; Text = $text; Icon = $icon; Count = $list.Count }
}
# Sau mỗi refresh thành công: ghi history (mọi provider Ok), quyết định + hiện balloon, lưu notify state. Mọi lỗi bị nuốt.
function Invoke-AgentViewRefreshHooks($Rows, $Settings, $Notify, [datetime]$Now = (Get-Date)) {
    $rows = @(ConvertTo-QuotaRows $Rows)
    try { Add-AgentViewHistory -Rows $rows -Now $Now } catch { }
    $balloon = $null
    try {
        $result = Get-AgentViewNotifications -Rows $rows -State (Read-AgentViewNotifyState) -Settings $Settings -Now $Now
        $balloon = Get-AgentViewBalloon $result.Notifications $Settings
        if ($balloon -and $Notify) { try { $Notify.ShowBalloonTip(8000, $balloon.Title, $balloon.Text, $balloon.Icon) } catch { } }
        Save-AgentViewNotifyState $result.State
    } catch { }
    return $balloon
}
function New-AgentViewTrayMenu {
    $strip = New-Object Windows.Forms.ContextMenuStrip
    $menu = @{ Strip = $strip }
    $menu.Settings = $strip.Items.Add('')
    $menu.Refresh = $strip.Items.Add('')
    $menu.Widget = $strip.Items.Add(''); $menu.Widget.CheckOnClick = $true
    $menu.Startup = $strip.Items.Add(''); $menu.Startup.CheckOnClick = $true
    $menu.Exit = $strip.Items.Add('')
    Update-AgentViewTrayMenuText $menu
    $menu
}
function Update-AgentViewTrayMenuText($Menu) {
    $Menu.Settings.Text = (T 'tray.settings')
    $Menu.Refresh.Text = (T 'tray.refresh')
    $Menu.Widget.Text = (T 'tray.floating_widget')
    $Menu.Startup.Text = (T 'tray.start_at_sign_in')
    $Menu.Exit.Text = (T 'tray.quit')
}
function Update-AgentViewTrayIcon($Tray) {
    $s = $Tray.State
    if (-not $Tray.Notify) { return }
    $old = $Tray.Notify.Icon
    $Tray.Notify.Icon = New-QuotaIcon $s.View -Loading:$s.Loading -Frame $s.Frame
    if ($old) { $old.Dispose() }
}
function Start-AgentViewRefresh($Tray) {
    $s = $Tray.State
    if ($null -ne $s.Worker) { return }
    $s.Loading = $true; $s.Frame = 0
    if ($Tray.Animation) { $Tray.Animation.Interval = 125; $Tray.Animation.Start() }
    Update-AgentViewPopup -Rows $s.View -Loading
    Update-AgentViewWidget -Rows $s.View -Loading
    $s.Worker = [PowerShell]::Create()
    [void]$s.Worker.AddScript({ param($path, $missingText, $readErrorText, $language)
        try {
            if (-not (Test-Path -LiteralPath $path)) { throw $missingText }
            . $path
            Set-AgentViewLanguage $language
            Get-AgentQuotas
        } catch {
            $errorText = $readErrorText; if (-not (Test-Path -LiteralPath $path)) { $errorText = $missingText }
            foreach ($provider in @('claude','codex')) {
                $providerName = 'Claude Code'; if ($provider -eq 'codex') { $providerName = 'Codex' }
                [pscustomobject]@{Provider=$provider;Name=$providerName;Ok=$false;Error=$errorText;FiveHourUsed=$null;WeekUsed=$null;FiveHourResetsAt=$null;WeekResetsAt=$null;FetchedAt=Get-Date} }
        }
    }).AddArgument((Join-Path $PSScriptRoot 'Quota.ps1')).AddArgument((T 'tray.missing_quota_ps1')).AddArgument((T 'tray.cannot_read_quota')).AddArgument((Get-AgentViewLanguage))
    $s.Pending = $s.Worker.BeginInvoke(); $s.Last = Get-Date
}
# Trên thread UI, sau ConvertTo-QuotaRows: history + thông báo, rồi lọc provider ẩn và cập nhật icon/tooltip/popup/widget.
function Complete-AgentViewRefresh($Tray, $Rows, [datetime]$Now = (Get-Date)) {
    $s = $Tray.State
    $s.Rows = @(ConvertTo-QuotaRows $Rows)
    $settings = (Get-AgentViewWidgetState).Settings
    [void](Invoke-AgentViewRefreshHooks -Rows $s.Rows -Settings $settings -Notify $Tray.Notify -Now $Now)
    $s.View = @(Select-AgentViewVisibleRows $s.Rows $settings)
    $s.Loading = $false; $s.Frame = 0
    if ($Tray.Animation) {
        $Tray.Animation.Stop()
        if ((Get-QuotaLevel (Get-QuotaTrayRemaining $s.View)) -eq 'crit') { $Tray.Animation.Interval = 400; $Tray.Animation.Start() }
    }
    Update-AgentViewPopup -Rows $s.View
    Update-AgentViewWidget -Rows $s.View
    if ($Tray.Notify) { Update-AgentViewTrayIcon $Tray; $Tray.Notify.Text = Format-QuotaTooltip $s.View }
}
# Áp settings vừa lưu từ cửa sổ cài đặt: ngôn ngữ (menu/tooltip/popup), chu kỳ refresh, provider ẩn, widget; rồi refresh ngay.
function Invoke-AgentViewSettingsApply($Settings, $Tray) {
    $ws = Get-AgentViewWidgetState
    if ($null -ne $Settings -and -not [object]::ReferenceEquals($Settings, $ws.Settings)) {
        $pairs = @{}
        if ($Settings -is [System.Collections.IDictionary]) { foreach ($k in $Settings.Keys) { $pairs[[string]$k] = $Settings[$k] } }
        else { foreach ($p in $Settings.PSObject.Properties) { $pairs[$p.Name] = $p.Value } }
        # Vị trí widget do widget tự quản; không ghi đè bằng bản có thể cũ của cửa sổ cài đặt.
        foreach ($k in $pairs.Keys) {
            if (@('WidgetEdge','WidgetOffset','WidgetScreen') -contains $k) { continue }
            $ws.Settings | Add-Member -NotePropertyName $k -NotePropertyValue $pairs[$k] -Force
        }
    }
    $settings = $ws.Settings
    $before = Get-AgentViewLanguage
    $language = [string](Get-AgentViewSettingValue $settings 'Language' 'auto')
    if (@('auto','vi','en') -notcontains $language) { $language = 'auto' }
    Set-AgentViewLanguage $language
    $languageChanged = ($before -ne (Get-AgentViewLanguage))
    $s = $Tray.State
    $s.RefreshSeconds = Get-AgentViewRefreshSeconds $settings
    $s.View = @(Select-AgentViewVisibleRows $s.Rows $settings)
    if ($Tray.Menu) {
        Update-AgentViewTrayMenuText $Tray.Menu
        try { $Tray.Menu.Startup.Checked = Test-Path (Get-AgentViewStartupPath) } catch { }
    }
    if ($Tray.Notify) {
        if ($s.Rows.Count) { Update-AgentViewTrayIcon $Tray; $Tray.Notify.Text = Format-QuotaTooltip $s.View } else { $Tray.Notify.Text = (T 'tray.updating_quota') }
    }
    # Chữ trong XAML popup dựng một lần ⇒ đổi ngôn ngữ thì bỏ cửa sổ, lần mở sau dựng lại.
    if ($languageChanged) { try { Close-AgentViewPopup -Force } catch { } }
    $wantWidget = [bool](Get-AgentViewSettingValue $settings 'WidgetEnabled' $false)
    if ($Tray.Menu) { $Tray.Menu.Widget.Checked = $wantWidget }
    if ($wantWidget -and -not (Test-AgentViewWidgetVisible)) { Show-AgentViewWidget -Rows $s.View -Loading:$s.Loading -OnOpenPopup $Tray.OpenPopup }
    elseif (-not $wantWidget -and (Test-AgentViewWidgetVisible)) { Hide-AgentViewWidget }
    else { Update-AgentViewWidget -Rows $s.View -Loading:$s.Loading }
    Update-AgentViewPopup -Rows $s.View -Loading:$s.Loading
    if ($Tray.Begin) { & $Tray.Begin }
}
function Start-AgentView {
    Initialize-AgentViewTrayNative
    $settings = (Get-AgentViewWidgetState).Settings
    $tray = @{
        State = @{ Rows=@(); View=@(); Worker=$null; Pending=$null; Last=[datetime]::MinValue; Frame=0; Loading=$false; RefreshSeconds=(Get-AgentViewRefreshSeconds $settings) }
        Context = (New-Object Windows.Forms.ApplicationContext); Notify = (New-Object Windows.Forms.NotifyIcon); Menu = (New-AgentViewTrayMenu)
        Animation = (New-Object Windows.Forms.Timer); Begin = $null; OpenPopup = $null; OpenSettings = $null; Apply = $null
    }
    $menu = $tray.Menu; $notify = $tray.Notify
    $menu.Widget.Checked = [bool](Get-AgentViewSettingValue $settings 'WidgetEnabled' $false)
    $menu.Startup.Checked = Test-Path (Get-AgentViewStartupPath)
    $notify.ContextMenuStrip = $menu.Strip; $notify.Icon = New-QuotaIcon @(); $notify.Text = (T 'tray.updating_quota'); $notify.Visible = $true
    $tray.Animation.Add_Tick({ $tray.State.Frame++; Update-AgentViewTrayIcon $tray }.GetNewClosure())
    $tray.Begin = { Start-AgentViewRefresh $tray }.GetNewClosure()
    $tray.Apply = { param($saved) Invoke-AgentViewSettingsApply -Settings $saved -Tray $tray }.GetNewClosure()
    $tray.OpenSettings = { Show-AgentViewSettingsWindow -OnSaved $tray.Apply }.GetNewClosure()
    $tray.OpenPopup = {
        $retry = { param($provider) & $tray.Begin }.GetNewClosure()
        Show-AgentViewPopup -Rows $tray.State.View -Loading:$tray.State.Loading -OnRefresh $tray.Begin -OnRetry $retry -OnSettings $tray.OpenSettings
    }.GetNewClosure()
    $menu.Settings.Add_Click({ & $tray.OpenSettings }.GetNewClosure())
    $menu.Widget.Add_Click({
        $s=Get-AgentViewWidgetState; $s.Settings.WidgetEnabled=$this.Checked
        if($this.Checked){Show-AgentViewWidget -Rows $tray.State.View -Loading:$tray.State.Loading -OnOpenPopup $tray.OpenPopup}else{Hide-AgentViewWidget}
        Save-AgentViewSettings $s.Settings
    }.GetNewClosure())
    if($menu.Widget.Checked){Show-AgentViewWidget -Rows $tray.State.View -OnOpenPopup $tray.OpenPopup}
    $menu.Refresh.Add_Click($tray.Begin)
    $menu.Startup.Add_Click({ Set-AgentViewStartup $this.Checked })
    $menu.Exit.Add_Click({ $tray.Context.ExitThread() }.GetNewClosure())
    $notify.Add_MouseClick({ if ($_.Button -eq [Windows.Forms.MouseButtons]::Left) { & $tray.OpenPopup } }.GetNewClosure())
    $timer = New-Object Windows.Forms.Timer; $timer.Interval = 250
    $timer.Add_Tick({
        $s = $tray.State
        if ($s.Worker -and $s.Pending.IsCompleted) {
            $rows = @()
            try { $rows = @(ConvertTo-QuotaRows ($s.Worker.EndInvoke($s.Pending))) } finally { $s.Worker.Dispose(); $s.Worker=$null }
            Complete-AgentViewRefresh $tray $rows
        }
        if (-not $s.Worker -and (Test-AgentViewRefreshDue $s)) { & $tray.Begin }
    }.GetNewClosure())
    try { & $tray.Begin; $timer.Start(); [Windows.Forms.Application]::Run($tray.Context) }
    finally {
        $timer.Stop(); $timer.Dispose(); $tray.Animation.Stop(); $tray.Animation.Dispose()
        Hide-AgentViewPopup
        Close-AgentViewSettingsWindow -Force
        Hide-AgentViewWidget
        if ($tray.State.Worker) { $tray.State.Worker.Stop(); $tray.State.Worker.Dispose() }
        $notify.Visible=$false; $notify.Icon.Dispose(); $notify.Dispose(); $menu.Strip.Dispose(); $tray.Context.Dispose()
    }
}
