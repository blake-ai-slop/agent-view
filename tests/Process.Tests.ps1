# Pester 3.4: chạy bằng powershell.exe 5.1. Chạy tiến trình con thật (powershell.exe), không gọi CLI agent.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\src\Process.ps1')
$child = Join-Path $here 'fixtures\child-echo.ps1'
$cwd = Join-Path ([IO.Path]::GetTempPath()) 'agent-view-process-tests'

Describe 'ConvertTo-ProcessArgument' {
  It 'quote theo quy tắc CommandLineToArgvW' {
    ConvertTo-ProcessArgument 'abc' | Should Be 'abc'
    ConvertTo-ProcessArgument '' | Should Be '""'
    ConvertTo-ProcessArgument 'a b' | Should Be '"a b"'
    ConvertTo-ProcessArgument 'a"b' | Should Be '"a\"b"'
    ConvertTo-ProcessArgument 'C:\dir x\' | Should Be '"C:\dir x\\"'
    ConvertTo-ProcessArgument 'a\\"b' | Should Be '"a\\\\\"b"'
    ConvertTo-ProcessArgument 'C:\a\b' | Should Be 'C:\a\b'
  }
  It 'Join-ProcessArguments ghép bằng dấu cách' {
    Join-ProcessArguments @('-p', '/usage', 'a b') | Should Be '-p /usage "a b"'
  }
}

Describe 'Get-AgentCliInvocation' {
  It '.exe gọi thẳng' {
    $i = Get-AgentCliInvocation 'C:\bin\claude.exe' @('-p', '/usage')
    $i.File | Should Be 'C:\bin\claude.exe'
    $i.ArgList -join ' ' | Should Be '-p /usage'
  }
  It 'shim .ps1/.cmd chạy qua powershell.exe 5.1, quote đơn được escape' {
    $i = Get-AgentCliInvocation "C:\it's\codex.cmd" @('app-server', "o'k")
    $i.File | Should Be 'powershell.exe'
    $i.ArgList[-2] | Should Be '-Command'
    $i.ArgList[-1] | Should Match ([regex]::Escape("& 'C:\it''s\codex.cmd' 'app-server' 'o''k'; exit `$LASTEXITCODE"))
  }
}

Describe 'Test-AgentInheritedEnvName' {
  It 'nhận đúng biến của phiên agent/terminal' {
    Test-AgentInheritedEnvName 'CLAUDECODE' | Should Be $true
    Test-AgentInheritedEnvName 'claude_code_entrypoint' | Should Be $true
    Test-AgentInheritedEnvName 'HC_SCOPE' | Should Be $true
    Test-AgentInheritedEnvName 'CLAUDE_CONFIG_DIR' | Should Be $false
    Test-AgentInheritedEnvName 'PATH' | Should Be $false
  }
}

Describe 'Invoke-AgentProcess' {
  It 'đối số có dấu cách/quote, stdout UTF-8, exit code, stderr không làm kẹt' {
    $inv = Get-AgentCliInvocation $child @('args', 'a b', 'x"y', "it's", 'C:\p q\')
    $r = Invoke-AgentProcess -Invocation $inv -Cwd $cwd -TimeoutMs 30000
    $r.Started | Should Be $true
    $r.TimedOut | Should Be $false
    $r.ExitCode | Should Be 3
    $r.Lines[0] | Should Be 'ARG[a b]'
    $r.Lines[1] | Should Be 'ARG[x"y]'
    $r.Lines[2] | Should Be "ARG[it's]"
    $r.Lines[3] | Should Be 'ARG[C:\p q\]'
    $r.Lines[4] | Should Be ('UTF8:' + [string][char]0x1EBF + [char]0x0103)
  }

  It 'xóa CLAUDECODE / CLAUDE_CODE_* / HC_* khỏi tiến trình con, giữ biến khác' {
    $env:CLAUDECODE = '1'; $env:CLAUDE_CODE_TESTVAR = '1'; $env:HC_TESTVAR = '1'; $env:AGENTVIEW_KEEP = 'yes'
    try {
      $r = Invoke-AgentProcess -Invocation (Get-AgentCliInvocation $child @('env')) -Cwd $cwd -TimeoutMs 30000
    }
    finally {
      Remove-Item Env:CLAUDECODE, Env:CLAUDE_CODE_TESTVAR, Env:HC_TESTVAR, Env:AGENTVIEW_KEEP -ErrorAction SilentlyContinue
    }
    $r.Lines -join '|' | Should Be 'CLAUDECODE=|CLAUDE_CODE_TESTVAR=|HC_TESTVAR=|AGENTVIEW_KEEP=yes'
  }

  It 'hội thoại qua stdin bằng OnLine; Done thì kill tiến trình còn chạy' {
    $onLine = { param($line) if ($line -eq 'hello') { @{ Write = @('ping'); Done = $false } } elseif ($line -eq 'got:ping') { @{ Write = @(); Done = $true } } }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-AgentProcess -Invocation (Get-AgentCliInvocation $child @('chat')) -Send @('first') -OnLine $onLine -Cwd $cwd -TimeoutMs 30000
    $r.TimedOut | Should Be $false
    $r.Killed | Should Be $true
    $r.Lines -join '|' | Should Be 'hello|got:first|got:ping'
    $clock.Elapsed.TotalSeconds | Should BeLessThan 25
  }

  It 'quá hạn: TimedOut và kill cả cây (kể cả tiến trình cháu)' {
    $pidFile = Join-Path ([IO.Path]::GetTempPath()) ("agent-view-tree-{0}.txt" -f [guid]::NewGuid())
    try {
      $r = Invoke-AgentProcess -Invocation (Get-AgentCliInvocation $child @('tree', $pidFile)) -Cwd $cwd -TimeoutMs 8000
      $r.TimedOut | Should Be $true
      $r.Killed | Should Be $true
      $r.Lines -join '|' | Should Be 'started'
      $grand = [int][IO.File]::ReadAllText($pidFile)
      Start-Sleep -Milliseconds 500
      Get-Process -Id $grand -ErrorAction SilentlyContinue | Should BeNullOrEmpty
    }
    finally { Remove-Item $pidFile -ErrorAction SilentlyContinue }
  }

  It 'file không tồn tại: không ném lỗi' {
    $r = Invoke-AgentProcess -Invocation @{ File = 'C:\khong-co\x.exe'; ArgList = @() } -Cwd $cwd -TimeoutMs 2000
    $r.Started | Should Be $false
    $r.ExitCode | Should BeNullOrEmpty
    @($r.Lines).Count | Should Be 0
  }
}
