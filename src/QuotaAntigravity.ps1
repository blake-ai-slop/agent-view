Register-AgentViewStrings 'antigravity' @{
  en = @{
    not_installed = 'not installed'
    not_signed_in = 'sign in to Antigravity'
    api_key = 'account quota unavailable with GEMINI_API_KEY'
    timed_out = 'timed out'
  }
  vi = @{
    not_installed = 'chưa cài'
    not_signed_in = 'hãy đăng nhập Antigravity'
    api_key = 'không có quota tài khoản khi dùng GEMINI_API_KEY'
    timed_out = 'hết thời gian'
  }
}

function ConvertFrom-AntigravityGroups($Groups, [datetime]$FetchedAt) {
  if ($Groups -isnot [array]) { return }

  foreach ($group in $Groups) {
    $label = $group.name
    if ($label -isnot [string] -or -not $label.Trim() -or $group.buckets -isnot [array]) { continue }
    $data = @{ FiveHour = $null; Week = $null; FiveHourResetsAt = $null; WeekResetsAt = $null; FetchedAt = $FetchedAt }
    $key = $null
    foreach ($bucket in $group.buckets) {
      if ($bucket.window -isnot [string]) { continue }
      switch ($bucket.window) {
        '5h' { $window = 'FiveHour' }
        'weekly' { $window = 'Week' }
        default { $window = $null }
      }
      if (-not $window) { continue }
      $fraction = $bucket.remaining_fraction
      if ($fraction -isnot [int] -and $fraction -isnot [long] -and $fraction -isnot [double] -and $fraction -isnot [decimal]) { continue }
      if ($fraction -lt 0 -or $fraction -gt 1 -or [double]::IsNaN($fraction)) { continue }

      $reset = $null
      if ($window -ne 'FiveHour' -or $fraction -ne 1) { $reset = ConvertTo-QuotaLocalTime $bucket.reset_time }
      $data[$window] = [int][math]::Round((1 - $fraction) * 100)
      $data[$window + 'ResetsAt'] = $reset
      if (-not $key -and $bucket.id -is [string]) { $key = $bucket.id -replace '-(weekly|5h)$', '' }
    }
    if ($null -eq $data.FiveHour -and $null -eq $data.Week) { continue }

    switch -Regex ($key) {
      'argon' { $id = 'argon'; $label = 'Argon' }
      '^gemini$' { $id = 'gemini'; $label = 'Gemini' }
      '^3p$' { $id = '3p'; $label = 'Claude/GPT' }
      default { $id = ($label.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
    }
    if ($id) { @{ Provider = "antigravity-$id"; Group = $label; Data = $data } }
  }
}

function Get-AntigravityErrorKey([string]$Message) {
  if ($Message -match '\bGEMINI_API_KEY\b') { return 'antigravity.api_key' }
  if ($Message -match '\b(?:not (?:logged|signed) in|unauthenticated|(?:log\s*in|sign\s*in|authentication) (?:is )?required|please (?:log|sign)\s*in)\b') {
    return 'antigravity.not_signed_in'
  }
  return 'quota.cannot_read_quota'
}

function Get-AntigravityQuota([hashtable]$Ops, [switch]$Manual) {
  $ErrorActionPreference = 'Stop'
  $name = 'Antigravity'
  $errorKey = 'quota.cannot_read_quota'
  try {
    $now = & $Ops.Now
    $src = & $Ops.Find 'agy'
    if (-not $src) { return New-AgentQuota 'antigravity' $name $null (T 'antigravity.not_installed') $now }

    $gap = [TimeSpan]::FromMinutes(5)
    if ($Manual) { $gap = [TimeSpan]::FromSeconds(30) }
    $state = $Ops.AntigravityState
    $attempt = $false
    # Reserve the run before starting the CLI so overlapping runspaces share the same throttle.
    [Threading.Monitor]::Enter($state.SyncRoot)
    try {
      $entry = $state['Usage']
      if (-not $entry -or (-not $entry.InFlight -and $now -ge $entry.LastRun.Add($gap))) {
        $entry = @{ LastRun = $now; InFlight = $true; Good = $entry.Good; ErrorKey = $entry.ErrorKey }
        $state['Usage'] = $entry
        $attempt = $true
      }
    }
    finally { [Threading.Monitor]::Exit($state.SyncRoot) }

    if ($attempt) {
      $good = $entry.Good
      try {
        $inv = Get-AgentCliInvocation $src @('-p', '/usage', '--output-format', 'json')
        $result = & $Ops.Run $inv @() $null 15000
        $now = & $Ops.Now
        if ($result.TimedOut) { $errorKey = 'antigravity.timed_out' }
        else {
          $outputText = ($result.Lines -join [Environment]::NewLine).Trim()
          $msg = $null
          if ($outputText.StartsWith('{')) {
            $msg = try { ConvertFrom-Json -InputObject $outputText -ErrorAction Stop } catch { $null }
          }
          if ($null -ne $result.ExitCode -and $result.ExitCode -eq 0 -and
              $msg.status -is [string] -and $msg.status -ceq 'SUCCESS' -and
              $msg.num_turns -is [int] -and $msg.num_turns -eq 0 -and
              $msg.usage -is [pscustomobject] -and $msg.usage.total_tokens -is [int] -and $msg.usage.total_tokens -eq 0 -and
              $msg.command -is [pscustomobject] -and $msg.command.name -is [string] -and $msg.command.name -ceq 'usage') {
            $rows = @(ConvertFrom-AntigravityGroups $msg.command.data.groups $now)
            if ($rows.Count) { $good = $rows; $errorKey = $null }
          }
          if ($errorKey) {
            $message = $outputText
            if ($msg) { $message = @($msg.response, $msg.message, $msg.error, $msg.error.message) -join ' ' }
            $errorKey = Get-AntigravityErrorKey $message
          }
        }
      }
      catch { $errorKey = 'quota.cannot_read_quota' }
      finally {
        $entry = @{ LastRun = $now; InFlight = $false; Good = $good; ErrorKey = $errorKey }
        $state['Usage'] = $entry
      }
    }

    if ($entry.Good) {
      foreach ($group in $entry.Good) {
        $data = Reset-QuotaElapsedWindows $group.Data $now
        $row = New-AgentQuota $group.Provider "$name · $($group.Group)" $data $null $data.FetchedAt
        Add-Member -InputObject $row -NotePropertyMembers @{ Family = 'antigravity'; Group = $group.Group }
        $row
      }
      return
    }
    if ($entry.ErrorKey) { $errorKey = $entry.ErrorKey }
    return New-AgentQuota 'antigravity' $name $null (T $errorKey) $now
  }
  catch { return New-AgentQuota 'antigravity' $name $null (T 'quota.cannot_read_quota') (Get-Date) }
}
