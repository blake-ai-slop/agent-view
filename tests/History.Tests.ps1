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

Describe 'History cache, thinning, throttled writes (v0.2.2)' {
    $now = [datetime]::SpecifyKind([datetime]'2026-11-07T10:00:20', [DateTimeKind]::Utc)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    function Write-RawHistory([string]$Path, [datetime]$From, [int]$Count, [int]$StepMinutes = 2) {
        $parts = for ($i = 0; $i -lt $Count; $i++) {
            $t = $From.AddMinutes($StepMinutes * $i).ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
            '{"p":"claude","w":"5h","u":' + $i + ',"t":"' + $t + '","r":"2026-11-07T13:00:00Z"}'
        }
        [void][IO.Directory]::CreateDirectory((Split-Path $Path))
        [IO.File]::WriteAllText($Path, '[' + ($parts -join ',') + ']')
    }
    It 'parses the file once while it is unchanged and reloads when it changes on disk' {
        $path = Join-Path $TestDrive 'cache\history.json'
        Write-RawHistory $path $now.AddMinutes(-30) 10
        @(Get-AgentViewHistory -Path $path).Count | Should Be 10
        @(Get-AgentViewHistory -Path $path).Count | Should Be 10
        $null = Get-AgentViewHistoryIndex -Path $path
        Get-AgentViewHistoryLoadCount -Path $path | Should Be 1
        Add-AgentViewHistory -Rows (New-TestRow) -Now $now -Path $path      # tự ghi file ⇒ không parse lại
        @(Get-AgentViewHistory -Path $path).Count | Should Be 12
        Get-AgentViewHistoryLoadCount -Path $path | Should Be 1
        Write-RawHistory $path $now.AddMinutes(-10) 3                       # file đổi ngoài app ⇒ nạp lại
        @(Get-AgentViewHistory -Path $path).Count | Should Be 3
        Get-AgentViewHistoryLoadCount -Path $path | Should Be 2
    }
    It 'indexes samples by provider|window in time order' {
        $path = Join-Path $TestDrive 'index.json'
        Add-AgentViewHistory -Rows @((New-TestRow), (New-TestRow 'codex' 7 8)) -Now $now -Path $path
        Add-AgentViewHistory -Rows @((New-TestRow -Five 41)) -Now $now.AddMinutes(1) -Path $path
        $idx = Get-AgentViewHistoryIndex -Path $path
        @($idx.Keys | Sort-Object) -join ',' | Should Be 'claude|5h,claude|week,codex|5h,codex|week'
        @($idx['claude|5h'] | ForEach-Object { $_.u }) -join ',' | Should Be '40,41'
        $idx['codex|week'][0].u | Should Be 8
    }
    It 'keeps one sample per minute within 2 hours and the first per 10 minutes per provider+window before that' {
        $path = Join-Path $TestDrive 'thin.json'
        $start = $now.AddHours(-5)
        for ($m = 0; $m -le 300; $m++) { Add-AgentViewHistory -Rows (New-TestRow -Five ($m % 100) -Week 1) -Now $start.AddMinutes($m) -Path $path }
        $idx = Get-AgentViewHistoryIndex -Path $path
        $boundary = $now.AddHours(-2)
        foreach ($k in 'claude|5h', 'claude|week') {
            $ts = @($idx[$k] | ForEach-Object { [datetime]::ParseExact($_.t, 'yyyy-MM-ddTHH:mm:ssZ', $inv, [Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal') })
            @($ts | Where-Object { $_ -ge $boundary }).Count | Should Be 121          # 08:00:20 .. 10:00:20, mỗi phút
            $old = @($ts | Where-Object { $_ -lt $boundary })
            $old.Count | Should Be 18                                                # 05:00 .. 07:59: 18 ô 10 phút
            @($old | ForEach-Object { $_.ToString('HH:mm:ss') })[0..2] -join ',' | Should Be '05:00:20,05:10:20,05:20:20'
        }
        # Ghi ra đĩa (flush) rồi nạp lại từ đầu: y nguyên.
        Save-AgentViewHistory -Path $path | Out-Null
        Clear-AgentViewHistoryCache
        @(Get-AgentViewHistory -Path $path).Count | Should Be 278
    }
    It 'thins an old-format dense file on load and drops > 8 days on the next add' {
        $path = Join-Path $TestDrive 'dense\history.json'
        Write-RawHistory $path $now.AddDays(-9) (9 * 24 * 30)                   # 9 ngày, 2 phút/mẫu (dạng file v0.2.1)
        $h = @(Get-AgentViewHistory -Path $path)
        # mẫu cuối 10:00:20 − 2 phút; 2 giờ cuối giữ cả (61 mẫu), trước đó 1 mẫu/ô 10 phút
        $h.Count | Should Be (61 + (9 * 24 * 6 - 12))
        Add-AgentViewHistory -Rows @() -Now $now -Path $path
        $h = @(Get-AgentViewHistory -Path $path)
        $cut = $now.AddDays(-8).ToString('yyyy-MM-ddTHH:mm:ssZ', $inv)
        @($h | Where-Object { [string]::CompareOrdinal($_.t, $cut) -lt 0 }).Count | Should Be 0
        $h.Count | Should BeLessThan (8 * 24 * 6 + 62)
    }
    It 'reads v0.2.1 files (unsorted, null resets, non-canonical times) and writes files v0.2.1 can read' {
        $path = Join-Path $TestDrive 'compat\history.json'
        [void][IO.Directory]::CreateDirectory((Split-Path $path))
        [IO.File]::WriteAllText($path, '[{"p":"claude","w":"week","u":12.5,"t":"2026-11-07T09:58:00Z","r":null},{"p":"claude","w":"week","u":12,"t":"2026-11-07T09:57:00Z","r":"2026-11-10T08:15:00Z"},{"p":"codex","w":"5h","u":3,"t":"2026-11-07T17:59:00+08:00","r":"2026-11-07T12:00:00.000Z"}]')
        $h = @(Get-AgentViewHistory -Path $path)
        $h.Count | Should Be 3
        @($h | Where-Object { $_.p -eq 'claude' } | ForEach-Object { $_.u }) -join ',' | Should Be '12,12.5'
        $codex = @($h | Where-Object { $_.p -eq 'codex' })[0]
        $codex.t | Should Be '2026-11-07T09:59:00Z'; $codex.r | Should Be '2026-11-07T12:00:00Z'
        Add-AgentViewHistory -Rows (New-TestRow 'claude' 40 13) -Now $now -Path $path
        # Bản cũ đọc bằng ConvertFrom-Json: mảng mẫu đủ p/w/u/t/r, không thêm trường.
        $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($path)); $raw = @($parsed)
        $raw.Count | Should Be 5
        foreach ($s in $raw) { (@($s.PSObject.Properties.Name) -join ',') | Should Be 'p,w,u,t,r' }
        @($raw | Where-Object { $_.w -eq 'week' -and $null -eq $_.r }).Count | Should Be 2   # mẫu cũ r=null + mẫu mới không có reset
        ($raw | Where-Object { $_.u -eq 12.5 }).t | Should Be '2026-11-07T09:58:00Z'
    }
    It 'throttles disk writes to once per 5 minutes and flushes on Save-AgentViewHistory' {
        $path = Join-Path $TestDrive 'throttle\history.json'
        $countFile = { $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($path)); @($parsed).Count }
        Add-AgentViewHistory -Rows (New-TestRow) -Now $now -Path $path           # lần đầu trong phiên: ghi ngay
        & $countFile | Should Be 2
        Add-AgentViewHistory -Rows (New-TestRow) -Now $now.AddMinutes(1) -Path $path
        Add-AgentViewHistory -Rows (New-TestRow) -Now $now.AddMinutes(4) -Path $path
        & $countFile | Should Be 2
        @(Get-AgentViewHistory -Path $path).Count | Should Be 6                 # bộ nhớ đã có, chưa ghi
        Add-AgentViewHistory -Rows (New-TestRow) -Now $now.AddMinutes(5) -Path $path
        & $countFile | Should Be 8
        Add-AgentViewHistory -Rows (New-TestRow) -Now $now.AddMinutes(6) -Path $path
        & $countFile | Should Be 8
        Save-AgentViewHistory -Path $path | Should Be $true                     # thoát app
        & $countFile | Should Be 10
        Save-AgentViewHistory -Path $path | Should Be $false                    # không có gì mới
        Get-AgentViewHistoryLoadCount -Path $path | Should Be 1
    }
    It 'flushes history in the tray teardown' {
        $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\src\Tray.ps1'))
        $teardown = $text.Substring($text.IndexOf('function Start-AgentView {'))
        $teardown = $teardown.Substring($teardown.IndexOf('finally {'))
        $teardown | Should Match 'Save-AgentViewHistory'
    }
}
