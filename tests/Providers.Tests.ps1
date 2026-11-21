# Pester 3.4: chạy bằng powershell.exe 5.1 -STA. Registry provider, phát hiện, Get-AgentQuotas theo registry (Fetch giả).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\src\Quota.ps1')
Set-AgentViewLanguage vi

function New-ProviderOps([hashtable]$Over) {
  $ops = @{
    FallbackState = @{}; CodexState = @{}; AntigravityState = @{}; ProviderPresence = @{}
    Now      = { [DateTime]::SpecifyKind((New-Object DateTime 2026, 11, 21, 12, 0, 0), 'Local') }
    GetEnv   = { param($n) $null }
    HomeDir  = { 'C:\home' }
    ReadText = { param($p) $null }
    Find     = { param($n) $null }
    Run      = { param($i, $s, $o, $t) throw 'Run không được gọi' }
  }
  if ($Over) { foreach ($k in $Over.Keys) { $ops[$k] = $Over[$k] } }
  return $ops
}

Describe 'Get-AgentProviders' {
  It 'thứ tự cố định claude, codex, antigravity với đủ trường' {
    $p = @(Get-AgentProviders)
    ($p.Family -join ',') | Should Be 'claude,codex,antigravity'
    ($p.Name -join ',') | Should Be 'Claude Code,Codex,Antigravity'
    ($p.Short -join ',') | Should Be 'Claude,Codex,Antigravity'
    ($p.Color -join ',') | Should Be '#E2875C,#C7CEDA,#6FA8F5'
    ($p.Cli -join ',') | Should Be 'claude,codex,agy'
    ($p.Fetch -join ',') | Should Be 'Get-ClaudeQuota,Get-CodexQuota,Get-AntigravityQuota'
    ($null -eq $p[0].Module -and $null -eq $p[1].Module) | Should Be $true
    $p[2].Module | Should Be 'QuotaAntigravity.ps1'
    @($p[2].KnownPaths) -join ',' | Should Be '%LOCALAPPDATA%\agy\bin\agy.exe'
    @($p[0].KnownPaths).Count | Should Be 0
    foreach ($x in $p) { @($x.PSObject.Properties.Name) -join ',' | Should Be 'Family,Name,Short,Color,Cli,KnownPaths,Fetch,Module' }
  }
  It 'Providers.ps1 dot-source một mình không in gì và không cần Quota.ps1' {
    $src = Join-Path $here '..\src\Providers.ps1'
    $out = powershell.exe -NoProfile -Command "`$o = . '$src' *>&1; 'out=' + @(`$o).Count; @(Get-AgentProviders).Count"
    ($out -join ',') | Should Be 'out=0,3'
  }
}

Describe 'Find-AgentCli' {
  It 'sau PATH thử KnownPaths (mở rộng biến môi trường) của provider có Cli khớp' {
    $dir = Join-Path $TestDrive 'kp'
    New-Item -ItemType Directory -Force (Join-Path $dir 'bin') | Out-Null
    $exe = Join-Path $dir 'bin\avfake.exe'
    Set-Content $exe 'x'
    $old = $env:AV_TEST_KNOWN
    try {
      $env:AV_TEST_KNOWN = $dir
      function Get-AgentProviders { [pscustomobject]@{ Family = 'fake'; Cli = 'av-test-cli-none'; KnownPaths = @('%AV_TEST_KNOWN%\missing.exe', '%AV_TEST_KNOWN%\bin\avfake.exe') } }
      Find-AgentCli 'av-test-cli-none' | Should Be $exe
      ($null -eq (Find-AgentCli 'av-test-other-none')) | Should Be $true
      Remove-Item $exe
      ($null -eq (Find-AgentCli 'av-test-cli-none')) | Should Be $true
    }
    finally { $env:AV_TEST_KNOWN = $old }
  }
  It 'PATH thắng KnownPaths' {
    function Get-AgentProviders { [pscustomobject]@{ Family = 'fake'; Cli = 'powershell'; KnownPaths = @('C:\nowhere\powershell.exe') } }
    Find-AgentCli 'powershell' | Should Match 'powershell\.exe$'
  }
}

Describe 'Get-AgentDetectedProviders' {
  It 'phát hiện theo CLI; claude cũng nhận khi chỉ có .claude.json' {
    $ops = New-ProviderOps @{
      Find = { param($n) if ($n -eq 'agy') { 'C:\agy\agy.exe' } }
      ReadText = { param($p) if ($p -eq 'C:\home\.claude.json') { '{}' } }
    }
    (@(Get-AgentDetectedProviders -Ops $ops) -join ',') | Should Be 'claude,antigravity'
    $ops = New-ProviderOps @{ GetEnv = { param($n) if ($n -eq 'CLAUDE_CONFIG_DIR') { 'D:\cfg' } }; ReadText = { param($p) if ($p -eq 'D:\cfg\.claude.json') { '{}' } } }
    (@(Get-AgentDetectedProviders -Ops $ops) -join ',') | Should Be 'claude'
  }
  It 'không có gì ⇒ rỗng; thao tác ngoài ném lỗi ⇒ coi như không có' {
    @(Get-AgentDetectedProviders -Ops (New-ProviderOps)).Count | Should Be 0
    @(Get-AgentDetectedProviders -Ops (New-ProviderOps @{ Find = { throw 'x' }; ReadText = { throw 'y' } })).Count | Should Be 0
  }
  It 'dùng cache cho tới -Rescan hoặc Reset-AgentDetectedProviders' {
    $box = @{ Names = @('codex'); Calls = 0 }
    $ops = New-ProviderOps @{ Find = { param($n) $box.Calls++; if ($box.Names -contains $n) { "C:\bin\$n.exe" } }.GetNewClosure() }
    (@(Get-AgentDetectedProviders -Ops $ops) -join ',') | Should Be 'codex'
    $calls = $box.Calls
    $box.Names = @('codex', 'claude')
    (@(Get-AgentDetectedProviders -Ops $ops) -join ',') | Should Be 'codex'
    $box.Calls | Should Be $calls
    (@(Get-AgentDetectedProviders -Ops $ops -Rescan) -join ',') | Should Be 'claude,codex'
    $box.Names = @()
    Reset-AgentDetectedProviders -Ops $ops
    @(Get-AgentDetectedProviders -Ops $ops).Count | Should Be 0
    $ops.ProviderPresence['Families'].GetType().Name | Should Be 'String[]'
  }
  It 'mặc định lưu trong AppDomain agent-view.ProviderPresence; Reset xóa' {
    $state = Get-QuotaDomainState 'agent-view.ProviderPresence'
    $saved = $state['Families']
    try {
      $state['Families'] = [string[]]@('codex')
      (@(Get-AgentDetectedProviders) -join ',') | Should Be 'codex'
      Reset-AgentDetectedProviders
      $state.ContainsKey('Families') | Should Be $false
    }
    finally { if ($null -ne $saved) { $state['Families'] = $saved } else { $state.Remove('Families') } }
  }
}

Describe 'Get-AgentQuotas theo registry (Fetch giả)' {
  function Get-AgentProviders {
    [pscustomobject]@{ Family = 'alpha'; Name = 'Alpha'; Cli = 'alpha'; KnownPaths = @(); Fetch = 'Get-TestAlphaQuota'; Module = $null }
    [pscustomobject]@{ Family = 'beta'; Name = 'Beta'; Cli = 'beta'; KnownPaths = @(); Fetch = 'Get-TestBetaQuota'; Module = $null }
    [pscustomobject]@{ Family = 'gamma'; Name = 'Gamma'; Cli = 'gamma'; KnownPaths = @(); Fetch = 'Get-TestMissingQuota'; Module = 'Missing.ps1' }
    [pscustomobject]@{ Family = 'delta'; Name = 'Delta'; Cli = 'delta'; KnownPaths = @(); Fetch = 'Get-TestThrowQuota'; Module = $null }
  }
  # alpha giống Claude: không có -Manual, 1 row không Family. beta giống Antigravity: -Manual, nhiều row có Family/Group.
  function Get-TestAlphaQuota([hashtable]$Ops) { $Ops.Log.Add('alpha'); New-AgentQuota 'alpha' 'Alpha' @{ FiveHour = 10; Week = 20 } $null (& $Ops.Now) }
  function Get-TestBetaQuota([hashtable]$Ops, [switch]$Manual) {
    $Ops.Log.Add("beta:$Manual")
    foreach ($g in 'one', 'two') {
      $q = New-AgentQuota "beta-$g" "Beta $g" @{ FiveHour = 1; Week = $null } $null (& $Ops.Now)
      $q | Add-Member -NotePropertyName Family -NotePropertyValue 'beta'
      $q | Add-Member -NotePropertyName Group -NotePropertyValue $g
      $q
    }
  }
  function Get-TestThrowQuota([hashtable]$Ops) { throw 'boom' }
  function New-RegistryOps([string[]]$Families) {
    New-ProviderOps @{ Log = (New-Object Collections.Generic.List[string]); ProviderPresence = @{ Families = [string[]]$Families } }
  }

  It 'theo thứ tự registry, phát từng row, thêm Family/Group khi thiếu' {
    $ops = New-RegistryOps @('alpha', 'beta', 'gamma', 'delta')
    $q = Get-AgentQuotas -Ops $ops
    $q.Count | Should Be 3
    ($q.Provider -join ',') | Should Be 'alpha,beta-one,beta-two'
    $q[0].Family | Should Be 'alpha'
    ($null -eq $q[0].Group) | Should Be $true
    @($q[0].PSObject.Properties.Name)[-2..-1] -join ',' | Should Be 'Family,Group'
    $q[1].Family | Should Be 'beta'; $q[1].Group | Should Be 'one'
    (@(Get-AgentQuotas -Ops $ops | ForEach-Object { $_.Provider }) -join ',') | Should Be 'alpha,beta-one,beta-two'
  }
  It 'bỏ Family không phát hiện và Family trong -Skip' {
    $ops = New-RegistryOps @('beta')
    (@(Get-AgentQuotas -Ops $ops).Provider -join ',') | Should Be 'beta-one,beta-two'
    ($ops.Log -join ',') | Should Be 'beta:False'
    $ops = New-RegistryOps @('alpha', 'beta')
    (@(Get-AgentQuotas -Ops $ops -Skip 'beta').Provider -join ',') | Should Be 'alpha'
    @(Get-AgentQuotas -Ops $ops -Skip 'alpha', 'beta').Count | Should Be 0
    ($ops.Log -join ',') | Should Be 'alpha'
  }
  It 'không phát hiện provider nào ⇒ không phát row nào' {
    $q = @(Get-AgentQuotas -Ops (New-RegistryOps @()))
    $q.Count | Should Be 0
  }
  It '-Manual chuyển cho Fetch có -Manual và quét lại phát hiện' {
    $ops = New-RegistryOps @('alpha')
    $ops.Find = { param($n) if ($n -in 'alpha', 'beta') { "C:\bin\$n.exe" } }
    (@(Get-AgentQuotas -Ops $ops).Provider -join ',') | Should Be 'alpha'
    (@(Get-AgentQuotas -Ops $ops -Manual).Provider -join ',') | Should Be 'alpha,beta-one,beta-two'
    ($ops.Log -join ',') | Should Be 'alpha,alpha,beta:True'
    ($ops.ProviderPresence['Families'] -join ',') | Should Be 'alpha,beta'
  }
  It 'Fetch thiếu hoặc ném lỗi ⇒ bỏ qua im lặng' {
    $ops = New-RegistryOps @('gamma', 'delta')
    $err = $null
    $q = @(Get-AgentQuotas -Ops $ops -ErrorVariable err)
    $q.Count | Should Be 0
  }
  It 'runspace thật: row phẳng, đếm đúng (Format ConvertTo-QuotaRows)' {
    . (Join-Path $here '..\src\Format.ps1')
    $ps = [PowerShell]::Create()
    try {
      [void]$ps.AddScript({ param($path)
        . $path
        function Get-AntigravityQuota([hashtable]$Ops, [switch]$Manual) {
          foreach ($g in 'gemini', '3p') {
            $q = New-AgentQuota "antigravity-$g" "Antigravity $g" @{ FiveHour = 5; Week = 6 } $null (Get-Date)
            $q | Add-Member -NotePropertyName Family -NotePropertyValue 'antigravity' -PassThru | Add-Member -NotePropertyName Group -NotePropertyValue $g -PassThru
          }
        }
        Get-AgentQuotas -Ops @{ ProviderPresence = @{ Families = [string[]]@('claude', 'antigravity') }; ReadText = { param($p) $null }; Find = { param($n) $null }; GetEnv = { param($n) $null }; Run = { throw 'no' } }
      }).AddArgument((Join-Path $here '..\src\Quota.ps1'))
      $rows = @(ConvertTo-QuotaRows ($ps.Invoke()))
      ($rows.Provider -join ',') | Should Be 'claude,antigravity-gemini,antigravity-3p'
      ($rows.Family -join ',') | Should Be 'claude,antigravity,antigravity'
    }
    finally { $ps.Dispose() }
  }
}

Describe 'Quota.ps1 nạp Module của registry' {
  It 'dot-source module cạnh Quota.ps1 nếu có, im lặng khi thiếu' {
    $dir = Join-Path $TestDrive 'mod'
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($f in 'Quota.ps1', 'Providers.ps1', 'Process.ps1', 'I18n.ps1') { Copy-Item (Join-Path $here "..\src\$f") $dir }
    $cmd = "`$o = . '$dir\Quota.ps1' *>&1; 'out=' + @(`$o).Count; [bool](Get-Command Get-AntigravityQuota -ErrorAction SilentlyContinue)"
    (@(powershell.exe -NoProfile -Command $cmd) -join ',') | Should Be 'out=0,False'
    Set-Content (Join-Path $dir 'QuotaAntigravity.ps1') "function Get-AntigravityQuota([hashtable]`$Ops, [switch]`$Manual) { }`r`n. (Join-Path `$PSScriptRoot 'Quota.ps1')" -Encoding ASCII
    (@(powershell.exe -NoProfile -Command $cmd) -join ',') | Should Be 'out=0,True'
  }
}
