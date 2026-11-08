# Pester 3.4: chạy bằng powershell.exe 5.1.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\src\Quota.ps1')
Set-AgentViewLanguage vi
$fx = Join-Path $here 'fixtures'

function New-TestOps([hashtable]$Over) {
  $ops = @{
    FallbackState = @{}
    Now      = { [DateTime]::SpecifyKind((New-Object DateTime 2026, 11, 7, 12, 0, 0), 'Local') }
    GetEnv   = { param($n) $null }
    HomeDir  = { 'C:\home' }
    ReadText = { param($p) $null }
    Find     = { param($n) $null }
    Run      = { param($i, $s, $o, $t) throw 'Run không được gọi' }
  }
  if ($Over) { foreach ($k in $Over.Keys) { $ops[$k] = $Over[$k] } }
  return $ops
}

Describe 'Dot-source' {
  It 'không in gì và định nghĩa Get-AgentQuotas' {
    $src = Join-Path $here '..\src\Quota.ps1'
    $out = powershell.exe -NoProfile -Command "`$o = . '$src' *>&1; 'out=' + @(`$o).Count; (Get-Command Get-AgentQuotas).Name; (Get-Command Invoke-AgentProcess).Name"
    ($out -join ',') | Should Be 'out=0,Get-AgentQuotas,Invoke-AgentProcess'
  }
}

Describe 'ConvertTo-QuotaPercent' {
  It 'nhận số 0-100, làm tròn' {
    ConvertTo-QuotaPercent 5 | Should Be 5
    ConvertTo-QuotaPercent 41.5 | Should Be 42
    ConvertTo-QuotaPercent ([decimal]0.4) | Should Be 0
    ConvertTo-QuotaPercent ([long]100) | Should Be 100
  }
  It 'loại chuỗi, bool, null, ngoài khoảng' {
    ConvertTo-QuotaPercent '5' | Should BeNullOrEmpty
    ConvertTo-QuotaPercent $true | Should BeNullOrEmpty
    ConvertTo-QuotaPercent $null | Should BeNullOrEmpty
    ConvertTo-QuotaPercent 101 | Should BeNullOrEmpty
    ConvertTo-QuotaPercent -1 | Should BeNullOrEmpty
  }
}

Describe 'ConvertFrom-QuotaEpoch / ConvertTo-QuotaLocalTime' {
  It 'epoch giây ⇒ giờ địa phương' {
    $d = ConvertFrom-QuotaEpoch 1794061534
    $d.Kind | Should Be 'Local'
    $d.ToUniversalTime().ToString('s') | Should Be '2026-11-07T14:25:34'
  }
  It 'epoch ms' {
    (ConvertFrom-QuotaEpoch ([long]1794045921071) -Milliseconds).ToUniversalTime().ToString('s') | Should Be '2026-11-07T10:05:21'
  }
  It 'loại giá trị sai' {
    ConvertFrom-QuotaEpoch 'x' | Should BeNullOrEmpty
    ConvertFrom-QuotaEpoch 0 | Should BeNullOrEmpty
  }
  It 'ISO có múi giờ ⇒ giờ địa phương' {
    $d = ConvertTo-QuotaLocalTime '2026-11-07T19:40:00.449382+07:00'
    $d.ToUniversalTime().ToString('s') | Should Be '2026-11-07T12:40:00'
    ConvertTo-QuotaLocalTime 'không phải ngày' | Should BeNullOrEmpty
    ConvertTo-QuotaLocalTime $null | Should BeNullOrEmpty
  }
}

Describe 'Get-JsonObjectText' {
  It 'cắt đúng object, bỏ qua chuỗi chứa ngoặc' {
    $t = Get-JsonObjectText '{"a":"x \"}\" {","k" : {"b":[1,{"c":"}"}]},"z":1}' 'k'
    $t | Should Be '{"b":[1,{"c":"}"}]}'
  }
  It 'bỏ qua lần xuất hiện không phải khóa' {
    Get-JsonObjectText '{"a":["k"],"k":{"x":1}}' 'k' | Should Be '{"x":1}'
  }
  It 'không có khóa hoặc không phải object ⇒ null' {
    Get-JsonObjectText '{"a":1}' 'k' | Should BeNullOrEmpty
    Get-JsonObjectText '{"k":1}' 'k' | Should BeNullOrEmpty
    Get-JsonObjectText '{"k":{"a":1' 'k' | Should BeNullOrEmpty
  }
}

Describe 'ConvertFrom-ClaudeConfigText' {
  It 'đọc fixture: chỉ hai cửa sổ + giờ đo' {
    $r = ConvertFrom-ClaudeConfigText ([IO.File]::ReadAllText("$fx\claude.json"))
    $r.FiveHour | Should Be 5
    $r.Week | Should Be 1
    $r.FiveHourResetsAt.ToUniversalTime().ToString('s') | Should Be '2026-11-07T12:40:00'
    $r.WeekResetsAt.ToUniversalTime().ToString('s') | Should Be '2026-11-14T04:00:00'
    $r.FetchedAt.ToUniversalTime().ToString('s') | Should Be '2026-11-07T10:05:21'
    @($r.Keys | Sort-Object) -join ',' | Should Be 'FetchedAt,FiveHour,FiveHourResetsAt,Week,WeekResetsAt'
  }
  It 'resets_at null vẫn nhận số' {
    $r = ConvertFrom-ClaudeConfigText '{"cachedUsageUtilization":{"fetchedAtMs":1794045921071,"utilization":{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":3}}}}'
    $r.FiveHour | Should Be 0
    $r.FiveHourResetsAt | Should BeNullOrEmpty
  }
  It 'accepts one valid window, rejects missing fetch time or empty data' {
    (ConvertFrom-ClaudeConfigText '{"cachedUsageUtilization":{"fetchedAtMs":1,"utilization":{"five_hour":{"utilization":1}}}}').FiveHour | Should Be 1
    ConvertFrom-ClaudeConfigText '{"cachedUsageUtilization":{"utilization":{"five_hour":{"utilization":1},"seven_day":{"utilization":1}}}}' | Should BeNullOrEmpty
    (ConvertFrom-ClaudeConfigText '{"cachedUsageUtilization":{"fetchedAtMs":1,"utilization":{"five_hour":{"utilization":"1"},"seven_day":{"utilization":1}}}}').Week | Should Be 1
    ConvertFrom-ClaudeConfigText '' | Should BeNullOrEmpty
    ConvertFrom-ClaudeConfigText '{"a":1}' | Should BeNullOrEmpty
  }
}

Describe 'ConvertFrom-ClaudeResetText' {
  $now = [DateTime]::SpecifyKind((New-Object DateTime 2026, 11, 7, 12, 0, 0), 'Local')
  It 'chỉ giờ: hôm nay hoặc ngày mai' {
    (ConvertFrom-ClaudeResetText '7:39pm' $now).ToString('yyyy-MM-dd HH:mm') | Should Be '2026-11-07 19:39'
    (ConvertFrom-ClaudeResetText '9am' $now).ToString('yyyy-MM-dd HH:mm') | Should Be '2026-11-08 09:00'
    (ConvertFrom-ClaudeResetText '12am' $now).ToString('yyyy-MM-dd HH:mm') | Should Be '2026-11-08 00:00'
    (ConvertFrom-ClaudeResetText '19:05' $now).ToString('yyyy-MM-dd HH:mm') | Should Be '2026-11-07 19:05'
  }
  It 'có ngày, sang năm khi đã qua' {
    (ConvertFrom-ClaudeResetText 'Nov 14, 10:59am' $now).ToString('yyyy-MM-dd HH:mm') | Should Be '2026-11-14 10:59'
    (ConvertFrom-ClaudeResetText 'Jan 2 at 12pm' $now).ToString('yyyy-MM-dd HH:mm') | Should Be '2027-01-02 12:00'
  }
  It 'lạ ⇒ null' {
    ConvertFrom-ClaudeResetText 'soon' $now | Should BeNullOrEmpty
    ConvertFrom-ClaudeResetText '13pm' $now | Should BeNullOrEmpty
    ConvertFrom-ClaudeResetText 'Foo 3, 1pm' $now | Should BeNullOrEmpty
    ConvertFrom-ClaudeResetText 'Feb 30, 1pm' $now | Should BeNullOrEmpty
  }
}

Describe 'ConvertFrom-ClaudeUsageReply' {
  $now = [DateTime]::SpecifyKind((New-Object DateTime 2026, 11, 7, 12, 0, 0), 'Local')
  $lines = [IO.File]::ReadAllLines("$fx\claude-usage.json")
  It 'đọc fixture' {
    $r = ConvertFrom-ClaudeUsageReply $lines $now
    $r.FiveHour | Should Be 10
    $r.Week | Should Be 1
    $r.FiveHourResetsAt.ToString('yyyy-MM-dd HH:mm') | Should Be '2026-11-07 19:39'
    $r.WeekResetsAt.ToString('yyyy-MM-dd HH:mm') | Should Be '2026-11-14 10:59'
  }
  It 'num_turns khác 0 hoặc is_error ⇒ null' {
    ConvertFrom-ClaudeUsageReply @(($lines -join '') -replace '"num_turns":0', '"num_turns":1') $now | Should BeNullOrEmpty
    ConvertFrom-ClaudeUsageReply @(($lines -join '') -replace '"is_error":false', '"is_error":true') $now | Should BeNullOrEmpty
    ConvertFrom-ClaudeUsageReply @(($lines -join '') -replace '"num_turns":0,', '') $now | Should BeNullOrEmpty
    ConvertFrom-ClaudeUsageReply @('not json') $now | Should BeNullOrEmpty
  }
  It 'thiếu giờ reset vẫn nhận số; nhãn trùng ⇒ null' {
    $r = ConvertFrom-ClaudeUsageText "Current session: 0% used`nCurrent week (all models): 7% used" $now
    $r.FiveHour | Should Be 0
    $r.Week | Should Be 7
    $r.FiveHourResetsAt | Should BeNullOrEmpty
    ConvertFrom-ClaudeUsageText "Current session: 1% used`nCurrent session: 2% used`nCurrent week (all models): 7% used" $now | Should BeNullOrEmpty
  }
}

Describe 'Codex JSON-RPC' {
  It 'trả lời initialize bằng initialized + rateLimits/read' {
    $s = Get-CodexStep '{"id":1,"result":{}}'
    $s.Done | Should Be $false
    @($s.Write).Count | Should Be 2
    $s.Write[1] | Should Be '{"method":"account/rateLimits/read","id":2}'
  }
  It 'bỏ qua thông báo/request server, xong ở id 2, initialize lỗi thì dừng' {
    @((Get-CodexStep '{"method":"x","id":1,"params":{}}').Write).Count | Should Be 0
    (Get-CodexStep 'rác').Done | Should Be $false
    (Get-CodexStep '{"id":2,"result":{}}').Done | Should Be $true
    (Get-CodexStep '{"id":1,"error":{"message":"x"}}').Done | Should Be $true
  }
  It 'hello là initialize id 1' {
    (Get-CodexHello | ConvertFrom-Json).method | Should Be 'initialize'
  }
  It 'đọc fixture, chọn cửa sổ theo windowDurationMins' {
    $r = ConvertFrom-CodexReply ([IO.File]::ReadAllLines("$fx\codex-reply.jsonl"))
    $r.FiveHour | Should Be 42
    $r.Week | Should Be 2
    $r.FiveHourResetsAt.ToUniversalTime().ToString('s') | Should Be '2026-11-07T14:25:34'
    $r.WeekResetsAt.ToUniversalTime().ToString('s') | Should Be '2026-11-14T02:48:14'
  }
  It 'rejects errors and accepts a single valid Codex window' {
    ConvertFrom-CodexReply @('{"id":2,"error":{"message":"x"}}') | Should BeNullOrEmpty
    (ConvertFrom-CodexReply @('{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300}}}}')).FiveHour | Should Be 1
    (ConvertFrom-CodexReply @('{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300},"secondary":{"usedPercent":null,"windowDurationMins":10080}}}}')).Week | Should BeNullOrEmpty
    ConvertFrom-CodexReply @('{"id":1,"result":{}}') | Should BeNullOrEmpty
  }
}

Describe 'Get-ClaudeConfigPath' {
  It 'ưu tiên CLAUDE_CONFIG_DIR' {
    Get-ClaudeConfigPath 'D:\cfg' 'C:\home' | Should Be 'D:\cfg\.claude.json'
    Get-ClaudeConfigPath $null 'C:\home' | Should Be 'C:\home\.claude.json'
  }
}

Describe 'Get-AgentQuotas' {
  $cacheText = [IO.File]::ReadAllText("$fx\claude.json")
  $usageLines = [IO.File]::ReadAllLines("$fx\claude-usage.json")
  $codexLines = [IO.File]::ReadAllLines("$fx\codex-reply.jsonl")
  # Giờ đo của fixture: 2026-11-07T10:05:21Z.
  $fetched = ConvertFrom-QuotaEpoch ([long]1794045921071) -Milliseconds

  It 'cache mới: không chạy claude; codex qua app-server; đúng hợp đồng' {
    $fetched = $fetched; $cacheText = $cacheText; $usageLines = $usageLines; $codexLines = $codexLines  # bản local để GetNewClosure bắt được
    $ops = New-TestOps @{
      Now      = { $fetched.AddMinutes(5) }.GetNewClosure()
      ReadText = { param($p) if ($p -eq 'C:\home\.claude.json') { $cacheText } }.GetNewClosure()
      Find     = { param($n) if ($n -eq 'codex') { 'C:\bin\codex.exe' } }
      Run      = { param($i, $s, $o, $t)
        if ($i.File -ne 'C:\bin\codex.exe' -or $i.ArgList[0] -ne 'app-server' -or -not $o) { throw 'sai lệnh' }
        @{ TimedOut = $false; ExitCode = $null; Lines = $codexLines } }.GetNewClosure()
    }
    $q = Get-AgentQuotas -Ops $ops
    $q.GetType().IsArray | Should Be $true
    $q.Count | Should Be 2
    $q[0].Provider | Should Be 'claude'
    $q[0].Name | Should Be 'Claude Code'
    $q[0].Ok | Should Be $true
    $q[0].Error | Should BeNullOrEmpty
    $q[0].FiveHourUsed | Should Be 5
    $q[0].WeekUsed | Should Be 1
    $q[0].FiveHourUsed.GetType().Name | Should Be 'Int32'
    $q[0].FiveHourResetsAt.GetType().Name | Should Be 'DateTime'
    $q[0].FetchedAt | Should Be $fetched
    $q[1].Provider | Should Be 'codex'
    $q[1].Name | Should Be 'Codex'
    $q[1].Ok | Should Be $true
    $q[1].FiveHourUsed | Should Be 42
    $q[1].WeekUsed | Should Be 2
    $q[1].FetchedAt | Should Be $fetched.AddMinutes(5)
    @($q[0].PSObject.Properties.Name) -join ',' | Should Be 'Provider,Name,Ok,Error,FiveHourUsed,WeekUsed,FiveHourResetsAt,WeekResetsAt,FetchedAt'
  }

  It 'CLAUDE_CONFIG_DIR được dùng' {
    $fetched = $fetched; $cacheText = $cacheText; $usageLines = $usageLines; $codexLines = $codexLines  # bản local để GetNewClosure bắt được
    $ops = New-TestOps @{
      Now      = { $fetched }.GetNewClosure()
      GetEnv   = { param($n) if ($n -eq 'CLAUDE_CONFIG_DIR') { 'D:\cfg' } }
      ReadText = { param($p) if ($p -eq 'D:\cfg\.claude.json') { $cacheText } }.GetNewClosure()
    }
    (Get-AgentQuotas -Ops $ops)[0].Ok | Should Be $true
  }

  It 'cache cũ: print /usage không ghi cache thì giữ nguyên số và FetchedAt' {
    $fetched = $fetched; $cacheText = $cacheText; $usageLines = $usageLines; $codexLines = $codexLines  # bản local để GetNewClosure bắt được
    $now = $fetched.AddMinutes(30)
    $ops = New-TestOps @{
      Now      = { $now }.GetNewClosure()
      ReadText = { param($p) $cacheText }.GetNewClosure()
      Find     = { param($n) if ($n -eq 'claude') { 'C:\bin\claude.exe' } }
      Run      = { param($i, $s, $o, $t)
        if (($i.ArgList -join ' ') -ne '-p /usage --output-format json --no-session-persistence' -or $o) { throw 'sai lệnh' }
        @{ TimedOut = $false; ExitCode = 0; Lines = $usageLines } }.GetNewClosure()
    }
    $q = Get-AgentQuotas -Ops $ops
    $q[0].Ok | Should Be $true
    $q[0].FiveHourUsed | Should Be 5
    $q[0].FetchedAt | Should Be $fetched
    $q[1].Ok | Should Be $false
    $q[1].Error | Should Be 'chưa cài'
  }

  It 'cache cũ ≤7 ngày + CLI lỗi ⇒ dùng cache cũ, FetchedAt = giờ cache' {
    $fetched = $fetched; $cacheText = $cacheText; $usageLines = $usageLines; $codexLines = $codexLines  # bản local để GetNewClosure bắt được
    $ops = New-TestOps @{
      Now      = { $fetched.AddHours(3) }.GetNewClosure()
      ReadText = { param($p) $cacheText }.GetNewClosure()
      Find     = { param($n) 'C:\bin\x.exe' }
      Run      = { param($i, $s, $o, $t) @{ TimedOut = $true; ExitCode = $null; Lines = @() } }
    }
    $q = Get-AgentQuotas -Ops $ops
    $q[0].Ok | Should Be $true
    $q[0].FetchedAt | Should Be $fetched
    $q[1].Ok | Should Be $false
    $q[1].Error | Should Be 'hết thời gian'
  }

  It 'cache quá 7 ngày + CLI hết giờ ⇒ lỗi' {
    $fetched = $fetched; $cacheText = $cacheText; $usageLines = $usageLines; $codexLines = $codexLines  # bản local để GetNewClosure bắt được
    $ops = New-TestOps @{
      Now      = { $fetched.AddDays(7).AddSeconds(1) }.GetNewClosure()
      ReadText = { param($p) $cacheText }.GetNewClosure()
      Find     = { param($n) 'C:\bin\x.exe' }
      Run      = { param($i, $s, $o, $t) @{ TimedOut = $true; ExitCode = $null; Lines = @() } }
    }
    $q = Get-AgentQuotas -Ops $ops
    $q[0].Ok | Should Be $false
    $q[0].Error | Should Be 'hết thời gian'
    $q[0].FiveHourUsed | Should BeNullOrEmpty
    $q[0].FiveHourResetsAt | Should BeNullOrEmpty
  }

  It 'không cache, không CLI ⇒ chưa cài' {
    $fetched = $fetched; $cacheText = $cacheText; $usageLines = $usageLines; $codexLines = $codexLines  # bản local để GetNewClosure bắt được
    $q = Get-AgentQuotas -Ops (New-TestOps)
    $q[0].Error | Should Be 'chưa cài'
    $q[1].Error | Should Be 'chưa cài'
  }

  It 'phản hồi rác ⇒ không đọc được' {
    $fetched = $fetched; $cacheText = $cacheText; $usageLines = $usageLines; $codexLines = $codexLines  # bản local để GetNewClosure bắt được
    $ops = New-TestOps @{
      Find = { param($n) 'C:\bin\x.exe' }
      Run  = { param($i, $s, $o, $t) @{ TimedOut = $false; ExitCode = 0; Lines = @('rác') } }
    }
    $q = Get-AgentQuotas -Ops $ops
    $q[0].Error | Should Be 'không đọc được'
    $q[1].Error | Should Be 'không đọc được'
  }

  It 'thao tác ngoài ném lỗi ⇒ không ném ra ngoài' {
    $fetched = $fetched; $cacheText = $cacheText; $usageLines = $usageLines; $codexLines = $codexLines  # bản local để GetNewClosure bắt được
    $ops = New-TestOps @{ ReadText = { param($p) throw 'x' }; Find = { param($n) throw 'y' } }
    $q = Get-AgentQuotas -Ops $ops
    $q.Count | Should Be 2
    $q[0].Ok | Should Be $false
    $q[1].Ok | Should Be $false
    $q[0].Error | Should Be 'không đọc được'
  }

  It 'pipeline nhận từng quota (không unary comma), gán biến vẫn ra 2 phần tử' {
    $ops = New-TestOps
    (Get-AgentQuotas -Ops $ops | ForEach-Object { $_.Provider }) -join ',' | Should Be 'claude,codex'
    @(Get-AgentQuotas -Ops $ops).Count | Should Be 2
    @(Get-AgentQuotas -Ops $ops | Where-Object { $_.Provider -eq 'codex' }).Count | Should Be 1
  }
}

Describe 'Codex qua Invoke-AgentProcess thật (app-server giả)' {
  # Lỗi e2e: console ở UTF-8 (chcp 65001) ⇒ Process.Start của .NET Framework ghi BOM lên stdin trước dòng initialize,
  # codex bỏ dòng đó ⇒ 'hết thời gian'. Fixture giả cũng bỏ dòng có BOM như codex thật.
  $fake = Join-Path $fx 'child-echo.ps1'
  $cwd = Join-Path ([IO.Path]::GetTempPath()) 'agent-view-quota-tests'

  It 'console UTF-8 có BOM: initialize ⇒ notification có method ⇒ reply id=2 đọc đúng số' {
    $fake = $fake; $cwd = $cwd; $invoke = Get-Command Invoke-AgentProcess  # closure không thấy hàm của script test
    $saved = [Console]::InputEncoding
    try { [Console]::InputEncoding = New-Object System.Text.UTF8Encoding $true }
    catch { Set-TestInconclusive 'không có console để đặt InputEncoding'; return }
    try {
      $ops = New-TestOps @{
        Find = { param($n) if ($n -eq 'codex') { $fake } }.GetNewClosure()
        Run  = { param($i, $s, $o, $t) & $invoke -Invocation $i -Send $s -OnLine $o -Cwd $cwd -TimeoutMs 20000 }.GetNewClosure()
      }
      $clock = [Diagnostics.Stopwatch]::StartNew()
      $q = Get-AgentQuotas -Ops $ops
      $clock.Stop()
      [Console]::InputEncoding.GetPreamble().Length | Should Be 3  # trả lại encoding cũ sau Process.Start
    }
    finally { try { [Console]::InputEncoding = $saved } catch {} }
    $q[1].Error | Should BeNullOrEmpty
    $q[1].Ok | Should Be $true
    $q[1].FiveHourUsed | Should Be 7
    $q[1].WeekUsed | Should Be 63
    $q[1].FiveHourResetsAt.ToUniversalTime().ToString('s') | Should Be '2026-11-07T14:25:34'
    $clock.Elapsed.TotalSeconds | Should BeLessThan 15
  }
}

Describe 'Optional quota windows across all sources' {
  It 'reads the sanitized weekly-only cache fixture' {
    $data=ConvertFrom-ClaudeConfigText ([IO.File]::ReadAllText("$fx/claude-week-only.json"))
    $data.FiveHour | Should BeNullOrEmpty
    $data.Week | Should Be 24
  }
  It 'preserves nulls and accepts one or both windows through real row normalization' {
    . "$PSScriptRoot/../src/Format.ps1"
    foreach ($mode in 'week','five','both','none') {
      $u=@{}; $limits=@{}; $lines=@()
      if ($mode -in @('five','both')) { $u.five_hour=@{utilization=0}; $limits.primary=@{usedPercent=0;windowDurationMins=300}; $lines+='Current session: 0% used' }
      if ($mode -in @('week','both')) { $u.seven_day=@{utilization=42}; $limits.secondary=@{usedPercent=42;windowDurationMins=10080}; $lines+='Current week (all models): 42% used' }
      $cache=@{cachedUsageUtilization=@{fetchedAtMs=1794045921071;utilization=$u}} | ConvertTo-Json -Depth 8 -Compress
      $reply=@{id=2;result=@{rateLimits=$limits}} | ConvertTo-Json -Depth 8 -Compress
      $usage=@{result=($lines -join "`n");is_error=$false;num_turns=0} | ConvertTo-Json -Compress
      foreach ($data in @((ConvertFrom-ClaudeConfigText $cache),(ConvertFrom-ClaudeUsageReply @($usage) (Get-Date)),(ConvertFrom-CodexReply @($reply)))) {
        $rows=@(ConvertTo-QuotaRows (New-AgentQuota 'test' 'Test' $data $null (Get-Date)))
        $rows.Count | Should Be 1
        $rows[0].Ok | Should Be ($mode -ne 'none')
        if ($mode -in @('week','none')) { $rows[0].FiveHourUsed | Should BeNullOrEmpty; $rows[0].FiveHourResetsAt | Should BeNullOrEmpty }
        else { $rows[0].FiveHourUsed | Should Be 0 }
        if ($mode -in @('five','none')) { $rows[0].WeekUsed | Should BeNullOrEmpty; $rows[0].WeekResetsAt | Should BeNullOrEmpty }
        else { $rows[0].WeekUsed | Should Be 42 }
      }
    }
  }
  It 'treats null objects and null utilization as absent, ignores is_active' {
    foreach ($missing in 'null','{}','{"utilization":null,"resets_at":"2026-11-08T00:00:00Z"}') {
      $r=ConvertFrom-ClaudeConfigText ('{"cachedUsageUtilization":{"fetchedAtMs":1,"utilization":{"five_hour":'+$missing+',"seven_day":{"utilization":4},"limits":[{"kind":"session","percent":99,"is_active":false}]}}}')
      $r.FiveHour | Should BeNullOrEmpty
      $r.FiveHourResetsAt | Should BeNullOrEmpty
      $r.Week | Should Be 4
    }
  }
}

Describe 'Claude stale cache and fallback retry' {
  $fetched = ConvertFrom-QuotaEpoch ([long]1794045921071) -Milliseconds
  $cacheText = [IO.File]::ReadAllText("$fx\claude.json")

  It 'keeps cache through exactly seven days, clears elapsed resets, preserves fetched time' {
    $clock = @{ Now = $fetched.AddDays(7) }
    $text = $cacheText
    $ops = New-TestOps @{
      Now = { $clock.Now }.GetNewClosure()
      ReadText = { param($p) $text }.GetNewClosure()
    }
    $q = Get-ClaudeQuota $ops
    $q.Ok | Should Be $true
    $q.FiveHourUsed | Should Be 0
    $q.FiveHourResetsAt | Should BeNullOrEmpty
    $q.FetchedAt | Should Be $fetched
    $clock.Now = $clock.Now.AddMilliseconds(1)
    (Get-ClaudeQuota $ops).Ok | Should Be $false
  }

  It 'resets only elapsed present windows, including a fresh cache at the boundary' {
    $at = Get-Date
    $cache = @{ FiveHour=53; Week=12; FiveHourResetsAt=$at; WeekResetsAt=$at.AddDays(1); FetchedAt=$at.AddMinutes(-1) }
    $r = Reset-ClaudeCachedWindows $cache $at
    $r.FiveHour | Should Be 0
    $r.FiveHourResetsAt | Should BeNullOrEmpty
    $r.Week | Should Be 12
    $r.WeekResetsAt | Should Be $at.AddDays(1)
    $r.FetchedAt | Should Be $cache.FetchedAt
    $cache.FiveHour | Should Be 53
    $cache.FiveHour=$null; $cache.FiveHourResetsAt=$null
    $r = Reset-ClaudeCachedWindows $cache $at.AddDays(2)
    $r.FiveHour | Should BeNullOrEmpty
    $r.Week | Should Be 0
    $r.WeekResetsAt | Should BeNullOrEmpty
  }

  It 'fresh cache applies an elapsed reset without invoking the CLI' {
    $text = $cacheText; $at = $fetched.AddMinutes(5)
    $data = ConvertFrom-ClaudeConfigText $text
    $data.FiveHourResetsAt = $at.AddSeconds(-1)
    $json = @{cachedUsageUtilization=@{fetchedAtMs=1794045921071;utilization=@{
      five_hour=@{utilization=53;resets_at=$data.FiveHourResetsAt.ToString('o')}
      seven_day=@{utilization=12;resets_at=$at.AddDays(1).ToString('o')}
    }}} | ConvertTo-Json -Depth 6
    $ops=New-TestOps @{
      Now={ $at }.GetNewClosure()
      ReadText={param($p) $json}.GetNewClosure()
      Find={throw 'must not find CLI'}
    }
    $q=Get-ClaudeQuota $ops
    $q.Ok | Should Be $true
    $q.FiveHourUsed | Should Be 0
    $q.WeekUsed | Should Be 12
    $q.FetchedAt | Should Be $fetched
  }

  It 'ignores usage text and retries cache refresh only after five minutes' {
    $clock=@{Now=$fetched.AddHours(1);Calls=0}
    $text=$cacheText
    $ops=New-TestOps @{
      Now={ $clock.Now }.GetNewClosure()
      ReadText={param($p) $text}.GetNewClosure()
      Find={param($n) 'C:\fake\claude.exe'}
      Run={param($i,$s,$o,$t) $clock.Calls++; @{ExitCode=0;TimedOut=$false;Lines=@('{"num_turns":0,"is_error":false,"result":"Total cost: $0.00; API time: 0s"}')}}.GetNewClosure()
    }
    (Get-ClaudeQuota $ops).FetchedAt | Should Be $fetched
    $clock.Now=$clock.Now.AddMinutes(4)
    (Get-ClaudeQuota $ops).Ok | Should Be $true
    $clock.Calls | Should Be 1
    $clock.Now=$clock.Now.AddMinutes(1)
    (Get-ClaudeQuota $ops).FetchedAt | Should Be $fetched
    $clock.Calls | Should Be 2
  }

  It 'throttles timeouts and never treats legacy usage text as refreshed cache' {
    $clock=@{Now=$fetched;Calls=0}
    $lines=[IO.File]::ReadAllLines("$fx\claude-usage.json")
    $ops=New-TestOps @{
      Now={ $clock.Now }.GetNewClosure()
      Find={param($n) 'C:\fake\claude.exe'}
      Run={param($i,$s,$o,$t)
        $clock.Calls++
        if($clock.Calls -eq 1) {return @{TimedOut=$true}}
        return @{ExitCode=0;TimedOut=$false;Lines=$lines}
      }.GetNewClosure()
    }
    (Get-ClaudeQuota $ops).Error | Should Be 'hết thời gian'
    (Get-ClaudeQuota $ops).Error | Should Be 'hết thời gian'
    $clock.Calls | Should Be 1
    $clock.Now=$clock.Now.AddMinutes(5)
    $q=Get-ClaudeQuota $ops
    $q.Ok | Should Be $false
    $q.FiveHourUsed | Should BeNullOrEmpty
    $ops.FallbackState.Count | Should Be 1
  }

  It 'shares the app fallback state across newly created refresh runspaces' {
    $path=Join-Path $here '..\src\Quota.ps1'
    $state=Get-ClaudeFallbackState
    $key='quota-test-'+[Guid]::NewGuid().ToString('N')
    $state[$key]='shared'
    try {
      foreach($i in 1..2) {
        $ps=[PowerShell]::Create()
        try {
          [void]$ps.AddScript({param($path,$key) . $path; (Get-ClaudeFallbackState)[$key]}).AddArgument($path).AddArgument($key)
          @($ps.Invoke())[0] | Should Be 'shared'
          $ps.HadErrors | Should Be $false
        } finally { $ps.Dispose() }
      }
    } finally { $state.Remove($key) }
  }
}
Describe 'Claude print refresh reads cache again' {
  $fetched = ConvertFrom-QuotaEpoch ([long]1794045921071) -Milliseconds
  $text = [IO.File]::ReadAllText("$fx\claude.json")
  $stats = '{"num_turns":0,"is_error":false,"result":"Total cost: $0.00; API time: 0s"}'

  It 'refreshes a cache older than five minutes and uses the new cache timestamp and numbers' {
    $clock=@{Now=$fetched.AddMinutes(6);Reads=0;Calls=0}
    $before=$text
    $after=$text.Replace('1794045921071','1794046221071').Replace('"utilization": 5,','"utilization": 27,')
    $reply=$stats
    $ops=New-TestOps @{
      Now={$clock.Now}.GetNewClosure()
      ReadText={param($p) $clock.Reads++; if($clock.Calls -gt 0){$after}else{$before}}.GetNewClosure()
      Find={param($n) 'C:\fake\claude.exe'}
      Run={param($i,$s,$o,$t) $clock.Calls++; @{ExitCode=0;TimedOut=$false;Lines=@($reply)}}.GetNewClosure()
    }
    $q=Get-ClaudeQuota $ops
    $q.Ok | Should Be $true
    $q.FiveHourUsed | Should Be 27
    $q.FetchedAt | Should Be $fetched.AddMinutes(5)
    $q.FetchedAt | Should Not Be $clock.Now
    $clock.Reads | Should Be 2
    (Get-ClaudeQuota $ops).FiveHourUsed | Should Be 27
    $clock.Calls | Should Be 1
  }

  It 'does not invoke the CLI at exactly five minutes but does just after the boundary' {
    $clock=@{Now=$fetched.AddMinutes(5);Calls=0}
    $before=$text; $reply=$stats
    $ops=New-TestOps @{
      Now={$clock.Now}.GetNewClosure()
      ReadText={param($p) $before}.GetNewClosure()
      Find={param($n) 'C:\fake\claude.exe'}
      Run={param($i,$s,$o,$t) $clock.Calls++; @{ExitCode=0;TimedOut=$false;Lines=@($reply)}}.GetNewClosure()
    }
    (Get-ClaudeQuota $ops).Ok | Should Be $true
    $clock.Calls | Should Be 0
    $clock.Now=$clock.Now.AddMilliseconds(1)
    (Get-ClaudeQuota $ops).Ok | Should Be $true
    $clock.Calls | Should Be 1
  }

  It 'does not read new cache after model turns, errors, malformed output or invalid metadata types' {
    foreach($reply in @(
      '{"num_turns":1,"is_error":false,"result":"Current session: 99% used"}',
      '{"num_turns":0,"is_error":true,"result":""}',
      '{"num_turns":"0","is_error":false,"result":""}',
      '{"num_turns":false,"is_error":false,"result":""}',
      '{"num_turns":0,"is_error":"false","result":""}',
      '{"is_error":false,"result":""}',
      '{"num_turns":0,"result":""}',
      'invalid json'
    )) {
      $clock=@{Reads=0}
      $before=$text; $at=$fetched.AddMinutes(6)
      $ops=New-TestOps @{
        Now={$at}.GetNewClosure()
        ReadText={param($p) $clock.Reads++; $before}.GetNewClosure()
        Find={param($n) 'C:\fake\claude.exe'}
        Run={param($i,$s,$o,$t) @{ExitCode=0;TimedOut=$false;Lines=@($reply)}}.GetNewClosure()
      }
      $q=Get-ClaudeQuota $ops
      $q.FetchedAt | Should Be $fetched
      $q.FiveHourUsed | Should Be 5
      $clock.Reads | Should Be 1
      $ops.FallbackState.Count | Should Be 1
    }
  }

  It 'keeps the old cache when reread fails, is corrupt, or has an older timestamp' {
    foreach($after in @($null,'broken',$text.Replace('1794045921071','1794045920071'),'throw')) {
      $clock=@{Calls=0}
      $before=$text; $at=$fetched.AddMinutes(6); $reply=$stats
      $ops=New-TestOps @{
        Now={$at}.GetNewClosure()
        ReadText={param($p)
          if($clock.Calls -eq 0){return $before}
          if($after -eq 'throw'){throw 'reread failed'}
          return $after
        }.GetNewClosure()
        Find={param($n) 'C:\fake\claude.exe'}
        Run={param($i,$s,$o,$t) $clock.Calls++; @{ExitCode=0;TimedOut=$false;Lines=@($reply)}}.GetNewClosure()
      }
      $q=Get-ClaudeQuota $ops
      $q.Ok | Should Be $true
      $q.FetchedAt | Should Be $fetched
      $q.FiveHourUsed | Should Be 5
    }
  }

  It 'accepts a cache created by a successful print call when no cache existed' {
    $clock=@{Calls=0}
    $after=$text; $at=$fetched.AddMinutes(1); $reply=$stats
    $ops=New-TestOps @{
      Now={$at}.GetNewClosure()
      ReadText={param($p) if($clock.Calls -gt 0){$after}}.GetNewClosure()
      Find={param($n) 'C:\fake\claude.exe'}
      Run={param($i,$s,$o,$t) $clock.Calls++; @{ExitCode=0;TimedOut=$false;Lines=@($reply)}}.GetNewClosure()
    }
    $q=Get-ClaudeQuota $ops
    $q.Ok | Should Be $true
    $q.FetchedAt | Should Be $fetched
  }

  It 'throttles all outcomes including successful calls, nonzero exit, timeout and thrown exceptions' {
    foreach($mode in 'success','exit','timeout','throw') {
      $clock=@{Now=$fetched.AddMinutes(6);Calls=0;Reads=0}
      $before=$text; $reply=$stats
      $ops=New-TestOps @{
        Now={$clock.Now}.GetNewClosure()
        ReadText={param($p) $clock.Reads++; $before}.GetNewClosure()
        Find={param($n) 'C:\fake\claude.exe'}
        Run={param($i,$s,$o,$t)
          $clock.Calls++
          if($mode -eq 'throw'){throw 'CLI failed'}
          @{ExitCode=$(if($mode -eq 'exit'){1}else{0});TimedOut=($mode -eq 'timeout');Lines=@($reply)}
        }.GetNewClosure()
      }
      (Get-ClaudeQuota $ops).Ok | Should Be $true
      $clock.Now=$clock.Now.AddMinutes(5).AddMilliseconds(-1)
      (Get-ClaudeQuota $ops).Ok | Should Be $true
      $clock.Calls | Should Be 1
      $clock.Now=$clock.Now.AddMilliseconds(1)
      (Get-ClaudeQuota $ops).Ok | Should Be $true
      $clock.Calls | Should Be 2
      if($mode -ne 'success'){$clock.Reads | Should Be 3}
    }
  }

  It 'reserves the retry before starting the CLI so an overlapping refresh cannot invoke it' {
    $clock=@{Now=$fetched.AddMinutes(6);Calls=0}
    $before=$text; $reply=$stats
    $ops=New-TestOps @{
      Now={$clock.Now}.GetNewClosure()
      ReadText={param($p) $before}.GetNewClosure()
      Find={param($n) 'C:\fake\claude.exe'}
    }
    $invoke=Get-Command Get-ClaudeQuota
    $ops.Run={param($i,$s,$o,$t)
      $clock.Calls++
      if($clock.Calls -gt 1){throw 'overlapping CLI invocation'}
      $null=& $invoke $ops
      @{ExitCode=0;TimedOut=$false;Lines=@($reply)}
    }.GetNewClosure()
    (Get-ClaudeQuota $ops).Ok | Should Be $true
    $clock.Calls | Should Be 1
  }
}
