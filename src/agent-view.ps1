if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $PSCommandPath)
    exit
}
# AGENT_VIEW_MUTEX (chỉ dạng Local\agent-view-<tên>): mutex riêng cho smoke test, không đụng app thật.
$mutexName = 'Local\agent-view'
if ($env:AGENT_VIEW_MUTEX -match '^Local\\agent-view-[A-Za-z0-9-]+$') { $mutexName = $env:AGENT_VIEW_MUTEX }
$mutex = New-Object Threading.Mutex $false,$mutexName
$owned = $false
try {
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { return }
    $quotaPath = Join-Path $PSScriptRoot 'Quota.ps1'
    if (Test-Path -LiteralPath $quotaPath) { . $quotaPath }
    . (Join-Path $PSScriptRoot 'Tray.ps1')
    Start-AgentView
} finally { if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
