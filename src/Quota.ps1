. (Join-Path $PSScriptRoot 'I18n.ps1')
Register-AgentViewStrings -Module 'quota' -Strings @{
    en = @{
        'cannot_read_quota' = 'cannot read quota'
        'not_installed' = 'not installed'
        'timed_out' = 'timed out'
    }
    vi = @{
        'cannot_read_quota' = 'không đọc được'
        'not_installed' = 'chưa cài'
        'timed_out' = 'hết thời gian'
    }
}
# Đọc quota đã dùng (cửa sổ 5h + tuần) và giờ reset của Claude Code và Codex. Windows PowerShell 5.1.
# Dot-source không có side effect: chỉ định nghĩa hàm. Dữ liệu thô có accountUuid/email/gói: chỉ giữ % + giờ reset,
# không log, không ghi file. Không đọc credentials, không gọi lượt model.
. (Join-Path $PSScriptRoot 'Process.ps1')

# ---------- hàm thuần ----------

# % hợp lệ: chỉ nhận kiểu số trong 0–100 (chuỗi, bool, null ⇒ $null). Số lẻ làm tròn.
function ConvertTo-QuotaPercent($Value) {
  if ($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) { return $null }
  if ($Value -lt 0 -or $Value -gt 100) { return $null }
  return [int][math]::Round([double]$Value, [MidpointRounding]::AwayFromZero)
}

# Epoch (giây hoặc mili giây) ⇒ [datetime] giờ địa phương. Sai kiểu/ngoài khoảng ⇒ $null.
function ConvertFrom-QuotaEpoch($Value, [switch]$Milliseconds) {
  if ($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) { return $null }
  if ($Value -le 0) { return $null }
  try {
    if ($Milliseconds) { $dto = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Value) }
    else { $dto = [DateTimeOffset]::FromUnixTimeSeconds([long]$Value) }
    return $dto.UtcDateTime.ToLocalTime()
  }
  catch { return $null }
}

# Chuỗi ISO 8601 có múi giờ (hoặc [datetime] nếu ConvertFrom-Json đã đổi) ⇒ [datetime] giờ địa phương. Lỗi ⇒ $null.
function ConvertTo-QuotaLocalTime($Value) {
  if ($Value -is [datetime]) {
    if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value.ToLocalTime() }
    return $Value
  }
  if ($Value -isnot [string] -or $Value.Length -gt 64) { return $null }
  $dto = [DateTimeOffset]::MinValue
  $styles = [Globalization.DateTimeStyles]::AllowWhiteSpaces
  if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) { return $null }
  return $dto.LocalDateTime
}

# Cắt đúng đoạn JSON object của một khóa từ văn bản lớn, không parse cả file (file có dữ liệu nhạy cảm và
# có thể có khóa trùng chữ hoa/thường làm ConvertFrom-Json 5.1 lỗi). Không tìm thấy ⇒ $null.
function Get-JsonObjectText([string]$Text, [string]$Key) {
  if (-not $Text) { return $null }
  $needle = '"' + $Key + '"'
  $from = 0
  while ($true) {
    $at = $Text.IndexOf($needle, $from, [StringComparison]::Ordinal)
    if ($at -lt 0) { return $null }
    $from = $at + 1
    $i = $at + $needle.Length
    while ($i -lt $Text.Length -and [char]::IsWhiteSpace($Text[$i])) { $i++ }
    if ($i -ge $Text.Length -or $Text[$i] -ne ':') { continue }
    $i++
    while ($i -lt $Text.Length -and [char]::IsWhiteSpace($Text[$i])) { $i++ }
    if ($i -ge $Text.Length -or $Text[$i] -ne '{') { return $null }
    break
  }
  $start = $i; $depth = 0; $inStr = $false
  for (; $i -lt $Text.Length; $i++) {
    $ch = $Text[$i]
    if ($inStr) {
      if ($ch -eq '\') { $i++ } elseif ($ch -eq '"') { $inStr = $false }
      continue
    }
    if ($ch -eq '"') { $inStr = $true }
    elseif ($ch -eq '{' -or $ch -eq '[') { $depth++ }
    elseif ($ch -eq '}' -or $ch -eq ']') {
      $depth--
      if ($depth -eq 0) { return $Text.Substring($start, $i - $start + 1) }
    }
  }
  return $null
}

function Test-JsonProperty($Object, [string]$Name) {
  return ($Object -is [pscustomobject] -and @($Object.PSObject.Properties.Name) -contains $Name)
}

# Văn bản .claude.json ⇒ @{ FiveHour; Week; FiveHourResetsAt; WeekResetsAt; FetchedAt } từ cachedUsageUtilization. Thiếu số ⇒ $null.
function ConvertFrom-ClaudeConfigText([string]$Text) {
  $objText = Get-JsonObjectText $Text 'cachedUsageUtilization'
  if (-not $objText) { return $null }
  $c = try { $objText | ConvertFrom-Json -ErrorAction Stop } catch { $null }
  if (-not (Test-JsonProperty $c 'utilization') -or -not (Test-JsonProperty $c 'fetchedAtMs')) { return $null }
  $fetched = ConvertFrom-QuotaEpoch $c.fetchedAtMs -Milliseconds
  if (-not $fetched) { return $null }
  $u = $c.utilization
  $five = $u.five_hour; $week = $u.seven_day
  $fiveUsed = ConvertTo-QuotaPercent $five.utilization
  $weekUsed = ConvertTo-QuotaPercent $week.utilization
  if ($null -eq $fiveUsed -and $null -eq $weekUsed) { return $null }
  $fiveReset = $null; $weekReset = $null
  if ($null -ne $fiveUsed -and (Test-JsonProperty $five 'resets_at')) { $fiveReset = ConvertTo-QuotaLocalTime $five.resets_at }
  if ($null -ne $weekUsed -and (Test-JsonProperty $week 'resets_at')) { $weekReset = ConvertTo-QuotaLocalTime $week.resets_at }
  return @{ FiveHour = $fiveUsed; Week = $weekUsed; FiveHourResetsAt = $fiveReset; WeekResetsAt = $weekReset; FetchedAt = $fetched }
}

# Giờ reset dạng CLI in ('7:39pm', 'Nov 14, 10:59am', '19:39') ⇒ [datetime] giờ địa phương gần nhất sau $Now. Lạ ⇒ $null.
# Múi giờ trong ngoặc đã bỏ trước khi gọi; CLI in theo múi giờ máy nên coi là giờ địa phương.
function ConvertFrom-ClaudeResetText([string]$Text, [datetime]$Now) {
  $m = [regex]::Match("$Text".Trim(), '^(?:(?<mon>[A-Za-z]{3})[A-Za-z]*\.?\s+(?<day>\d{1,2})(?:st|nd|rd|th)?,?\s+(?:at\s+)?)?(?<h>\d{1,2})(?::(?<mi>\d{2}))?\s*(?<ap>[ap]\.?m\.?)?$', 'IgnoreCase')
  if (-not $m.Success) { return $null }
  $h = [int]$m.Groups['h'].Value
  $mi = 0; if ($m.Groups['mi'].Success) { $mi = [int]$m.Groups['mi'].Value }
  if ($mi -gt 59) { return $null }
  if ($m.Groups['ap'].Success) {
    if ($h -lt 1 -or $h -gt 12) { return $null }
    $pm = $m.Groups['ap'].Value.ToLowerInvariant().StartsWith('p')
    if ($h -eq 12) { $h = 0 }
    if ($pm) { $h += 12 }
  }
  elseif ($h -gt 23 -or -not $m.Groups['mi'].Success) { return $null }
  try {
    if ($m.Groups['mon'].Success) {
      $mon = [array]::IndexOf(@('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'), $m.Groups['mon'].Value.ToLowerInvariant()) + 1
      if ($mon -lt 1) { return $null }
      $at = [DateTime]::SpecifyKind((New-Object DateTime $Now.Year, $mon, ([int]$m.Groups['day'].Value), $h, $mi, 0), [DateTimeKind]::Local)
      if ($at -lt $Now.AddDays(-2)) { $at = $at.AddYears(1) }
      return $at
    }
    $at = [DateTime]::SpecifyKind((New-Object DateTime $Now.Year, $Now.Month, $Now.Day, $h, $mi, 0), [DateTimeKind]::Local)
    if ($at -lt $Now.AddMinutes(-1)) { $at = $at.AddDays(1) }
    return $at
  }
  catch { return $null }
}

# Văn bản /usage của Claude, thuần. Mỗi nhãn phải đúng một dòng khớp từ đầu dòng; không phụ thuộc ký tự '·'.
function ConvertFrom-ClaudeUsageText([string]$Text, [datetime]$Now) {
  $lines = @("$Text" -split '\r?\n')
  $out = @{ FiveHour = $null; Week = $null; FiveHourResetsAt = $null; WeekResetsAt = $null }
  foreach ($w in @(@('FiveHour', 'Current session'), @('Week', 'Current week\s*\(all models\)'))) {
    $label = $w[1]
    $hits = @($lines | ForEach-Object { [regex]::Match($_, "^\s*$label\s*:\s*(\d{1,3})\s*%\s*used\b(.*)$") } | Where-Object { $_.Success })
    if ($hits.Count -eq 0) { continue }
    if ($hits.Count -ne 1) { return $null }
    $used = [int]$hits[0].Groups[1].Value
    if ($used -gt 100) { continue }
    $reset = $null
    $r = [regex]::Match($hits[0].Groups[2].Value, '\bresets\s+(.+?)\s*$')
    if ($r.Success) {
      $t = ($r.Groups[1].Value -replace '\s*\([^)]*\)\s*$', '').Trim()
      $reset = ConvertFrom-ClaudeResetText $t $Now
    }
    $out[$w[0]] = $used
    $out[$w[0] + 'ResetsAt'] = $reset
  }
  if ($null -eq $out.FiveHour -and $null -eq $out.Week) { return $null }
  return $out
}

# Stdout JSON của `claude -p /usage --output-format json`, thuần. Chỉ nhận is_error=false và num_turns=0
# (có lượt model ⇒ chữ model viết, không phải số thật).
# Chỉ dùng envelope để xác nhận CLI không gọi model; chữ result không phải nguồn quota.
function Get-ClaudeUsageEnvelope([string[]]$Lines) {
  $msg = try { (@($Lines) -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop } catch { $null }
  if (-not (Test-JsonProperty $msg 'result') -or $msg.result -isnot [string]) { return $null }
  if (-not (Test-JsonProperty $msg 'is_error') -or $msg.is_error -isnot [bool] -or $msg.is_error) { return $null }
  if (-not (Test-JsonProperty $msg 'num_turns') -or $msg.num_turns -isnot [int] -or $msg.num_turns -ne 0) { return $null }
  return $msg
}

# Parser legacy chỉ nhận chữ có % thật; refresh hiện tại chỉ đọc số từ cache.
function ConvertFrom-ClaudeUsageReply([string[]]$Lines, [datetime]$Now) {
  $msg = Get-ClaudeUsageEnvelope $Lines
  if (-not $msg) { return $null }
  return ConvertFrom-ClaudeUsageText $msg.result $Now
}

# Bước hội thoại JSON-RPC của `codex app-server`, thuần. Chỉ initialize / initialized / account/rateLimits/read.
function Get-CodexHello { '{"method":"initialize","id":1,"params":{"clientInfo":{"name":"agent_view","title":"agent-view","version":"0"}}}' }
function Get-CodexStep([string]$Line) {
  $none = @{ Write = @(); Done = $false }
  $msg = try { $Line | ConvertFrom-Json -ErrorAction Stop } catch { $null }
  # Bỏ qua thông báo và request từ server (có method), kể cả khi trùng id.
  if ($msg -isnot [pscustomobject] -or (Test-JsonProperty $msg 'method') -or -not (Test-JsonProperty $msg 'id')) { return $none }
  if ($msg.id -eq 1) {
    if (Test-JsonProperty $msg 'error') { return @{ Write = @(); Done = $true } }
    return @{ Write = @('{"method":"initialized"}', '{"method":"account/rateLimits/read","id":2}'); Done = $false }
  }
  if ($msg.id -eq 2) { return @{ Write = @(); Done = $true } }
  return $none
}

# Phản hồi id=2 của Codex ⇒ @{ FiveHour; Week; FiveHourResetsAt; WeekResetsAt }, thuần. Chọn cửa sổ theo windowDurationMins.
function ConvertFrom-CodexReply([string[]]$Lines) {
  foreach ($line in @($Lines)) {
    $msg = try { $line | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    if ($msg -isnot [pscustomobject] -or -not (Test-JsonProperty $msg 'id') -or (Test-JsonProperty $msg 'method')) { continue }
    if ($msg.id -ne 2) { continue }
    if ((Test-JsonProperty $msg 'error') -or -not (Test-JsonProperty $msg 'result')) { return $null }
    if (-not (Test-JsonProperty $msg.result 'rateLimits')) { return $null }
    $limits = $msg.result.rateLimits
    $five = $null; $week = $null
    foreach ($name in 'primary', 'secondary') {
      if (-not (Test-JsonProperty $limits $name)) { continue }
      $w = $limits.$name
      if (-not (Test-JsonProperty $w 'windowDurationMins')) { continue }
      if ($w.windowDurationMins -eq 300) { $five = $w } elseif ($w.windowDurationMins -eq 10080) { $week = $w }
    }
    $fiveUsed = $null; $weekUsed = $null
    if (Test-JsonProperty $five 'usedPercent') { $fiveUsed = ConvertTo-QuotaPercent $five.usedPercent }
    if (Test-JsonProperty $week 'usedPercent') { $weekUsed = ConvertTo-QuotaPercent $week.usedPercent }
    if ($null -eq $fiveUsed -and $null -eq $weekUsed) { return $null }
    $fiveReset = $null; $weekReset = $null
    if ($null -ne $fiveUsed -and (Test-JsonProperty $five 'resetsAt')) { $fiveReset = ConvertFrom-QuotaEpoch $five.resetsAt }
    if ($null -ne $weekUsed -and (Test-JsonProperty $week 'resetsAt')) { $weekReset = ConvertFrom-QuotaEpoch $week.resetsAt }
    return @{ FiveHour = $fiveUsed; Week = $weekUsed; FiveHourResetsAt = $fiveReset; WeekResetsAt = $weekReset }
  }
  return $null
}

# Đường dẫn .claude.json: $env:CLAUDE_CONFIG_DIR\.claude.json nếu biến có, không thì <home>\.claude.json.
function Get-ClaudeConfigPath([string]$ConfigDir, [string]$HomeDir) {
  if ($ConfigDir) { return (Join-Path $ConfigDir '.claude.json') }
  return (Join-Path $HomeDir '.claude.json')
}

function New-AgentQuota([string]$Provider, [string]$Name, $Data, [string]$ErrorText, $FetchedAt) {
  $ok = ($null -ne $Data -and ($null -ne $Data.FiveHour -or $null -ne $Data.Week))
  if (-not $ok -and -not $ErrorText) { $ErrorText = (T 'quota.cannot_read_quota') }
  if ($ok) { $ErrorText = $null }
  $q = [pscustomobject]@{
    Provider = $Provider; Name = $Name; Ok = [bool]$ok; Error = $ErrorText
    FiveHourUsed = $null; WeekUsed = $null; FiveHourResetsAt = $null; WeekResetsAt = $null; FetchedAt = $FetchedAt
  }
  if ($ok) {
    if ($null -ne $Data.FiveHour) { $q.FiveHourUsed = [int]$Data.FiveHour; $q.FiveHourResetsAt = $Data.FiveHourResetsAt }
    if ($null -ne $Data.Week) { $q.WeekUsed = [int]$Data.Week; $q.WeekResetsAt = $Data.WeekResetsAt }
  }
  return $q
}

# ---------- phần chạm ngoài, tiêm được qua -Ops ----------

function Get-QuotaHomeDir { [Environment]::GetFolderPath('UserProfile') }

# Thư mục làm việc rỗng, cố định, riêng user (Claude tạo thư mục trong ~/.claude/projects cho mỗi cwd).
function Get-QuotaCwd { Join-Path (Get-QuotaHomeDir) '.agent-view\limits-cwd' }

function Find-AgentCli([string]$Name) {
  $c = Get-Command $Name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return $null
}

function Read-QuotaTextFile([string]$Path) {
  try {
    if (-not [IO.File]::Exists($Path)) { return $null }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  }
  catch { return $null }
}

# AppDomain chia sẻ throttle giữa các runspace trong cùng phiên app.
# Chỉ giữ thời điểm thử lại/lỗi chung, không giữ phản hồi hay dữ liệu tài khoản.
function Get-ClaudeFallbackState {
  $domain = [AppDomain]::CurrentDomain
  [Threading.Monitor]::Enter($domain)
  try {
    $key = 'agent-view.ClaudeFallbackState'
    $state = $domain.GetData($key)
    if ($null -eq $state) {
      $state = [hashtable]::Synchronized(@{})
      $domain.SetData($key, $state)
    }
    return $state
  }
  finally { [Threading.Monitor]::Exit($domain) }
}

# Giữ tuổi cache và cửa sổ thiếu; không suy đoán giờ reset kế tiếp.
function Reset-ClaudeCachedWindows([hashtable]$Cache, [datetime]$Now) {
  $data = $Cache.Clone()
  foreach ($window in @('FiveHour', 'Week')) {
    $reset = $window + 'ResetsAt'
    if ($null -ne $data[$window] -and $null -ne $data[$reset] -and $data[$reset] -le $Now) {
      $data[$window] = 0
      $data[$reset] = $null
    }
  }
  return $data
}

function New-QuotaOps {
  return @{
    FallbackState = Get-ClaudeFallbackState
    Now      = { Get-Date }
    GetEnv   = { param($name) [Environment]::GetEnvironmentVariable($name) }
    HomeDir  = { Get-QuotaHomeDir }
    ReadText = { param($path) Read-QuotaTextFile $path }
    Find     = { param($name) Find-AgentCli $name }
    Run      = { param($invocation, $send, $onLine, $timeoutMs) Invoke-AgentProcess -Invocation $invocation -Send $send -OnLine $onLine -Cwd (Get-QuotaCwd) -TimeoutMs $timeoutMs }
  }
}

# Cache ≤5 phút dùng luôn; cũ hơn thì print /usage chỉ để kích Claude ghi lại cache.
# Mọi lần thử (kể cả thành công/timeout) cách nhau ≥5 phút trong AppDomain của app.
# Không lấy số từ text CLI; cache cũ dùng tối đa 7 ngày và áp dụng reset đã qua.
function Get-ClaudeQuota([hashtable]$Ops) {
  $name = 'Claude Code'
  try {
    $now = & $Ops.Now
    $path = Get-ClaudeConfigPath (& $Ops.GetEnv 'CLAUDE_CONFIG_DIR') (& $Ops.HomeDir)
    $cache = ConvertFrom-ClaudeConfigText (& $Ops.ReadText $path)
    if ($cache -and ($now - $cache.FetchedAt).TotalMinutes -le 5) {
      $cache = Reset-ClaudeCachedWindows $cache $now
      return New-AgentQuota 'claude' $name $cache $null $cache.FetchedAt
    }
    $err = (T 'quota.cannot_read_quota')
    $src = & $Ops.Find 'claude'
    if (-not $src) { $err = (T 'quota.not_installed') }
    else {
      $key = "$src|$path"
      $attempt = $false
      # Đặt lịch trước khi chạy CLI: runspace khác cũng không gọi trùng.
      [Threading.Monitor]::Enter($Ops.FallbackState.SyncRoot)
      try {
        $last = $Ops.FallbackState[$key]
        if ($last -and $now -lt $last.RetryAt) { $err = $last.Error }
        else {
          $Ops.FallbackState[$key] = @{ RetryAt = $now.AddMinutes(5); Error = $err }
          $attempt = $true
        }
      }
      finally { [Threading.Monitor]::Exit($Ops.FallbackState.SyncRoot) }
      if ($attempt) {
        $inv = Get-AgentCliInvocation $src @('-p', '/usage', '--output-format', 'json', '--no-session-persistence')
        $r = $null
        try { $r = & $Ops.Run $inv @() $null 12000 } catch {}
        if ($r -and $r.TimedOut) { $err = (T 'quota.timed_out') }
        elseif ($r -and $r.ExitCode -eq 0 -and (Get-ClaudeUsageEnvelope $r.Lines)) {
          # CLI có thể không ghi lại nếu chưa qua TTL nội bộ; không làm mới tuổi giả.
          $updated = $null
          try { $updated = ConvertFrom-ClaudeConfigText (& $Ops.ReadText $path) } catch {}
          if ($updated -and (-not $cache -or $updated.FetchedAt -gt $cache.FetchedAt)) { $cache = $updated }
        }
        $Ops.FallbackState[$key] = @{ RetryAt = (& $Ops.Now).AddMinutes(5); Error = $err }
      }
    }
    $now = & $Ops.Now
    if ($cache -and ($now - $cache.FetchedAt).TotalDays -le 7) {
      $cache = Reset-ClaudeCachedWindows $cache $now
      return New-AgentQuota 'claude' $name $cache $null $cache.FetchedAt
    }
    return New-AgentQuota 'claude' $name $null $err $now
  }
  catch { return New-AgentQuota 'claude' $name $null (T 'quota.cannot_read_quota') (Get-Date) }
}

function Get-CodexQuota([hashtable]$Ops) {
  $name = 'Codex'
  try {
    $now = & $Ops.Now
    $src = & $Ops.Find 'codex'
    if (-not $src) { return New-AgentQuota 'codex' $name $null (T 'quota.not_installed') $now }
    $inv = Get-AgentCliInvocation $src @('app-server')
    $r = & $Ops.Run $inv @(Get-CodexHello) { param($line) Get-CodexStep $line } 12000
    $at = & $Ops.Now
    $data = $null
    if ($r) { $data = ConvertFrom-CodexReply $r.Lines }
    if ($data) { return New-AgentQuota 'codex' $name $data $null $at }
    if ($r -and $r.TimedOut) { return New-AgentQuota 'codex' $name $null (T 'quota.timed_out') $at }
    return New-AgentQuota 'codex' $name $null (T 'quota.cannot_read_quota') $at
  }
  catch { return New-AgentQuota 'codex' $name $null (T 'quota.cannot_read_quota') (Get-Date) }
}

# Quota của mọi provider, thứ tự cố định claude, codex: phát 2 object ra pipeline, không ném lỗi.
# Ok khi có ít nhất một cửa sổ; số và reset của cửa sổ thiếu là $null. Tên trường luôn giữ nguyên.
# -Ops: hashtable ghi đè một phần các thao tác ngoài (Now, GetEnv, HomeDir, ReadText, Find, Run).
function Get-AgentQuotas {
  param([hashtable]$Ops)
  $all = New-QuotaOps
  if ($Ops) { foreach ($k in @($Ops.Keys)) { $all[$k] = $Ops[$k] } }
  Get-ClaudeQuota $all
  Get-CodexQuota $all
}
