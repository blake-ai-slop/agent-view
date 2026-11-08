. "$PSScriptRoot/../src/Cli.ps1"
Describe 'Release update checks' {
 BeforeEach {
  $script:updateOldLocal=$env:LOCALAPPDATA; $script:updateOldSource=$env:AGENT_VIEW_SOURCE
  $env:LOCALAPPDATA=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $env:AGENT_VIEW_SOURCE='https://raw.githubusercontent.com/example/agent-view/main'
  Mock Invoke-WebRequest { throw 'Tests must not access the network' }
 }
 AfterEach { $env:LOCALAPPDATA=$script:updateOldLocal; $env:AGENT_VIEW_SOURCE=$script:updateOldSource }
 It 'compares numeric versions with optional v and missing zero components' {
  Compare-AgentViewVersion '0.2.10' '0.2.9' | Should Be 1
  Compare-AgentViewVersion 'v1' '1.0.0' | Should Be 0
  Compare-AgentViewVersion '0.2' '1' | Should Be -1
  foreach ($v in @('bad','1.2-beta','1.2.3.4','99999999999999999999999')) { Compare-AgentViewVersion $v '0.2.0' | Should Be 0 }
 }
 It 'derives only supported GitHub sources and skips local sources' {
  Get-AgentViewReleaseApiUrl | Should Be 'https://api.github.com/repos/example/agent-view/releases/latest'
  Get-AgentViewReleaseApiUrl 'https://github.com/example/agent-view' | Should Be 'https://api.github.com/repos/example/agent-view/releases/latest'
  foreach ($source in @($TestDrive,'https://example.test/agent-view/main','https://raw.githubusercontent.com.evil/example/agent-view/main')) { $null -eq (Get-AgentViewReleaseApiUrl $source) | Should Be $true }
  $env:AGENT_VIEW_SOURCE=$TestDrive
  (Invoke-AgentViewUpdateCheck -Force -Fetch { throw 'Must not fetch' }).Status | Should Be skipped
 }
 It 'parses a stable release tag and uses anonymous bounded GET with the version user agent' {
  Mock Invoke-WebRequest { @{Content='{"tag_name":"v0.2.2","html_url":"https://github.com/example/agent-view/releases/tag/v0.2.2","published_at":"2026-11-08T00:00:00Z","draft":false,"prerelease":false}'} }
  $r=Get-AgentViewLatestRelease
  $r.Version | Should Be '0.2.2'; $r.PublishedAt | Should Be '2026-11-08T00:00:00Z'
  Assert-MockCalled Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $UseBasicParsing -and $TimeoutSec -eq 10 -and $Headers.Count -eq 1 -and $Headers['User-Agent'] -eq ('agent-view/'+$script:AgentViewVersion) }
 }
 It 'rejects prereleases drafts malformed tags and network errors briefly' {
  foreach ($json in @('{"tag_name":"v1","prerelease":true}','{"tag_name":"v1","draft":true}','{"tag_name":"weird"}')) {
   Mock Invoke-WebRequest { @{Content=$json} }
   { Get-AgentViewLatestRelease } | Should Throw 'Could not fetch latest release'
  }
  Mock Invoke-WebRequest { throw 'private response details' }
  { Get-AgentViewLatestRelease } | Should Throw 'Could not fetch latest release'
 }
 It 'checks the exact 24 hour boundary and treats corrupt timestamps as due' {
  $now=[datetime]'2026-11-08T12:00:00Z'
  Test-AgentViewUpdateCheckDue @{LastCheck=$now.AddHours(-24).ToString('o')} $now | Should Be $true
  Test-AgentViewUpdateCheckDue @{LastCheck=$now.AddHours(-24).AddSeconds(1).ToString('o')} $now | Should Be $false
  Test-AgentViewUpdateCheckDue @{LastCheck='bad'} $now | Should Be $true
 }
 It 'skips disabled checks without fetching but force overrides settings and throttle' {
  (Invoke-AgentViewUpdateCheck -Settings @{UpdateCheck=$false} -Fetch { throw 'Must not fetch' }).Status | Should Be skipped
  (Invoke-AgentViewUpdateCheck -Force -Settings @{UpdateCheck=$false} -Fetch { @{Version='0.0.1';Url='https://github.com/example'} }).Status | Should Be latest
  (Invoke-AgentViewUpdateCheck -Fetch { throw 'Must not fetch' }).Status | Should Be skipped
  (Invoke-AgentViewUpdateCheck -Force -Fetch { @{Version='99';Url='https://github.com/example'} }).Status | Should Be newer
 }
 It 'notifies once per version across state reloads and records real checks' {
  $a=Invoke-AgentViewUpdateCheck -Force -Fetch { @{Version='99.0.0';Url='https://github.com/example'} }
  $a.Status | Should Be newer; $a.ShouldNotify | Should Be $true
  (Invoke-AgentViewUpdateCheck -Force -Fetch { @{Version='99.0.0';Url='https://github.com/example'} }).ShouldNotify | Should Be $false
  (Invoke-AgentViewUpdateCheck -Force -Fetch { @{Version='99.0.1';Url='https://github.com/example'} }).ShouldNotify | Should Be $true
  (Read-AgentViewUpdateState).NotifiedVersion | Should Be '99.0.1'
 }
 It 'persists failed attempts to avoid repeated requests' {
  $now=[datetime]'2026-11-08T12:00:00Z'
  $r=Invoke-AgentViewUpdateCheck -Now $now -Fetch { throw 'network error' }
  $r.Status | Should Be error; $r.ShouldNotify | Should Be $false
  ([datetime](Read-AgentViewUpdateState).LastCheck).ToUniversalTime() | Should Be $now.ToUniversalTime()
  (Invoke-AgentViewUpdateCheck -Now $now.AddMinutes(5) -Fetch { throw 'Must not fetch' }).Status | Should Be skipped
 }
 It 'recovers corrupt state and writes no temporary leftovers' {
  $path=Join-Path $env:LOCALAPPDATA 'agent-view/update-state.json'
  New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
  foreach ($bad in @('{broken','[]','{"LastCheck":"no date"}','{"LastCheck":"2026-11-08","LatestVersion":42}')) {
   Set-Content $path $bad; $null -eq (Read-AgentViewUpdateState) | Should Be $true
  }
  (Invoke-AgentViewUpdateCheck -Force -Fetch { @{Version='99';Url='https://github.com/example'} }).Status | Should Be newer
  @(Get-ChildItem (Split-Path $path) -Filter '*.tmp').Count | Should Be 0
 }
 It 'starts the installed command in a separate visible console without waiting' {
  Mock Start-Process {}
  Start-AgentViewUpdate
  Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -like '*cmd.exe' -and $ArgumentList -like '*agent-view*agentview.cmd*update*' -and $WindowStyle -eq 'Normal' -and -not $Wait }
 }
 It 'routes CLI check through force checking with fake fetch and preserves install behavior' {
  Mock Get-AgentViewLatestRelease { @{Version='99.0.0';Url='https://github.com/example'} }
  Mock Invoke-AgentViewUpdate { throw 'Must not install' }
  Invoke-AgentViewCli @('update','--check') (Get-AgentViewPaths) 6>$null | Should Be 0
  Assert-MockCalled Get-AgentViewLatestRelease -Times 1 -Exactly
  Assert-MockCalled Invoke-AgentViewUpdate -Times 0 -Exactly
  Mock Get-AgentViewLatestRelease { throw 'network failure' }
  Invoke-AgentViewCli @('update','--check') (Get-AgentViewPaths) 6>$null | Should Be 1
 }
 It 'loads without checking the network reading state or launching a process' {
  Mock Get-Content { throw 'Must not read state' }
  Mock Start-Process { throw 'Must not launch' }
  $output=. "$PSScriptRoot/../src/Update.ps1"
  $null -eq $output | Should Be $true
  Assert-MockCalled Get-Content -Times 0 -Exactly -Scope It
  Assert-MockCalled Invoke-WebRequest -Times 0 -Exactly -Scope It
  Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
 }
}
