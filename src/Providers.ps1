# Registry provider dùng chung (tầng dữ liệu/cài đặt). Windows PowerShell 5.1. Không chứa code UI.
# Dot-source không có side effect: chỉ định nghĩa hàm. Thứ tự cố định: claude, codex, antigravity.
# Family = id provider (khóa settings/theme/row); Cli = tên lệnh; KnownPaths = đường dẫn thử sau PATH (chưa mở rộng biến môi trường);
# Fetch = tên hàm đọc quota; Module = file cần dot-source cạnh Quota.ps1 ($null nếu nằm trong Quota.ps1).
function Get-AgentProviders {
  @(
    [pscustomobject]@{ Family = 'claude'; Name = 'Claude Code'; Short = 'Claude'; Color = '#E2875C'; Cli = 'claude'; KnownPaths = @(); Fetch = 'Get-ClaudeQuota'; Module = $null }
    [pscustomobject]@{ Family = 'codex'; Name = 'Codex'; Short = 'Codex'; Color = '#C7CEDA'; Cli = 'codex'; KnownPaths = @(); Fetch = 'Get-CodexQuota'; Module = $null }
    [pscustomobject]@{ Family = 'antigravity'; Name = 'Antigravity'; Short = 'Antigravity'; Color = '#6FA8F5'; Cli = 'agy'; KnownPaths = @('%LOCALAPPDATA%\agy\bin\agy.exe'); Fetch = 'Get-AntigravityQuota'; Module = 'QuotaAntigravity.ps1' }
  )
}

# Một provider có mặt trên máy? Chỉ kiểm file (Find = PATH + KnownPaths bằng Test-Path), không chạy tiến trình.
# Claude: có CLI hoặc có .claude.json (đọc được cache dù không có CLI). Lỗi ⇒ coi như không có.
function Test-AgentProviderPresent($Provider, [hashtable]$Ops) {
  try {
    if (& $Ops.Find $Provider.Cli) { return $true }
    if ($Provider.Family -eq 'claude') {
      $path = Get-ClaudeConfigPath (& $Ops.GetEnv 'CLAUDE_CONFIG_DIR') (& $Ops.HomeDir)
      if (& $Ops.ReadText $path) { return $true }
    }
  } catch {}
  return $false
}

# Danh sách Family đã phát hiện, phát từng chuỗi (caller bọc @()). Cache trong Ops.ProviderPresence
# (mặc định AppDomain 'agent-view.ProviderPresence'); chỉ quét lại khi chưa có cache hoặc -Rescan. Cần Quota.ps1 đã nạp.
function Get-AgentDetectedProviders {
  param([switch]$Rescan, [hashtable]$Ops)
  $all = New-QuotaOps
  if ($Ops) { foreach ($k in @($Ops.Keys)) { $all[$k] = $Ops[$k] } }
  $state = $all.ProviderPresence
  $found = $null
  if (-not $Rescan) { $found = $state['Families'] }
  if ($null -eq $found) {
    $found = [string[]]@(foreach ($p in Get-AgentProviders) { if (Test-AgentProviderPresent $p $all) { $p.Family } })
    $state['Families'] = $found
  }
  foreach ($f in @($found)) { [string]$f }
}

# Xóa cache phát hiện (nút Quét lại): lần gọi Get-AgentDetectedProviders/Get-AgentQuotas kế tiếp quét lại.
function Reset-AgentDetectedProviders {
  param([hashtable]$Ops)
  $state = $null
  if ($Ops -and $Ops.ProviderPresence) { $state = $Ops.ProviderPresence } else { $state = Get-QuotaDomainState 'agent-view.ProviderPresence' }
  $state.Remove('Families')
}
