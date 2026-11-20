. "$PSScriptRoot/../src/Tray.ps1"
Set-AgentViewLanguage vi
function New-TestRow($Five, $Week, $Ok=$true) {
    [pscustomobject]@{Provider='claude';Name='Claude Code';Ok=$Ok;Error='không có dữ liệu';FiveHourUsed=$Five;WeekUsed=$Week;FiveHourResetsAt=[datetime]'2026-11-07T18:30:00';WeekResetsAt=[datetime]'2026-11-10T08:15:00';FetchedAt=[datetime]'2026-11-07T17:00:00'}
}
Describe 'Quota display rules' {
    It 'uses the most constrained window including zero remaining' {
        Get-QuotaRemaining (New-TestRow 28 5) | Should Be 72
        Get-QuotaRemaining (New-TestRow 100 5) | Should Be 0
        Get-QuotaRemaining (New-TestRow 0 0) | Should Be 100
    }
    It 'supports one or no window' {
        Get-QuotaRemaining (New-TestRow $null 25) | Should Be 75
        Get-QuotaRemaining (New-TestRow 40 $null) | Should Be 60
        ($null -eq (Get-QuotaRemaining (New-TestRow $null $null))) | Should Be $true
    }
    It 'honors every level boundary' {
        Get-QuotaLevel 31 | Should Be 'ok'
        Get-QuotaLevel 30 | Should Be 'warn'
        Get-QuotaLevel 11 | Should Be 'warn'
        Get-QuotaLevel 10 | Should Be 'crit'
        Get-QuotaLevel 0 | Should Be 'crit'
        Get-QuotaLevel $null | Should Be 'unk'
    }
    It 'formats provider tooltip and limits length' {
        $codex = New-TestRow 5 0; $codex.Provider='codex'; $codex.Name='Codex'
        Format-QuotaTooltip @((New-TestRow 28 0),$codex) | Should Be "agent-view`nClaude 72%`nCodex 95%"
        $bad = New-TestRow $null $null $false; $bad.Error='x'*100
        (Format-QuotaTooltip @($bad)).Length | Should Be 63
        Format-QuotaTooltip @($bad) | Should Match 'Claude : '
    }

}

Describe 'Tray settings and notification helpers' {
    It 'filters hidden providers and keeps order' {
        $codex = New-TestRow 5 0; $codex.Provider='codex'; $codex.Name='Codex'
        $rows = @((New-TestRow 28 0), $codex)
        @(Select-AgentViewVisibleRows $rows ([pscustomobject]@{HiddenProviders=@('claude')})).Count | Should Be 1
        @(Select-AgentViewVisibleRows $rows ([pscustomobject]@{HiddenProviders=@('claude')}))[0].Provider | Should Be 'codex'
        @(Select-AgentViewVisibleRows $rows ([pscustomobject]@{WidgetEnabled=$false})).Count | Should Be 2
        @(Select-AgentViewVisibleRows (,@($rows)) $null).Count | Should Be 2
    }
    It 'merges notifications into one balloon and picks warning at the low threshold' {
        Get-AgentViewBalloon @() $null | Should Be $null
        $low = @{ Kind='low'; Remaining=25; Title='Claude Code: còn 25%'; Text='Giới hạn 5 giờ' }
        $b = Get-AgentViewBalloon @($low) $null
        $b.Title | Should Be 'Claude Code: còn 25%'; $b.Text | Should Be 'Giới hạn 5 giờ'; $b.Icon | Should Be 'Info'
        $crit = @{ Kind='low'; Remaining=8; Title='Codex: còn 8%'; Text='Giới hạn tuần' }
        $reset = @{ Kind='reset'; Remaining=100; Title='Codex: đã đầy lại'; Text='Giới hạn 5 giờ · còn 100%' }
        $b = Get-AgentViewBalloon @($low, $crit, $reset) $null
        $b.Count | Should Be 3; $b.Icon | Should Be 'Warning'; $b.Title | Should Be 'agent-view'
        $b.Text | Should Be "Claude Code: còn 25% · Giới hạn 5 giờ`nCodex: còn 8% · Giới hạn tuần`nCodex: đã đầy lại · Giới hạn 5 giờ · còn 100%"
        (Get-AgentViewBalloon @($low) ([pscustomobject]@{NotifyThresholds=@(40,25)})).Icon | Should Be 'Warning'
    }
}

Describe 'Bezel tray layout' {
    It 'uses the specified strokes and font sizes' {
        $sizes=@(16,20,24,32); $strokes=@(2,2,2.5,3); $fonts=@(9,11,13,17)
        for ($i=0;$i -lt 4;$i++) {
            $layout=Get-QuotaIconLayout $sizes[$i] 76
            $layout.Stroke | Should Be $strokes[$i]
            $layout.FontSize | Should Be $fonts[$i]
            $layout.Label | Should Be '76'
        }
        (Get-QuotaIconLayout 16 100).Label | Should Be '✓'
        (Get-QuotaIconLayout 20 100).Label | Should Be '✓'
        (Get-QuotaIconLayout 24 100).Label | Should Be '100'
        (Get-QuotaIconLayout 16 $null).Label | Should Be '?'
        (Get-QuotaIconLayout 16 $null -Loading).Label | Should Be ''
    }
}

Describe 'Refresh runspace reuse (v0.2.2)' {
    # Quota.ps1 giả: đếm số lần nạp trong runspace, trả row mang số lần nạp + id runspace (qua Error).
    $quota = Join-Path $TestDrive 'Quota.ps1'
    [IO.File]::WriteAllText($quota, @'
$global:FakeQuotaLoads = 1 + [int]$global:FakeQuotaLoads
function Set-AgentViewLanguage($Language) { }
function Get-AgentQuotas {
    if ($global:FakeQuotaThrow) { throw 'boom' }
    [pscustomobject]@{ Provider = 'claude'; Name = 'Claude Code'; Ok = $false; Error = ('{0}|{1}' -f $global:FakeQuotaLoads, [runspace]::DefaultRunspace.InstanceId); FiveHourUsed = $null; WeekUsed = $null; FiveHourResetsAt = $null; WeekResetsAt = $null; FetchedAt = $null }
}
'@)
    function New-RefreshTray {
        @{ State = @{ Rows = @(); View = @(); Worker = $null; Pending = $null; Runspace = $null; QuotaPath = $quota; Last = [datetime]::MinValue; Frame = 0; Loading = $false; RefreshSeconds = 120 }
           Notify = $null; Menu = $null; Animation = $null }
    }
    function Invoke-TestRefresh($Tray) {
        $null = Start-AgentViewRefresh $Tray
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $Tray.State.Pending.IsCompleted -and $sw.ElapsedMilliseconds -lt 20000) { Start-Sleep -Milliseconds 20 }
        $rows = @(Receive-AgentViewRefresh $Tray)
        if ($Tray.State.Worker) { throw "worker not released" }
        return ,$rows
    }
    It 'runs two refreshes in the same runspace and loads Quota.ps1 once' {
        $tray = New-RefreshTray
        try {
            $a = Invoke-TestRefresh $tray
            $rs = $tray.State.Runspace
            $rs | Should Not Be $null
            $b = Invoke-TestRefresh $tray
            [object]::ReferenceEquals($rs, $tray.State.Runspace) | Should Be $true
            $a[0].Error | Should Be ('1|' + $rs.InstanceId)
            $b[0].Error | Should Be ('1|' + $rs.InstanceId)
        } finally { Reset-AgentViewRefreshRunspace $tray.State }
    }
    It 'keeps the per-provider error rows when Get-AgentQuotas throws, and stays on the same runspace' {
        $tray = New-RefreshTray
        try {
            $null = Invoke-TestRefresh $tray
            $rs = $tray.State.Runspace
            $rs.SessionStateProxy.SetVariable('FakeQuotaThrow', $true)
            $rows = Invoke-TestRefresh $tray
            @($rows | ForEach-Object { $_.Provider }) -join ',' | Should Be 'claude,codex'
            $rows[0].Ok | Should Be $false
            $rows[0].Error | Should Be (T 'tray.cannot_read_quota')
            [object]::ReferenceEquals($rs, $tray.State.Runspace) | Should Be $true
        } finally { Reset-AgentViewRefreshRunspace $tray.State }
    }
    It 'recreates the runspace (and reloads Quota.ps1) after it breaks' {
        $tray = New-RefreshTray
        try {
            $null = Invoke-TestRefresh $tray
            $old = $tray.State.Runspace
            $old.Close()                                   # hỏng giữa hai lần refresh
            $rows = Invoke-TestRefresh $tray
            $tray.State.Runspace | Should Not Be $null
            [object]::ReferenceEquals($old, $tray.State.Runspace) | Should Be $false
            $rows[0].Error | Should Be ('1|' + $tray.State.Runspace.InstanceId)
            # Runspace hỏng ngay sau khi chạy xong ⇒ Receive bỏ nó, lần sau tạo mới.
            Start-AgentViewRefresh $tray
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while (-not $tray.State.Pending.IsCompleted -and $sw.ElapsedMilliseconds -lt 20000) { Start-Sleep -Milliseconds 20 }
            $tray.State.Runspace.Close()
            $null = Receive-AgentViewRefresh $tray
            $tray.State.Runspace | Should Be $null
        } finally { Reset-AgentViewRefreshRunspace $tray.State }
    }
    It 'reports a missing Quota.ps1 like before' {
        $tray = New-RefreshTray
        $tray.State.QuotaPath = Join-Path $TestDrive 'nope\Quota.ps1'
        try {
            $rows = Invoke-TestRefresh $tray
            $rows.Count | Should Be 2
            $rows[0].Error | Should Be (T 'tray.missing_quota_ps1')
        } finally { Reset-AgentViewRefreshRunspace $tray.State }
    }
}

Describe 'Adaptive refresh schedule' {
    $now = [datetime]'2026-11-20T12:00:00'
    It 'uses normal cadence, extends idle cadence, and resumes immediately' {
        $s = @{Last=$now; RefreshSeconds=120}
        (Get-AgentViewNextRefresh $s $now 0).At | Should Be $now.AddSeconds(120)
        (Get-AgentViewNextRefresh $s $now 600001).At | Should Be $now.AddSeconds(600)
        (Get-AgentViewNextRefresh $s $now.AddSeconds(180) 600001).Due | Should Be $false
        (Get-AgentViewNextRefresh $s $now.AddSeconds(180) 0).Due | Should Be $true
    }
    It 'coalesces cache changes until the sixty second minimum' {
        $s = @{Last=$now; RefreshSeconds=120; CacheChanged=$true}
        $p = Get-AgentViewNextRefresh $s $now.AddSeconds(59)
        $p.Due | Should Be $false; $p.At | Should Be $now.AddSeconds(60); $p.Reason | Should Be 'cache'
        (Get-AgentViewNextRefresh $s $now.AddSeconds(60)).Due | Should Be $true
    }
    It 'refreshes five seconds after the nearest future reset including hidden rows' {
        $a = New-TestRow 10 20; $a.FiveHourResetsAt=$now.AddSeconds(-1); $a.WeekResetsAt=$now.AddSeconds(30)
        $b = New-TestRow 90 20; $b.FiveHourResetsAt=$now.AddSeconds(20); $b.WeekResetsAt=$null
        $reset = Get-AgentViewResetRefreshAt @($a,$b) $now
        $reset | Should Be $now.AddSeconds(25)
        $s = @{Last=$now; RefreshSeconds=120; ResetAt=$reset}
        (Get-AgentViewNextRefresh $s $now).Reason | Should Be 'reset'
        (Get-AgentViewNextRefresh $s $now.AddSeconds(25)).Due | Should Be $true
        $a.WeekResetsAt=$now.AddSeconds(-5)
        Get-AgentViewResetRefreshAt @($a) $now | Should Be $null
    }
    It 'polls only metadata every five seconds and preserves a pending change' {
        $script:cacheStamp = $now
        function Get-ClaudeConfigPath { 'fake-cache' }
        Mock Get-ClaudeConfigPath { 'fake-cache' }
        Mock Get-Item { [pscustomobject]@{LastWriteTimeUtc=$script:cacheStamp} }
        $s = @{}
        Update-AgentViewCacheStamp $s $now
        $s.CacheChanged | Should Not Be $true
        $script:cacheStamp = $now.AddSeconds(1)
        Update-AgentViewCacheStamp $s $now.AddSeconds(4)
        $s.CacheChanged | Should Not Be $true
        Update-AgentViewCacheStamp $s $now.AddSeconds(5)
        $s.CacheChanged | Should Be $true
        Update-AgentViewCacheStamp $s $now.AddSeconds(10)
        $s.CacheChanged | Should Be $true
        Assert-MockCalled Get-Item -Times 3 -Exactly
    }
}
Describe 'Refresh loading and manual contract' {
    function New-AdaptiveTray($Path) {
        $animation = @{Interval=400; Running=$false}
        $animation | Add-Member ScriptMethod Start { $this.Running=$true }
        $animation | Add-Member ScriptMethod Stop { $this.Running=$false }
        @{ State=@{Rows=@();View=@();Worker=$null;Pending=$null;Runspace=$null;QuotaPath=$Path;Last=(Get-Date).AddMinutes(-2);Frame=0;Loading=$false}; Animation=$animation; Notify=$null }
    }
    function Wait-AdaptiveRefresh($Tray) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $Tray.State.Pending.IsCompleted -and $sw.Elapsed.TotalSeconds -lt 10) { Start-Sleep -Milliseconds 10 }
        @(Receive-AgentViewRefresh $Tray)
    }
    BeforeEach {
        Mock Update-AgentViewPopup { }
        Mock Update-AgentViewWidget { }
        Mock Update-AgentViewTrayIcon { }
        Mock Invoke-AgentViewRefreshHooks { }
        Mock Request-AgentViewMemoryTrim { }
    }
    It 'keeps automatic refresh quiet and shows loading for manual and initial refresh' {
        $path = Join-Path $TestDrive 'manual-quota.ps1'
        [IO.File]::WriteAllText($path, 'function Set-AgentViewLanguage($Language) {}; function Get-AgentQuotas { param([switch]$Manual) [pscustomobject]@{Provider="codex";Ok=$false;Error=[string][bool]$Manual} }')
        $tray = New-AdaptiveTray $path
        try {
            Start-AgentViewRefresh $tray
            $tray.State.Loading | Should Be $false
            $tray.Animation.Running | Should Be $false
            $rows = @(Wait-AdaptiveRefresh $tray); $rows[0].Error | Should Be 'False'
            Assert-MockCalled Update-AgentViewPopup -Times 0 -Exactly
            Assert-MockCalled Update-AgentViewWidget -Times 0 -Exactly
            Start-AgentViewRefresh $tray -Manual
            $tray.State.Loading | Should Be $true
            $tray.Animation.Interval | Should Be 125
            $tray.Animation.Running | Should Be $true
            $rows = @(Wait-AdaptiveRefresh $tray); $rows[0].Error | Should Be 'True'
            Assert-MockCalled Update-AgentViewPopup -Times 1 -Exactly -ParameterFilter {$Loading}
            Assert-MockCalled Update-AgentViewWidget -Times 1 -Exactly -ParameterFilter {$Loading}
            $tray.State.Last = [datetime]::MinValue
            Start-AgentViewRefresh $tray
            $tray.State.Loading | Should Be $true
            $rows = @(Wait-AdaptiveRefresh $tray); $rows[0].Error | Should Be 'False'
        } finally { Reset-AgentViewRefreshRunspace $tray.State }
    }
    It 'supports old quota commands without a Manual parameter' {
        $path = Join-Path $TestDrive 'old-quota.ps1'
        [IO.File]::WriteAllText($path, 'function Set-AgentViewLanguage($Language) {}; function Get-AgentQuotas { [CmdletBinding()] param() [pscustomobject]@{Provider="codex";Ok=$false;Error="old"} }')
        $tray = New-AdaptiveTray $path
        try {
            Start-AgentViewRefresh $tray -Manual
            $rows = @(Wait-AdaptiveRefresh $tray); $rows[0].Error | Should Be 'old'
        } finally { Reset-AgentViewRefreshRunspace $tray.State }
    }
    It 'stops critical blinking after sixty seconds and restarts only on entry or manual refresh' {
        $now = [datetime]'2026-11-20T12:00:00'
        $tray = New-AdaptiveTray ''; $s=$tray.State
        $row=New-TestRow 95 0
        Complete-AgentViewRefresh $tray @($row) $now
        $s.CritUntil | Should Be $now.AddSeconds(60)
        $tray.Animation.Interval | Should Be 400
        Update-AgentViewCriticalAnimation $tray $now.AddSeconds(59)
        $s.Frame | Should Be 1
        Update-AgentViewCriticalAnimation $tray $now.AddSeconds(60)
        $tray.Animation.Running | Should Be $false; $s.Frame | Should Be 0
        Complete-AgentViewRefresh $tray @($row) $now.AddSeconds(90)
        $tray.Animation.Running | Should Be $false
        $s.Manual=$true
        Complete-AgentViewRefresh $tray @($row) $now.AddSeconds(100)
        $s.CritUntil | Should Be $now.AddSeconds(160)
        $s.Manual=$false
        Complete-AgentViewRefresh $tray @((New-TestRow 10 0)) $now.AddSeconds(110)
        Complete-AgentViewRefresh $tray @($row) $now.AddSeconds(120)
        $s.CritUntil | Should Be $now.AddSeconds(180)
    }
}
