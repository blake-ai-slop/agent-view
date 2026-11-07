param([string]$Source = $env:AGENT_VIEW_SOURCE, [switch]$DeferSelf, [switch]$Quiet)
# Gỡ agent-view: dừng app, gỡ lệnh agentview khỏi PATH người dùng, xóa shortcut tự chạy và thư mục cài.
# -DeferSelf: gọi từ `agentview uninstall` (cmd còn đang đọc agentview.cmd) ⇒ thư mục cài được xóa trễ vài giây.
function Remove-AgentViewFiles($Paths, [switch]$Deferred) {
    # Only remove the named application directory, never its parent.
    $full = [IO.Path]::GetFullPath($Paths.Root)
    if ([IO.Path]::GetFileName($full.TrimEnd('\')) -ne 'agent-view') { throw 'Thư mục cài không hợp lệ' }
    Remove-Item -LiteralPath $Paths.Shortcut -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $full)) { return }
    if (-not $Deferred) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop; return }
    $shim = [IO.Path]::GetFullPath($Paths.Shim)
    Get-ChildItem -LiteralPath $full -Recurse -File -Force | Where-Object { $_.FullName -ne $shim } | Remove-Item -Force -ErrorAction Stop
    $cmd = '/d /c ping -n 6 127.0.0.1 >nul & rmdir /s /q "' + $full + '"'
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') -ArgumentList $cmd -WindowStyle Hidden
}
function Find-AgentViewCliScript([string]$ScriptRoot) {
    $candidates = @()
    if ($ScriptRoot) { $candidates += (Join-Path $ScriptRoot 'Cli.ps1'), (Join-Path $ScriptRoot 'src/Cli.ps1') }
    $candidates += Join-Path $env:LOCALAPPDATA 'agent-view/Cli.ps1'
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}
if ($MyInvocation.InvocationName -eq '.') { return }

$__code = & {
    $q = $Quiet -or ($env:AGENT_VIEW_QUIET -match '^(?i)(1|true|yes|y|on)$')
    $say = { param($kind, $text, $detail) if (-not $q -or $kind -eq 'fail') { Write-AgentViewStep $kind $text $detail } }
    $temp = $null
    $cli = Find-AgentViewCliScript $PSScriptRoot
    if (-not $cli) {
        # Bản cũ chưa có Cli.ps1 và đang chạy qua irm | iex: tải Cli.ps1 từ nguồn.
        $base = $Source; if ([string]::IsNullOrWhiteSpace($base)) { $base = 'https://raw.githubusercontent.com/blake-ai-slop/agent-view/main' }
        $temp = Join-Path ([IO.Path]::GetTempPath()) ('agent-view-cli-' + [guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($temp)
        $cli = Join-Path $temp 'Cli.ps1'
        try { Invoke-WebRequest -UseBasicParsing -Uri ($base.TrimEnd('/') + '/src/Cli.ps1') -OutFile $cli -ErrorAction Stop }
        catch { Write-Host ('✗ Không tải được Cli.ps1 để gỡ: ' + $_.Exception.Message) -ForegroundColor Red; Write-Host ('  Gỡ tay: tắt agent-view rồi xóa ' + (Join-Path $env:LOCALAPPDATA 'agent-view')) -ForegroundColor Red; return 1 }
    }
    . $cli
    $paths = Get-AgentViewPaths
    $step = 'dừng app'
    if (-not $q) { Write-Host ''; Write-Host 'agent-view · gỡ cài đặt' -ForegroundColor Cyan; Write-Host '' }
    try {
        $n = Stop-AgentViewApp $paths
        if ($n -gt 0) { & $say ok 'Đã dừng agent-view' } else { & $say info 'agent-view không chạy' }
        $step = 'gỡ lệnh agentview khỏi PATH'
        $changed = Set-AgentViewUserPathEntry $paths.Bin $false
        & $say ok 'Gỡ lệnh agentview' ($paths.Bin + $(if ($changed) { ' (đã xóa khỏi PATH người dùng)' } else { ' (không có trong PATH)' }))
        $step = 'xóa shortcut và thư mục cài'
        $hadShortcut = Test-Path -LiteralPath $paths.Shortcut
        Remove-AgentViewFiles $paths -Deferred:$DeferSelf
        if ($hadShortcut) { & $say ok 'Đã xóa tự chạy khi đăng nhập' $paths.Shortcut } else { & $say skip 'Không có shortcut tự chạy' }
        & $say ok $(if ($DeferSelf) { 'Đã xóa thư mục cài (phần còn lại tự xóa sau vài giây)' } else { 'Đã xóa thư mục cài' }) $paths.Root
        if (-not $q) { Write-Host ''; Write-Host '✓ Đã gỡ agent-view.' -ForegroundColor Green }
        return 0
    } catch {
        Write-AgentViewStep fail ('Lỗi ở bước "' + $step + '": ' + $_.Exception.Message) 'Đóng các cửa sổ đang mở file trong thư mục cài rồi thử lại.'
        return 1
    } finally { if ($temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue } }
}
if ($PSCommandPath) { exit $__code }
$global:LASTEXITCODE = $__code
