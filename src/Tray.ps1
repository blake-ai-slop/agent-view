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
        'update_click' = 'Click to update'
        'quota_groups' = '{0} {1}% ({2} groups)'
        'no_agent' = 'No agent detected (Claude Code, Codex, Antigravity)'
        'provider_added' = 'Added {0}'
        'provider_added_text' = 'Hide it in Settings'
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
        'update_click' = 'Bấm để cập nhật'
        'quota_groups' = '{0} {1}% ({2} nhóm)'
        'no_agent' = 'Chưa phát hiện agent nào (Claude Code, Codex, Antigravity)'
        'provider_added' = 'Đã thêm {0}'
        'provider_added_text' = 'Ẩn trong Cài đặt'
    }
}
. (Join-Path $PSScriptRoot 'Theme.ps1')
# Registry provider (tên/Short/thứ tự); Settings.ps1 cũng nạp nếu có. Thiếu file ⇒ dùng Name của row.
if (-not (Test-Path function:Get-AgentProviders) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Providers.ps1'))) { . (Join-Path $PSScriptRoot 'Providers.ps1') }
. (Join-Path $PSScriptRoot 'Format.ps1')
. (Join-Path $PSScriptRoot 'History.ps1')
. (Join-Path $PSScriptRoot 'Forecast.ps1')
. (Join-Path $PSScriptRoot 'Notify.ps1')
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,PresentationFramework,PresentationCore,WindowsBase,WindowsFormsIntegration
. (Join-Path $PSScriptRoot 'Popup.ps1')
. (Join-Path $PSScriptRoot 'Widget.ps1')
. (Join-Path $PSScriptRoot 'SettingsWindow.ps1')
# Toast agent-view (v0.2.1); thiếu file ⇒ chỉ balloon.
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Toast.ps1')) { . (Join-Path $PSScriptRoot 'Toast.ps1') }
# Kiểm tra cập nhật (v0.2.1); thiếu file ⇒ không có mục menu/chip/tự kiểm.
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Update.ps1')) { . (Join-Path $PSScriptRoot 'Update.ps1') }
# Registry entry của một Family; thiếu registry/không có ⇒ $null.
function Get-AgentViewProviderInfo([string]$Family) {
    if (-not (Test-Path function:Get-AgentProviders)) { return $null }
    foreach ($p in @(Get-AgentProviders)) { if ($p.Family -ceq $Family) { return $p } }
    return $null
}
# NotifyIcon.Text trên .NET Framework/PS5.1 tối đa 63 ký tự (≥64 ném 'Text length must be less than 64').
# Gom theo Family (tên Short): Family nhiều nhóm (Antigravity) hiện nhóm sát nhất + số nhóm. Dài quá ⇒ bỏ tiêu đề,
# rồi bỏ số nhóm và rút gọn lỗi để giữ % của mọi Family; cuối cùng mới cắt cứng kèm '…'.
function Get-AgentViewTrayTextMax { 63 }
function Limit-AgentViewText([string]$Text, [int]$Max) {
    if ($null -eq $Text -or $Text.Length -le $Max) { return $Text }
    if ($Max -le 1) { return '…'.Substring(0, [math]::Max(0, $Max)) }
    $cut = $Text.Substring(0, $Max - 1)
    if ($cut.Length -and [char]::IsHighSurrogate($cut[$cut.Length-1])) { $cut = $cut.Substring(0, $cut.Length-1) }
    return ($cut + '…')
}
function Format-QuotaTooltip($Rows) {
    $max = Get-AgentViewTrayTextMax
    $rows = @(ConvertTo-QuotaRows $Rows)
    $order = New-Object 'System.Collections.Generic.List[string]'; $groups = @{}
    foreach ($row in $rows) {
        $family = Get-QuotaRowFamily $row
        if (-not $groups.ContainsKey($family)) { $groups[$family] = New-Object System.Collections.ArrayList; $order.Add($family) }
        [void]$groups[$family].Add($row)
    }
    $items = foreach ($family in $order) {
        $list = $groups[$family].ToArray()
        $info = Get-AgentViewProviderInfo $family
        $name = if ($info) { [string]$info.Short } elseif ($family -eq 'claude') { 'Claude' } else { Limit-AgentViewText ([string]$list[0].Name) 16 }
        $values = @($list | Where-Object { $_.Ok } | ForEach-Object { Get-QuotaRemaining $_ } | Where-Object { $null -ne $_ })
        $value = $null; if ($values.Count) { $value = [int]($values | Measure-Object -Minimum).Minimum }
        [pscustomobject]@{ Name = $name; Value = $value; Count = $list.Count; Error = [string]$list[0].Error }
    }
    $items = @($items)
    $full = @(foreach ($it in $items) {
        if ($null -eq $it.Value) { T 'tray.quota_error' -Args @($it.Name, $it.Error) }
        elseif ($it.Count -gt 1) { T 'tray.quota_groups' -Args @($it.Name, $it.Value, $it.Count) }
        else { T 'tray.quota_value' -Args @($it.Name, $it.Value) }
    })
    $text = 'agent-view' + "`n" + ($full -join "`n")
    if ($text.Length -le $max) { return $text }
    $text = $full -join "`n"
    if ($text.Length -le $max) { return $text }
    # Gọn: bỏ số nhóm; lỗi chia đều phần còn lại.
    $fixed = @(foreach ($it in $items) { if ($null -eq $it.Value) { T 'tray.quota_error' -Args @($it.Name, '') } else { T 'tray.quota_value' -Args @($it.Name, $it.Value) } })
    $errCount = @($items | Where-Object { $null -eq $_.Value }).Count
    $used = ($fixed | Measure-Object -Property Length -Sum).Sum + [math]::Max(0, $fixed.Count - 1)
    $each = 0; if ($errCount) { $each = [math]::Max(0, [math]::Floor(($max - $used) / $errCount)) }
    $parts = @(for ($i = 0; $i -lt $items.Count; $i++) {
        if ($null -ne $items[$i].Value) { $fixed[$i] } else { $fixed[$i] + (Limit-AgentViewText $items[$i].Error $each) }
    })
    return (Limit-AgentViewText ($parts -join "`n") $max)
}
# Gán NotifyIcon.Text an toàn: cắt ≤63 rồi try/catch (Text ≥64 ném trên .NET Framework). Trả $true nếu gán được.
function Set-AgentViewTrayText($Notify, [string]$Text) {
    if (-not $Notify) { return $false }
    try { $Notify.Text = Limit-AgentViewText ([string]$Text) (Get-AgentViewTrayTextMax); return $true } catch { return $false }
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
function Get-QuotaIconLayout([int]$Size, $Remaining, [switch]$Loading, [switch]$NoAgent) {
    $spec = switch ($Size) { 16 { @(2,10,9,6.5) } 20 { @(2,12,11,8) } 24 { @(2.5,14,13,10) } default { @(3,19,17,13) } }
    $label = '?'; $index = 2
    if ($null -ne $Remaining) { $label = [string][int]$Remaining; $index = $label.Length }
    $fontSize = $spec[[math]::Min(3,$index)]
    if ($Remaining -eq 100 -and $Size -le 20) { $label = '✓' }
    if ($NoAgent -and $null -eq $Remaining) { $label = '–' }   # không phát hiện agent nào
    if ($Loading) { $label = '' }
    [pscustomobject]@{Size=$Size;Stroke=$spec[0];FontSize=$fontSize;Label=$label;RoundCaps=($Size -ge 24)}
}
function Get-QuotaTrayRemaining($Rows) {
    $values = @($Rows | Where-Object { $_.Ok } | ForEach-Object { Get-QuotaRemaining $_ } | Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    return [int]($values | Measure-Object -Minimum).Minimum
}
function New-QuotaIconBitmap($Rows, [int]$Size = 16, [switch]$Loading, [int]$Frame = 0, [switch]$NoAgent) {
    $remaining = Get-QuotaTrayRemaining $Rows
    $level = Get-QuotaLevel $remaining
    $theme = Get-AgentViewTheme
    $layout = Get-QuotaIconLayout $Size $remaining -Loading:$Loading -NoAgent:$NoAgent
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
function New-QuotaIcon($Rows, [switch]$Loading, [int]$Frame = 0, [switch]$NoAgent) {
    $size = [Windows.Forms.SystemInformation]::SmallIconSize.Width
    $bitmap = New-QuotaIconBitmap $Rows -Size $size -Loading:$Loading -Frame $Frame -NoAgent:$NoAgent
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
    if (-not ('AgentView.Native' -as [type])) { Add-Type 'namespace AgentView { public static class Native { [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
public static uint IdleMilliseconds() { var info = new LASTINPUTINFO(); info.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(info); return GetLastInputInfo(ref info) ? unchecked((uint)System.Environment.TickCount - info.dwTime) : 0; } } }' }
}
# Dọn bộ nhớ lúc rảnh (v0.2.2): GC rồi trả working set cho OS. Chạy trễ qua timer UI (sau refresh/đóng popup/toast,
# lúc không có hoạt ảnh), tối đa 1 lần/phút. Lỗi bị nuốt.
if ($null -eq $script:AgentViewMemoryTrim) { $script:AgentViewMemoryTrim = @{ Timer = $null; Last = [datetime]::MinValue; MinSeconds = 60; Count = 0 } }
function Invoke-AgentViewMemoryTrim([switch]$Force) {
    $t = $script:AgentViewMemoryTrim
    $now = Get-Date
    if (-not $Force -and $now -ge $t.Last -and ($now - $t.Last).TotalSeconds -lt $t.MinSeconds) { return $false }
    $t.Last = $now
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
    try {
        if (-not ('AgentView.Memory' -as [type])) { Add-Type 'namespace AgentView { public static class Memory { [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern bool SetProcessWorkingSetSize(System.IntPtr process, System.IntPtr min, System.IntPtr max); } }' }
        [void][AgentView.Memory]::SetProcessWorkingSetSize([IntPtr](-1), [IntPtr](-1), [IntPtr](-1))   # -1 = tiến trình hiện tại
    } catch { }
    $t.Count++
    return $true
}
function Request-AgentViewMemoryTrim([int]$DelayMs = 3000) {
    $t = $script:AgentViewMemoryTrim
    try {
        if (-not $t.Timer) {
            $t.Timer = New-Object Windows.Forms.Timer
            $t.Timer.Add_Tick({ $this.Stop(); try { [void](Invoke-AgentViewMemoryTrim) } catch { } })
        }
        $t.Timer.Stop(); $t.Timer.Interval = [math]::Max(1, $DelayMs); $t.Timer.Start()
    } catch { }
}
function Stop-AgentViewMemoryTrim {
    $t = $script:AgentViewMemoryTrim
    if ($t.Timer) { try { $t.Timer.Stop(); $t.Timer.Dispose() } catch { }; $t.Timer = $null }
}
# Đọc một trường settings (pscustomobject hoặc hashtable); thiếu/null ⇒ mặc định. Settings.ps1 có thể chưa có trường mới.
function Get-AgentViewSettingValue($Settings, [string]$Name, $Default) {
    Get-AgentViewNotifySetting $Settings $Name $Default
}
# Chu kỳ refresh: 60/120/300 giây; giá trị khác hoặc thiếu ⇒ 120.
function Get-AgentViewRefreshSeconds($Settings) {
    $v = Get-AgentViewSettingValue $Settings 'RefreshSeconds' 120
    try { $i = [int]$v } catch { return 120 }
    if (@(60, 120, 300) -contains $i) { return $i }
    return 120
}
# Hàm thuần: caller giữ CacheChanged tới khi refresh thực sự bắt đầu.
function Get-AgentViewNextRefresh($State, [datetime]$Now, [double]$IdleMs = 0) {
    $seconds = 120; if ($State.RefreshSeconds) { $seconds = [int]$State.RefreshSeconds }
    if ($IdleMs -gt 600000) { $seconds = [math]::Max($seconds, 600) }
    $at = $State.Last.AddSeconds($seconds); $reason = 'interval'
    if ($State.CacheChanged) {
        $cacheAt = $State.Last.AddSeconds(60)
        if ($cacheAt -lt $at) { $at = $cacheAt; $reason = 'cache' }
    }
    if ($State.ResetAt -and $State.ResetAt -lt $at) { $at = $State.ResetAt; $reason = 'reset' }
    [pscustomobject]@{ At = $at; Reason = $reason; Due = ($Now -ge $at) }
}
function Test-AgentViewRefreshDue($State, [datetime]$Now = (Get-Date)) {
    (Get-AgentViewNextRefresh $State $Now).Due
}
function Get-AgentViewResetRefreshAt($Rows, [datetime]$Now) {
    $next = $null
    foreach ($row in $Rows) {
        foreach ($value in @($row.FiveHourResetsAt, $row.WeekResetsAt)) {
            if ($null -eq $value) { continue }
            try { $reset = [datetime]$value } catch { continue }
            if ($reset -gt $Now -and ($null -eq $next -or $reset -lt $next)) { $next = $reset }
        }
    }
    if ($null -ne $next) { $next.AddSeconds(5) }
}
# Chỉ metadata trên UI thread; đường dẫn do Quota.ps1 quyết định.
function Update-AgentViewCacheStamp($State, [datetime]$Now) {
    if ($State.CachePollAt -and $Now -lt $State.CachePollAt) { return }
    $State.CachePollAt = $Now.AddSeconds(5)
    if (-not (Get-Command Get-ClaudeConfigPath -ErrorAction SilentlyContinue)) { return }
    $stamp = $null
    try {
        $path = Get-ClaudeConfigPath $env:CLAUDE_CONFIG_DIR ([Environment]::GetFolderPath('UserProfile'))
        $file = Get-Item -LiteralPath $path -ErrorAction Stop
        $stamp = $file.LastWriteTimeUtc
    } catch { }
    if ($State.CacheStampKnown -and $stamp -ne $State.CacheStamp) { $State.CacheChanged = $true }
    $State.CacheStamp = $stamp; $State.CacheStampKnown = $true
}
function Update-AgentViewCriticalAnimation($Tray, [datetime]$Now = (Get-Date)) {
    $s = $Tray.State
    if (-not $s.Loading -and (-not $s.CritUntil -or $Now -ge $s.CritUntil)) {
        $Tray.Animation.Stop(); $s.Frame = 0
        Update-AgentViewTrayIcon $Tray
        return
    }
    $s.Frame++; Update-AgentViewTrayIcon $Tray
}
# Bỏ provider bị ẩn khỏi phần hiển thị (icon/tooltip/popup/widget) theo quy tắc chung Select-QuotaShownRows
# (id = Provider hoặc Family; ẩn hết ⇒ hiện lại tất cả). Phát từng row; caller bọc @().
function Select-AgentViewVisibleRows($Rows, $Settings) {
    Select-QuotaShownRows $Rows (Get-AgentViewHiddenIds $Settings)
}
function Get-AgentViewHiddenIds($Settings) {
    [string[]]@(@(Get-AgentViewSettingValue $Settings 'HiddenProviders' @()) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
}
function Set-AgentViewSettingValue($Settings, [string]$Name, $Value) {
    if ($Settings -is [System.Collections.IDictionary]) { $Settings[$Name] = $Value }
    else { $Settings | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}
# ---------------------------------------------------------------- provider (v0.3.0)
# Family đã phát hiện, đọc cache AppDomain 'agent-view.ProviderPresence' (runspace refresh ghi). Chưa quét ⇒ $null.
function Get-AgentViewDetectedFamilies {
    $state = [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence')
    if ($null -eq $state) { return $null }
    $found = $state['Families']
    if ($null -eq $found) { return $null }
    return ,([string[]]@(@($found) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }))
}
# Cho popup/widget/settings: Detected = Family phát hiện được (chưa quét ⇒ rỗng); Hidden = id đang ẩn có hiệu lực
# (mọi Family phát hiện được đều bị ẩn ⇒ rỗng, như fallback hiển thị); NoAgent = đã quét và không thấy agent nào.
function Get-AgentViewProviderView($Settings) {
    $found = Get-AgentViewDetectedFamilies
    $detected = [string[]]@(); if ($null -ne $found) { $detected = [string[]]@($found) }
    $hidden = Get-AgentViewHiddenIds $Settings
    if ($detected.Count -gt 0 -and @($detected | Where-Object { $hidden -ccontains $_ }).Count -eq $detected.Count) { $hidden = [string[]]@() }
    @{ Detected = $detected; Hidden = [string[]]$hidden; NoAgent = ($null -ne $found -and $detected.Count -eq 0) }
}
# Nút "Quét lại" (thread UI): xóa cache phát hiện rồi refresh tay (Quota.ps1 quét lại trong runspace, không chạy
# tiến trình trên UI). Refresh đang chạy ⇒ xếp hàng, timer chạy ngay khi xong. Trả $true nếu đã bắt đầu.
function Invoke-AgentViewProviderRescan($Tray) {
    $state = [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence')
    if ($null -ne $state) { $state.Remove('Families') }
    if ($Tray.State.Worker) { $Tray.State.RescanQueued = $true; return $false }
    Start-AgentViewRefresh $Tray -Manual
    return $true
}
# Hàm thuần: Family phát hiện được mà chưa có trong KnownProviders. Notify chỉ khi KnownProviders trước đó không rỗng
# (bản cài cũ chưa ghi ⇒ chỉ ghi, không toast hàng loạt khi nâng cấp).
function Get-AgentViewProviderAdditions($Known, $Detected) {
    $k = [string[]]@(@($Known) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $added = [string[]]@(@($Detected) | Where-Object { $_ -and $k -cnotcontains [string]$_ } | ForEach-Object { [string]$_ } | Select-Object -Unique)
    [pscustomobject]@{ Added = $added; Known = [string[]]@($k + $added); Notify = ($added.Count -gt 0 -and $k.Count -gt 0) }
}
# Sau mỗi refresh (thread UI): Family mới ⇒ thêm vào KnownProviders, lưu settings; KnownProviders cũ không rỗng ⇒ tự hiện
# (bỏ id Family khỏi HiddenProviders, bộ cài ẩn sẵn Family chưa cài) + 1 toast "Đã thêm X". Trả kết quả additions hoặc $null.
function Update-AgentViewKnownProviders($Tray, $Settings) {
    $found = Get-AgentViewDetectedFamilies
    if ($null -eq $found -or $null -eq $Settings) { return $null }
    $r = Get-AgentViewProviderAdditions (Get-AgentViewSettingValue $Settings 'KnownProviders' @()) $found
    if ($r.Added.Count -eq 0) { return $r }
    Set-AgentViewSettingValue $Settings 'KnownProviders' $r.Known
    if ($r.Notify) {
        $hidden = Get-AgentViewHiddenIds $Settings
        $left = [string[]]@($hidden | Where-Object { $r.Added -cnotcontains $_ })
        if ($left.Count -ne $hidden.Count) {
            Set-AgentViewSettingValue $Settings 'HiddenProviders' $left
            # Family vừa hiện chưa được fetch (đã Skip) ⇒ refresh nền ở tick kế.
            if ($Tray -and $Tray.State) { $Tray.State.Last = (Get-Date).AddSeconds(-3600) }
        }
    }
    try { Save-AgentViewSettings $Settings } catch { }
    if ($r.Notify) {
        $items = @(foreach ($family in $r.Added) {
            $info = Get-AgentViewProviderInfo $family
            $name = $family; if ($info) { $name = [string]$info.Name }
            # Toast.ps1 nhận Kind low|reset|update; 'update' = biểu tượng thông báo không có %.
            @{ Provider = $family; Window = $null; Kind = 'update'; Remaining = $null; Title = (T 'tray.provider_added' -Args @($name)); Text = (T 'tray.provider_added_text') }
        })
        $balloon = Get-AgentViewBalloon $items $null
        $click = $null; if ($Tray) { $click = $Tray.OpenSettings; if (-not $click) { $click = $Tray.OpenToastPopup } }
        $notify = $null; if ($Tray) { $notify = $Tray.Notify }
        try { $r | Add-Member -NotePropertyName Shown -NotePropertyValue (Show-AgentViewNotification $balloon $notify $click) -Force } catch { }
    }
    return $r
}
# Lệnh CLI (agentview providers show|hide) ghi settings.json khi app đang chạy: đầu mỗi refresh, file đổi ⇒ nạp lại
# HiddenProviders/KnownProviders vào settings đang dùng. Lần đầu chỉ ghi mốc. Trả $true nếu đã nạp lại.
function Sync-AgentViewSettingsFile($State, $Settings, [string]$Path = (Join-Path $env:LOCALAPPDATA 'agent-view/settings.json')) {
    if ($null -eq $State -or $null -eq $Settings) { return $false }
    try { $stamp = [IO.File]::GetLastWriteTimeUtc($Path) } catch { return $false }
    if (-not $State.SettingsStampKnown) { $State.SettingsStamp = $stamp; $State.SettingsStampKnown = $true; return $false }
    if ($stamp -eq $State.SettingsStamp) { return $false }
    $State.SettingsStamp = $stamp
    try { $disk = Get-AgentViewSettings $Path } catch { return $false }
    Set-AgentViewSettingValue $Settings 'HiddenProviders' ([string[]]@($disk.HiddenProviders))
    Set-AgentViewSettingValue $Settings 'KnownProviders' ([string[]]@($disk.KnownProviders))
    return $true
}
function Get-AgentViewTrayText($State) {
    if ($State.NoAgent) { return (T 'tray.no_agent') }
    return (Format-QuotaTooltip $State.View)
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
        $text = (@($list | ForEach-Object { '{0} · {1}' -f $_.Title, $_.Text })) -join "`n"
    }
    if (-not $text) { $text = $title }
    if ($title.Length -gt 63) { $title = $title.Substring(0, 62) + '…' }
    if ($text.Length -gt 255) { $text = $text.Substring(0, 254) + '…' }
    $icon = [Windows.Forms.ToolTipIcon]::Info; if ($warning) { $icon = [Windows.Forms.ToolTipIcon]::Warning }
    [pscustomobject]@{ Title = $title; Text = $text; Icon = $icon; Count = $list.Count; Warning = $warning; Items = $list }
}
# Hiện thông báo đã gộp: toast agent-view nếu có và người dùng không bận; bận/không có/toast ném ⇒ balloon NotifyIcon.
# Trả 'toast' | 'balloon' | $null (không hiện được).
function Show-AgentViewNotification($Balloon, $Notify, [scriptblock]$OnClick) {
    if (-not $Balloon) { return $null }
    if ((Get-Command Show-AgentViewToast -ErrorAction SilentlyContinue) -and -not (Test-AgentViewUserBusy)) {
        try { Show-AgentViewToast -Items $Balloon.Items -Warning:$Balloon.Warning -OnClick $OnClick; return 'toast' } catch { }
    }
    if ($Notify) { try { $Notify.ShowBalloonTip(8000, $Balloon.Title, $Balloon.Text, $Balloon.Icon); return 'balloon' } catch { } }
    return $null
}
# Sau mỗi refresh thành công: ghi history (mọi provider Ok), quyết định + hiện thông báo (toast/balloon), lưu notify state. Mọi lỗi bị nuốt.
function Invoke-AgentViewRefreshHooks($Rows, $Settings, $Notify, [datetime]$Now = (Get-Date), [scriptblock]$OnClick = $null) {
    $rows = @(ConvertTo-QuotaRows $Rows)
    try { Add-AgentViewHistory -Rows $rows -Now $Now } catch { }
    $balloon = $null
    try {
        $result = Get-AgentViewNotifications -Rows $rows -State (Read-AgentViewNotifyState) -Settings $Settings -Now $Now
        $balloon = Get-AgentViewBalloon $result.Notifications $Settings
        if ($balloon) { $balloon | Add-Member -NotePropertyName Shown -NotePropertyValue (Show-AgentViewNotification $balloon $Notify $OnClick) -Force }
        Save-AgentViewNotifyState $result.State
    } catch { }
    return $balloon
}
# ---------------------------------------------------------------- kiểm tra cập nhật (Update.ps1)
function Test-AgentViewUpdateAvailable { [bool](Get-Command Invoke-AgentViewUpdateCheck -ErrorAction SilentlyContinue) }
# Trạng thái cập nhật của tray. Latest = phiên bản mới hơn bản đang chạy (từ state đã lưu hoặc lần kiểm gần nhất), không có ⇒ $null.
function New-AgentViewUpdateTrayState {
    $u = @{ Latest = $null; Url = $null; Worker = $null; Pending = $null; Force = $false; Manual = $false; ManualQueued = $false; Job = $null }
    if (Test-AgentViewUpdateAvailable) {
        try {
            $saved = Read-AgentViewUpdateState
            if ($saved -and $saved.LatestVersion -and (Compare-AgentViewVersion $saved.LatestVersion $script:AgentViewVersion) -gt 0) { $u.Latest = [string]$saved.LatestVersion; $u.Url = $saved.LatestUrl }
        } catch { }
    }
    $u
}
# Mục menu: đang kiểm tay ⇒ 'Đang kiểm tra…' (disabled); có bản mới ⇒ 'Cập nhật lên vX' (install); còn lại ⇒ 'Kiểm tra cập nhật' (check).
function Get-AgentViewUpdateMenuModel($Update) {
    if ($Update -and $Update.Manual -and ($Update.Worker -or $Update.ManualQueued)) { return [pscustomobject]@{ Text = (T 'update.checking'); Enabled = $false; Action = 'none' } }
    if ($Update -and $Update.Latest) { return [pscustomobject]@{ Text = (T 'update.install' -Args @($Update.Latest)); Enabled = $true; Action = 'install' } }
    [pscustomobject]@{ Text = (T 'update.check'); Enabled = $true; Action = 'check' }
}
function Set-AgentViewUpdateMenu($Menu) {
    if (-not $Menu -or -not $Menu.Update) { return }
    $model = Get-AgentViewUpdateMenuModel $Menu.UpdateState
    $Menu.Update.Text = $model.Text; $Menu.Update.Enabled = $model.Enabled
}
# Item toast kiểu 'update' cho một kết quả kiểm: newer ⇒ 'Có bản mới' + 'Bấm để cập nhật'; latest; error; skipped (nguồn không hỗ trợ).
function Get-AgentViewUpdateToastItem($Result) {
    if (-not $Result) { return $null }
    $title = $null; $text = ''
    switch ([string]$Result.Status) {
        'newer' { $title = T 'update.available' -Args @($Result.Latest); $text = T 'tray.update_click' }
        'latest' { $title = T 'update.latest' -Args @($Result.Current) }
        'error' { $title = T 'update.error' }
        'skipped' { $title = T 'update.unsupported' }
    }
    if (-not $title) { return $null }
    @{ Provider = 'agent-view'; Window = $null; Kind = 'update'; Remaining = $null; Title = $title; Text = $text; Status = [string]$Result.Status }
}
# Hiện kết quả qua cùng kênh với quota (toast; người dùng bận ⇒ balloon). Trả 'toast' | 'balloon' | $null.
function Show-AgentViewUpdateNotification($Result, $Notify, [scriptblock]$OnInstall) {
    $item = Get-AgentViewUpdateToastItem $Result
    if (-not $item) { return $null }
    $balloon = Get-AgentViewBalloon @($item) $null
    $click = $null; if ($item.Status -eq 'newer') { $click = $OnInstall }
    Show-AgentViewNotification $balloon $Notify $click
}
# Chạy Invoke-AgentViewUpdateCheck trong runspace nền (không chặn UI). -Manual ⇒ -Force + báo mọi kết quả.
# $Tray.Update.Job (test) thay script nền; nhận ($updatePath, $force, $language).
function Start-AgentViewUpdateCheck($Tray, [switch]$Manual) {
    $u = $Tray.Update
    if (-not $u -or -not (Test-AgentViewUpdateAvailable)) { return $false }
    if ($u.Worker) {
        # Tự kiểm đang chạy (không Force) ⇒ xếp kiểm tay chạy ngay sau.
        if ($Manual -and -not $u.Force) { $u.Manual = $true; $u.ManualQueued = $true; Set-AgentViewUpdateMenu $Tray.Menu }
        return $false
    }
    $job = $u.Job
    if (-not $job) {
        $job = { param($updatePath, $force, $language)
            . $updatePath
            Set-AgentViewLanguage $language
            Invoke-AgentViewUpdateCheck -Force:$force
        }
    }
    $u.Force = [bool]$Manual; $u.Manual = [bool]$Manual; $u.ManualQueued = $false
    $u.Worker = [PowerShell]::Create()
    [void]$u.Worker.AddScript($job).AddArgument((Join-Path $PSScriptRoot 'Update.ps1')).AddArgument([bool]$Manual).AddArgument((Get-AgentViewLanguage))
    $u.Pending = $u.Worker.BeginInvoke()
    Set-AgentViewUpdateMenu $Tray.Menu
    return $true
}
# Gọi từ timer UI: worker xong ⇒ lấy kết quả rồi Complete. Runspace lỗi/không trả gì ⇒ status error.
function Receive-AgentViewUpdateCheck($Tray) {
    $u = $Tray.Update
    if (-not $u -or -not $u.Worker -or -not $u.Pending.IsCompleted) { return $null }
    $result = $null
    try { $out = @($u.Worker.EndInvoke($u.Pending)); if ($out.Count) { $result = $out[$out.Count - 1] } } catch { }
    finally { $u.Worker.Dispose(); $u.Worker = $null; $u.Pending = $null }
    if (-not $result -or -not $result.Status) { $result = @{ Status = 'error'; Current = $script:AgentViewVersion; Latest = $null; Url = $null; ShouldNotify = $false } }
    $queued = $u.ManualQueued
    $shown = Complete-AgentViewUpdateCheck $Tray $result -Manual:($u.Force -and -not $queued)
    if ($queued) { [void](Start-AgentViewUpdateCheck $Tray -Manual) }
    return $shown
}
# Trên thread UI: ghi bản mới vào trạng thái tray, đổi menu + chip popup, rồi thông báo.
# Kiểm tay ⇒ luôn báo; tự kiểm ⇒ chỉ khi newer + ShouldNotify (error/skipped im lặng).
function Complete-AgentViewUpdateCheck($Tray, $Result, [switch]$Manual) {
    $u = $Tray.Update
    $u.Manual = $false
    switch ([string]$Result.Status) {
        'newer' { $u.Latest = [string]$Result.Latest; $u.Url = $Result.Url }
        'latest' { $u.Latest = $null; $u.Url = $null }
    }
    Set-AgentViewUpdateMenu $Tray.Menu
    try { Sync-AgentViewPopupUpdate $Tray } catch { }
    if ($Manual -or ($Result.Status -eq 'newer' -and $Result.ShouldNotify)) {
        try { return (Show-AgentViewUpdateNotification $Result $Tray.Notify $Tray.InstallUpdate) } catch { }
    }
    return $null
}
function Sync-AgentViewPopupUpdate($Tray) {
    if (-not $Tray.Update) { return }
    $install = $null; if ($Tray.Update.Latest) { $install = $Tray.InstallUpdate }
    Set-AgentViewPopupUpdate -Version $Tray.Update.Latest -OnUpdate $install
}
# Bấm mục menu cập nhật: có bản mới ⇒ cập nhật (console riêng); không ⇒ kiểm tay nền.
function Invoke-AgentViewUpdateMenu($Tray) {
    $model = Get-AgentViewUpdateMenuModel $Tray.Update
    if ($model.Action -eq 'install') { & $Tray.InstallUpdate; return 'install' }
    if ($model.Action -eq 'check') { [void](Start-AgentViewUpdateCheck $Tray -Manual); return 'check' }
    return 'none'
}
# Timer tự kiểm: lần đầu sau 2 phút, sau đó mỗi giờ; module tự lo UpdateCheck=false và hạn 24 giờ.
function Get-AgentViewUpdateTimerPlan { @{ FirstMs = 120000; EveryMs = 3600000 } }
function Invoke-AgentViewUpdateTimerTick($Tray, $Timer) {
    try { if ($Timer) { $Timer.Interval = (Get-AgentViewUpdateTimerPlan).EveryMs } } catch { }
    try { [void](Start-AgentViewUpdateCheck $Tray) } catch { }
}

function New-AgentViewTrayMenu {
    $strip = New-Object Windows.Forms.ContextMenuStrip
    $menu = @{ Strip = $strip; Update = $null; UpdateState = $null }
    $menu.Settings = $strip.Items.Add('')
    $menu.Refresh = $strip.Items.Add('')
    $menu.Widget = $strip.Items.Add(''); $menu.Widget.CheckOnClick = $true
    $menu.Startup = $strip.Items.Add(''); $menu.Startup.CheckOnClick = $true
    if (Test-AgentViewUpdateAvailable) { $menu.Update = $strip.Items.Add('') }   # ngay trên Thoát
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
    Set-AgentViewUpdateMenu $Menu
}
function Update-AgentViewTrayIcon($Tray) {
    $s = $Tray.State
    if (-not $Tray.Notify) { return }
    $old = $Tray.Notify.Icon
    $Tray.Notify.Icon = New-QuotaIcon $s.View -Loading:$s.Loading -Frame $s.Frame -NoAgent:([bool]$s.NoAgent)
    if ($old) { $old.Dispose() }
}
# Runspace refresh quota dùng chung giữa các lần refresh (State.Runspace): tạo 1 lần, Quota.ps1 nạp 1 lần trong đó.
# Không ở trạng thái Opened (hỏng/đã đóng) ⇒ bỏ và tạo mới.
function Get-AgentViewRefreshRunspace($State) {
    $rs = $State.Runspace
    if ($rs -and $rs.RunspaceStateInfo.State -ne [Management.Automation.Runspaces.RunspaceState]::Opened) { Reset-AgentViewRefreshRunspace $State; $rs = $null }
    if (-not $rs) {
        $rs = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.Open()
        $State.Runspace = $rs
    }
    return $rs
}
function Reset-AgentViewRefreshRunspace($State) {
    if ($State.Runspace) { try { $State.Runspace.Dispose() } catch { } }
    $State.Runspace = $null
}
function Start-AgentViewRefresh($Tray, [switch]$Manual) {
    $s = $Tray.State
    if ($null -ne $s.Worker) { return }
    $s.Manual = [bool]$Manual
    $s.Loading = ($Manual -or $s.Last -eq [datetime]::MinValue)
    $s.CacheChanged = $false
    if ($Manual) { $s.CritUntil = (Get-Date).AddSeconds(60) }
    if ($s.Loading) {
        $s.Frame = 0
        if ($Tray.Animation) { $Tray.Animation.Interval = 125; $Tray.Animation.Start() }
        Update-AgentViewPopup -Rows $s.View -Loading
        Update-AgentViewWidget -Rows $s.View -Loading
    }
    $quotaPath = $s.QuotaPath; if (-not $quotaPath) { $quotaPath = Join-Path $PSScriptRoot 'Quota.ps1' }
    $settings = $null; try { $settings = (Get-AgentViewWidgetState).Settings } catch { }
    try { [void](Sync-AgentViewSettingsFile $s $settings) } catch { }
    $hidden = Get-AgentViewHiddenIds $settings
    $s.Worker = [PowerShell]::Create()
    try { $s.Worker.Runspace = Get-AgentViewRefreshRunspace $s } catch { Reset-AgentViewRefreshRunspace $s }   # lỗi ⇒ runspace riêng của PowerShell như cũ
    # Script chạy ở scope global của runspace ⇒ Quota.ps1 dot-source một lần, các lần sau dùng lại hàm đã nạp.
    [void]$s.Worker.AddScript({ param($path, $missingText, $readErrorText, $language, $manual, $hidden)
        try {
            if (-not (Test-Path -LiteralPath $path)) { throw $missingText }
            if ($AgentViewQuotaLoaded -ne $path -or -not (Get-Command Get-AgentQuotas -ErrorAction SilentlyContinue)) {
                $AgentViewQuotaLoaded = $null
                . $path
                $AgentViewQuotaLoaded = $path
            }
            # Quy tắc bỏ fetch dùng chung (Format.ps1 · Get-QuotaSkipFamilies), nạp một lần như Quota.ps1.
            $formatPath = Join-Path (Split-Path -Parent $path) 'Format.ps1'
            if (-not (Get-Command Get-QuotaSkipFamilies -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $formatPath)) { . $formatPath }
            Set-AgentViewLanguage $language
            $quotaCmd = Get-Command Get-AgentQuotas
            $quotaArgs = @{}
            if ($manual -and $quotaCmd.Parameters.ContainsKey('Manual')) { $quotaArgs.Manual = $true }
            if (@($hidden).Count -and $quotaCmd.Parameters.ContainsKey('Skip') -and (Get-Command Get-AgentDetectedProviders -ErrorAction SilentlyContinue) -and (Get-Command Get-QuotaSkipFamilies -ErrorAction SilentlyContinue)) {
                $skip = [string[]]@(Get-QuotaSkipFamilies $hidden @(Get-AgentDetectedProviders -Rescan:$manual))
                if ($skip.Count) { $quotaArgs.Skip = $skip }
            }
            Get-AgentQuotas @quotaArgs
        } catch {
            $errorText = $readErrorText; if (-not (Test-Path -LiteralPath $path)) { $errorText = $missingText }
            foreach ($provider in @('claude','codex')) {
                $providerName = 'Claude Code'; if ($provider -eq 'codex') { $providerName = 'Codex' }
                [pscustomobject]@{Provider=$provider;Name=$providerName;Ok=$false;Error=$errorText;FiveHourUsed=$null;WeekUsed=$null;FiveHourResetsAt=$null;WeekResetsAt=$null;FetchedAt=Get-Date} }
        }
    }).AddArgument($quotaPath).AddArgument((T 'tray.missing_quota_ps1')).AddArgument((T 'tray.cannot_read_quota')).AddArgument((Get-AgentViewLanguage)).AddArgument([bool]$Manual).AddArgument([string[]]$hidden)
    $s.Pending = $s.Worker.BeginInvoke(); $s.Last = Get-Date
}
# Worker xong ⇒ lấy rows rồi giải phóng PowerShell (giữ runspace). Lần gọi lỗi/runspace hỏng ⇒ bỏ runspace, lần sau tạo lại.
# EndInvoke ném ⇒ vẫn ném như trước (sau khi dọn). Chưa xong ⇒ $null. Phát từng row; caller bọc @().
function Receive-AgentViewRefresh($Tray) {
    $s = $Tray.State
    if (-not $s.Worker -or -not $s.Pending -or -not $s.Pending.IsCompleted) { return $null }
    $rows = @(); $healthy = $false
    try {
        $rows = @(ConvertTo-QuotaRows ($s.Worker.EndInvoke($s.Pending)))
        $healthy = ($s.Worker.InvocationStateInfo.State -ne [Management.Automation.PSInvocationState]::Failed)
    } finally {
        if ($s.Runspace -and (-not $healthy -or $s.Runspace.RunspaceStateInfo.State -ne [Management.Automation.Runspaces.RunspaceState]::Opened)) { Reset-AgentViewRefreshRunspace $s }
        $s.Worker.Dispose(); $s.Worker = $null; $s.Pending = $null
    }
    return $rows
}
# Trên thread UI, sau ConvertTo-QuotaRows: history + thông báo, rồi lọc provider ẩn và cập nhật icon/tooltip/popup/widget.
function Complete-AgentViewRefresh($Tray, $Rows, [datetime]$Now = (Get-Date)) {
    $s = $Tray.State
    $s.Rows = @(ConvertTo-QuotaRows $Rows)
    $settings = (Get-AgentViewWidgetState).Settings
    [void](Invoke-AgentViewRefreshHooks -Rows $s.Rows -Settings $settings -Notify $Tray.Notify -Now $Now -OnClick $Tray.OpenToastPopup)
    try { [void](Update-AgentViewKnownProviders $Tray $settings) } catch { }
    $found = Get-AgentViewDetectedFamilies
    $s.NoAgent = ($null -ne $found -and $found.Count -eq 0)
    $s.View = @(Select-AgentViewVisibleRows $s.Rows $settings)
    $s.ResetAt = Get-AgentViewResetRefreshAt $s.Rows $Now
    $level = Get-QuotaLevel (Get-QuotaTrayRemaining $s.View)
    if ($level -eq 'crit' -and ($s.Level -ne 'crit' -or $s.Manual)) { $s.CritUntil = $Now.AddSeconds(60) }
    if ($level -ne 'crit') { $s.CritUntil = $null }
    $s.Level = $level
    $s.Loading = $false; $s.Frame = 0
    if ($Tray.Animation) {
        $Tray.Animation.Stop()
        if ($level -eq 'crit' -and $Now -lt $s.CritUntil) { $Tray.Animation.Interval = 400; $Tray.Animation.Start() }
    }
    Update-AgentViewPopup -Rows $s.View
    Update-AgentViewWidget -Rows $s.View
    if ($Tray.Notify) { Update-AgentViewTrayIcon $Tray; [void](Set-AgentViewTrayText $Tray.Notify (Get-AgentViewTrayText $s)) }
    Request-AgentViewMemoryTrim
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
        if ($s.Rows.Count -or $s.NoAgent) { Update-AgentViewTrayIcon $Tray; [void](Set-AgentViewTrayText $Tray.Notify (Get-AgentViewTrayText $s)) } else { [void](Set-AgentViewTrayText $Tray.Notify (T 'tray.updating_quota')) }
    }
    # Chữ trong XAML popup dựng một lần ⇒ đổi ngôn ngữ thì bỏ cửa sổ, lần mở sau dựng lại.
    if ($languageChanged) { try { Close-AgentViewPopup -Force } catch { } }
    try { Sync-AgentViewPopupUpdate $Tray } catch { }
    $wantWidget = [bool](Get-AgentViewSettingValue $settings 'WidgetEnabled' $false)
    if ($Tray.Menu) { $Tray.Menu.Widget.Checked = $wantWidget }
    if ($wantWidget -and -not (Test-AgentViewWidgetVisible)) { Show-AgentViewWidget -Rows $s.View -Loading:$s.Loading -OnOpenPopup $Tray.OpenPopup }
    elseif (-not $wantWidget -and (Test-AgentViewWidgetVisible)) { Hide-AgentViewWidget }
    else { Update-AgentViewWidget -Rows $s.View -Loading:$s.Loading }
    Update-AgentViewPopup -Rows $s.View -Loading:$s.Loading
    if ($Tray.Begin) { & $Tray.Begin }
}
# Popup từ icon khay/widget/toast; nút "Quét lại" của trạng thái trống gọi Invoke-AgentViewProviderRescan.
function Show-AgentViewTrayPopup($Tray) {
    $retry = { param($provider) & $Tray.Begin }.GetNewClosure()
    $install = $null; if ($Tray.Update.Latest) { $install = $Tray.InstallUpdate }
    $rescanProvider = ${function:Invoke-AgentViewProviderRescan}
    $rescan = { & $rescanProvider $Tray }.GetNewClosure()
    Show-AgentViewPopup -Rows $Tray.State.View -Loading:$Tray.State.Loading -OnRefresh $Tray.Begin -OnRetry $retry -OnSettings $Tray.OpenSettings -UpdateVersion $Tray.Update.Latest -OnUpdate $install -OnRescan $rescan
}
function Show-AgentViewTraySettings($Tray) {
    $rescanProvider = ${function:Invoke-AgentViewProviderRescan}
    $rescan = { & $rescanProvider $Tray }.GetNewClosure()
    Show-AgentViewSettingsWindow -OnSaved $Tray.Apply -Rows $Tray.State.Rows -OnRescan $rescan
}

function Start-AgentView {
    Initialize-AgentViewTrayNative
    $settings = (Get-AgentViewWidgetState).Settings
    $tray = @{
        State = @{ Rows=@(); View=@(); Worker=$null; Pending=$null; Runspace=$null; QuotaPath=$null; Last=[datetime]::MinValue; Frame=0; Loading=$false; RefreshSeconds=(Get-AgentViewRefreshSeconds $settings); NoAgent=$false; RescanQueued=$false }
        Context = (New-Object Windows.Forms.ApplicationContext); Notify = (New-Object Windows.Forms.NotifyIcon); Menu = (New-AgentViewTrayMenu)
        Animation = (New-Object Windows.Forms.Timer); Begin = $null; OpenPopup = $null; OpenToastPopup = $null; OpenSettings = $null; Apply = $null
        Update = (New-AgentViewUpdateTrayState); UpdateTimer = $null; InstallUpdate = { try { Start-AgentViewUpdate } catch { } }
    }
    $menu = $tray.Menu; $notify = $tray.Notify
    $menu.UpdateState = $tray.Update; Set-AgentViewUpdateMenu $menu
    $menu.Widget.Checked = [bool](Get-AgentViewSettingValue $settings 'WidgetEnabled' $false)
    $menu.Startup.Checked = Test-Path (Get-AgentViewStartupPath)
    $notify.ContextMenuStrip = $menu.Strip; $notify.Icon = New-QuotaIcon @(); [void](Set-AgentViewTrayText $notify (T 'tray.updating_quota')); $notify.Visible = $true
    $tray.Animation.Add_Tick({ Update-AgentViewCriticalAnimation $tray }.GetNewClosure())
    $tray.Begin = { Start-AgentViewRefresh $tray -Manual }.GetNewClosure()
    $tray.Apply = { param($saved) Invoke-AgentViewSettingsApply -Settings $saved -Tray $tray }.GetNewClosure()
    $tray.OpenSettings = { Show-AgentViewTraySettings $tray }.GetNewClosure()
    $tray.OpenPopup = { Show-AgentViewTrayPopup $tray }.GetNewClosure()
    # Bấm toast = mở popup như bấm icon (không đóng popup nếu đang mở).
    $tray.OpenToastPopup = { if (-not (Test-AgentViewPopupOpen)) { & $tray.OpenPopup } }.GetNewClosure()
    $menu.Settings.Add_Click({ & $tray.OpenSettings }.GetNewClosure())
    $menu.Widget.Add_Click({
        $s=Get-AgentViewWidgetState; $s.Settings.WidgetEnabled=$this.Checked
        if($this.Checked){Show-AgentViewWidget -Rows $tray.State.View -Loading:$tray.State.Loading -OnOpenPopup $tray.OpenPopup}else{Hide-AgentViewWidget}
        Save-AgentViewSettings $s.Settings
    }.GetNewClosure())
    if($menu.Widget.Checked){Show-AgentViewWidget -Rows $tray.State.View -OnOpenPopup $tray.OpenPopup}
    $menu.Refresh.Add_Click($tray.Begin)
    $menu.Startup.Add_Click({ Set-AgentViewStartup $this.Checked })
    if ($menu.Update) { $menu.Update.Add_Click({ try { [void](Invoke-AgentViewUpdateMenu $tray) } catch { } }.GetNewClosure()) }
    $menu.Exit.Add_Click({ $tray.Context.ExitThread() }.GetNewClosure())
    $notify.Add_MouseClick({ if ($_.Button -eq [Windows.Forms.MouseButtons]::Left) { & $tray.OpenPopup } }.GetNewClosure())
    $timer = New-Object Windows.Forms.Timer; $timer.Interval = 250
    $timer.Add_Tick({
        $s = $tray.State
        if ($s.Worker -and $s.Pending.IsCompleted) {
            $rows = @(Receive-AgentViewRefresh $tray)
            Complete-AgentViewRefresh $tray $rows
        }
        $now = Get-Date
        Update-AgentViewCacheStamp $s $now
        if (-not $s.Worker -and $s.RescanQueued) { $s.RescanQueued = $false; Start-AgentViewRefresh $tray -Manual }
        if (-not $s.Worker -and (Get-AgentViewNextRefresh $s $now ([AgentView.Native]::IdleMilliseconds())).Due) { Start-AgentViewRefresh $tray }
        try { [void](Receive-AgentViewUpdateCheck $tray) } catch { }   # lỗi cập nhật không ảnh hưởng refresh quota
    }.GetNewClosure())
    if (Test-AgentViewUpdateAvailable) {
        $tray.UpdateTimer = New-Object Windows.Forms.Timer
        $tray.UpdateTimer.Interval = (Get-AgentViewUpdateTimerPlan).FirstMs
        $tray.UpdateTimer.Add_Tick({ Invoke-AgentViewUpdateTimerTick $tray $this }.GetNewClosure())
    }
    try { Start-AgentViewRefresh $tray; $timer.Start(); if ($tray.UpdateTimer) { $tray.UpdateTimer.Start() }; [Windows.Forms.Application]::Run($tray.Context) }
    finally {
        $timer.Stop(); $timer.Dispose(); $tray.Animation.Stop(); $tray.Animation.Dispose()
        if ($tray.UpdateTimer) { $tray.UpdateTimer.Stop(); $tray.UpdateTimer.Dispose() }
        if ($tray.Update.Worker) { try { $tray.Update.Worker.Stop(); $tray.Update.Worker.Dispose() } catch { } }
        Hide-AgentViewPopup
        if (Get-Command Close-AgentViewToast -ErrorAction SilentlyContinue) { try { Close-AgentViewToast -Force } catch { } }
        Close-AgentViewSettingsWindow -Force
        Hide-AgentViewWidget
        if ($tray.State.Worker) { $tray.State.Worker.Stop(); $tray.State.Worker.Dispose() }
        Reset-AgentViewRefreshRunspace $tray.State
        Stop-AgentViewMemoryTrim
        try { [void](Save-AgentViewHistory) } catch { }   # ghi phần history chưa lưu (ghi đĩa bị giãn 5 phút)
        $notify.Visible=$false; $notify.Icon.Dispose(); $notify.Dispose(); $menu.Strip.Dispose(); $tray.Context.Dispose()
    }
}
