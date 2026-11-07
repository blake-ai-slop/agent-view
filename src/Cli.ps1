# Lệnh `agentview` + hàm dùng chung cho installer.ps1/uninstall.ps1 (đường dẫn, phát hiện đang chạy, PATH người dùng, shim, tự chạy).
# Dot-source không side effect. Chạy được trên Windows PowerShell 5.1 và pwsh 7; app luôn chạy bằng powershell.exe.
# Biến môi trường ẩn cho thử nghiệm: AGENT_VIEW_STARTUP_DIR (thư mục Startup), AGENT_VIEW_USER_PATH_FILE (PATH người dùng giả).
$script:AgentViewVersion = '0.0.0'  # dự phòng khi thiếu Version.ps1 (vd. bản sao tạm lúc gỡ); nguồn thật: src/Version.ps1
$script:AgentViewDefaultSource = 'https://raw.githubusercontent.com/blake-ai-slop/agent-view/main'
$script:AgentViewCommands = @('up','start','down','stop','restart','status','widget','autostart','update','uninstall','version','help')
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
    'reset ' + (Format-QuotaResetRelative $At $Now) + ' (' + (Format-QuotaResetAbsolute $At $Now) + ')'
}
function Get-AgentViewAppLine($App) {
    $state = switch ($App.State) { running { 'đang chạy' } other { 'một bản khác đang chạy' } default { 'không chạy' } }
    'agent-view ' + $App.Version + ' · ' + $state + ' · tự chạy: ' + $(if ($App.Autostart) { 'bật' } else { 'tắt' }) + ' · widget: ' + $(if ($App.Widget) { 'bật' } else { 'tắt' })
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
        $lines.Add([pscustomobject]@{ Text=('{0,-13} còn {1,3}%  {2}' -f $q.Name, $remaining, (Get-QuotaStatusText $level)); Color=(Get-AgentViewLevelColor $level) })
        foreach ($w in @(@('5 giờ',$q.FiveHourUsed,$q.FiveHourResetsAt), @('Tuần',$q.WeekUsed,$q.WeekResetsAt))) {
            if ($null -eq $w[1]) { continue }  # provider có thể bỏ một cửa sổ (Ok nhưng 5h/Tuần = null)
            $left = 100 - [int]$w[1]
            $lines.Add([pscustomobject]@{ Text=('  {0,-11} còn {1,3}%  {2}' -f $w[0], $left, (Format-AgentViewReset $w[2] $Now)); Color=(Get-AgentViewLevelColor (Get-QuotaLevel $left)) })
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
    switch -regex ([string]$Value) { '^(?i)(on|1|true|bật|bat)$' { return $true } '^(?i)(off|0|false|tắt|tat)$' { return $false } }
    return $null
}
function Test-AgentViewYesFlag($Rest) { @($Rest | Where-Object { $_ -match '^(?i)(-y|--yes|-yes|/y)$' }).Count -gt 0 }

function Show-AgentViewHelp {
    Write-Host ('agentview ' + $script:AgentViewVersion + ' — điều khiển agent-view từ terminal') -ForegroundColor Cyan
    Write-Host ''
    $rows = @(
        @('up','Chạy agent-view nếu chưa chạy (bí danh: start)'), @('down','Tắt agent-view (bí danh: stop)'), @('restart','Khởi động lại'),
        @('status','Xem quota còn lại và trạng thái app (--json: dạng máy đọc)'), @('widget on|off','Bật/tắt widget nổi'),
        @('autostart on|off','Bật/tắt tự chạy khi đăng nhập Windows'), @('update','Cập nhật bản mới nhất, giữ lựa chọn hiện tại'),
        @('uninstall','Gỡ agent-view (-y: không hỏi lại)'), @('version','In phiên bản'), @('help','Trợ giúp này'))
    foreach ($r in $rows) { Write-Host ('  agentview {0,-17}' -f $r[0]) -ForegroundColor White -NoNewline; Write-Host $r[1] }
}
function Invoke-AgentViewRestartIfRunning($Paths) {
    if ((Get-AgentViewRunState $Paths) -ne 'running') { return 0 }
    Write-Host 'Khởi động lại agent-view để áp dụng…'
    [void](Stop-AgentViewApp $Paths)
    if (Start-AgentViewApp $Paths) { Write-AgentViewStep ok 'Đã khởi động lại agent-view.'; return 0 }
    Write-AgentViewStep fail 'Không khởi động lại được agent-view.' 'Thử: agentview up'; return 1
}
function Invoke-AgentViewUp($Paths) {
    switch (Get-AgentViewRunState $Paths) {
        running { Write-AgentViewStep info 'agent-view đã chạy sẵn (icon ở khay cạnh đồng hồ).'; return 0 }
        other { Write-AgentViewStep fail 'Một bản agent-view khác đang chạy (không phải bản cài ở đây).' 'Thoát bản đó (chuột phải icon khay → Thoát) rồi thử lại.'; return 1 }
    }
    if (-not (Test-Path -LiteralPath $Paths.Launcher)) { Write-AgentViewStep fail ('Không thấy ' + $Paths.Launcher) 'Cài lại: agentview update'; return 1 }
    if (Start-AgentViewApp $Paths) { Write-AgentViewStep ok 'Đã chạy agent-view — bấm icon cạnh đồng hồ để xem quota.'; return 0 }
    Write-AgentViewStep fail 'agent-view không khởi động được.' 'Thử lại: agentview restart'; return 1
}
function Invoke-AgentViewDown($Paths) {
    $n = Stop-AgentViewApp $Paths
    if ($n -gt 0) { Write-AgentViewStep ok 'Đã tắt agent-view.' } else { Write-AgentViewStep info 'agent-view không chạy.' }
    return 0
}
function Invoke-AgentViewStatus($Paths, $Rest) {
    $app = Get-AgentViewAppInfo $Paths
    $json = @($Rest | Where-Object { $_ -match '^(?i)--?json$' }).Count -gt 0
    if (-not $json) { Write-Host 'Đang đọc quota…' -ForegroundColor DarkGray }
    . (Join-Path $PSScriptRoot 'Quota.ps1')
    $quotas = @(Get-AgentQuotas)
    if ($json) { Write-Host (ConvertTo-AgentViewStatusJson $quotas $app); return 0 }
    foreach ($l in (Format-AgentViewStatusLines $quotas $app)) { Write-Host $l.Text -ForegroundColor $l.Color }
    return 0
}
function Invoke-AgentViewToggle($Paths, [string]$What, $Rest) {
    $label = @{ widget='Widget nổi'; autostart='Tự chạy khi đăng nhập' }[$What]
    $current = if ($What -eq 'widget') { [bool](Get-AgentViewSettings $Paths.Settings).WidgetEnabled } else { Test-AgentViewAutostart $Paths }
    if (@($Rest).Count -eq 0) { Write-Host ($label + ': ' + $(if ($current) { 'bật' } else { 'tắt' }) + '   (đổi: agentview ' + $What + ' on|off)'); return 0 }
    $on = ConvertFrom-AgentViewSwitch $Rest[0]
    if ($null -eq $on) { Write-AgentViewStep fail ('Không hiểu "' + $Rest[0] + '".') ('Dùng: agentview ' + $What + ' on|off'); return 1 }
    if ($What -eq 'widget') { $s = Get-AgentViewSettings $Paths.Settings; $s.WidgetEnabled = $on; Save-AgentViewSettings $s $Paths.Settings }
    else { Set-AgentViewAutostart $Paths $on }
    Write-AgentViewStep ok ($label + ': ' + $(if ($on) { 'bật' } else { 'tắt' }))
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
            Write-Host ('Tải trình cài từ ' + $source + ' …') -ForegroundColor DarkGray
            try { Invoke-WebRequest -UseBasicParsing -Uri ($source.TrimEnd('/') + '/installer.ps1') -OutFile $installer -ErrorAction Stop }
            catch { Write-AgentViewStep fail 'Không tải được trình cài.' ($_.Exception.Message + ' — kiểm tra mạng rồi thử lại: agentview update'); return 1 }
        }
        if (-not (Test-Path -LiteralPath $installer)) { Write-AgentViewStep fail ('Không thấy ' + $installer); return 1 }
        $argText = '-NoProfile -ExecutionPolicy Bypass -File "' + $installer + '" -Yes'
        if ((Get-AgentViewRunState $Paths) -ne 'running') { $argText += ' -NoStart' }
        $old = $env:AGENT_VIEW_SOURCE; $env:AGENT_VIEW_SOURCE = $source
        try { return (Invoke-AgentViewChild $argText) }
        finally { $env:AGENT_VIEW_SOURCE = $old }
    } finally { if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue } }
}
function Invoke-AgentViewUninstall($Paths, $Rest) {
    if (-not (Test-AgentViewYesFlag $Rest)) {
        if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { Write-AgentViewStep fail 'Cần xác nhận.' 'Chạy: agentview uninstall -y'; return 1 }
        $answer = Read-Host 'Gỡ agent-view khỏi máy này? [y/N]'
        if ($answer -notmatch '^(?i)(y|yes|c|có|co)$') { Write-Host 'Đã hủy, không gỡ gì.'; return 0 }
    }
    $script = $Paths.Uninstall; if (-not (Test-Path -LiteralPath $script)) { $script = Join-Path $PSScriptRoot 'uninstall.ps1' }
    if (-not (Test-Path -LiteralPath $script)) { Write-AgentViewStep fail 'Không thấy uninstall.ps1.' 'Cài lại bằng agentview update rồi thử lại.'; return 1 }
    # Cli.ps1/uninstall.ps1 nằm trong thư mục sắp xóa: chạy bản sao ở %TEMP%; shim agentview.cmd được xóa trễ vì cmd còn đang đọc nó.
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('agent-view-uninstall-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($tempDir)
    Copy-Item -LiteralPath $script -Destination (Join-Path $tempDir 'uninstall.ps1') -Force
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $tempDir 'Cli.ps1') -Force
    $ver = Join-Path $PSScriptRoot 'Version.ps1'; if (Test-Path -LiteralPath $ver) { Copy-Item -LiteralPath $ver -Destination (Join-Path $tempDir 'Version.ps1') -Force }
    $code = Invoke-AgentViewChild ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $tempDir 'uninstall.ps1') + '" -DeferSelf')
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    return $code
}
function Invoke-AgentViewCli([string[]]$Argv, $Paths = (Get-AgentViewPaths)) {
    $cmd = Resolve-AgentViewCommand $Argv
    if ($cmd.Error) {
        Write-Host ('agentview: không có lệnh "' + $Argv[0] + '".') -ForegroundColor Red
        if ($cmd.Suggestion) { Write-Host ('Ý bạn là: agentview ' + $cmd.Suggestion + ' ?') -ForegroundColor Yellow }
        Write-Host 'Gõ agentview help để xem danh sách lệnh.'
        return 1
    }
    try {
        switch ($cmd.Command) {
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
    } catch { Write-AgentViewStep fail ('Lỗi khi chạy "agentview ' + $cmd.Command + '": ' + $_.Exception.Message); return 1 }
    return 1
}

if ($MyInvocation.InvocationName -eq '.') { return }
exit (Invoke-AgentViewCli $args)
