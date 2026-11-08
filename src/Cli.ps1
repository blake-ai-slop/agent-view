. (Join-Path $PSScriptRoot 'I18n.ps1')
Register-AgentViewStrings -Module 'cli' -Strings @{
    en = @{
        'widget_label' = ' · widget: '
        'reset' = 'reset'
        'language_help' = 'Show or change language (auto: Windows language)'
        'language_invalid' = 'Use: agentview lang auto|vi|en'

        'running' = 'running'
        'another_copy_is_running' = 'another copy is running'
        'stopped' = 'stopped'
        'start_at_sign_in' = ' · start at sign-in: '
        'on' = 'on'
        'off' = 'off'
        'left' = '{0,-13} {1,3}% left  {2}'
        '5_hours' = '5 hours'
        'week' = 'Week'
        'left_9' = '  {0,-11} {1,3}% left  {2}'
        'control_agent_view_from_your_terminal' = ' — control agent-view from your terminal'
        'start_agent_view_if_stopped_alias_start' = 'Start agent-view if stopped (alias: start)'
        'stop_agent_view_alias_stop' = 'Stop agent-view (alias: stop)'
        'restart_agent_view' = 'Restart agent-view'
        'show_remaining_quota_and_app_status_json_machine_readable' = 'Show remaining quota and app status (--json: machine readable)'
        'turn_the_floating_widget_on_off' = 'Turn the floating widget on/off'
        'turn_start_at_windows_sign_in_on_off' = 'Turn start at Windows sign-in on/off'
        'update_to_the_latest_version_keeping_preferences' = 'Update to the latest version, keeping preferences'
        'uninstall_agent_view_y_skip_confirmation' = 'Uninstall agent-view (-y: skip confirmation)'
        'print_version' = 'Print version'
        'show_this_help' = 'Show this help'
        'restarting_agent_view_to_apply_changes' = 'Restarting agent-view to apply changes…'
        'restarted_agent_view' = 'Restarted agent-view.'
        'could_not_restart_agent_view' = 'Could not restart agent-view.'
        'try_agentview_up' = 'Try: agentview up'
        'agent_view_is_already_running_tray_icon_beside_the_clock' = 'agent-view is already running (tray icon beside the clock).'
        'another_copy_of_agent_view_is_running_from_a_different_location' = 'Another copy of agent-view is running from a different location.'
        'quit_that_copy_right_click_its_tray_icon_quit_and_try_again' = 'Quit that copy (right-click its tray icon → Quit) and try again.'
        'cannot_find' = 'Cannot find '
        'reinstall_agentview_update' = 'Reinstall: agentview update'
        'started_agent_view_click_the_tray_icon_to_view_quota' = 'Started agent-view — click the tray icon to view quota.'
        'could_not_start_agent_view' = 'Could not start agent-view.'
        'try_again_agentview_restart' = 'Try again: agentview restart'
        'stopped_agent_view' = 'Stopped agent-view.'
        'agent_view_is_stopped' = 'agent-view is stopped.'
        'reading_quota' = 'Reading quota…'
        'floating_widget' = 'Floating widget'
        'start_at_sign_in_37' = 'Start at sign-in'
        'change_agentview' = '   (change: agentview '
        'unknown_value' = 'Unknown value "'
        'use_agentview' = 'Use: agentview '
        'downloading_installer_from' = 'Downloading installer from '
        'could_not_download_the_installer' = 'Could not download the installer.'
        'check_your_connection_and_retry_agentview_update' = ' — check your connection and retry: agentview update'
        'confirmation_required' = 'Confirmation required.'
        'run_agentview_uninstall_y' = 'Run: agentview uninstall -y'
        'uninstall_agent_view_from_this_computer_y_n' = 'Uninstall agent-view from this computer? [y/N]'
        'cancelled_nothing_was_removed' = 'Cancelled. Nothing was removed.'
        'cannot_find_uninstall_ps1' = 'Cannot find uninstall.ps1.'
        'reinstall_with_agentview_update_and_try_again' = 'Reinstall with agentview update and try again.'
        'agentview_unknown_command' = 'agentview: unknown command "'
        'did_you_mean_agentview' = 'Did you mean: agentview '
        'type_agentview_help_for_available_commands' = 'Type agentview help for available commands.'
        'error_running_agentview' = 'Error running "agentview '
    }
    vi = @{
        'widget_label' = ' · widget: '
        'reset' = 'reset'
        'language_help' = 'Xem hoặc đổi ngôn ngữ (auto: theo Windows)'
        'language_invalid' = 'Dùng: agentview lang auto|vi|en'

        'running' = 'đang chạy'
        'another_copy_is_running' = 'một bản khác đang chạy'
        'stopped' = 'không chạy'
        'start_at_sign_in' = ' · tự chạy: '
        'on' = 'bật'
        'off' = 'tắt'
        'left' = '{0,-13} còn {1,3}%  {2}'
        '5_hours' = '5 giờ'
        'week' = 'Tuần'
        'left_9' = '  {0,-11} còn {1,3}%  {2}'
        'control_agent_view_from_your_terminal' = ' — điều khiển agent-view từ terminal'
        'start_agent_view_if_stopped_alias_start' = 'Chạy agent-view nếu chưa chạy (bí danh: start)'
        'stop_agent_view_alias_stop' = 'Tắt agent-view (bí danh: stop)'
        'restart_agent_view' = 'Khởi động lại'
        'show_remaining_quota_and_app_status_json_machine_readable' = 'Xem quota còn lại và trạng thái app (--json: dạng máy đọc)'
        'turn_the_floating_widget_on_off' = 'Bật/tắt widget nổi'
        'turn_start_at_windows_sign_in_on_off' = 'Bật/tắt tự chạy khi đăng nhập Windows'
        'update_to_the_latest_version_keeping_preferences' = 'Cập nhật bản mới nhất, giữ lựa chọn hiện tại'
        'uninstall_agent_view_y_skip_confirmation' = 'Gỡ agent-view (-y: không hỏi lại)'
        'print_version' = 'In phiên bản'
        'show_this_help' = 'Trợ giúp này'
        'restarting_agent_view_to_apply_changes' = 'Khởi động lại agent-view để áp dụng…'
        'restarted_agent_view' = 'Đã khởi động lại agent-view.'
        'could_not_restart_agent_view' = 'Không khởi động lại được agent-view.'
        'try_agentview_up' = 'Thử: agentview up'
        'agent_view_is_already_running_tray_icon_beside_the_clock' = 'agent-view đã chạy sẵn (icon ở khay cạnh đồng hồ).'
        'another_copy_of_agent_view_is_running_from_a_different_location' = 'Một bản agent-view khác đang chạy (không phải bản cài ở đây).'
        'quit_that_copy_right_click_its_tray_icon_quit_and_try_again' = 'Thoát bản đó (chuột phải icon khay → Thoát) rồi thử lại.'
        'cannot_find' = 'Không thấy '
        'reinstall_agentview_update' = 'Cài lại: agentview update'
        'started_agent_view_click_the_tray_icon_to_view_quota' = 'Đã chạy agent-view — bấm icon cạnh đồng hồ để xem quota.'
        'could_not_start_agent_view' = 'agent-view không khởi động được.'
        'try_again_agentview_restart' = 'Thử lại: agentview restart'
        'stopped_agent_view' = 'Đã tắt agent-view.'
        'agent_view_is_stopped' = 'agent-view không chạy.'
        'reading_quota' = 'Đang đọc quota…'
        'floating_widget' = 'Widget nổi'
        'start_at_sign_in_37' = 'Tự chạy khi đăng nhập'
        'change_agentview' = '   (đổi: agentview '
        'unknown_value' = 'Không hiểu "'
        'use_agentview' = 'Dùng: agentview '
        'downloading_installer_from' = 'Tải trình cài từ '
        'could_not_download_the_installer' = 'Không tải được trình cài.'
        'check_your_connection_and_retry_agentview_update' = ' — kiểm tra mạng rồi thử lại: agentview update'
        'confirmation_required' = 'Cần xác nhận.'
        'run_agentview_uninstall_y' = 'Chạy: agentview uninstall -y'
        'uninstall_agent_view_from_this_computer_y_n' = 'Gỡ agent-view khỏi máy này? [y/N]'
        'cancelled_nothing_was_removed' = 'Đã hủy, không gỡ gì.'
        'cannot_find_uninstall_ps1' = 'Không thấy uninstall.ps1.'
        'reinstall_with_agentview_update_and_try_again' = 'Cài lại bằng agentview update rồi thử lại.'
        'agentview_unknown_command' = 'agentview: không có lệnh "'
        'did_you_mean_agentview' = 'Ý bạn là: agentview '
        'type_agentview_help_for_available_commands' = 'Gõ agentview help để xem danh sách lệnh.'
        'error_running_agentview' = 'Lỗi khi chạy "agentview '
    }
}
# Lệnh `agentview` + hàm dùng chung cho installer.ps1/uninstall.ps1 (đường dẫn, phát hiện đang chạy, PATH người dùng, shim, tự chạy).
# Dot-source không side effect. Chạy được trên Windows PowerShell 5.1 và pwsh 7; app luôn chạy bằng powershell.exe.
# Biến môi trường ẩn cho thử nghiệm: AGENT_VIEW_STARTUP_DIR (thư mục Startup), AGENT_VIEW_USER_PATH_FILE (PATH người dùng giả).
$script:AgentViewVersion = '0.0.0'  # dự phòng khi thiếu Version.ps1 (vd. bản sao tạm lúc gỡ); nguồn thật: src/Version.ps1
$script:AgentViewDefaultSource = 'https://raw.githubusercontent.com/blake-ai-slop/agent-view/main'
$script:AgentViewCommands = @('up','start','down','stop','restart','status','lang','widget','autostart','update','uninstall','version','help')
foreach ($__dep in @('Version.ps1','Settings.ps1','Format.ps1')) { $__p = Join-Path $PSScriptRoot $__dep; if (Test-Path -LiteralPath $__p) { . $__p } }
Remove-Variable __dep,__p -ErrorAction SilentlyContinue

# ---------- đường dẫn ----------
function Get-AgentViewStartupRoot {
    if ($env:AGENT_VIEW_STARTUP_DIR) { return $env:AGENT_VIEW_STARTUP_DIR }
    [Environment]::GetFolderPath('Startup')
}
function Get-AgentViewPaths([string]$LocalRoot = $env:LOCALAPPDATA, [string]$StartupRoot = (Get-AgentViewStartupRoot)) {
    $root = Join-Path $LocalRoot 'agent-view'
    $bin = Join-Path $root 'bin'
    [pscustomobject]@{
        Root=$root; Entry=(Join-Path $root 'agent-view.ps1'); Launcher=(Join-Path $root 'launch.vbs'); Cli=(Join-Path $root 'Cli.ps1')
        Uninstall=(Join-Path $root 'uninstall.ps1'); Settings=(Join-Path $root 'settings.json'); Bin=$bin; Shim=(Join-Path $bin 'agentview.cmd')
        Shortcut=(Join-Path $StartupRoot 'agent-view.lnk')
    }
}
function Get-AgentViewLaunchScript([string]$Entry) {
    $command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $Entry + '"'
    return 'CreateObject("WScript.Shell").Run "' + $command.Replace('"','""') + '", 0, False'
}
function Get-AgentViewShimText {
    # %LOCALAPPDATA% được cmd mở rộng lúc chạy; một lệnh duy nhất để exit code của Cli.ps1 truyền ra ngoài.
    "@echo off`r`n`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -ExecutionPolicy Bypass -File `"%LOCALAPPDATA%\agent-view\Cli.ps1`" %*`r`n"
}
function Write-AgentViewTextFile([string]$Path, [string]$Text, [string]$Encoding = 'ascii') {
    $enc = switch ($Encoding) { 'unicode' { New-Object Text.UnicodeEncoding $false,$true } 'utf8bom' { New-Object Text.UTF8Encoding $true } default { New-Object Text.ASCIIEncoding } }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    if ([IO.File]::Exists($Path) -and [IO.File]::ReadAllText($Path, $enc) -eq $Text) { return $false }  # không ghi lại shim đang chạy
    [IO.File]::WriteAllText($Path, $Text, $enc); return $true
}

# ---------- PATH người dùng (HKCU, giữ REG_EXPAND_SZ) ----------
function Test-AgentViewPathSegment([string]$Segment, [string]$Dir) {
    $a = [Environment]::ExpandEnvironmentVariables($Segment.Trim().Trim('"')).TrimEnd('\','/')
    $b = $Dir.Trim().TrimEnd('\','/')
    return $a -ieq $b
}
function Add-AgentViewPathEntry([string]$PathValue, [string]$Dir) {
    $parts = @(([string]$PathValue).Split(';') | Where-Object { $_.Trim() -ne '' })
    if (@($parts | Where-Object { Test-AgentViewPathSegment $_ $Dir }).Count -gt 0) { return ($parts -join ';') }
    return ((@($parts) + $Dir) -join ';')
}
function Remove-AgentViewPathEntry([string]$PathValue, [string]$Dir) {
    $parts = @(([string]$PathValue).Split(';') | Where-Object { $_.Trim() -ne '' -and -not (Test-AgentViewPathSegment $_ $Dir) })
    return ($parts -join ';')
}
function Get-AgentViewUserPath {
    if ($env:AGENT_VIEW_USER_PATH_FILE) {
        if (Test-Path -LiteralPath $env:AGENT_VIEW_USER_PATH_FILE) { return [IO.File]::ReadAllText($env:AGENT_VIEW_USER_PATH_FILE) }
        return ''
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if (-not $key) { return '' }
    try { return [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { $key.Close() }
}
function Set-AgentViewUserPath([string]$Value) {
    if ($env:AGENT_VIEW_USER_PATH_FILE) { [IO.File]::WriteAllText($env:AGENT_VIEW_USER_PATH_FILE, $Value); return }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        if ($key.GetValueNames() -contains 'Path') { $kind = $key.GetValueKind('Path') }
        if ($Value) { $key.SetValue('Path', $Value, $kind) } else { $key.DeleteValue('Path', $false) }
    } finally { $key.Close() }
    # Ghi/xóa một biến tạm qua API .NET để Windows phát WM_SETTINGCHANGE: terminal mở sau sẽ thấy PATH mới.
    [Environment]::SetEnvironmentVariable('AGENT_VIEW_PATH_REFRESH', $null, 'User')
}
# Trả $true nếu PATH người dùng đã đổi. Luôn cập nhật $env:Path của tiến trình hiện tại.
function Set-AgentViewUserPathEntry([string]$Dir, [bool]$Present) {
    $old = Get-AgentViewUserPath
    if ($Present) { $new = Add-AgentViewPathEntry $old $Dir; $env:Path = Add-AgentViewPathEntry $env:Path $Dir }
    else { $new = Remove-AgentViewPathEntry $old $Dir; $env:Path = Remove-AgentViewPathEntry $env:Path $Dir }
    if ($new -eq (@(([string]$old).Split(';') | Where-Object { $_.Trim() -ne '' }) -join ';')) { return $false }
    Set-AgentViewUserPath $new
    return $true
}

# ---------- trạng thái chạy (MỘT nguồn cho install/uninstall/CLI) ----------
function Get-AgentViewProcessIds([string]$Entry) {
    $escaped = [regex]::Escape($Entry)
    @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -match ('(?i)-File\s+"?' + $escaped + '(?:"|\s|$)')
    } | ForEach-Object { [int]$_.ProcessId })
}
function Test-AgentViewMutex {
    $m = $null
    if ([Threading.Mutex]::TryOpenExisting('Local\agent-view', [ref]$m)) { $m.Dispose(); return $true }
    return $false
}
# running: bản cài này đang chạy; other: mutex bị một bản agent-view khác giữ; stopped.
function Resolve-AgentViewRunState($ProcessIds, [bool]$MutexHeld) {
    if (@($ProcessIds | Where-Object { $null -ne $_ }).Count -gt 0) { return 'running' }
    if ($MutexHeld) { return 'other' }
    return 'stopped'
}
function Get-AgentViewRunState($Paths) {
    Resolve-AgentViewRunState (Get-AgentViewProcessIds $Paths.Entry) (Test-AgentViewMutex)
}
function Stop-AgentViewApp($Paths) {
    $ids = @(Get-AgentViewProcessIds $Paths.Entry)
    foreach ($id in $ids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    foreach ($id in $ids) { Wait-Process -Id $id -Timeout 5 -ErrorAction SilentlyContinue }
    return $ids.Count
}
function Start-AgentViewApp($Paths, [int]$TimeoutMs = 10000) {
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + $Paths.Launcher + '"') -WindowStyle Hidden
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $TimeoutMs) {
        Start-Sleep -Milliseconds 400
        if (@(Get-AgentViewProcessIds $Paths.Entry).Count -gt 0) {
            Start-Sleep -Milliseconds 1500  # bản trùng mutex sẽ tự thoát ngay
            return (@(Get-AgentViewProcessIds $Paths.Entry).Count -gt 0)
        }
    }
    return $false
}

# ---------- tự chạy khi đăng nhập ----------
function Test-AgentViewAutostart($Paths) { Test-Path -LiteralPath $Paths.Shortcut }
function Set-AgentViewAutostart($Paths, [bool]$Enabled) {
    if (-not $Enabled) { Remove-Item -LiteralPath $Paths.Shortcut -Force -ErrorAction SilentlyContinue; return }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Paths.Shortcut))
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($Paths.Shortcut)
        $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $shortcut.Arguments = '"' + $Paths.Launcher + '"'
        $shortcut.WorkingDirectory = $Paths.Root
        $shortcut.Save()
    } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}

# ---------- in ----------
function Write-AgentViewStep([string]$Kind, [string]$Text, [string]$Detail) {
    $mark = @{ ok='✓'; fail='✗'; skip='–'; info='·' }[$Kind]
    $color = @{ ok='Green'; fail='Red'; skip='DarkGray'; info='Gray' }[$Kind]
    Write-Host ('  ' + $mark + ' ') -ForegroundColor $color -NoNewline
    Write-Host $Text -NoNewline
    if ($Detail) { Write-Host ('  ' + $Detail) -ForegroundColor DarkGray } else { Write-Host '' }
}

# ---------- status ----------
function Get-AgentViewLevelColor([string]$Level) {
    switch ($Level) { ok { 'Green' } warn { 'Yellow' } crit { 'Red' } default { 'DarkGray' } }
}
function Format-AgentViewReset($At, [datetime]$Now) {
    if ($null -eq $At) { return '' }
    (T 'cli.reset') + ' ' + (Format-QuotaResetRelative $At $Now) + ' (' + (Format-QuotaResetAbsolute $At $Now) + ')'
}
function Get-AgentViewAppLine($App) {
    $state = switch ($App.State) { running { (T 'cli.running') } other { (T 'cli.another_copy_is_running') } default { (T 'cli.stopped') } }
    'agent-view ' + $App.Version + ' · ' + $state + (T 'cli.start_at_sign_in') + $(if ($App.Autostart) { (T 'cli.on') } else { (T 'cli.off') }) + (T 'cli.widget_label') + $(if ($App.Widget) { (T 'cli.on') } else { (T 'cli.off') })
}
# Dòng in cho `status`: mỗi phần tử @{Text; Color}.
function Format-AgentViewStatusLines($Quotas, $App, [datetime]$Now = (Get-Date)) {
    $lines = New-Object 'System.Collections.Generic.List[object]'
    $lines.Add([pscustomobject]@{ Text=(Get-AgentViewAppLine $App); Color=$(if ($App.State -eq 'running') { 'Green' } else { 'Yellow' }) })
    $lines.Add([pscustomobject]@{ Text=''; Color='Gray' })
    foreach ($q in @($Quotas | Where-Object { $null -ne $_ })) {
        $remaining = Get-QuotaRemaining $q
        if (-not $q.Ok -or $null -eq $remaining) {
            $lines.Add([pscustomobject]@{ Text=('{0,-13} {1}' -f $q.Name, $q.Error); Color='DarkGray' }); continue
        }
        $level = Get-QuotaLevel $remaining
        $lines.Add([pscustomobject]@{ Text=((T 'cli.left') -f $q.Name, $remaining, (Get-QuotaStatusText $level)); Color=(Get-AgentViewLevelColor $level) })
        foreach ($w in @(@((T 'cli.5_hours'),$q.FiveHourUsed,$q.FiveHourResetsAt), @((T 'cli.week'),$q.WeekUsed,$q.WeekResetsAt))) {
            if ($null -eq $w[1]) { continue }  # provider có thể bỏ một cửa sổ (Ok nhưng 5h/Tuần = null)
            $left = 100 - [int]$w[1]
            $lines.Add([pscustomobject]@{ Text=((T 'cli.left_9') -f $w[0], $left, (Format-AgentViewReset $w[2] $Now)); Color=(Get-AgentViewLevelColor (Get-QuotaLevel $left)) })
        }
    }
    return $lines.ToArray()
}
function ConvertTo-AgentViewIsoTime($At) { if ($null -eq $At) { return $null }; ([datetime]$At).ToString('yyyy-MM-ddTHH:mm:sszzz') }
# JSON máy đọc: chỉ các trường liệt kê dưới đây (không có dữ liệu tài khoản), ký tự ngoài ASCII được escape \uXXXX.
function ConvertTo-AgentViewStatusJson($Quotas, $App) {
    $rows = @(foreach ($q in @($Quotas | Where-Object { $null -ne $_ })) {
        $remaining = $null; if ($q.Ok) { $remaining = Get-QuotaRemaining $q }
        $five = $null; $week = $null
        if ($q.Ok -and $null -ne $q.FiveHourUsed) { $five = 100 - [int]$q.FiveHourUsed }
        if ($q.Ok -and $null -ne $q.WeekUsed) { $week = 100 - [int]$q.WeekUsed }
        $fiveAt = $null; $weekAt = $null; $err = $null; if (-not $q.Ok) { $err = [string]$q.Error }
        if ($null -ne $five) { $fiveAt = ConvertTo-AgentViewIsoTime $q.FiveHourResetsAt }
        if ($null -ne $week) { $weekAt = ConvertTo-AgentViewIsoTime $q.WeekResetsAt }
        [ordered]@{
            provider=[string]$q.Provider; name=[string]$q.Name; ok=[bool]$q.Ok; error=$err
            remaining=$remaining; level=(Get-QuotaLevel $remaining); fiveHourRemaining=$five; weekRemaining=$week
            fiveHourResetsAt=$fiveAt; weekResetsAt=$weekAt; fetchedAt=(ConvertTo-AgentViewIsoTime $q.FetchedAt)
        }
    })
    $obj = [ordered]@{ version=[string]$App.Version; state=[string]$App.State; running=($App.State -eq 'running'); autostart=[bool]$App.Autostart; widget=[bool]$App.Widget; quotas=$rows }
    $json = $obj | ConvertTo-Json -Depth 5 -Compress
    [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
}
function Get-AgentViewAppInfo($Paths) {
    $settings = Get-AgentViewSettings $Paths.Settings
    [pscustomobject]@{ Version=$script:AgentViewVersion; State=(Get-AgentViewRunState $Paths); Autostart=(Test-AgentViewAutostart $Paths); Widget=[bool]$settings.WidgetEnabled }
}

# ---------- phân tích lệnh ----------
function Get-AgentViewEditDistance([string]$A, [string]$B) {
    # Damerau (optimal string alignment): đổi chỗ hai ký tự liền nhau tính 1.
    $n = $A.Length; $m = $B.Length
    $d = New-Object 'int[,]' ($n + 1), ($m + 1)
    for ($i = 0; $i -le $n; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        $pi = $i - 1; $ca = $A[$pi]
        for ($j = 1; $j -le $m; $j++) {
            $pj = $j - 1; $cb = $B[$pj]
            $cost = 1; if ($ca -eq $cb) { $cost = 0 }
            $del = $d[$pi, $j] + 1; $ins = $d[$i, $pj] + 1; $sub = $d[$pi, $pj] + $cost
            $best = [math]::Min([math]::Min($del, $ins), $sub)
            if ($i -gt 1 -and $j -gt 1) {
                $pi2 = $i - 2; $pj2 = $j - 2
                if ($ca -eq $B[$pj2] -and $A[$pi2] -eq $cb) { $tr = $d[$pi2, $pj2] + 1; if ($tr -lt $best) { $best = $tr } }
            }
            $d[$i, $j] = $best
        }
    }
    return $d[$n, $m]
}
function Get-AgentViewSuggestion([string]$Word) {
    $w = $Word.ToLowerInvariant(); $best = $null; $bestScore = 99
    foreach ($c in $script:AgentViewCommands) {
        $score = Get-AgentViewEditDistance $w $c
        if ($w.Length -ge 2 -and $c.StartsWith($w)) { $score = [math]::Min($score, 1) }
        if ($score -lt $bestScore) { $best = $c; $bestScore = $score }
    }
    if ($bestScore -le [math]::Max(1, [math]::Min(2, [int][math]::Floor($w.Length / 3)))) { return $best }
    return $null
}
function Resolve-AgentViewCommand([string[]]$Argv) {
    $argv = @($Argv | Where-Object { $null -ne $_ })
    $rest = @(); if ($argv.Count -gt 1) { $rest = @($argv[1..($argv.Count - 1)]) }
    if ($argv.Count -eq 0) { return [pscustomobject]@{ Command='help'; Rest=@(); Error=$null; Suggestion=$null } }
    $word = ([string]$argv[0]).ToLowerInvariant()
    $alias = @{ start='up'; stop='down'; '-h'='help'; '--help'='help'; '/?'='help'; '-v'='version'; '--version'='version' }
    if ($alias.ContainsKey($word)) { $word = $alias[$word] }
    if ($script:AgentViewCommands -contains $word) { return [pscustomobject]@{ Command=$word; Rest=$rest; Error=$null; Suggestion=$null } }
    [pscustomobject]@{ Command=$null; Rest=$rest; Error='unknown'; Suggestion=(Get-AgentViewSuggestion $word) }
}
function ConvertFrom-AgentViewSwitch([string]$Value) {
    switch -regex ([string]$Value) { '^(?i)(on|1|true|b\u1eadt|bat)$' { return $true } '^(?i)(off|0|false|t\u1eaft|tat)$' { return $false } }
    return $null
}
function Test-AgentViewYesFlag($Rest) { @($Rest | Where-Object { $_ -match '^(?i)(-y|--yes|-yes|/y)$' }).Count -gt 0 }

function Show-AgentViewHelp {
    Write-Host ('agentview ' + $script:AgentViewVersion + (T 'cli.control_agent_view_from_your_terminal')) -ForegroundColor Cyan
    Write-Host ''
    $rows = @(
        @('lang [auto|vi|en]',(T 'cli.language_help')),
        @('up',(T 'cli.start_agent_view_if_stopped_alias_start')), @('down',(T 'cli.stop_agent_view_alias_stop')), @('restart',(T 'cli.restart_agent_view')),
        @('status',(T 'cli.show_remaining_quota_and_app_status_json_machine_readable')), @('widget on|off',(T 'cli.turn_the_floating_widget_on_off')),
        @('autostart on|off',(T 'cli.turn_start_at_windows_sign_in_on_off')), @('update',(T 'cli.update_to_the_latest_version_keeping_preferences')),
        @('uninstall',(T 'cli.uninstall_agent_view_y_skip_confirmation')), @('version',(T 'cli.print_version')), @('help',(T 'cli.show_this_help')))
    foreach ($r in $rows) { Write-Host ('  agentview {0,-17}' -f $r[0]) -ForegroundColor White -NoNewline; Write-Host $r[1] }
}
function Invoke-AgentViewRestartIfRunning($Paths) {
    if ((Get-AgentViewRunState $Paths) -ne 'running') { return 0 }
    Write-Host (T 'cli.restarting_agent_view_to_apply_changes')
    [void](Stop-AgentViewApp $Paths)
    if (Start-AgentViewApp $Paths) { Write-AgentViewStep ok (T 'cli.restarted_agent_view'); return 0 }
    Write-AgentViewStep fail (T 'cli.could_not_restart_agent_view') (T 'cli.try_agentview_up'); return 1
}
function Invoke-AgentViewUp($Paths) {
    switch (Get-AgentViewRunState $Paths) {
        running { Write-AgentViewStep info (T 'cli.agent_view_is_already_running_tray_icon_beside_the_clock'); return 0 }
        other { Write-AgentViewStep fail (T 'cli.another_copy_of_agent_view_is_running_from_a_different_location') (T 'cli.quit_that_copy_right_click_its_tray_icon_quit_and_try_again'); return 1 }
    }
    if (-not (Test-Path -LiteralPath $Paths.Launcher)) { Write-AgentViewStep fail ((T 'cli.cannot_find') + $Paths.Launcher) (T 'cli.reinstall_agentview_update'); return 1 }
    if (Start-AgentViewApp $Paths) { Write-AgentViewStep ok (T 'cli.started_agent_view_click_the_tray_icon_to_view_quota'); return 0 }
    Write-AgentViewStep fail (T 'cli.could_not_start_agent_view') (T 'cli.try_again_agentview_restart'); return 1
}
function Invoke-AgentViewDown($Paths) {
    $n = Stop-AgentViewApp $Paths
    if ($n -gt 0) { Write-AgentViewStep ok (T 'cli.stopped_agent_view') } else { Write-AgentViewStep info (T 'cli.agent_view_is_stopped') }
    return 0
}
function Invoke-AgentViewStatus($Paths, $Rest) {
    $app = Get-AgentViewAppInfo $Paths
    $json = @($Rest | Where-Object { $_ -match '^(?i)--?json$' }).Count -gt 0
    if (-not $json) { Write-Host (T 'cli.reading_quota') -ForegroundColor DarkGray }
    . (Join-Path $PSScriptRoot 'Quota.ps1')
    $quotas = @(Get-AgentQuotas)
    if ($json) { Write-Host (ConvertTo-AgentViewStatusJson $quotas $app); return 0 }
    foreach ($l in (Format-AgentViewStatusLines $quotas $app)) { Write-Host $l.Text -ForegroundColor $l.Color }
    return 0
}
function Invoke-AgentViewToggle($Paths, [string]$What, $Rest) {
    $label = @{ widget=(T 'cli.floating_widget'); autostart=(T 'cli.start_at_sign_in_37') }[$What]
    $current = if ($What -eq 'widget') { [bool](Get-AgentViewSettings $Paths.Settings).WidgetEnabled } else { Test-AgentViewAutostart $Paths }
    if (@($Rest).Count -eq 0) { Write-Host ($label + ': ' + $(if ($current) { (T 'cli.on') } else { (T 'cli.off') }) + (T 'cli.change_agentview') + $What + ' on|off)'); return 0 }
    $on = ConvertFrom-AgentViewSwitch $Rest[0]
    if ($null -eq $on) { Write-AgentViewStep fail ((T 'cli.unknown_value') + $Rest[0] + '".') ((T 'cli.use_agentview') + $What + ' on|off'); return 1 }
    if ($What -eq 'widget') { $s = Get-AgentViewSettings $Paths.Settings; $s.WidgetEnabled = $on; Save-AgentViewSettings $s $Paths.Settings }
    else { Set-AgentViewAutostart $Paths $on }
    Write-AgentViewStep ok ($label + ': ' + $(if ($on) { (T 'cli.on') } else { (T 'cli.off') }))
    if ($on -eq $current) { return 0 }
    return (Invoke-AgentViewRestartIfRunning $Paths)
}
# Chạy powershell.exe con chung console (giữ màu, không lẫn output vào giá trị trả về); trả exit code.
function Invoke-AgentViewChild([string]$ArgumentText) {
    # Không dùng Start-Process -Wait: trên PS 5.1 nó chờ cả tiến trình cháu (lệnh xóa trễ của uninstall).
    $psi = New-Object Diagnostics.ProcessStartInfo (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'), $ArgumentText
    $psi.UseShellExecute = $false
    $p = [Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    return [int]$p.ExitCode
}
function Invoke-AgentViewUpdate($Paths) {
    # Gọi thẳng installer.ps1 (bộ cài thật) bằng -File trong powershell.exe; install.ps1 chỉ là bootstrap cho irm | iex.
    $source = $env:AGENT_VIEW_SOURCE; if ([string]::IsNullOrWhiteSpace($source)) { $source = $script:AgentViewDefaultSource }
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('agent-view-update-' + [guid]::NewGuid().ToString('N'))
    try {
        if (Test-Path -LiteralPath $source -PathType Container) { $installer = Join-Path $source 'installer.ps1' }
        else {
            [void][IO.Directory]::CreateDirectory($tempDir); $installer = Join-Path $tempDir 'installer.ps1'
            Write-Host ((T 'cli.downloading_installer_from') + $source + ' …') -ForegroundColor DarkGray
            try { Invoke-WebRequest -UseBasicParsing -Uri ($source.TrimEnd('/') + '/installer.ps1') -OutFile $installer -ErrorAction Stop }
            catch { Write-AgentViewStep fail (T 'cli.could_not_download_the_installer') ($_.Exception.Message + (T 'cli.check_your_connection_and_retry_agentview_update')); return 1 }
        }
        if (-not (Test-Path -LiteralPath $installer)) { Write-AgentViewStep fail ((T 'cli.cannot_find') + $installer); return 1 }
        $argText = '-NoProfile -ExecutionPolicy Bypass -File "' + $installer + '" -Yes'
        if ((Get-AgentViewRunState $Paths) -ne 'running') { $argText += ' -NoStart' }
        $old = $env:AGENT_VIEW_SOURCE; $env:AGENT_VIEW_SOURCE = $source
        try { return (Invoke-AgentViewChild $argText) }
        finally { $env:AGENT_VIEW_SOURCE = $old }
    } finally { if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue } }
}
function Invoke-AgentViewUninstall($Paths, $Rest) {
    if (-not (Test-AgentViewYesFlag $Rest)) {
        if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { Write-AgentViewStep fail (T 'cli.confirmation_required') (T 'cli.run_agentview_uninstall_y'); return 1 }
        $answer = Read-Host (T 'cli.uninstall_agent_view_from_this_computer_y_n')
        if ($answer -notmatch '^(?i)(y|yes|c|c\u00f3|co)$') { Write-Host (T 'cli.cancelled_nothing_was_removed'); return 0 }
    }
    $script = $Paths.Uninstall; if (-not (Test-Path -LiteralPath $script)) { $script = Join-Path $PSScriptRoot 'uninstall.ps1' }
    if (-not (Test-Path -LiteralPath $script)) { Write-AgentViewStep fail (T 'cli.cannot_find_uninstall_ps1') (T 'cli.reinstall_with_agentview_update_and_try_again'); return 1 }
    # Cli.ps1/uninstall.ps1 nằm trong thư mục sắp xóa: chạy bản sao ở %TEMP%; shim agentview.cmd được xóa trễ vì cmd còn đang đọc nó.
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('agent-view-uninstall-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($tempDir)
    Copy-Item -LiteralPath $script -Destination (Join-Path $tempDir 'uninstall.ps1') -Force
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $tempDir 'Cli.ps1') -Force
    foreach ($dep in @('I18n.ps1','Settings.ps1','Format.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $dep) -Destination (Join-Path $tempDir $dep) -Force }
    $ver = Join-Path $PSScriptRoot 'Version.ps1'; if (Test-Path -LiteralPath $ver) { Copy-Item -LiteralPath $ver -Destination (Join-Path $tempDir 'Version.ps1') -Force }
    $code = Invoke-AgentViewChild ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $tempDir 'uninstall.ps1') + '" -DeferSelf')
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    return $code
}
function Invoke-AgentViewCli([string[]]$Argv, $Paths = (Get-AgentViewPaths)) {
    Set-AgentViewLanguage (Get-AgentViewSettings $Paths.Settings).Language
    $cmd = Resolve-AgentViewCommand $Argv
    if ($cmd.Error) {
        Write-Host ((T 'cli.agentview_unknown_command') + $Argv[0] + '".') -ForegroundColor Red
        if ($cmd.Suggestion) { Write-Host ((T 'cli.did_you_mean_agentview') + $cmd.Suggestion + ' ?') -ForegroundColor Yellow }
        Write-Host (T 'cli.type_agentview_help_for_available_commands')
        return 1
    }
    try {
        switch ($cmd.Command) {
            lang {
                if ($cmd.Rest.Count -eq 0) { Write-Host (Get-AgentViewLanguage); return 0 }
                if ($cmd.Rest.Count -ne 1 -or $cmd.Rest[0] -notin @('auto','vi','en')) { Write-AgentViewStep fail (T 'cli.language_invalid'); return 1 }
                $settings = Get-AgentViewSettings $Paths.Settings
                $settings.Language = $cmd.Rest[0].ToLowerInvariant()
                Save-AgentViewSettings $settings $Paths.Settings
                Set-AgentViewLanguage $settings.Language
                Write-Host (Get-AgentViewLanguage)
                return (Invoke-AgentViewRestartIfRunning $Paths)
            }
            help { Show-AgentViewHelp; return 0 }
            version { Write-Host ('agent-view ' + $script:AgentViewVersion); return 0 }
            up { return (Invoke-AgentViewUp $Paths) }
            down { return (Invoke-AgentViewDown $Paths) }
            restart { [void](Invoke-AgentViewDown $Paths); return (Invoke-AgentViewUp $Paths) }
            status { return (Invoke-AgentViewStatus $Paths $cmd.Rest) }
            widget { return (Invoke-AgentViewToggle $Paths 'widget' $cmd.Rest) }
            autostart { return (Invoke-AgentViewToggle $Paths 'autostart' $cmd.Rest) }
            update { return (Invoke-AgentViewUpdate $Paths) }
            uninstall { return (Invoke-AgentViewUninstall $Paths $cmd.Rest) }
        }
    } catch { Write-AgentViewStep fail ((T 'cli.error_running_agentview') + $cmd.Command + '": ' + $_.Exception.Message); return 1 }
    return 1
}

if ($MyInvocation.InvocationName -eq '.') { return }
exit (Invoke-AgentViewCli $args)
