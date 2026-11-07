# Chạy CLI con cho agent-view: timeout, kill cả cây, stdout UTF-8. Viết cho Windows PowerShell 5.1.
# Dot-source không có side effect: chỉ định nghĩa hàm.

# Quote một đối số theo quy tắc CommandLineToArgvW / MSVCRT (PS 5.1 không có ProcessStartInfo.ArgumentList).
function ConvertTo-ProcessArgument([string]$Value) {
  if ($null -eq $Value) { $Value = '' }
  if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
  $sb = New-Object System.Text.StringBuilder
  $null = $sb.Append('"')
  $slashes = 0
  foreach ($ch in $Value.ToCharArray()) {
    if ($ch -eq '\') { $slashes++; continue }
    if ($ch -eq '"') {
      $null = $sb.Append('\', 2 * $slashes + 1)
      $null = $sb.Append('"')
    }
    else {
      if ($slashes -gt 0) { $null = $sb.Append('\', $slashes) }
      $null = $sb.Append($ch)
    }
    $slashes = 0
  }
  if ($slashes -gt 0) { $null = $sb.Append('\', 2 * $slashes) }
  $null = $sb.Append('"')
  return $sb.ToString()
}

function Join-ProcessArguments([string[]]$ArgList) {
  return (@($ArgList) | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' '
}

# Dựng lệnh gọi CLI, thuần. Shim .ps1/.cmd/.bat chạy qua powershell.exe (5.1), không pwsh; .exe gọi thẳng.
function Get-AgentCliInvocation([string]$Source, [string[]]$CliArgs, [string]$Shell = 'powershell.exe') {
  $ext = [IO.Path]::GetExtension("$Source").ToLowerInvariant()
  if (@('.ps1', '.cmd', '.bat') -notcontains $ext) { return @{ File = $Source; ArgList = @($CliArgs) } }
  $call = "[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding `$false; `$OutputEncoding = [Console]::OutputEncoding; & '$($Source.Replace("'", "''"))'"
  foreach ($a in @($CliArgs)) { $call += " '$("$a".Replace("'", "''"))'" }
  $call += '; exit $LASTEXITCODE'
  return @{ File = $Shell; ArgList = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $call) }
}

# Biến môi trường của phiên agent/terminal đang chạy không được truyền xuống tiến trình con.
function Test-AgentInheritedEnvName([string]$Name) {
  return ($Name -match '^(CLAUDECODE|CLAUDE_PID)$' -or $Name -match '^(CLAUDE_CODE_|HC_)')
}

# Kill cả cây tiến trình. Không ném lỗi.
function Stop-AgentProcessTree($Process) {
  try {
    $null = & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $Process.Id 2>&1
  }
  catch {}
  try { if (-not $Process.HasExited) { $Process.Kill() } } catch {}
  try { $null = $Process.WaitForExit(2000) } catch {}
}

# .NET Framework: Process.Start tạo StandardInput bằng Console.InputEncoding với AutoFlush, nên ghi preamble NGAY lúc Start.
# Khi console đang ở UTF-8 (chcp 65001, vd pane terminal/agent) preamble đó là BOM EF BB BF đứng trước dòng đầu tiên
# ⇒ `codex app-server` báo "expected value at line 1 column 1", bỏ dòng initialize và không trả lời gì.
# Đổi tạm Console.InputEncoding sang UTF-8 không BOM quanh Process.Start rồi trả lại. Không có console ⇒ không đổi.
function Start-AgentProcessNoBom([System.Diagnostics.ProcessStartInfo]$StartInfo) {
  $saved = $null
  try {
    $cur = [Console]::InputEncoding
    if ($cur -and $cur.GetPreamble().Length -gt 0) {
      [Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false
      $saved = $cur
    }
  }
  catch { $saved = $null }
  try { return [Diagnostics.Process]::Start($StartInfo) }
  finally { if ($saved) { try { [Console]::InputEncoding = $saved } catch {} } }
}

# Chạy CLI trong $Cwd, đọc stdout bằng UTF-8, không quá $TimeoutMs, kill cả cây nếu còn chạy khi xong.
# $OnLine (nếu có) nhận từng dòng, trả @{ Write = @(...); Done = $bool }. Stdin đóng ngay khi không có $OnLine.
# Ra: @{ Started; TimedOut; Killed; ExitCode; Lines }. Không ném lỗi.
function Invoke-AgentProcess {
  param(
    [hashtable]$Invocation,
    [string[]]$Send = @(),
    [scriptblock]$OnLine = $null,
    [string]$Cwd,
    [int]$TimeoutMs = 12000
  )
  $res = @{ Started = $false; TimedOut = $false; Killed = $false; ExitCode = $null; Lines = @() }
  $p = $null
  $lines = New-Object 'System.Collections.Generic.List[string]'
  try {
    if ($Cwd) { $null = New-Item -ItemType Directory -Path $Cwd -Force -ErrorAction Stop }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Invocation.File
    $psi.Arguments = Join-ProcessArguments @($Invocation.ArgList)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($Cwd) { $psi.WorkingDirectory = $Cwd }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    foreach ($k in @($psi.EnvironmentVariables.Keys)) {
      if (Test-AgentInheritedEnvName $k) { $psi.EnvironmentVariables.Remove($k) }
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-AgentProcessNoBom $psi
    $res.Started = $true
    $null = $p.StandardError.ReadToEndAsync()  # xả stderr để không kẹt pipe; không dùng nội dung
    # .NET Framework không có StandardInputEncoding: tự ghi UTF-8 không BOM lên BaseStream.
    $stdin = New-Object System.IO.StreamWriter($p.StandardInput.BaseStream, $utf8)
    $stdin.AutoFlush = $true
    foreach ($l in @($Send)) { $stdin.WriteLine($l) }
    if (-not $OnLine) { $stdin.Close(); $stdin = $null }
    $read = $null; $done = $false
    while (-not $done) {
      $left = $TimeoutMs - [int]$clock.ElapsedMilliseconds
      if ($left -le 0) { $res.TimedOut = $true; break }
      if (-not $read) { $read = $p.StandardOutput.ReadLineAsync() }
      if (-not $read.Wait([math]::Min($left, 200))) { continue }
      $line = $read.Result; $read = $null
      if ($null -eq $line) { break }
      $lines.Add($line)
      if ($OnLine) {
        $step = & $OnLine $line
        if ($step) {
          if ($stdin) { foreach ($l in @($step.Write)) { if ($null -ne $l) { $stdin.WriteLine($l) } } }
          if ($step.Done) { $done = $true }
        }
      }
    }
    if (-not $done -and -not $res.TimedOut) {
      $left = $TimeoutMs - [int]$clock.ElapsedMilliseconds
      if ($left -le 0 -or -not $p.WaitForExit($left)) { $res.TimedOut = $true }
      else { $p.WaitForExit(); $res.ExitCode = $p.ExitCode }
    }
  }
  catch { }
  finally {
    if ($p) {
      try {
        if (-not $p.HasExited) { Stop-AgentProcessTree $p; $res.Killed = $true }
      }
      catch {}
      try { $p.Dispose() } catch {}
    }
  }
  $res.Lines = $lines.ToArray()
  return $res
}
