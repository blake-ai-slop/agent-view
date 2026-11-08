$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here/../src/History.ps1"

function New-TestRow($Provider = 'claude', $Five = 40, $Week = 10, $FiveReset = $null, $WeekReset = $null, $Ok = $true) {
    [pscustomobject]@{ Provider = $Provider; Name = ('secret' + '@' + 'example.com'); Ok = $Ok; Error = $null
        FiveHourUsed = $Five; WeekUsed = $Week; FiveHourResetsAt = $FiveReset; WeekResetsAt = $WeekReset; FetchedAt = $null }
}

Describe 'Add-AgentViewHistory / Get-AgentViewHistory' {
    $now = [datetime]::SpecifyKind([datetime]'2026-11-07T10:00:20', [DateTimeKind]::Utc)
    It 'records one sample per numeric window with ISO UTC times and nothing else' {
        $path = Join-Path $TestDrive 'a\history.json'
        $reset = [datetime]::SpecifyKind([datetime]'2026-11-07T13:00:00', [DateTimeKind]::Utc).ToLocalTime()
        Add-AgentViewHistory -Rows @((New-TestRow -FiveReset $reset), (New-TestRow 'codex' $null 55), (New-TestRow 'x' 1 1 -Ok $false)) -Now $now -Path $path
        $h = @(Get-AgentViewHistory -Path $path)
        $h.Count | Should Be 3
        $h[0].p | Should Be 'claude'; $h[0].w | Should Be '5h'; $h[0].u | Should Be 40
        $h[0].t | Should Be '2026-11-07T10:00:20Z'; $h[0].r | Should Be '2026-11-07T13:00:00Z'
        ($null -eq $h[1].r) | Should Be $true
        $h[2].p | Should Be 'codex'; $h[2].w | Should Be 'week'
        $text = [IO.File]::ReadAllText($path)
        $text | Should Not Match 'secret'
        $text | Should Not Match 'Name'
    }
    It 'keeps at most one sample per minute per window' {
        $path = Join-Path $TestDrive 'dup.json'
        Add-AgentViewHistory -Rows (New-TestRow) -Now $now -Path $path
        Add-AgentViewHistory -Rows (New-TestRow -Five 41) -Now $now.AddSeconds(30) -Path $path
        @(Get-AgentViewHistory -Path $path).Count | Should Be 2
        Add-AgentViewHistory -Rows (New-TestRow -Five 42) -Now $now.AddSeconds(40) -Path $path
        $h = @(Get-AgentViewHistory -Path $path)
        $h.Count | Should Be 4
        @($h | Where-Object { $_.w -eq '5h' } | ForEach-Object { $_.u }) -join ',' | Should Be '40,42'
    }
    It 'drops samples older than 8 days' {
        $path = Join-Path $TestDrive 'old.json'
        Add-AgentViewHistory -Rows (New-TestRow -Five 1) -Now $now.AddDays(-8).AddMinutes(-1) -Path $path
        Add-AgentViewHistory -Rows (New-TestRow -Five 2) -Now $now.AddDays(-7) -Path $path
        Add-AgentViewHistory -Rows (New-TestRow -Five 3) -Now $now -Path $path
        @(Get-AgentViewHistory -Path $path | Where-Object { $_.w -eq '5h' } | ForEach-Object { $_.u }) -join ',' | Should Be '2,3'
    }
    It 'starts over from a corrupt file without throwing' {
        $path = Join-Path $TestDrive 'bad.json'
        [IO.File]::WriteAllText($path, '{not json')
        @(Get-AgentViewHistory -Path $path).Count | Should Be 0
        { Add-AgentViewHistory -Rows (New-TestRow) -Now $now -Path $path } | Should Not Throw
        @(Get-AgentViewHistory -Path $path).Count | Should Be 2
        [IO.File]::WriteAllText($path, '[{"p":"claude","w":"bogus","u":1,"t":"2026-11-07T10:00:00Z"},{"p":"claude","w":"5h","u":"x","t":"2026-11-07T10:00:00Z"},5]')
        @(Get-AgentViewHistory -Path $path).Count | Should Be 0
        @(Get-AgentViewHistory -Path (Join-Path $TestDrive 'missing.json')).Count | Should Be 0
    }
    Context 'atomic write (Mock scoped here)' {
        It 'writes atomically: a failed move keeps the old file and leaves no temp file' {
            $path = Join-Path $TestDrive 'atomic\history.json'
            Add-AgentViewHistory -Rows (New-TestRow) -Now $now -Path $path
            $before = [IO.File]::ReadAllText($path)
            Mock Move-Item { throw 'disk full' }
            { Add-AgentViewHistory -Rows (New-TestRow -Five 90) -Now $now.AddMinutes(5) -Path $path } | Should Not Throw
            [IO.File]::ReadAllText($path) | Should Be $before
            @(Get-ChildItem (Split-Path $path) -Filter '*.tmp').Count | Should Be 0
            Assert-MockCalled Move-Item -Times 1
        }
    }
    It 'writes a JSON array even with a single sample and with none' {
        $path = Join-Path $TestDrive 'one.json'
        Add-AgentViewHistory -Rows (New-TestRow 'claude' 5 $null) -Now $now -Path $path
        [IO.File]::ReadAllText($path).TrimStart() | Should Match '^\['
        @(Get-AgentViewHistory -Path $path).Count | Should Be 1
        $empty = Join-Path $TestDrive 'empty.json'
        Add-AgentViewHistory -Rows @() -Now $now -Path $empty
        [IO.File]::ReadAllText($empty) | Should Be '[]'
    }
    It 'defaults to LOCALAPPDATA\agent-view\history.json' {
        Get-AgentViewHistoryPath | Should Be (Join-Path $env:LOCALAPPDATA 'agent-view\history.json')
    }
}
