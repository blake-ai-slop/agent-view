$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here/../src/I18n.ps1"
. "$here/../src/Format.ps1"
. "$here/../src/Quota.ps1"
. "$here/../src/Notify.ps1"
Set-AgentViewLanguage en
$script:TestStrings = [AppDomain]::CurrentDomain.GetData('agent-view.strings')

$script:Now = [datetime]::SpecifyKind([datetime]'2026-11-07T10:00:00', [DateTimeKind]::Utc).ToLocalTime()
$script:Reset1 = [datetime]::SpecifyKind([datetime]'2026-11-07T12:00:00', [DateTimeKind]::Utc)
$script:Reset2 = [datetime]::SpecifyKind([datetime]'2026-11-07T17:00:00', [DateTimeKind]::Utc)

# Row thật qua New-AgentQuota + ConvertTo-QuotaRows.
function New-Row([string]$Provider = 'claude', $FiveUsed = $null, $FiveReset = $null, $WeekUsed = $null, $WeekReset = $null, [string]$ErrorText) {
    $name = if ($Provider -eq 'claude') { 'Claude Code' } else { 'Codex' }
    $data = $null
    if ($null -ne $FiveUsed -or $null -ne $WeekUsed) {
        $data = [pscustomobject]@{ FiveHour = $FiveUsed; FiveHourResetsAt = $FiveReset; Week = $WeekUsed; WeekResetsAt = $WeekReset }
    }
    @(ConvertTo-QuotaRows @(New-AgentQuota $Provider $name $data $ErrorText $script:Now))
}
function Step($Rows, $State, $Settings = @{}, $Minutes = 0) {
    Get-AgentViewNotifications -Rows $Rows -State $State -Settings $Settings -Now $script:Now.AddMinutes($Minutes)
}

Describe 'Get-AgentViewNotifications' {
    It 'low thresholds 30 then 10 fire exactly once each across refreshes' {
        $s = $null; $all = @()
        $i = 0
        foreach ($used in @(50, 65, 71, 75, 80, 88, 91, 95, 99)) {
            $r = Step (New-Row -FiveUsed $used -FiveReset $script:Reset1) $s @{} ($i++)
            $all += $r.Notifications; $s = $r.State
        }
        $all.Count | Should Be 2
        $all[0].Kind | Should Be 'low'; $all[0].Remaining | Should Be 29; $all[0].Threshold | Should Be 30
        $all[0].Title | Should Be 'Claude Code: 29% left'
        $all[0].Text | Should Match '^5-hour limit · resets '
        $all[1].Remaining | Should Be 9; $all[1].Threshold | Should Be 10
        $all[0].Window | Should Be '5h'; $all[0].Provider | Should Be 'claude'
    }
    It 'crossing two thresholds at once reports only the lowest and marks both' {
        $r = Step (New-Row -FiveUsed 50 -FiveReset $script:Reset1) $null
        $r.Notifications.Count | Should Be 0
        $r = Step (New-Row -FiveUsed 95 -FiveReset $script:Reset1) $r.State @{} 1
        $r.Notifications.Count | Should Be 1
        $r.Notifications[0].Threshold | Should Be 10
        $r = Step (New-Row -FiveUsed 75 -FiveReset $script:Reset1) $r.State @{} 2   # lên lại 25 nhưng cùng chu kỳ
        $r.Notifications.Count | Should Be 0
    }
    It 'first run reports low but never reset' {
        $r = Step (New-Row -FiveUsed 80 -FiveReset $script:Reset1 -WeekUsed 10) $null
        @($r.Notifications | Where-Object { $_.Kind -eq 'reset' }).Count | Should Be 0
        @($r.Notifications | Where-Object { $_.Kind -eq 'low' }).Count | Should Be 1
    }
    It 'new cycle reports reset once only when the previous cycle went low' {
        # Chu kỳ chưa từng thấp ⇒ không báo
        $r = Step (New-Row -FiveUsed 50 -FiveReset $script:Reset1) $null
        $r = Step (New-Row -FiveUsed 2 -FiveReset $script:Reset2) $r.State @{} 1
        $r.Notifications.Count | Should Be 0
        # Từng thấp rồi khóa đổi ⇒ báo 1 lần
        $r = Step (New-Row -FiveUsed 85 -FiveReset $script:Reset1) $null
        $r = Step (New-Row -FiveUsed 1 -FiveReset $script:Reset2) $r.State @{} 1
        $r.Notifications.Count | Should Be 1
        $r.Notifications[0].Kind | Should Be 'reset'
        $r.Notifications[0].Title | Should Be 'Claude Code: full again'
        $r.Notifications[0].Text | Should Be '5-hour limit · 99% left'
        $r.Notifications[0].Text | Should Not Match 'Claude'
        $r = Step (New-Row -FiveUsed 3 -FiveReset $script:Reset2) $r.State @{} 2
        $r.Notifications.Count | Should Be 0
        # Cùng khóa nhưng còn lại tăng ≥50 (resets_at null) ⇒ cũng là chu kỳ mới
        $r = Step (New-Row -WeekUsed 75) $null
        $r = Step (New-Row -WeekUsed 20) $r.State @{} 1
        @($r.Notifications | Where-Object { $_.Kind -eq 'reset' -and $_.Window -eq 'week' }).Count | Should Be 1
        # Ngưỡng low mở lại trong chu kỳ mới
        $r = Step (New-Row -WeekUsed 72) $r.State @{} 2
        @($r.Notifications | Where-Object { $_.Kind -eq 'low' }).Count | Should Be 1
        # NotifyReset=false ⇒ không báo reset
        $r = Step (New-Row -FiveUsed 85 -FiveReset $script:Reset1) $null
        (Step (New-Row -FiveUsed 1 -FiveReset $script:Reset2) $r.State @{ NotifyReset = $false } 1).Notifications.Count | Should Be 0
    }
    It 'resets_at jitter within the same minute keeps the cycle' {
        $r = Step (New-Row -FiveUsed 85 -FiveReset $script:Reset1) $null
        $r = Step (New-Row -FiveUsed 86 -FiveReset $script:Reset1.AddSeconds(20).ToString('o')) $r.State @{} 1
        $r.Notifications.Count | Should Be 0
    }
    It 'hidden provider is skipped and keeps its old state' {
        $r = Step @((New-Row -FiveUsed 50 -FiveReset $script:Reset1), (New-Row 'codex' -FiveUsed 50)) $null
        $r = Step @((New-Row -FiveUsed 80 -FiveReset $script:Reset1), (New-Row 'codex' -FiveUsed 80)) $r.State @{ HiddenProviders = @('codex') } 1
        $r.Notifications.Count | Should Be 1
        $r.Notifications[0].Provider | Should Be 'claude'
        $r.State.w['codex|5h'].r | Should Be 50
    }
    It 'NotifyEnabled=false emits nothing but still updates state' {
        $r = Step (New-Row -FiveUsed 50 -FiveReset $script:Reset1) $null
        $r = Step (New-Row -FiveUsed 95 -FiveReset $script:Reset1) $r.State @{ NotifyEnabled = $false } 1
        $r.Notifications.Count | Should Be 0
        $r.State.w['claude|5h'].r | Should Be 5
        @($r.State.w['claude|5h'].n) -contains 10 | Should Be $true
        (Step (New-Row -FiveUsed 96 -FiveReset $script:Reset1) $r.State @{} 2).Notifications.Count | Should Be 0
    }
    It 'error rows are skipped and keep previous state' {
        $r = Step (New-Row -FiveUsed 50 -FiveReset $script:Reset1) $null
        $before = $r.State.w['claude|5h'].t
        $r = Step (New-Row -ErrorText 'boom') $r.State @{} 5
        $r.Notifications.Count | Should Be 0
        $r.State.w['claude|5h'].r | Should Be 50
        $r.State.w['claude|5h'].t | Should Be $before
    }
    It 'null window (provider without 5h) only tracks the existing window' {
        $r = Step (New-Row 'codex' -WeekUsed 75 -WeekReset $script:Reset2) $null
        $r.State.w.ContainsKey('codex|5h') | Should Be $false
        $r.Notifications.Count | Should Be 1
        $r.Notifications[0].Window | Should Be 'week'
        $r.Notifications[0].Text | Should Match '^Weekly limit · resets '
        $r.Notifications[0].Key | Should Be 'codex|week|2026-11-07T17:00Z|low30'
    }
    It 'custom thresholds and missing settings use defaults' {
        $r = Step (New-Row -FiveUsed 45 -FiveReset $script:Reset1) $null ([pscustomobject]@{ NotifyThresholds = @(10, 60) })
        $r.Notifications.Count | Should Be 1; $r.Notifications[0].Threshold | Should Be 60
        (Step (New-Row -FiveUsed 75 -FiveReset $script:Reset1) $null $null).Notifications[0].Threshold | Should Be 30
    }
    It 'prunes state entries unseen for more than 8 days' {
        $old = $script:Now.AddDays(-9).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $state = @{ v = 1; w = @{ 'gone|5h' = @{ k = 'gone|5h|none'; r = 5; n = @(30, 10); low = $true; t = $old } } }
        $r = Step (New-Row -FiveUsed 10 -FiveReset $script:Reset1) $state
        $r.State.w.ContainsKey('gone|5h') | Should Be $false
        $r.State.w.ContainsKey('claude|5h') | Should Be $true
        $state.w.ContainsKey('gone|5h') | Should Be $true   # không sửa object của caller
    }
    It 'uses vi strings' {
        Set-AgentViewLanguage vi
        try {
            $r = Step (New-Row -FiveUsed 75 -FiveReset $script:Reset1) $null
            $r.Notifications[0].Title | Should Be 'Claude Code: còn 25%'
            $r.Notifications[0].Text | Should Match '^Giới hạn 5 giờ · reset '
            $r = Step (New-Row -WeekUsed 85 -WeekReset $script:Reset1) $null
            $r = Step (New-Row -WeekUsed 0 -WeekReset $script:Reset2) $r.State @{} 1
            $r.Notifications[0].Kind | Should Be 'reset'
            $r.Notifications[0].Title | Should Be 'Claude Code: đã đầy lại'
            $r.Notifications[0].Text | Should Be 'Giới hạn tuần · còn 100%'
        } finally { Set-AgentViewLanguage en }
    }
}

Describe 'Notify state file' {
    It 'round-trips through disk and continues without duplicate alerts' {
        $path = Join-Path $TestDrive 'a\notify-state.json'
        $r = Step (New-Row -FiveUsed 75 -FiveReset $script:Reset1 -WeekUsed 95 -WeekReset $script:Reset2) $null
        $r.Notifications.Count | Should Be 2
        Save-AgentViewNotifyState $r.State -Path $path
        @(Get-ChildItem (Split-Path $path) -Filter '*.tmp').Count | Should Be 0
        $raw = Get-Content -LiteralPath $path -Raw
        $raw | Should Not Match 'Claude Code'
        $loaded = Read-AgentViewNotifyState -Path $path
        $loaded.w['claude|week'].n.Count | Should Be 2
        $loaded.w['claude|5h'].low | Should Be $true
        (Step (New-Row -FiveUsed 76 -FiveReset $script:Reset1 -WeekUsed 96 -WeekReset $script:Reset2) $loaded @{} 1).Notifications.Count | Should Be 0
        $r2 = Step (New-Row -FiveUsed 1 -FiveReset $script:Reset2 -WeekUsed 96 -WeekReset $script:Reset2) $loaded @{} 2
        @($r2.Notifications | Where-Object { $_.Kind -eq 'reset' }).Count | Should Be 1
    }
    It 'missing, corrupt or wrong-shape files read as null' {
        Read-AgentViewNotifyState -Path (Join-Path $TestDrive 'none.json') | Should Be $null
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $bad -Value '{ not json'
        Read-AgentViewNotifyState -Path $bad | Should Be $null
        Set-Content -LiteralPath $bad -Value '[1,2]'
        Read-AgentViewNotifyState -Path $bad | Should Be $null
        Set-Content -LiteralPath $bad -Value '{"v":1,"w":{"x|5h":{"k":5},"claude|5h":{"k":"claude|5h|none","r":40,"n":[30],"low":true,"t":"2026-11-07T10:00:00Z"}}}'
        $s = Read-AgentViewNotifyState -Path $bad
        $s.w.ContainsKey('x|5h') | Should Be $false
        $s.w['claude|5h'].r | Should Be 40
    }
}
