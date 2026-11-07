# Test child for Process.Tests.ps1 / Quota.Tests.ps1. Modes: args | env | chat | tree <pidfile> | app-server
param([string]$Mode)
$rest = @($args)
$utf8 = New-Object System.Text.UTF8Encoding $false
$out = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8)
$out.AutoFlush = $true
switch ($Mode) {
  'args' {
    foreach ($a in $rest) { $out.WriteLine("ARG[$a]") }
    $out.WriteLine('UTF8:' + [string][char]0x1EBF + [char]0x0103)
    [Console]::Error.WriteLine('noise on stderr')
    exit 3
  }
  'env' {
    foreach ($n in 'CLAUDECODE', 'CLAUDE_CODE_TESTVAR', 'HC_TESTVAR', 'AGENTVIEW_KEEP') {
      $out.WriteLine("$n=" + [Environment]::GetEnvironmentVariable($n))
    }
  }
  'chat' {
    $in = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)
    $out.WriteLine('hello')
    while ($true) {
      $l = $in.ReadLine()
      if ($null -eq $l) { break }
      $out.WriteLine("got:$l")
    }
    Start-Sleep -Seconds 60
  }
  'tree' {
    $child = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 60' -PassThru -WindowStyle Hidden
    [IO.File]::WriteAllText($rest[0], [string]$child.Id)
    $out.WriteLine('started')
    Start-Sleep -Seconds 60
  }
  'app-server' {
    # Giả `codex app-server`: JSON-RPC theo dòng. Như codex thật, dòng không parse được (vd có BOM U+FEFF ở đầu)
    # chỉ bị báo lỗi ra stderr và bỏ qua. Phát notification có method trước reply id=2.
    $in = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8, $false)
    while ($true) {
      $l = $in.ReadLine()
      if ($null -eq $l) { break }
      $msg = $null
      if ($l.Length -eq 0 -or $l[0] -ne [char]'{') { [Console]::Error.WriteLine('Failed to deserialize JSONRPCMessage: expected value at line 1 column 1'); continue }
      try { $msg = $l | ConvertFrom-Json -ErrorAction Stop } catch { [Console]::Error.WriteLine('Failed to deserialize JSONRPCMessage'); continue }
      switch ($msg.method) {
        'initialize' { $out.WriteLine('{"id":1,"result":{"userAgent":"fake/0"}}') }
        'initialized' { $out.WriteLine('{"method":"remoteControl/status/changed","params":{}}') }
        'account/rateLimits/read' {
          $out.WriteLine('{"method":"account/rateLimits/updated","id":2,"params":{}}')
          $out.WriteLine('{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":7,"windowDurationMins":300,"resetsAt":1794061534},"secondary":{"usedPercent":63,"windowDurationMins":10080,"resetsAt":1794624494}}}}')
        }
      }
    }
    Start-Sleep -Seconds 60
  }
}
