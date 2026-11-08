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
