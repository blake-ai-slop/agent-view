$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here/../src/I18n.ps1"
. "$here/../src/Format.ps1"
. "$here/../src/Quota.ps1"
. "$here/../src/History.ps1"
. "$here/../src/Forecast.ps1"
Set-AgentViewLanguage en
$script:TestStrings = [AppDomain]::CurrentDomain.GetData('agent-view.strings')

$utc = { param($s) [datetime]::SpecifyKind([datetime]$s, [DateTimeKind]::Utc) }
# Mẫu đều: bắt đầu $Start% lúc Now-$Minutes, tăng $RatePerHour %/giờ, mỗi $Step phút.
function New-Samples([datetime]$Now, $Minutes, $Step, $Start, $RatePerHour, $Reset) {
    $r = if ($null -ne $Reset) { ([datetime]$Reset).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
    for ($m = $Minutes; $m -ge 0; $m -= $Step) {
        [pscustomobject]@{ p = 'claude'; w = '5h'; u = $Start + $RatePerHour * ($Minutes - $m) / 60.0
            t = $Now.AddMinutes(-$m).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); r = $r }
    }
}

Describe 'Get-AgentViewForecast' {
    $now = (& $utc '2026-11-07T10:00:00').ToLocalTime()
    $reset = $now.AddHours(4)
    It 'linear rate gives runout At within one minute' {
        $s = @(New-Samples $now 30 5 40 20 $reset)     # 40% → 50% trong 30 phút = 20%/giờ
        $f = Get-AgentViewForecast -Samples $s -Used 50 -ResetsAt $reset -Window '5h' -Now $now
        $f.Kind | Should Be 'runout'
        [math]::Abs($f.RatePerHour - 20) -lt 0.001 | Should Be $true
        [math]::Abs(($f.At - $now.AddHours(2.5)).TotalMinutes) -le 1 | Should Be $true
    }
    It 'enough vs runout around ResetsAt' {
        $s = @(New-Samples $now 30 5 40 20 $reset)
        $late = $now.AddHours(2.5).AddMinutes(-2)
        (Get-AgentViewForecast -Samples @(New-Samples $now 30 5 40 20 $late) -Used 50 -ResetsAt $late -Window '5h' -Now $now).Kind | Should Be 'enough'
        $later = $now.AddHours(2.5).AddMinutes(2)
        (Get-AgentViewForecast -Samples @(New-Samples $now 30 5 40 20 $later) -Used 50 -ResetsAt $later -Window '5h' -Now $now).Kind | Should Be 'runout'
    }
    It 'null ResetsAt uses null-cycle samples and a 7-day horizon' {
        $wk = { param($rate) @(New-Samples $now 600 60 10 $rate $null | ForEach-Object { $_.w = 'week'; $_ }) }
        (Get-AgentViewForecast -Samples (& $wk 0.5) -Used 15 -ResetsAt $null -Window 'week' -Now $now).Kind | Should Be 'enough'   # 170 giờ
        (Get-AgentViewForecast -Samples (& $wk 1) -Used 20 -ResetsAt $null -Window 'week' -Now $now).Kind | Should Be 'runout'     # 80 giờ
        (Get-AgentViewForecast -Samples @(New-Samples $now 30 5 40 20 $reset) -Used 50 -ResetsAt $null -Window '5h' -Now $now).Kind | Should Be 'unknown'
    }
    It 'ignores samples from the previous cycle and outside the lookback' {
        $oldReset = $now.AddMinutes(-20)
        $old = @(New-Samples $now.AddMinutes(-25) 30 5 60 80 $oldReset)    # chu kỳ cũ, tốc độ khác
        $cur = @(New-Samples $now 15 5 0 20 $reset)
        $f = Get-AgentViewForecast -Samples ($old + $cur) -Used 5 -ResetsAt $reset -Window '5h' -Now $now
        [math]::Abs($f.RatePerHour - 20) -lt 0.001 | Should Be $true
        # Mẫu cũ hơn 60 phút (5h) bị bỏ ⇒ chỉ còn 2 mẫu
        $stale = @(New-Samples $now.AddMinutes(-70) 30 5 0 20 $reset) + @(New-Samples $now 5 5 30 20 $reset)
        (Get-AgentViewForecast -Samples $stale -Used 32 -ResetsAt $reset -Window '5h' -Now $now).Kind | Should Be 'unknown'
        # Tuần nhìn lại 24 giờ: cùng mẫu đó vẫn dùng được
        (Get-AgentViewForecast -Samples $stale -Used 32 -ResetsAt $reset -Window 'week' -Now $now).Kind | Should Be 'runout'
        # resets_at lệch vài giây giữa các lần đọc vẫn cùng chu kỳ
        (Get-AgentViewForecast -Samples @(New-Samples $now 30 5 40 20 $reset.AddSeconds(30)) -Used 50 -ResetsAt $reset -Window '5h' -Now $now).Kind | Should Be 'runout'
    }
    It 'zero or negative rate is unknown' {
        (Get-AgentViewForecast -Samples @(New-Samples $now 30 5 40 0 $reset) -Used 40 -ResetsAt $reset -Window '5h' -Now $now).Kind | Should Be 'unknown'
        $neg = Get-AgentViewForecast -Samples @(New-Samples $now 30 5 40 (-10) $reset) -Used 35 -ResetsAt $reset -Window '5h' -Now $now
        $neg.Kind | Should Be 'unknown'; ($null -eq $neg.At) | Should Be $true
    }
    It 'fewer than 3 samples or a span under 10 minutes is unknown' {
        (Get-AgentViewForecast -Samples @(New-Samples $now 30 30 40 20 $reset) -Used 50 -ResetsAt $reset -Window '5h' -Now $now).Kind | Should Be 'unknown'
        (Get-AgentViewForecast -Samples @(New-Samples $now 9 3 40 20 $reset) -Used 50 -ResetsAt $reset -Window '5h' -Now $now).Kind | Should Be 'unknown'
        (Get-AgentViewForecast -Samples @(New-Samples $now 10 5 40 20 $reset) -Used 50 -ResetsAt $reset -Window '5h' -Now $now).Kind | Should Be 'runout'
        (Get-AgentViewForecast -Samples @() -Used 50 -ResetsAt $reset -Window '5h' -Now $now).Kind | Should Be 'unknown'
        (Get-AgentViewForecast -Samples $null -Used 50 -ResetsAt $reset -Window '5h' -Now $now).Kind | Should Be 'unknown'
    }
    It 'Used >= 100 is runout now' {
        $f = Get-AgentViewForecast -Samples @() -Used 100 -ResetsAt $reset -Window '5h' -Now $now
        $f.Kind | Should Be 'runout'; $f.At | Should Be $now
    }
    It 'works on real rows through ConvertTo-QuotaRows and the history file' {
        $data = ConvertFrom-ClaudeConfigText ([IO.File]::ReadAllText("$here\fixtures\claude.json"))
        $row = @(ConvertTo-QuotaRows @(New-AgentQuota 'claude' 'Claude Code' $data $null $data.FetchedAt))[0]
        $t0 = $data.FetchedAt.AddMinutes(-30)
        $path = Join-Path $TestDrive 'history.json'
        for ($i = 0; $i -le 6; $i++) {
            $r = [pscustomobject]@{ Provider = $row.Provider; Ok = $true; FiveHourUsed = $row.FiveHourUsed + $i
                WeekUsed = $row.WeekUsed; FiveHourResetsAt = $row.FiveHourResetsAt; WeekResetsAt = $row.WeekResetsAt }
            Add-AgentViewHistory -Rows @(ConvertTo-QuotaRows @($r)) -Now $t0.AddMinutes(5 * $i) -Path $path
        }
        $s = @(Get-AgentViewHistory -Path $path | Where-Object { $_.p -eq 'claude' -and $_.w -eq '5h' })
        $s.Count | Should Be 7
        $f = Get-AgentViewForecast -Samples $s -Used ($row.FiveHourUsed + 6) -ResetsAt $row.FiveHourResetsAt -Window '5h' -Now $t0.AddMinutes(30)
        [math]::Abs($f.RatePerHour - 12) -lt 0.001 | Should Be $true
        $f.Kind | Should Match '^(runout|enough)$'
        $w = Get-AgentViewForecast -Samples @(Get-AgentViewHistory -Path $path | Where-Object { $_.w -eq 'week' }) -Used $row.WeekUsed -ResetsAt $row.WeekResetsAt -Window 'week' -Now $t0.AddMinutes(30)
        $w.Kind | Should Be 'unknown'   # tuần không đổi ⇒ tốc độ 0
    }
}

Describe 'Format-AgentViewForecast' {
    $now = [datetime]'2026-11-07T10:00:00'
    It 'registers en/vi strings for the forecast module' {
        $script:TestStrings['forecast'].en.runout | Should Be 'Runs out ~{0}'
        $script:TestStrings['forecast'].vi.runout | Should Be 'Hết lúc ~{0}'
        $script:TestStrings['forecast'].vi.enough | Should Be 'Đủ tới lúc reset'
        $script:TestStrings['forecast'].vi.unknown | Should Be 'Chưa đủ dữ liệu'
    }
    It 'formats each kind' {
        Set-AgentViewLanguage en
        Format-AgentViewForecast @{ Kind = 'runout'; At = $now.AddMinutes(150) } -Now $now | Should Be 'Runs out ~12:30'
        Format-AgentViewForecast @{ Kind = 'runout'; At = [datetime]'2026-11-12T09:00:00' } -Now $now | Should Be ('Runs out ~' + (Format-QuotaResetAbsolute ([datetime]'2026-11-12T09:00:00') $now))
        Format-AgentViewForecast @{ Kind = 'enough' } -Now $now | Should Be 'Enough until reset'
        Format-AgentViewForecast @{ Kind = 'unknown' } -Now $now | Should Be 'Not enough data yet'
        Format-AgentViewForecast $null -Now $now | Should Be 'Not enough data yet'
        Set-AgentViewLanguage vi
        Format-AgentViewForecast @{ Kind = 'runout'; At = $now.AddMinutes(5) } -Now $now | Should Be 'Hết lúc ~10:05'
        Format-AgentViewForecast @{ Kind = 'enough' } -Now $now | Should Be 'Đủ tới lúc reset'
        Set-AgentViewLanguage en
    }
    It 'dot-sources without i18n loaded' {
        $ps = [PowerShell]::Create()
        try {
            [void]$ps.AddScript(". '$here\..\src\Forecast.ps1'; . '$here\..\src\History.ps1'; 'ok'")
            $ps.Invoke() | Should Be 'ok'
            $ps.HadErrors | Should Be $false
        } finally { $ps.Dispose() }
    }
}

Describe 'Forecast on thinned history (v0.2.2)' {
    It 'gives the same 5h forecast and the same week verdict as on the dense samples' {
        $now = (& $utc '2026-11-07T10:00:30').ToLocalTime()
        $path = Join-Path $TestDrive 'thin-forecast.json'
        $five = $now.AddMinutes(170); $week = $now.AddDays(2)
        $dense5 = New-Object System.Collections.Generic.List[object]; $denseW = New-Object System.Collections.Generic.List[object]
        for ($m = 2 * 24 * 60; $m -ge 0; $m -= 2) {
            $t = $now.AddMinutes(-$m)
            $u5 = [math]::Round(30 + 18 * (2880 - $m) / 2880.0 + ($m % 7) / 10.0, 2); $uw = [math]::Round(20 + 15 * (2880 - $m) / 2880.0, 2)
            $row = [pscustomobject]@{ Provider = 'claude'; Ok = $true; FiveHourUsed = $u5; WeekUsed = $uw; FiveHourResetsAt = $five; WeekResetsAt = $week }
            Add-AgentViewHistory -Rows @($row) -Now $t -Path $path
            $ts = $t.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $dense5.Add([pscustomobject]@{ p = 'claude'; w = '5h'; u = $u5; t = $ts; r = $five.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') })
            $denseW.Add([pscustomobject]@{ p = 'claude'; w = 'week'; u = $uw; t = $ts; r = $week.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') })
        }
        $idx = Get-AgentViewHistoryIndex -Path $path
        $idx['claude|week'].Count | Should BeLessThan ($denseW.Count / 3)
        $a = Get-AgentViewForecast -Samples $dense5.ToArray() -Used 48 -ResetsAt $five -Window '5h' -Now $now
        $b = Get-AgentViewForecast -Samples $idx['claude|5h'] -Used 48 -ResetsAt $five -Window '5h' -Now $now
        $b.Kind | Should Be $a.Kind
        $b.RatePerHour | Should Be $a.RatePerHour
        $b.At | Should Be $a.At
        $c = Get-AgentViewForecast -Samples $denseW.ToArray() -Used 35 -ResetsAt $week -Window 'week' -Now $now
        $d = Get-AgentViewForecast -Samples $idx['claude|week'] -Used 35 -ResetsAt $week -Window 'week' -Now $now
        $d.Kind | Should Be $c.Kind
        [math]::Abs($d.RatePerHour - $c.RatePerHour) -lt 0.02 | Should Be $true
    }
}
