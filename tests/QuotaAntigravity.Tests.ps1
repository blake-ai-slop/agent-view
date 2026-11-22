$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\src\Quota.ps1')
. (Join-Path $here '..\src\QuotaAntigravity.ps1')

Describe 'Antigravity quota' {
  $fixture = Join-Path $here 'fixtures\antigravity-usage.json'
  $base = [datetime]::Parse('2030-01-01T00:00:00Z').ToLocalTime()
  # Parse from scratch so tests can change the envelope independently.
  function New-AgyResponse { Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json }
  function New-AgyFake {
    return @{
      Now = $base; Calls = 0; Result = @{ ExitCode = 0; TimedOut = $false; Lines = [IO.File]::ReadAllLines($fixture) }
    }
  }
  function New-AgyOps($Fake) {
    return @{
      AntigravityState = [hashtable]::Synchronized(@{})
      Find = { param($name) $Fake.Found = $name; 'C:\fixture\agy.exe' }.GetNewClosure()
      Now = { $Fake.Now }.GetNewClosure()
      Run = {
        param($invocation, $send, $onLine, $timeoutMs)
        $Fake.Calls++
        $Fake.Invocation = $invocation
        $Fake.Send = $send
        $Fake.OnLine = $onLine
        $Fake.TimeoutMs = $timeoutMs
        if ($Fake.Throw) { throw 'simulated process failure' }
        if ($Fake.DuringRun) { & $Fake.DuringRun }
        $Fake.Result
      }.GetNewClosure()
    }
  }

  It 'invokes usage only and maps the recorded groups to quota rows' {
    $fake = New-AgyFake
    $rows = @(Get-AntigravityQuota (New-AgyOps $fake))
    $fake.Found | Should Be 'agy'
    $fake.Calls | Should Be 1
    $fake.Invocation.File | Should Be 'C:\fixture\agy.exe'
    ($fake.Invocation.ArgList -join ' ') | Should Be '-p /usage --output-format json'
    @($fake.Invocation.Env.Keys).Count | Should Be 1
    $fake.Invocation.Env['AGY_CLI_DISABLE_AUTO_UPDATE'] | Should BeExactly 'true'
    $fake.Send.Count | Should Be 0
    $fake.OnLine | Should BeNullOrEmpty
    $fake.TimeoutMs | Should Be 15000
    $rows.Count | Should Be 3
    ($rows.Provider -join ',') | Should Be 'antigravity-gemini,antigravity-3p,antigravity-argon'
    ($rows.Group -join ',') | Should Be 'Gemini,Claude/GPT,Argon'
    ($rows.Family -join ',') | Should Be 'antigravity,antigravity,antigravity'
    $rows[0].Name | Should Be 'Antigravity · Gemini'
    $rows[0].Ok | Should Be $true
    $rows[0].FetchedAt | Should Be $base
    $rows[0].FiveHourUsed | Should Be 0
    $rows[0].FiveHourResetsAt | Should BeNullOrEmpty
    $rows[0].WeekUsed | Should Be 3
    $rows[0].WeekResetsAt | Should Be $base.AddDays(7)
    $rows[1].WeekUsed | Should Be 0
    $rows[1].WeekResetsAt | Should Be $base.AddDays(7)
    $rows[2].FiveHourUsed | Should BeNullOrEmpty
    $rows[2].FiveHourResetsAt | Should BeNullOrEmpty
    $rows[2].WeekUsed | Should Be 0
  }

  It 'uses a slug for new groups and ignores unsupported or invalid buckets' {
    $fake = New-AgyFake
    $reply = New-AgyResponse
    $reply.command.data.groups = @(@{
      name = ' Nova ++ 9 Models! '
      buckets = @(
        @{ id = 'nova-monthly'; window = 'monthly'; remaining_fraction = 0.8; reset_time = '2030-02-01T00:00:00Z' }
        @{ id = 'nova-5h'; window = '5h'; remaining_fraction = 0.625; reset_time = '2030-01-01T05:00:00Z' }
        @{ id = 'nova-weekly'; window = 'weekly'; remaining_fraction = '0.2'; reset_time = '2030-01-08T00:00:00Z' }
      )
    })
    $fake.Result.Lines = @($reply | ConvertTo-Json -Depth 9)
    $rows = @(Get-AntigravityQuota (New-AgyOps $fake))
    $rows.Count | Should Be 1
    $rows[0].Provider | Should Be 'antigravity-nova-9-models'
    $rows[0].Group | Should Be ' Nova ++ 9 Models! '
    $rows[0].FiveHourUsed | Should Be 38
    $rows[0].FiveHourResetsAt | Should Be $base.AddHours(5)
    $rows[0].WeekUsed | Should BeNullOrEmpty
  }

  It 'rejects non-usage, non-zero turns or tokens, invalid status and unsuccessful process exit' {
    foreach ($field in @('command','status','status_array','turns','tokens','missing','string','exit','no_exit','array')) {
      $fake = New-AgyFake
      $reply = New-AgyResponse
      switch ($field) {
        command { $reply.command.name = 'other' }
        status { $reply.status = 'ERROR' }
        status_array { $reply.status = @('SUCCESS') }
        turns { $reply.num_turns = 1 }
        tokens { $reply.usage.total_tokens = 1 }
        missing { $reply.usage.PSObject.Properties.Remove('total_tokens') }
        string { $reply.num_turns = '0' }
        exit { $fake.Result.ExitCode = 1 }
        no_exit { $fake.Result.ExitCode = $null }
      }
      $json = $reply | ConvertTo-Json -Depth 9
      if ($field -eq 'array') { $json = "[$json]" }
      $fake.Result.Lines = @($json)
      $rows = @(Get-AntigravityQuota (New-AgyOps $fake))
      $rows.Count | Should Be 1
      $rows[0].Provider | Should Be 'antigravity'
      $rows[0].Ok | Should Be $false
      $rows[0].Error | Should Be (T 'quota.cannot_read_quota')
    }
  }

  It 'returns one localized row when agy is missing and does not run it' {
    $fake = New-AgyFake
    $ops = New-AgyOps $fake
    $ops.Find = { $null }
    $q = Get-AntigravityQuota $ops
    $q.Provider | Should Be 'antigravity'
    $q.Ok | Should Be $false
    $q.Error | Should Be (T 'antigravity.not_installed')
    $fake.Calls | Should Be 0
  }

  It 'classifies timeout and synthetic auth replies and uses the generic error for unknown output' {
    $cases = @(
      @{ Output = 'ignored'; Timeout = $true; Key = 'antigravity.timed_out' }
      @{ Output = 'Not logged in.'; Key = 'antigravity.not_signed_in' }
      @{ Output = '{"status":"ERROR","error":{"message":"Please sign in."}}'; Key = 'antigravity.not_signed_in' }
      @{ Output = '{"status":"ERROR","response":"Account quota is unavailable with GEMINI_API_KEY."}'; Key = 'antigravity.api_key' }
      @{ Output = '{invalid json'; Key = 'quota.cannot_read_quota' }
    )
    foreach ($case in $cases) {
      $fake = New-AgyFake
      $fake.Result = @{ ExitCode = 1; TimedOut = [bool]$case.Timeout; Lines = @($case.Output) }
      $q = Get-AntigravityQuota (New-AgyOps $fake)
      $q.Ok | Should Be $false
      $q.Error | Should Be (T $case.Key)
    }
  }

  It 'shares one throttle across callers, separating 5-minute automatic and 30-second manual boundaries' {
    $fake = New-AgyFake
    $ops = New-AgyOps $fake
    $other = New-AgyOps $fake
    $other.AntigravityState = $ops.AntigravityState
    $null = Get-AntigravityQuota $ops
    $fake.Now = $base.AddSeconds(29)
    $rows = @(Get-AntigravityQuota $other -Manual)
    $rows[0].FetchedAt | Should Be $base
    $fake.Calls | Should Be 1
    $fake.Now = $base.AddSeconds(30)
    (Get-AntigravityQuota $other -Manual)[0].FetchedAt | Should Be $fake.Now
    $fake.Calls | Should Be 2
    $fake.Now = $base.AddSeconds(329)
    (Get-AntigravityQuota $ops)[0].FetchedAt | Should Be $base.AddSeconds(30)
    $fake.Calls | Should Be 2
    $fake.Now = $base.AddSeconds(330)
    (Get-AntigravityQuota $ops)[0].FetchedAt | Should Be $fake.Now
    $fake.Calls | Should Be 3
  }

  It 'reuses the last good metrics after failure and applies elapsed resets without changing FetchedAt' {
    $fake = New-AgyFake
    $ops = New-AgyOps $fake
    $reply = New-AgyResponse
    $reply.command.data.groups[0].buckets[0].reset_time = $base.AddMinutes(2).ToUniversalTime().ToString('o')
    $fake.Result.Lines = @($reply | ConvertTo-Json -Depth 9)
    (Get-AntigravityQuota $ops)[0].WeekUsed | Should Be 3
    $fake.Throw = $true
    $fake.Now = $base.AddMinutes(5)
    $rows = @(Get-AntigravityQuota $ops)
    $fake.Calls | Should Be 2
    $rows.Count | Should Be 3
    $rows[0].WeekUsed | Should Be 0
    $rows[0].WeekResetsAt | Should BeNullOrEmpty
    $rows[0].FetchedAt | Should Be $base
    $rows[2].FiveHourUsed | Should BeNullOrEmpty
    $null = Get-AntigravityQuota $ops -Manual
    $fake.Calls | Should Be 2
    $ops.AntigravityState.Usage.Good[0].Data.Week | Should Be 3
  }

  It 'prevents an overlapping caller from starting agy even after the retry gap' {
    $fake = New-AgyFake
    $ops = New-AgyOps $fake
    $getQuota = Get-Command Get-AntigravityQuota
    $fake.DuringRun = {
      $fake.Now = $fake.Now.AddSeconds(30)
      $other = & $getQuota $ops -Manual
      $fake.OverlapError = $other.Error
    }.GetNewClosure()
    (Get-AntigravityQuota $ops)[0].Ok | Should Be $true
    $fake.OverlapError | Should Be (T 'quota.cannot_read_quota')
    $fake.Calls | Should Be 1
  }

  It 'throttles failed initial calls and recovers on manual retry' {
    $fake = New-AgyFake
    $ops = New-AgyOps $fake
    $fake.Throw = $true
    (Get-AntigravityQuota $ops).Error | Should Be (T 'quota.cannot_read_quota')
    $fake.Throw = $false
    $fake.Now = $base.AddSeconds(29)
    (Get-AntigravityQuota $ops -Manual).Ok | Should Be $false
    $fake.Calls | Should Be 1
    $fake.Now = $base.AddSeconds(30)
    (Get-AntigravityQuota $ops -Manual)[0].Ok | Should Be $true
    $fake.Calls | Should Be 2
  }
}
