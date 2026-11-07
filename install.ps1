param(
    [string]$Source = $env:AGENT_VIEW_SOURCE,
    [switch]$Yes, [switch]$NoAutostart, [switch]$Widget, [switch]$NoStart, [switch]$Quiet
)
# Cài agent-view vào %LOCALAPPDATA%\agent-view. Chạy file local hoặc `irm <url>/install.ps1 | iex`
# (khi đó tham số qua biến môi trường AGENT_VIEW_YES/NO_AUTOSTART/WIDGET/NO_START/QUIET=1, hoặc
# `& ([scriptblock]::Create((irm <url>/install.ps1))) -Yes`). Tải hết vào thư mục tạm trước rồi mới thay bản cũ.
$script:AgentViewPayload = @('Tray.ps1','agent-view.ps1','Quota.ps1','Process.ps1','Theme.ps1','Format.ps1','Ring.ps1','Popup.ps1','Widget.ps1','Settings.ps1','Version.ps1','Cli.ps1')
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
    if ($a -match '^(?i)(y|yes|c|co|có)$') { return $true }
    if ($a -match '^(?i)(n|no|k|khong|không)$') { return $false }
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
        Write-Host '    Gõ y (có) hoặc n (không), Enter = mặc định.' -ForegroundColor DarkGray
    }
    return $Default
}
function Write-InstallStep([string]$Kind, [string]$Text, [string]$Detail) {
    if ($script:InstallQuiet -and $Kind -ne 'fail') { return }
    $mark = @{ ok='✓'; fail='✗'; skip='–'; info='·' }[$Kind]
    $color = @{ ok='Green'; fail='Red'; skip='DarkGray'; info='Gray' }[$Kind]
    Write-Host ('  ' + $mark + ' ') -ForegroundColor $color -NoNewline
    Write-Host $Text -NoNewline
    if ($Detail) { Write-Host ('  ' + $Detail) -ForegroundColor DarkGray } else { Write-Host '' }
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
            if (-not (Test-Path -LiteralPath $src)) { throw "Thiếu file cài đặt: $($item.From) (trong $($From.Base))" }
            Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction Stop
        } else {
            $url = $From.Base + '/' + $item.From
            try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $target -ErrorAction Stop }
            catch { throw "Không tải được $url — $($_.Exception.Message)" }
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
    return ('Quota còn lại: ' + ($parts -join ' · '))
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
    $script = Get-AgentViewToastScript 'agent-view đang chạy' 'Bấm icon cạnh đồng hồ để xem quota.'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ' + $encoded)
}

function Invoke-AgentViewInstall([string]$Source, [hashtable]$Flags, [string]$ScriptRoot, [string]$ScriptPath) {
    $envValues = Get-AgentViewInstallEnv
    $script:InstallQuiet = ([bool]$Flags['Quiet']) -or (Test-AgentViewTruthy $envValues['AGENT_VIEW_QUIET'])
    $retry = if ($ScriptPath) { 'powershell -ExecutionPolicy Bypass -File "' + $ScriptPath + '"' } else { 'chạy lại lệnh cài (irm …/install.ps1 | iex)' }
    $staging = Join-Path ([IO.Path]::GetTempPath()) ('agent-view-install-' + [guid]::NewGuid().ToString('N'))
    $step = 'chuẩn bị'; $touched = $false
    Write-InstallLine ''
    Write-InstallLine 'agent-view · cài đặt' 'Cyan'
    Write-InstallLine ''
    try {
        $step = 'tải file'
        $from = Get-AgentViewPayloadSource $Source $ScriptRoot
        $count = Save-AgentViewPayload $from $staging
        Write-InstallStep ok ($(if ($from.Local) { 'Đã chép ' } else { 'Đã tải ' }) + $count + ' file') $from.Base
        . (Join-Path $staging 'Cli.ps1')
        $paths = Get-AgentViewPaths

        $step = 'đọc cấu hình hiện có'
        $existing = [pscustomobject]@{ Installed=(Test-Path -LiteralPath $paths.Entry); Autostart=(Test-AgentViewAutostart $paths); Widget=[bool](Get-AgentViewSettings $paths.Settings).WidgetEnabled }
        $opt = Resolve-AgentViewInstallOptions $Flags $envValues (Test-AgentViewInteractive) $existing
        if ($opt.Ask) {
            Write-InstallLine ''
            $opt.Autostart = Read-AgentViewYesNo 'Tự chạy khi đăng nhập Windows?' $opt.Autostart
            $opt.Widget = Read-AgentViewYesNo 'Bật widget nổi trên màn hình?' $opt.Widget
            $opt.Start = Read-AgentViewYesNo 'Chạy agent-view ngay bây giờ?' $opt.Start
            Write-InstallLine ''
        }

        $step = 'dừng bản cũ'
        $state = Get-AgentViewRunState $paths
        if ($state -eq 'running') { [void](Stop-AgentViewApp $paths); Write-InstallStep ok 'Đã dừng bản đang chạy — cập nhật từ bản cũ' }
        elseif ($existing.Installed) { Write-InstallStep ok 'Cập nhật từ bản cũ' $paths.Root }
        else { Write-InstallStep info 'Cài mới' }

        $step = 'chép file vào thư mục cài'
        $touched = $true
        $n = Install-AgentViewFiles $staging $paths
        Write-InstallStep ok ("Đã cài $n file") $paths.Root

        $step = 'tạo lệnh agentview'
        [void](Write-AgentViewTextFile $paths.Shim (Get-AgentViewShimText))
        $pathChanged = Set-AgentViewUserPathEntry $paths.Bin $true
        Write-InstallStep ok 'Lệnh agentview' ($paths.Shim + $(if ($pathChanged) { ' (đã thêm vào PATH người dùng)' } else { ' (đã có trong PATH)' }))

        $step = 'đặt tự chạy khi đăng nhập'
        Set-AgentViewAutostart $paths $opt.Autostart
        if ($opt.Autostart) { Write-InstallStep ok 'Tự chạy khi đăng nhập: bật' $paths.Shortcut } else { Write-InstallStep skip 'Tự chạy khi đăng nhập: tắt' }

        $step = 'lưu cài đặt widget'
        $settings = Get-AgentViewSettings $paths.Settings
        if ([bool]$settings.WidgetEnabled -ne [bool]$opt.Widget -or -not (Test-Path -LiteralPath $paths.Settings)) { $settings.WidgetEnabled = [bool]$opt.Widget; Save-AgentViewSettings $settings $paths.Settings }
        Write-InstallStep $(if ($opt.Widget) { 'ok' } else { 'skip' }) ('Widget nổi: ' + $(if ($opt.Widget) { 'bật' } else { 'tắt' }))

        $started = $false
        if ($opt.Start) {
            $step = 'khởi động'
            $now = Get-AgentViewRunState $paths
            if ($now -eq 'other') { Write-InstallStep fail 'Chưa khởi động: một bản agent-view khác đang chạy.' 'Thoát bản đó (chuột phải icon khay → Thoát) rồi gõ: agentview up' }
            elseif (Start-AgentViewApp $paths) { $started = $true; Write-InstallStep ok 'Đã khởi động agent-view' }
            else { throw 'agent-view không khởi động được (tiến trình thoát ngay). Thử: agentview up' }
        } else { Write-InstallStep skip 'Chưa chạy (gõ agentview up khi cần)' }
        if ($started -and -not $script:InstallQuiet) { try { Show-AgentViewFirstToast } catch { } }

        Write-InstallLine ''
        if ($started) { Write-InstallLine '✓ Xong! agent-view đang chạy ở khay (cạnh đồng hồ).' 'Green' }
        else { Write-InstallLine '✓ Xong! agent-view đã được cài.' 'Green' }
        if ($started -and -not $script:InstallQuiet) { $summary = Get-AgentViewQuotaSummary $paths; if ($summary) { Write-InstallLine ('  ' + $summary) } }
        Write-InstallLine '  Gõ `agentview help` để xem lệnh.'
        if ($pathChanged -and $ScriptPath) { Write-InstallLine '  Lệnh agentview dùng được ở terminal mở mới (PATH vừa cập nhật).' 'DarkGray' }
        return 0
    } catch {
        Write-InstallStep fail ('Lỗi ở bước "' + $step + '": ' + $_.Exception.Message)
        if (-not $touched) { Write-Host '    Chưa thay đổi gì trên máy; bản cũ (nếu có) vẫn giữ nguyên.' -ForegroundColor Red }
        Write-Host ('    Thử lại: ' + $retry) -ForegroundColor Red
        return 1
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
$__code = Invoke-AgentViewInstall -Source $Source -ScriptRoot $PSScriptRoot -ScriptPath $PSCommandPath -Flags @{ Yes=[bool]$Yes; NoAutostart=[bool]$NoAutostart; Widget=[bool]$Widget; NoStart=[bool]$NoStart; Quiet=[bool]$Quiet }
if ($PSCommandPath) { exit $__code }
$global:LASTEXITCODE = $__code
