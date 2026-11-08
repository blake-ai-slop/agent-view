param([string]$Source = $env:AGENT_VIEW_SOURCE, [switch]$DeferSelf, [switch]$Quiet)
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
Register-AgentViewStrings -Module 'uninstall' -Strings @{
    en = @{
        'invalid_installation_directory' = 'Invalid installation directory'
        'could_not_download_cli_ps1_to_uninstall' = '✗ Could not download Cli.ps1 to uninstall: '
        'remove_manually_stop_agent_view_then_delete' = '  Remove manually: stop agent-view, then delete '
        'stopping_the_app' = 'stopping the app'
        'agent_view_uninstall' = 'agent-view · uninstall'
        'stopped_agent_view' = 'Stopped agent-view'
        'agent_view_is_stopped' = 'agent-view is stopped'
        'removing_agentview_from_path' = 'removing agentview from PATH'
        'removed_the_agentview_command' = 'Removed the agentview command'
        'removed_from_user_path' = ' (removed from user PATH)'
        'not_in_path' = ' (not in PATH)'
        'removing_shortcut_and_installation_directory' = 'removing shortcut and installation directory'
        'removed_start_at_sign_in' = 'Removed start at sign-in'
        'no_start_at_sign_in_shortcut' = 'No start-at-sign-in shortcut'
        'removed_installation_directory_remaining_files_will_be_removed_sh' = 'Removed installation directory (remaining files will be removed shortly)'
        'removed_installation_directory' = 'Removed installation directory'
        'uninstalled_agent_view' = '✓ Uninstalled agent-view.'
        'error_at_step' = 'Error at step "'
        'close_windows_using_files_in_the_installation_directory_and_try_a' = 'Close windows using files in the installation directory and try again.'
    }
    vi = @{
        'invalid_installation_directory' = 'Thư mục cài không hợp lệ'
        'could_not_download_cli_ps1_to_uninstall' = '✗ Không tải được Cli.ps1 để gỡ: '
        'remove_manually_stop_agent_view_then_delete' = '  Gỡ tay: tắt agent-view rồi xóa '
        'stopping_the_app' = 'dừng app'
        'agent_view_uninstall' = 'agent-view · gỡ cài đặt'
        'stopped_agent_view' = 'Đã dừng agent-view'
        'agent_view_is_stopped' = 'agent-view không chạy'
        'removing_agentview_from_path' = 'gỡ lệnh agentview khỏi PATH'
        'removed_the_agentview_command' = 'Gỡ lệnh agentview'
        'removed_from_user_path' = ' (đã xóa khỏi PATH người dùng)'
        'not_in_path' = ' (không có trong PATH)'
        'removing_shortcut_and_installation_directory' = 'xóa shortcut và thư mục cài'
        'removed_start_at_sign_in' = 'Đã xóa tự chạy khi đăng nhập'
        'no_start_at_sign_in_shortcut' = 'Không có shortcut tự chạy'
        'removed_installation_directory_remaining_files_will_be_removed_sh' = 'Đã xóa thư mục cài (phần còn lại tự xóa sau vài giây)'
        'removed_installation_directory' = 'Đã xóa thư mục cài'
        'uninstalled_agent_view' = '✓ Đã gỡ agent-view.'
        'error_at_step' = 'Lỗi ở bước "'
        'close_windows_using_files_in_the_installation_directory_and_try_a' = 'Đóng các cửa sổ đang mở file trong thư mục cài rồi thử lại.'
    }
}
# Gỡ agent-view: dừng app, gỡ lệnh agentview khỏi PATH người dùng, xóa shortcut tự chạy và thư mục cài.
# -DeferSelf: gọi từ `agentview uninstall` (cmd còn đang đọc agentview.cmd) ⇒ thư mục cài được xóa trễ vài giây.
function Remove-AgentViewFiles($Paths, [switch]$Deferred) {
    # Only remove the named application directory, never its parent.
    $full = [IO.Path]::GetFullPath($Paths.Root)
    if ([IO.Path]::GetFileName($full.TrimEnd('\')) -ne 'agent-view') { throw (T 'uninstall.invalid_installation_directory') }
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
        try { foreach ($dep in @('Cli.ps1','I18n.ps1','Settings.ps1','Format.ps1','Version.ps1')) { Invoke-WebRequest -UseBasicParsing -Uri ($base.TrimEnd('/') + '/src/' + $dep) -OutFile (Join-Path $temp $dep) -ErrorAction Stop } }
        catch { Write-Host ((T 'uninstall.could_not_download_cli_ps1_to_uninstall') + $_.Exception.Message) -ForegroundColor Red; Write-Host ((T 'uninstall.remove_manually_stop_agent_view_then_delete') + (Join-Path $env:LOCALAPPDATA 'agent-view')) -ForegroundColor Red; return 1 }
    }
    . $cli
    $paths = Get-AgentViewPaths
    $step = (T 'uninstall.stopping_the_app')
    if (-not $q) { Write-Host ''; Write-Host (T 'uninstall.agent_view_uninstall') -ForegroundColor Cyan; Write-Host '' }
    try {
        $n = Stop-AgentViewApp $paths
        if ($n -gt 0) { & $say ok (T 'uninstall.stopped_agent_view') } else { & $say info (T 'uninstall.agent_view_is_stopped') }
        $step = (T 'uninstall.removing_agentview_from_path')
        $changed = Set-AgentViewUserPathEntry $paths.Bin $false
        & $say ok (T 'uninstall.removed_the_agentview_command') ($paths.Bin + $(if ($changed) { (T 'uninstall.removed_from_user_path') } else { (T 'uninstall.not_in_path') }))
        $step = (T 'uninstall.removing_shortcut_and_installation_directory')
        $hadShortcut = Test-Path -LiteralPath $paths.Shortcut
        Remove-AgentViewFiles $paths -Deferred:$DeferSelf
        if ($hadShortcut) { & $say ok (T 'uninstall.removed_start_at_sign_in') $paths.Shortcut } else { & $say skip (T 'uninstall.no_start_at_sign_in_shortcut') }
        & $say ok $(if ($DeferSelf) { (T 'uninstall.removed_installation_directory_remaining_files_will_be_removed_sh') } else { (T 'uninstall.removed_installation_directory') }) $paths.Root
        if (-not $q) { Write-Host ''; Write-Host (T 'uninstall.uninstalled_agent_view') -ForegroundColor Green }
        return 0
    } catch {
        Write-AgentViewStep fail ((T 'uninstall.error_at_step') + $step + '": ' + $_.Exception.Message) (T 'uninstall.close_windows_using_files_in_the_installation_directory_and_try_a')
        return 1
    } finally { if ($temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue } }
}
if ($PSCommandPath) { exit $__code }
$global:LASTEXITCODE = $__code
