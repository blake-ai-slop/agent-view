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
        $bad = New-TestRow $null $null $false; $bad.Error='x'*200
        (Format-QuotaTooltip @($bad)).Length | Should Be 63
        Format-QuotaTooltip @($bad) | Should Match '^agent-view|^Claude : x'
        Format-QuotaTooltip @($bad) | Should Match 'Claude : '
    }
    It 'keeps five multi-provider rows within the 63-char NotifyIcon limit grouped by family' {
        $codex = New-TestRow 5 0; $codex.Provider='codex'; $codex.Name='Codex'
        $groups = foreach ($g in @(@('gemini',30,'Gemini 3 Pro (High) and an extremely long model group label'), @('3p',55,'Claude Sonnet / GPT-OSS with a very long descriptive name'), @('argon',80,'Argon experimental group with long name'))) {
            $r = New-TestRow $g[1] $null; $r.Provider = 'antigravity-' + $g[0]; $r.Name = 'Antigravity · ' + $g[2]
            $r | Add-Member -NotePropertyName Family -NotePropertyValue 'antigravity'; $r | Add-Member -NotePropertyName Group -NotePropertyValue $g[2]; $r }
        $rows = @((New-TestRow 28 0), $codex) + @($groups)
        $rows.Count | Should Be 5
        $tip = Format-QuotaTooltip $rows
        $tip | Should Be "agent-view`nClaude 72%`nCodex 95%`nAntigravity 20% (3 nhóm)"
        $tip.Length | Should BeLessThan 64
        # Một Family lỗi dài 200 ký tự ⇒ vẫn ≤63 và giữ % của mọi Family còn lại.
        $mixed = @($rows | ForEach-Object { $_.PSObject.Copy() }); $mixed[1].Ok = $false; $mixed[1].Error = 'z' * 200
        $tip = Format-QuotaTooltip $mixed
        $tip.Length | Should BeLessThan 64
        $tip | Should Match 'Claude 72%'; $tip | Should Match 'Antigravity 20%'; $tip | Should Match 'Codex : z+…'
        # Toàn lỗi với thông báo dài ⇒ vẫn ≤63, mọi Family còn tên.
        $errs = foreach ($r in $rows) { $e = $r.PSObject.Copy(); $e.Ok = $false; $e.Error = 'không đọc được quota vì một lỗi rất dài ' + ('y' * 200); $e }
        $tip = Format-QuotaTooltip $errs
        $tip.Length | Should BeLessThan 64
        foreach ($n in 'Claude','Codex','Antigravity') { $tip | Should Match $n }
        Set-AgentViewLanguage en
        try {
            Format-QuotaTooltip $rows | Should Match 'Antigravity 20% \(3 groups\)'
            $tip = Format-QuotaTooltip $mixed
            $tip.Length | Should BeLessThan 64; $tip | Should Match 'Claude 72%'; $tip | Should Match 'Antigravity 20%'
        } finally { Set-AgentViewLanguage vi }
    }
    It 'assigns every tooltip to a real NotifyIcon without throwing (vi + en)' {
        $codex = New-TestRow 5 0; $codex.Provider='codex'; $codex.Name='Codex'
        $ag = foreach ($g in 'gemini','3p','argon') { $r = New-TestRow 40 $null; $r.Provider = "antigravity-$g"; $r.Name = "Antigravity · $g with a very very long label"; $r | Add-Member -NotePropertyName Family -NotePropertyValue 'antigravity'; $r }
        $five = @((New-TestRow 28 0), $codex) + @($ag)
        $bad = New-TestRow $null $null $false; $bad.Error = 'x' * 200
        $allBad = foreach ($r in $five) { $e = $r.PSObject.Copy(); $e.Ok = $false; $e.Error = 'e' * 200; $e }
        $icon = New-Object Windows.Forms.NotifyIcon
        try {
            { $icon.Text = 'x' * 64 } | Should Throw          # giới hạn thật của .NET Framework
            foreach ($lang in 'vi','en') {
                Set-AgentViewLanguage $lang
                foreach ($text in @((Format-QuotaTooltip $five), (Format-QuotaTooltip @($bad)), (Format-QuotaTooltip $allBad), (Get-AgentViewTrayText @{ NoAgent = $true; View = @() }), (T 'tray.updating_quota'))) {
                    { $icon.Text = $text } | Should Not Throw
                    $icon.Text | Should Be $text
                }
                Set-AgentViewTrayText $icon ('y' * 300) | Should Be $true
                $icon.Text.Length | Should Be 63
                Set-AgentViewTrayText $icon (Get-AgentViewTrayText @{ NoAgent = $true; View = @() }) | Should Be $true
                $icon.Text | Should Be (T 'tray.no_agent')
            }
            Set-AgentViewTrayText $null 'x' | Should Be $false
        } finally { $icon.Dispose(); Set-AgentViewLanguage vi }
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
        # Mọi provider đều bị ẩn (settings cũ claude+codex) ⇒ hiện lại tất cả.
        @(Select-AgentViewVisibleRows $rows ([pscustomobject]@{HiddenProviders=@('claude','codex')})).Count | Should Be 2
        $ag = New-TestRow 50 0; $ag.Provider='antigravity-argon'; $ag | Add-Member -NotePropertyName Family -NotePropertyValue 'antigravity'
        @(Select-AgentViewVisibleRows @($rows + $ag) @{HiddenProviders=@('antigravity')} | ForEach-Object Provider) -join ',' | Should Be 'claude,codex'
        @(Select-AgentViewVisibleRows @($rows + $ag) @{HiddenProviders=@('antigravity-argon')} | ForEach-Object Provider) -join ',' | Should Be 'claude,codex'
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

Describe 'Provider wiring (v0.3.0)' {
    $savedPresence = [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence')
    $savedLocal = $env:LOCALAPPDATA
    function Set-Presence($Families) {
        $state = [hashtable]::Synchronized(@{})
        if ($null -ne $Families) { $state['Families'] = [string[]]@($Families) }
        [AppDomain]::CurrentDomain.SetData('agent-view.ProviderPresence', $state)
    }
    BeforeEach {
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force)
    }
    It 'exposes the provider view for popup/widget/settings' {
        Set-Presence $null
        $v = Get-AgentViewProviderView ([pscustomobject]@{HiddenProviders=@('codex')})
        $v.Detected.Count | Should Be 0; $v.NoAgent | Should Be $false
        Set-Presence @()
        (Get-AgentViewProviderView $null).NoAgent | Should Be $true
        Set-Presence @('claude','codex','antigravity')
        $v = Get-AgentViewProviderView @{HiddenProviders=@('antigravity-argon','codex')}
        ($v.Detected -join ',') | Should Be 'claude,codex,antigravity'
        ($v.Hidden -join ',') | Should Be 'antigravity-argon,codex'
        $v.NoAgent | Should Be $false
        Set-Presence @('claude','codex')
        @((Get-AgentViewProviderView @{HiddenProviders=@('claude','codex')}).Hidden).Count | Should Be 0
    }
    It 'draws a grey dash icon when no agent is detected' {
        (Get-QuotaIconLayout 16 $null -NoAgent).Label | Should Be '–'
        (Get-QuotaIconLayout 16 $null).Label | Should Be '?'
        (Get-QuotaIconLayout 16 $null -NoAgent -Loading).Label | Should Be ''
        $bmp = New-QuotaIconBitmap @() -Size 16 -NoAgent
        try { $bmp.Width | Should Be 16 } finally { $bmp.Dispose() }
        Get-AgentViewTrayText @{ NoAgent = $true; View = @() } | Should Be 'Chưa phát hiện agent nào (Claude Code, Codex, Antigravity)'
    }
    It 'records new families and toasts only when KnownProviders was not empty' {
        $r = Get-AgentViewProviderAdditions @() @('claude','codex')
        ($r.Added -join ',') | Should Be 'claude,codex'; $r.Notify | Should Be $false
        $r = Get-AgentViewProviderAdditions @('claude','codex') @('claude','codex','antigravity')
        ($r.Added -join ',') | Should Be 'antigravity'; ($r.Known -join ',') | Should Be 'claude,codex,antigravity'; $r.Notify | Should Be $true
        (Get-AgentViewProviderAdditions @('claude') @('claude')).Added.Count | Should Be 0
    }
    Context 'adds a newly installed family,' {
        It 'adds a newly installed family, unhides it, saves settings and shows one toast' {
            Mock Show-AgentViewNotification { 'toast' }
            Set-Presence @('claude','codex','antigravity')
            $settings = [pscustomobject]@{ HiddenProviders = @('antigravity','codex-x'); KnownProviders = @('claude','codex'); Language = 'vi' }
            $tray = @{ State = @{ Last = Get-Date }; Notify = $null; OpenSettings = { 'settings' } }
            $r = Update-AgentViewKnownProviders $tray $settings
            ($settings.KnownProviders -join ',') | Should Be 'claude,codex,antigravity'
            ($settings.HiddenProviders -join ',') | Should Be 'codex-x'
            $r.Shown | Should Be 'toast'
            ($tray.State.Last -lt (Get-Date).AddMinutes(-30)) | Should Be $true
            Assert-MockCalled Show-AgentViewNotification -Times 1 -Exactly -ParameterFilter { $Balloon.Count -eq 1 -and $Balloon.Title -eq 'Đã thêm Antigravity' -and $Balloon.Text -eq 'Ẩn trong Cài đặt' -and $Balloon.Items[0].Kind -eq 'update' }
            $saved = Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'agent-view/settings.json') -Raw | ConvertFrom-Json
            ($saved.KnownProviders -join ',') | Should Be 'claude,codex,antigravity'
            # Lần sau không còn gì mới ⇒ không toast.
            $null = Update-AgentViewKnownProviders $tray $settings
            Assert-MockCalled Show-AgentViewNotification -Times 1 -Exactly
        }
    }
    Context 'only records (no toast, keeps ' {
        It 'only records (no toast, keeps hidden) when upgrading from settings without KnownProviders' {
            Mock Show-AgentViewNotification { 'toast' }
            Set-Presence @('claude','codex')
            $settings = @{ HiddenProviders = @('codex') }
            $r = Update-AgentViewKnownProviders @{ State = @{}; Notify = $null } $settings
            $r.Notify | Should Be $false
            ($settings.KnownProviders -join ',') | Should Be 'claude,codex'
            ($settings.HiddenProviders -join ',') | Should Be 'codex'
            Assert-MockCalled Show-AgentViewNotification -Times 0 -Exactly
            Set-Presence $null
            ($null -eq (Update-AgentViewKnownProviders @{ State = @{} } $settings)) | Should Be $true
        }
    }
    It 'opens Settings with current groups and queues a rescan from the button while busy' {
        Set-Presence @('antigravity')
        $tray = @{
            State = @{
                Rows = @(
                    @{ Provider='antigravity-gemini'; Group='Gemini' }
                    @{ Provider='antigravity-3p'; Group='Claude/GPT' }
                    @{ Provider='antigravity-argon'; Group='Argon' }
                )
                Worker = 'busy'; RescanQueued = $false
            }
            Apply = {}
        }
        try {
            Show-AgentViewTraySettings $tray
            $st = Get-AgentViewSettingsWindowState
            ($st.Providers[2].Groups.Box.Content -join ',') | Should Be 'Gemini,Claude/GPT,Argon'
            $st.Ui.Rescan.Visibility | Should Be Visible
            $st.Ui.Rescan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
            $tray.State.RescanQueued | Should Be $true
            [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence').ContainsKey('Families') | Should Be $false
        } finally { Close-AgentViewSettingsWindow -Force }
    }
    It 'opens the popup with a rescan button that queues a rescan while busy' {
        Set-Presence @()
        $tray = @{ State = @{ View = @(); Loading = $false; Worker = 'busy'; RescanQueued = $false }; Begin = { }; OpenSettings = $null; Update = @{ Latest = $null } }
        try {
            Show-AgentViewTrayPopup $tray
            $st = Get-AgentViewPopupState
            $st.NoAgent | Should Be $true
            $st.Empty.RescanBtn.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
            $tray.State.RescanQueued | Should Be $true
            [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence').ContainsKey('Families') | Should Be $false
        } finally { Close-AgentViewPopup -Force; [AppDomain]::CurrentDomain.SetData('agent-view.popup', $null) }
    }
    Context 'rescans by clearing the detect' {
        It 'rescans by clearing the detection cache then refreshing manually, or queues while busy' {
            Mock Start-AgentViewRefresh { }
            Set-Presence @('claude')
            $tray = @{ State = @{ Worker = $null } }
            Invoke-AgentViewProviderRescan $tray | Should Be $true
            ($null -eq [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence')['Families']) | Should Be $true
            Assert-MockCalled Start-AgentViewRefresh -Times 1 -Exactly -ParameterFilter { $Manual }
            $tray.State.Worker = 'busy'
            Invoke-AgentViewProviderRescan $tray | Should Be $false
            $tray.State.RescanQueued | Should Be $true
            Assert-MockCalled Start-AgentViewRefresh -Times 1 -Exactly
        }
    }
    It 'picks up HiddenProviders written by the CLI when the settings file changes' {
        $path = Join-Path $env:LOCALAPPDATA 'agent-view/settings.json'
        $state = @{}; $settings = [pscustomobject]@{ HiddenProviders = @(); KnownProviders = @('claude') }
        Save-AgentViewSettings ([pscustomobject]@{ HiddenProviders = @() }) $path
        Sync-AgentViewSettingsFile $state $settings $path | Should Be $false
        Sync-AgentViewSettingsFile $state $settings $path | Should Be $false
        Save-AgentViewSettings ([pscustomobject]@{ HiddenProviders = @('antigravity'); KnownProviders = @('claude','antigravity') }) $path
        [IO.File]::SetLastWriteTimeUtc($path, (Get-Date).ToUniversalTime().AddSeconds(5))
        Sync-AgentViewSettingsFile $state $settings $path | Should Be $true
        ($settings.HiddenProviders -join ',') | Should Be 'antigravity'
        ($settings.KnownProviders -join ',') | Should Be 'claude,antigravity'
    }
    It 'passes hidden families as -Skip to Get-AgentQuotas in the refresh runspace' {
        $dir = Join-Path $TestDrive ('skip-' + [guid]::NewGuid().ToString('N')); [void](New-Item -ItemType Directory -Path $dir)
        foreach ($f in @('Format.ps1','I18n.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../src/$f") -Destination $dir }
        $quota = Join-Path $dir 'Quota.ps1'
        [IO.File]::WriteAllText($quota, 'function Get-AgentDetectedProviders { param([switch]$Rescan, [hashtable]$Ops) "claude"; "codex"; "antigravity" }; function Get-AgentQuotas { param([hashtable]$Ops, [switch]$Manual, [string[]]$Skip) [pscustomobject]@{Provider="claude";Name="Claude Code";Ok=$false;Error=("skip=" + (@($Skip) -join ","));FiveHourUsed=$null;WeekUsed=$null} }')
        $ws = (Get-AgentViewWidgetState).Settings
        $old = $ws.HiddenProviders
        $tray = @{ State = @{ Rows=@(); View=@(); Worker=$null; Pending=$null; Runspace=$null; QuotaPath=$quota; Last=(Get-Date).AddMinutes(-5); Frame=0; Loading=$false; SettingsStampKnown=$true; SettingsStamp=[IO.File]::GetLastWriteTimeUtc((Join-Path $env:LOCALAPPDATA 'agent-view/settings.json')) }; Notify=$null; Animation=$null }
        try {
            foreach ($case in @(@(@('antigravity','codex-x'), 'skip=antigravity'), @(@('claude','codex','antigravity'), 'skip='), @(@(), 'skip='))) {
                $ws | Add-Member -NotePropertyName HiddenProviders -NotePropertyValue ([string[]]$case[0]) -Force
                Start-AgentViewRefresh $tray
                $sw = [Diagnostics.Stopwatch]::StartNew()
                while (-not $tray.State.Pending.IsCompleted -and $sw.ElapsedMilliseconds -lt 20000) { Start-Sleep -Milliseconds 20 }
                $rows = @(Receive-AgentViewRefresh $tray)
                $rows[0].Error | Should Be $case[1]
            }
        } finally {
            $ws | Add-Member -NotePropertyName HiddenProviders -NotePropertyValue $old -Force
            Reset-AgentViewRefreshRunspace $tray.State
        }
    }
    $env:LOCALAPPDATA = $savedLocal
    [AppDomain]::CurrentDomain.SetData('agent-view.ProviderPresence', $savedPresence)
}
