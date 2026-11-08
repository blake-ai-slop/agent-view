# Checking never installs an update. Loading only defines functions and strings.
. (Join-Path $PSScriptRoot 'I18n.ps1')
. (Join-Path $PSScriptRoot 'Settings.ps1')
. (Join-Path $PSScriptRoot 'Version.ps1')
Register-AgentViewStrings -Module 'update' -Strings @{
 en=@{unsupported='Update checks are unavailable for this source';check='Check for updates';install='Update to v{0}';available='Update available: v{0}';latest="You're on the latest version (v{0})";error="Couldn't check for updates";checking='Checking…';automatic='Check for updates automatically';cli_new='Update available v{0} — run agentview update'}
 vi=@{unsupported='Nguồn cài đặt này không hỗ trợ kiểm tra cập nhật';check='Kiểm tra cập nhật';install='Cập nhật lên v{0}';available='Có bản mới: v{0}';latest='Đang dùng bản mới nhất (v{0})';error='Không kiểm tra được cập nhật';checking='Đang kiểm tra…';automatic='Tự kiểm tra cập nhật';cli_new='Có bản mới v{0} — chạy agentview update'}
}
function Get-AgentViewUpdateSource {
 if (-not [string]::IsNullOrWhiteSpace($env:AGENT_VIEW_SOURCE)) { return $env:AGENT_VIEW_SOURCE }
 return 'https://raw.githubusercontent.com/blake-ai-slop/agent-view/main'
}
function Get-AgentViewReleaseApiUrl([string]$Source = (Get-AgentViewUpdateSource)) {
 if ($Source -match '^https://raw\.githubusercontent\.com/([a-zA-Z0-9-]+)/agent-view/[^/]+/?$' -or $Source -match '^https://github\.com/([a-zA-Z0-9-]+)/agent-view(?:/(?:tree|raw)/[^/]+)?/?$') {
  return ('https://api.github.com/repos/'+$Matches[1]+'/agent-view/releases/latest')
 }
 return $null
}
function Compare-AgentViewVersion([string]$A, [string]$B) {
 if ($A -cnotmatch '^v?\d+(?:\.\d+){0,2}$' -or $B -cnotmatch '^v?\d+(?:\.\d+){0,2}$') { return 0 }
 $aa=$A.TrimStart('v').Split('.'); $bb=$B.TrimStart('v').Split('.')
 try {
  for ($i=0; $i -lt 3; $i++) {
   $x=0L; $y=0L
   if ($i -lt $aa.Length) { $x=[long]$aa[$i] }; if ($i -lt $bb.Length) { $y=[long]$bb[$i] }
   if ($x -gt $y) { return 1 }; if ($x -lt $y) { return -1 }
  }
 } catch { return 0 }
 return 0
}
function Get-AgentViewLatestRelease([string]$ApiUrl = (Get-AgentViewReleaseApiUrl), [int]$TimeoutSec = 10) {
 if (-not $ApiUrl) { throw 'Unsupported update source' }
 try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $response=Invoke-WebRequest -Uri $ApiUrl -UseBasicParsing -TimeoutSec $TimeoutSec -Headers @{'User-Agent'=('agent-view/'+$script:AgentViewVersion)} -ErrorAction Stop
  $r=$response.Content | ConvertFrom-Json -ErrorAction Stop
  if ($r.draft -or $r.prerelease -or $r.tag_name -cnotmatch '^v?\d+(?:\.\d+){0,2}$' -or $r.html_url -notmatch '^https://github\.com/') { throw 'Invalid release' }
  return @{Version=([string]$r.tag_name).TrimStart('v');Url=[string]$r.html_url;PublishedAt=$r.published_at}
 } catch { throw 'Could not fetch latest release' }
}
function Test-AgentViewUpdateCheckDue($State, [datetime]$Now = (Get-Date), [double]$IntervalHours = 24) {
 if (-not $State -or -not $State.LastCheck) { return $true }
 try { return (($Now.ToUniversalTime()-([datetime]$State.LastCheck).ToUniversalTime()).TotalHours -ge $IntervalHours) } catch { return $true }
}
function Read-AgentViewUpdateState([string]$Path = (Join-Path $env:LOCALAPPDATA 'agent-view/update-state.json')) {
 try {
  $s=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if (-not $s.LastCheck) { return $null }; [void][datetime]::Parse($s.LastCheck)
  foreach ($key in @('LatestVersion','LatestUrl','NotifiedVersion')) { if ($null -ne $s.$key -and $s.$key -isnot [string]) { return $null } }
  return @{LastCheck=$s.LastCheck;LatestVersion=$s.LatestVersion;LatestUrl=$s.LatestUrl;NotifiedVersion=$s.NotifiedVersion}
 } catch { return $null }
}
function Save-AgentViewUpdateState($State, [string]$Path = (Join-Path $env:LOCALAPPDATA 'agent-view/update-state.json')) {
 $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try {
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
  [IO.File]::WriteAllText($temp,($State | ConvertTo-Json),(New-Object Text.UTF8Encoding $true))
  Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
 } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
function Invoke-AgentViewUpdateCheck {
 param([switch]$Force, [datetime]$Now = (Get-Date), $Settings = (Get-AgentViewSettings), [scriptblock]$Fetch = { param($url) Get-AgentViewLatestRelease -ApiUrl $url })
 $state=Read-AgentViewUpdateState
 $result=@{Status='skipped';Current=$script:AgentViewVersion;Latest=$null;Url=$null;Error=$null;ShouldNotify=$false}
 if ($state) { $result.Latest=$state.LatestVersion; $result.Url=$state.LatestUrl }
 if (-not $Force -and ($Settings.UpdateCheck -eq $false -or -not (Test-AgentViewUpdateCheckDue $state $Now))) { return $result }
 $api=Get-AgentViewReleaseApiUrl
 if (-not $api) { return $result }
 if (-not $state) { $state=@{LastCheck=$null;LatestVersion=$null;LatestUrl=$null;NotifiedVersion=$null} }
 $state.LastCheck=$Now.ToUniversalTime().ToString('o')
 try {
  $release=& $Fetch $api
  if (-not $release.Version -or $release.Version -cnotmatch '^v?\d+(?:\.\d+){0,2}$') { throw 'Invalid release' }
  $result.Latest=([string]$release.Version).TrimStart('v'); $result.Url=$release.Url
  $state.LatestVersion=$result.Latest; $state.LatestUrl=$result.Url; $result.Status='latest'
  if ((Compare-AgentViewVersion $result.Latest $result.Current) -gt 0) {
   $result.Status='newer'; $result.ShouldNotify=($result.Latest -ne $state.NotifiedVersion)
   if ($result.ShouldNotify) { $state.NotifiedVersion=$result.Latest }
  }
 } catch { $result.Status='error'; $result.Error="Couldn't check for updates" }
 try { Save-AgentViewUpdateState $state } catch { $result.Status='error'; $result.Error='Could not save update state'; $result.ShouldNotify=$false }
 return $result
}
function Start-AgentViewUpdate {
 $shim=Join-Path $env:LOCALAPPDATA 'agent-view/bin/agentview.cmd'
 Start-Process -FilePath (Join-Path $env:WINDIR 'System32/cmd.exe') -ArgumentList ('/c ""'+$shim+'" update"') -WindowStyle Normal | Out-Null
}
