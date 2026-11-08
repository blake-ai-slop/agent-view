param(
    [string]$Source = $env:AGENT_VIEW_SOURCE,
    [switch]$Yes, [switch]$NoAutostart, [switch]$Widget, [switch]$NoStart, [switch]$Quiet
)
$__i18n = Join-Path $PSScriptRoot 'src/I18n.ps1'
if (-not (Test-Path -LiteralPath $__i18n)) { $__i18n = Join-Path $PSScriptRoot 'I18n.ps1' }
if (Test-Path -LiteralPath $__i18n) { . $__i18n } else {
    $__tempI18n = Join-Path ([IO.Path]::GetTempPath()) ('agent-view-i18n-' + [guid]::NewGuid().ToString('N') + '.ps1')
    try {
        $__base = $Source; if (-not $__base) { $__base = 'https://raw.githubusercontent.com/blake-ai-slop/agent-view/main' }
        if (Test-Path -LiteralPath $__base -PathType Container) { Copy-Item -LiteralPath (Join-Path $__base 'src/I18n.ps1') -Destination $__tempI18n -ErrorAction Stop }
        else { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri ($__base.TrimEnd('/') + '/src/I18n.ps1') -OutFile $__tempI18n -ErrorAction Stop }
        . $__tempI18n
    } finally { Remove-Item -LiteralPath $__tempI18n -Force -ErrorAction SilentlyContinue }
}
Register-AgentViewStrings -Module 'installer' -Strings @{
    en = @{
        'files' = ' files'
        'type_y_yes_or_n_no_enter_default' = '    Type y (yes) or n (no), Enter = default.'
        'missing_installation_file_in' = 'Missing installation file: {0} (in {1})'
        'could_not_download' = 'Could not download {0} — {1}'
        'remaining_quota' = 'Remaining quota: '
        'agent_view_is_running' = 'agent-view is running'
        'click_the_tray_icon_beside_the_clock_to_view_quota' = 'Click the tray icon beside the clock to view quota.'
        'run_the_install_command_again_irm_install_ps1_iex' = 'run the install command again (irm …/install.ps1 | iex)'
        'preparing' = 'preparing'
        'agent_view_install' = 'agent-view · install'
        'downloading_files' = 'downloading files'
        'copied' = 'Copied '
        'downloaded' = 'Downloaded '
        'reading_existing_preferences' = 'reading existing preferences'
        'start_automatically_at_windows_sign_in' = 'Start automatically at Windows sign-in?'
        'enable_the_floating_desktop_widget' = 'Enable the floating desktop widget?'
        'start_agent_view_now' = 'Start agent-view now?'
        'stopping_the_previous_version' = 'stopping the previous version'
        'stopped_the_running_copy_upgrading' = 'Stopped the running copy — upgrading'
        'upgrading_an_existing_installation' = 'Upgrading an existing installation'
        'new_installation' = 'New installation'
        'copying_installation_files' = 'copying installation files'
        'installed_files' = 'Installed {0} files'
        'creating_the_agentview_command' = 'creating the agentview command'
        'agentview_command' = 'agentview command'
        'added_to_user_path' = ' (added to user PATH)'
        'already_in_path' = ' (already in PATH)'
        'setting_start_at_sign_in' = 'setting start at sign-in'
        'start_at_sign_in_on' = 'Start at sign-in: on'
        'start_at_sign_in_off' = 'Start at sign-in: off'
        'saving_widget_preferences' = 'saving widget preferences'
        'floating_widget' = 'Floating widget: '
        'on' = 'on'
        'off' = 'off'
        'starting' = 'starting'
        'not_started_another_copy_of_agent_view_is_running' = 'Not started: another copy of agent-view is running.'
        'quit_that_copy_right_click_its_tray_icon_quit_then_run_agentview_' = 'Quit that copy (right-click its tray icon → Quit), then run: agentview up'
        'started_agent_view' = 'Started agent-view'
        'could_not_start_agent_view_process_exited_try_agentview_up' = 'Could not start agent-view (process exited). Try: agentview up'
        'not_started_run_agentview_up_when_needed' = 'Not started (run agentview up when needed)'
        'done_agent_view_is_running_in_the_tray_beside_the_clock' = '✓ Done! agent-view is running in the tray beside the clock.'
        'done_agent_view_is_installed' = '✓ Done! agent-view is installed.'
        'type_agentview_help_for_available_commands' = '  Type `agentview help` for available commands.'
        'open_a_new_terminal_to_use_agentview_path_was_updated' = '  Open a new terminal to use agentview (PATH was updated).'
        'error_at_step' = 'Error at step "'
        'no_changes_were_made_any_existing_installation_is_intact' = '    No changes were made; any existing installation is intact.'
        'try_again' = '    Try again: '
    }
    vi = @{
        'files' = ' file'
        'type_y_yes_or_n_no_enter_default' = '    Gõ y (có) hoặc n (không), Enter = mặc định.'
        'missing_installation_file_in' = 'Thiếu file cài đặt: {0} (trong {1})'
        'could_not_download' = 'Không tải được {0} — {1}'
        'remaining_quota' = 'Quota còn lại: '
        'agent_view_is_running' = 'agent-view đang chạy'
        'click_the_tray_icon_beside_the_clock_to_view_quota' = 'Bấm icon cạnh đồng hồ để xem quota.'
        'run_the_install_command_again_irm_install_ps1_iex' = 'chạy lại lệnh cài (irm …/install.ps1 | iex)'
        'preparing' = 'chuẩn bị'
        'agent_view_install' = 'agent-view · cài đặt'
        'downloading_files' = 'tải file'
        'copied' = 'Đã chép '
        'downloaded' = 'Đã tải '
        'reading_existing_preferences' = 'đọc cấu hình hiện có'
        'start_automatically_at_windows_sign_in' = 'Tự chạy khi đăng nhập Windows?'
        'enable_the_floating_desktop_widget' = 'Bật widget nổi trên màn hình?'
        'start_agent_view_now' = 'Chạy agent-view ngay bây giờ?'
        'stopping_the_previous_version' = 'dừng bản cũ'
        'stopped_the_running_copy_upgrading' = 'Đã dừng bản đang chạy — cập nhật từ bản cũ'
        'upgrading_an_existing_installation' = 'Cập nhật từ bản cũ'
        'new_installation' = 'Cài mới'
        'copying_installation_files' = 'chép file vào thư mục cài'
        'installed_files' = 'Đã cài {0} file'
        'creating_the_agentview_command' = 'tạo lệnh agentview'
        'agentview_command' = 'Lệnh agentview'
        'added_to_user_path' = ' (đã thêm vào PATH người dùng)'
        'already_in_path' = ' (đã có trong PATH)'
        'setting_start_at_sign_in' = 'đặt tự chạy khi đăng nhập'
        'start_at_sign_in_on' = 'Tự chạy khi đăng nhập: bật'
        'start_at_sign_in_off' = 'Tự chạy khi đăng nhập: tắt'
        'saving_widget_preferences' = 'lưu cài đặt widget'
        'floating_widget' = 'Widget nổi: '
        'on' = 'bật'
        'off' = 'tắt'
        'starting' = 'khởi động'
        'not_started_another_copy_of_agent_view_is_running' = 'Chưa khởi động: một bản agent-view khác đang chạy.'
        'quit_that_copy_right_click_its_tray_icon_quit_then_run_agentview_' = 'Thoát bản đó (chuột phải icon khay → Thoát) rồi gõ: agentview up'
        'started_agent_view' = 'Đã khởi động agent-view'
        'could_not_start_agent_view_process_exited_try_agentview_up' = 'agent-view không khởi động được (tiến trình thoát ngay). Thử: agentview up'
        'not_started_run_agentview_up_when_needed' = 'Chưa chạy (gõ agentview up khi cần)'
        'done_agent_view_is_running_in_the_tray_beside_the_clock' = '✓ Xong! agent-view đang chạy ở khay (cạnh đồng hồ).'
        'done_agent_view_is_installed' = '✓ Xong! agent-view đã được cài.'
        'type_agentview_help_for_available_commands' = '  Gõ `agentview help` để xem lệnh.'
        'open_a_new_terminal_to_use_agentview_path_was_updated' = '  Lệnh agentview dùng được ở terminal mở mới (PATH vừa cập nhật).'
        'error_at_step' = 'Lỗi ở bước "'
        'no_changes_were_made_any_existing_installation_is_intact' = '    Chưa thay đổi gì trên máy; bản cũ (nếu có) vẫn giữ nguyên.'
        'try_again' = '    Thử lại: '
    }
}
# Bộ cài thật của agent-view: cài vào %LOCALAPPDATA%\agent-view. Thường được install.ps1 (bootstrap ASCII, chạy được qua
# `irm <url>/install.ps1 | iex`) tải về thư mục tạm rồi chạy bằng powershell.exe -File; cũng chạy thẳng được bằng -File.
# Tham số: cờ -Yes/-NoAutostart/-Widget/-NoStart/-Quiet hoặc biến môi trường AGENT_VIEW_YES/NO_AUTOSTART/WIDGET/NO_START/QUIET=1.
# Biến do bootstrap đặt: AGENT_VIEW_SOURCE (nguồn đã chọn), AGENT_VIEW_BOOTSTRAP=1, AGENT_VIEW_INSTALL_SCRIPT (đường dẫn install.ps1 nếu chạy file).
# Tải hết vào thư mục tạm trước rồi mới thay bản cũ. File này có BOM (tiếng Việt cho PS 5.1) nên KHÔNG được iex trực tiếp.
$script:AgentViewPayload = @('I18n.ps1','Ui.ps1','Tray.ps1','agent-view.ps1','Quota.ps1','Process.ps1','Theme.ps1','Format.ps1','Ring.ps1','Popup.ps1','Widget.ps1','Settings.ps1','SettingsWindow.ps1','History.ps1','Forecast.ps1','Update.ps1','Notify.ps1','Toast.ps1','Version.ps1','Cli.ps1')
$script:AgentViewDefaultInstallSource = 'https://raw.githubusercontent.com/blake-ai-slop/agent-view/main'
$script:InstallQuiet = $false

function Test-AgentViewTruthy([string]$Value) { return ([string]$Value -match '^(?i)(1|true|yes|y|on)$') }
function Get-AgentViewInstallEnv {
    $h = @{}
    foreach ($n in @('AGENT_VIEW_YES','AGENT_VIEW_NO_AUTOSTART','AGENT_VIEW_WIDGET','AGENT_VIEW_NO_START','AGENT_VIEW_QUIET')) { $h[$n] = [Environment]::GetEnvironmentVariable($n) }
    $h
}
# Quyết định lựa chọn cài. Có bất kỳ cờ/biến nào (-Yes, -NoAutostart, -Widget, -NoStart, -Quiet) hoặc không tương tác ⇒ không hỏi.
# Mặc định: tự chạy bật (bản cũ: giữ như cũ), widget theo settings hiện có (mặc định tắt), chạy ngay.
function Resolve-AgentViewInstallOptions([hashtable]$Flags, [hashtable]$EnvValues, [bool]$Interactive, $Existing) {
    if (-not $Flags) { $Flags = @{} }; if (-not $EnvValues) { $EnvValues = @{} }
    $pick = { param($flag, $envName) ([bool]$Flags[$flag]) -or (Test-AgentViewTruthy $EnvValues[$envName]) }
    $yes = & $pick 'Yes' 'AGENT_VIEW_YES'; $noAuto = & $pick 'NoAutostart' 'AGENT_VIEW_NO_AUTOSTART'
    $widget = & $pick 'Widget' 'AGENT_VIEW_WIDGET'; $noStart = & $pick 'NoStart' 'AGENT_VIEW_NO_START'; $quiet = & $pick 'Quiet' 'AGENT_VIEW_QUIET'
    $autoDefault = $true
    if ($Existing -and $Existing.Installed) { $autoDefault = [bool]$Existing.Autostart }
    $widgetDefault = ($Existing -and [bool]$Existing.Widget)
    [pscustomobject]@{
        Ask = ($Interactive -and -not ($yes -or $noAuto -or $widget -or $noStart -or $quiet))
        Autostart = ($autoDefault -and -not $noAuto); Widget = ($widget -or $widgetDefault); Start = (-not $noStart); Quiet = $quiet
    }
}
function Test-AgentViewInteractive {
    if (-not [Environment]::UserInteractive) { return $false }
    try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
    if (@([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^(?i)-noni' }).Count -gt 0) { return $false }
    return $true
}
function ConvertFrom-AgentViewYesNo([string]$Answer, [bool]$Default) {
    $a = ([string]$Answer).Trim()
    if ($a -eq '') { return $Default }
    if ($a -match '^(?i)(y|yes|c|co|c\u00f3)$') { return $true }
    if ($a -match '^(?i)(n|no|k|khong|kh\u00f4ng)$') { return $false }
    return $null
}
function Read-AgentViewYesNo([string]$Question, [bool]$Default) {
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    for ($i = 0; $i -lt 3; $i++) {
        Write-Host ('  ? ' + $Question + ' ' + $hint + ' ') -ForegroundColor Cyan -NoNewline
        $line = [Console]::ReadLine()
        if ($null -eq $line) { return $Default }
        $v = ConvertFrom-AgentViewYesNo $line $Default
        if ($null -ne $v) { return $v }
        Write-Host (T 'installer.type_y_yes_or_n_no_enter_default') -ForegroundColor DarkGray
    }
    return $Default
}
function Write-InstallStep([string]$Kind, [string]$Text, [string]$Detail) {
    if ($script:InstallQuiet -and $Kind -ne 'fail') { return }
    Write-AgentViewConsoleStep $Kind $Text $Detail
}
function Write-InstallLine([string]$Text, [string]$Color = 'Gray') { if (-not $script:InstallQuiet) { Write-Host $Text -ForegroundColor $Color } }

# Nguồn payload: repo local (chạy file trong repo), thư mục local (AGENT_VIEW_SOURCE là thư mục), hoặc URL.
function Get-AgentViewPayloadSource([string]$Source, [string]$ScriptRoot) {
    if ([string]::IsNullOrWhiteSpace($Source)) {
        if ($ScriptRoot -and (Test-Path -LiteralPath (Join-Path $ScriptRoot 'src/agent-view.ps1'))) { return [pscustomobject]@{ Local=$true; Base=$ScriptRoot } }
        return [pscustomobject]@{ Local=$false; Base=$script:AgentViewDefaultInstallSource }
    }
    if (Test-Path -LiteralPath $Source -PathType Container) { return [pscustomobject]@{ Local=$true; Base=$Source } }
    [pscustomobject]@{ Local=$false; Base=$Source.TrimEnd('/') }
}
function Get-AgentViewPayloadItems {
    @($script:AgentViewPayload | ForEach-Object { [pscustomobject]@{ From="src/$_"; Name=$_ } }) + [pscustomobject]@{ From='uninstall.ps1'; Name='uninstall.ps1' }
}
# Chép/tải toàn bộ payload vào $Staging; lỗi ⇒ ném, chưa đụng thư mục cài.
function Save-AgentViewPayload($From, [string]$Staging) {
    [void][IO.Directory]::CreateDirectory($Staging)
    if (-not $From.Local) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { } }
    $count = 0
    foreach ($item in (Get-AgentViewPayloadItems)) {
        $target = Join-Path $Staging $item.Name
        if ($From.Local) {
            $src = Join-Path $From.Base $item.From
            if (-not (Test-Path -LiteralPath $src)) { throw (T 'installer.missing_installation_file_in' -Args @($item.From,$From.Base)) }
            Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction Stop
        } else {
            $url = $From.Base + '/' + $item.From
            try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $target -ErrorAction Stop }
            catch { throw (T 'installer.could_not_download' -Args @($url,$_.Exception.Message)) }
        }
        $count++
    }
    return $count
}
# Thay file trong thư mục cài; lỗi giữa chừng ⇒ khôi phục bản cũ từ backup.
function Install-AgentViewFiles([string]$Staging, $Paths) {
    [void][IO.Directory]::CreateDirectory($Paths.Root)
    $backup = Join-Path $Staging '.backup'; [void][IO.Directory]::CreateDirectory($backup)
    $done = New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($item in (Get-AgentViewPayloadItems)) {
            $target = Join-Path $Paths.Root $item.Name
            if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $backup $item.Name) -Force -ErrorAction Stop }
            Copy-Item -LiteralPath (Join-Path $Staging $item.Name) -Destination $target -Force -ErrorAction Stop
            $done.Add($item.Name)
        }
        [IO.File]::WriteAllText($Paths.Launcher, (Get-AgentViewLaunchScript $Paths.Entry), (New-Object Text.UnicodeEncoding $false,$true))
    } catch {
        foreach ($name in $done) {
            $old = Join-Path $backup $name
            if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination (Join-Path $Paths.Root $name) -Force -ErrorAction SilentlyContinue }
            else { Remove-Item -LiteralPath (Join-Path $Paths.Root $name) -Force -ErrorAction SilentlyContinue }
        }
        throw
    }
    return $done.Count
}
function Format-AgentViewQuotaSummary($Status) {
    $parts = @(foreach ($q in @($Status.quotas)) { if ($q.ok -and $null -ne $q.remaining) { '{0} {1}%' -f $q.name, $q.remaining } })
    if ($parts.Count -eq 0) { return $null }
    return ((T 'installer.remaining_quota') + ($parts -join ' · '))
}
# Đọc quota bằng `Cli.ps1 status --json` của bản đã cài, quá hạn thì giết cả cây và bỏ qua.
function Get-AgentViewQuotaSummary($Paths, [int]$TimeoutMs = 8000) {
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $Paths.Cli + '" status --json'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEndAsync(); [void]$p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null; return $null }
        $line = @($out.Result -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('{') })[-1]
        if (-not $line) { return $null }
        return (Format-AgentViewQuotaSummary ($line | ConvertFrom-Json))
    } catch { return $null }
}
function Get-AgentViewToastScript([string]$Title, [string]$Body) {
    $t = [Security.SecurityElement]::Escape($Title); $b = [Security.SecurityElement]::Escape($Body)
    $xml = "<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$b</text></binding></visual></toast>"
@"
try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    `$x = New-Object Windows.Data.Xml.Dom.XmlDocument
    `$x.LoadXml("$xml")
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new(`$x))
} catch {
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing
    `$n = New-Object System.Windows.Forms.NotifyIcon
    `$n.Icon = [System.Drawing.SystemIcons]::Information; `$n.Visible = `$true
    `$n.ShowBalloonTip(8000, '$($Title.Replace("'","''"))', '$($Body.Replace("'","''"))', 'Info')
    Start-Sleep -Seconds 9; `$n.Dispose()
}
"@
}
# Toast chạy trong powershell.exe ẩn riêng (WinRT có trên PS 5.1, kể cả khi người dùng cài từ pwsh 7); không chờ.
function Show-AgentViewFirstToast {
    $script = Get-AgentViewToastScript (T 'installer.agent_view_is_running') (T 'installer.click_the_tray_icon_beside_the_clock_to_view_quota')
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ' + $encoded)
}

function Invoke-AgentViewInstall([string]$Source, [hashtable]$Flags, [string]$ScriptRoot, [string]$ScriptPath) {
    $envValues = Get-AgentViewInstallEnv
    $script:InstallQuiet = ([bool]$Flags['Quiet']) -or (Test-AgentViewTruthy $envValues['AGENT_VIEW_QUIET'])
    $retry = if ($ScriptPath) { 'powershell -ExecutionPolicy Bypass -File "' + $ScriptPath + '"' } else { (T 'installer.run_the_install_command_again_irm_install_ps1_iex') }
    $staging = Join-Path ([IO.Path]::GetTempPath()) ('agent-view-install-' + [guid]::NewGuid().ToString('N'))
    $step = (T 'installer.preparing'); $touched = $false
    Write-InstallLine ''
    Write-InstallLine (T 'installer.agent_view_install') 'Cyan'
    Write-InstallLine ''
    try {
        $step = (T 'installer.downloading_files')
        $from = Get-AgentViewPayloadSource $Source $ScriptRoot
        $count = Save-AgentViewPayload $from $staging
        Write-InstallStep ok ($(if ($from.Local) { (T 'installer.copied') } else { (T 'installer.downloaded') }) + $count + (T 'installer.files')) $from.Base
        . (Join-Path $staging 'Cli.ps1')
        $paths = Get-AgentViewPaths

        $step = (T 'installer.reading_existing_preferences')
        $existing = [pscustomobject]@{ Installed=(Test-Path -LiteralPath $paths.Entry); Autostart=(Test-AgentViewAutostart $paths); Widget=[bool](Get-AgentViewSettings $paths.Settings).WidgetEnabled }
        $opt = Resolve-AgentViewInstallOptions $Flags $envValues (Test-AgentViewInteractive) $existing
        if ($opt.Ask) {
            Write-InstallLine ''
            $opt.Autostart = Read-AgentViewYesNo (T 'installer.start_automatically_at_windows_sign_in') $opt.Autostart
            $opt.Widget = Read-AgentViewYesNo (T 'installer.enable_the_floating_desktop_widget') $opt.Widget
            $opt.Start = Read-AgentViewYesNo (T 'installer.start_agent_view_now') $opt.Start
            Write-InstallLine ''
        }

        $step = (T 'installer.stopping_the_previous_version')
        $state = Get-AgentViewRunState $paths
        if ($state -eq 'running') { [void](Stop-AgentViewApp $paths); Write-InstallStep ok (T 'installer.stopped_the_running_copy_upgrading') }
        elseif ($existing.Installed) { Write-InstallStep ok (T 'installer.upgrading_an_existing_installation') $paths.Root }
        else { Write-InstallStep info (T 'installer.new_installation') }

        $step = (T 'installer.copying_installation_files')
        $touched = $true
        $n = Install-AgentViewFiles $staging $paths
        Write-InstallStep ok ((T 'installer.installed_files' -Args @($n))) $paths.Root

        $step = (T 'installer.creating_the_agentview_command')
        [void](Write-AgentViewTextFile $paths.Shim (Get-AgentViewShimText))
        $pathChanged = Set-AgentViewUserPathEntry $paths.Bin $true
        Write-InstallStep ok (T 'installer.agentview_command') ($paths.Shim + $(if ($pathChanged) { (T 'installer.added_to_user_path') } else { (T 'installer.already_in_path') }))

        $step = (T 'installer.setting_start_at_sign_in')
        Set-AgentViewAutostart $paths $opt.Autostart
        if ($opt.Autostart) { Write-InstallStep ok (T 'installer.start_at_sign_in_on') $paths.Shortcut } else { Write-InstallStep skip (T 'installer.start_at_sign_in_off') }

        $step = (T 'installer.saving_widget_preferences')
        $settings = Get-AgentViewSettings $paths.Settings
        if ([bool]$settings.WidgetEnabled -ne [bool]$opt.Widget -or -not (Test-Path -LiteralPath $paths.Settings)) { $settings.WidgetEnabled = [bool]$opt.Widget; Save-AgentViewSettings $settings $paths.Settings }
        Write-InstallStep $(if ($opt.Widget) { 'ok' } else { 'skip' }) ((T 'installer.floating_widget') + $(if ($opt.Widget) { (T 'installer.on') } else { (T 'installer.off') }))

        $started = $false
        if ($opt.Start) {
            $step = (T 'installer.starting')
            $now = Get-AgentViewRunState $paths
            if ($now -eq 'other') { Write-InstallStep fail (T 'installer.not_started_another_copy_of_agent_view_is_running') (T 'installer.quit_that_copy_right_click_its_tray_icon_quit_then_run_agentview_') }
            elseif (Start-AgentViewApp $paths) { $started = $true; Write-InstallStep ok (T 'installer.started_agent_view') }
            else { throw (T 'installer.could_not_start_agent_view_process_exited_try_agentview_up') }
        } else { Write-InstallStep skip (T 'installer.not_started_run_agentview_up_when_needed') }
        if ($started -and -not $script:InstallQuiet) { try { Show-AgentViewFirstToast } catch { } }

        Write-InstallLine ''
        if ($started) { Write-InstallLine (T 'installer.done_agent_view_is_running_in_the_tray_beside_the_clock') 'Green' }
        else { Write-InstallLine (T 'installer.done_agent_view_is_installed') 'Green' }
        if ($started -and -not $script:InstallQuiet) { $summary = Get-AgentViewQuotaSummary $paths; if ($summary) { Write-InstallLine ('  ' + $summary) } }
        Write-InstallLine (T 'installer.type_agentview_help_for_available_commands')
        if ($pathChanged -and $ScriptPath) { Write-InstallLine (T 'installer.open_a_new_terminal_to_use_agentview_path_was_updated') 'DarkGray' }
        return 0
    } catch {
        Write-InstallStep fail ((T 'installer.error_at_step') + $step + '": ' + $_.Exception.Message)
        if (-not $touched) { Write-Host (T 'installer.no_changes_were_made_any_existing_installation_is_intact') -ForegroundColor Red }
        Write-Host ((T 'installer.try_again') + $retry) -ForegroundColor Red
        return 1
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
$__scriptPath = $PSCommandPath
if ($env:AGENT_VIEW_BOOTSTRAP -eq '1') { $__scriptPath = $env:AGENT_VIEW_INSTALL_SCRIPT }  # chạy qua install.ps1: thử lại bằng chính lệnh người dùng đã gõ
$__code = Invoke-AgentViewInstall -Source $Source -ScriptRoot $PSScriptRoot -ScriptPath $__scriptPath -Flags @{ Yes=[bool]$Yes; NoAutostart=[bool]$NoAutostart; Widget=[bool]$Widget; NoStart=[bool]$NoStart; Quiet=[bool]$Quiet }
if ($PSCommandPath) { exit $__code }
$global:LASTEXITCODE = $__code
