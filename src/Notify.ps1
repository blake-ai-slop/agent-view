# Quyết định thông báo quota (thuần, không I/O trừ Read/Save state). Dot-source không side effect ngoài đăng ký chuỗi.
# State: @{ v = 1; w = @{ '<provider>|<5h|week>' = @{ k = khóa chu kỳ; r = % còn lại lần trước; n = @(ngưỡng đã báo); low = từng ≤ ngưỡng cao nhất; t = ISO UTC lần thấy cuối } } }
# Khóa chu kỳ = provider|window|resets_at (ISO UTC làm tròn phút; null ⇒ 'none'). Chỉ lưu khóa/ngưỡng/số.
if (Get-Command Register-AgentViewStrings -ErrorAction SilentlyContinue) {
    Register-AgentViewStrings -Module 'notify' -Strings @{
        en = @{ low = '{0}: {1}% left'; limit5h = '5-hour limit'; limitWeek = 'Weekly limit'; resets = '{0} · resets {1}'
                reset_title = '{0}: full again'; reset_text = '{0} · {1}% left' }
        vi = @{ low = '{0}: còn {1}%'; limit5h = 'Giới hạn 5 giờ'; limitWeek = 'Giới hạn tuần'; resets = '{0} · reset {1}'
                reset_title = '{0}: đã đầy lại'; reset_text = '{0} · còn {1}%' }
    }
}

function Get-AgentViewNotifyStatePath { Join-Path $env:LOCALAPPDATA 'agent-view\notify-state.json' }

function ConvertTo-AgentViewNotifyUtc($Value) {
    if ($null -eq $Value -or '' -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    try { return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } catch { return $null }
}

function Get-AgentViewNotifyCycleKey([string]$Provider, [string]$Window, $ResetsAt) {
    $r = ConvertTo-AgentViewNotifyUtc $ResetsAt
    $part = 'none'
    if ($null -ne $r) {
        $r = New-Object DateTime ([long]([math]::Round($r.Ticks / [TimeSpan]::TicksPerMinute) * [TimeSpan]::TicksPerMinute)), ([DateTimeKind]::Utc)
        $part = $r.ToString('yyyy-MM-ddTHH:mmZ', [Globalization.CultureInfo]::InvariantCulture)
    }
    return ('{0}|{1}|{2}' -f $Provider, $Window, $part)
}

function Get-AgentViewNotifySetting($Settings, [string]$Name, $Default) {
    if ($null -eq $Settings) { return $Default }
    $v = $null
    if ($Settings -is [System.Collections.IDictionary]) { if ($Settings.Contains($Name)) { $v = $Settings[$Name] } }
    elseif ($Settings.PSObject.Properties[$Name]) { $v = $Settings.$Name }
    if ($null -eq $v) { return $Default }
    return $v
}

function Get-AgentViewNotifyThresholds($Settings) {
    $raw = Get-AgentViewNotifySetting $Settings 'NotifyThresholds' @(30, 10)
    $out = @()
    foreach ($t in @($raw)) {
        if ($null -eq $t) { continue }
        try { $i = [int]$t } catch { continue }
        if ($i -ge 1 -and $i -le 100 -and $out -notcontains $i) { $out += $i }
    }
    return @($out | Sort-Object -Descending)
}

function Copy-AgentViewNotifyEntry($Entry) {
    return @{ k = [string]$Entry.k; r = [int]$Entry.r; n = @(@($Entry.n) | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ }); low = [bool]$Entry.low; t = [string]$Entry.t }
}

function Get-AgentViewNotifyLabel([string]$Window) {
    if ($Window -eq '5h') { return (Get-AgentViewText -Key 'notify.limit5h') }
    return (Get-AgentViewText -Key 'notify.limitWeek')
}

function Get-AgentViewNotifications($Rows, $State, $Settings, [datetime]$Now = (Get-Date)) {
    $enabled = [bool](Get-AgentViewNotifySetting $Settings 'NotifyEnabled' $true)
    $notifyReset = [bool](Get-AgentViewNotifySetting $Settings 'NotifyReset' $true)
    $hidden = @(Get-AgentViewNotifySetting $Settings 'HiddenProviders' @()) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }
    $thresholds = @(Get-AgentViewNotifyThresholds $Settings)
    $high = if ($thresholds.Count) { $thresholds[0] } else { $null }
    $nowUtc = $Now.ToUniversalTime()
    $nowText = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $firstRun = ($null -eq $State)

    # Chép state cũ (không sửa object của caller), dọn mục không thấy > 8 ngày.
    $windows = @{}
    if (-not $firstRun -and $State.w -is [System.Collections.IDictionary]) {
        $cutoff = $nowUtc.AddDays(-8)
        foreach ($name in @($State.w.Keys)) {
            $e = $State.w[$name]
            if ($null -eq $e) { continue }
            $seen = ConvertTo-AgentViewNotifyUtc $e.t
            if ($null -eq $seen -or $seen -lt $cutoff) { continue }
            $windows[[string]$name] = Copy-AgentViewNotifyEntry $e
        }
    }

    $list = New-Object System.Collections.ArrayList
    $rowList = if (Get-Command ConvertTo-QuotaRows -ErrorAction SilentlyContinue) { @(ConvertTo-QuotaRows $Rows) } else { @($Rows) }
    foreach ($row in $rowList) {
        if ($null -eq $row -or $row.Ok -ne $true -or $row.Provider -isnot [string]) { continue }
        if ($hidden -contains $row.Provider) { continue }
        $display = if ($row.Name) { [string]$row.Name } else { $row.Provider }
        foreach ($w in @(@('5h', 'FiveHourUsed', 'FiveHourResetsAt'), @('week', 'WeekUsed', 'WeekResetsAt'))) {
            $used = $row.($w[1])
            if ($null -eq $used -or $used -isnot [ValueType]) { continue }
            $remaining = [int][math]::Max(0, [math]::Min(100, 100 - [double]$used))
            $slot = '{0}|{1}' -f $row.Provider, $w[0]
            $key = Get-AgentViewNotifyCycleKey $row.Provider $w[0] $row.($w[2])
            $prev = $windows[$slot]
            $entry = $null
            if ($null -ne $prev) {
                $newCycle = ($prev.k -ne $key) -or (($remaining - $prev.r) -ge 50)
                if ($newCycle) {
                    if ($prev.low -and $enabled -and $notifyReset) {
                        # Tiêu đề mang tên provider; nội dung chỉ tên cửa sổ + % còn (không lặp provider).
                        $label = Get-AgentViewNotifyLabel $w[0]
                        [void]$list.Add(@{ Key = ($prev.k + '|reset'); Provider = $row.Provider; Window = $w[0]; Kind = 'reset'; Remaining = $remaining
                            Title = (Get-AgentViewText -Key 'notify.reset_title' -Args @($display)); Text = (Get-AgentViewText -Key 'notify.reset_text' -Args @($label, $remaining)) })
                    }
                } else { $entry = $prev }
            }
            if ($null -eq $entry) { $entry = @{ k = $key; r = $remaining; n = @(); low = $false; t = $nowText } }

            $crossed = @($thresholds | Where-Object { $remaining -le $_ -and $entry.n -notcontains $_ })
            if ($crossed.Count) {
                $lowest = ($crossed | Measure-Object -Minimum).Minimum
                $entry.n = @(@($entry.n) + $crossed | Sort-Object -Descending -Unique)
                if ($enabled) {
                    $limit = Get-AgentViewNotifyLabel $w[0]
                    $resetAt = ConvertTo-AgentViewNotifyUtc $row.($w[2])
                    $text = $limit
                    if ($null -ne $resetAt) {
                        $local = $resetAt.ToLocalTime()
                        $when = if (Get-Command Format-QuotaResetAbsolute -ErrorAction SilentlyContinue) { Format-QuotaResetAbsolute $local $Now } else { $local.ToString('dd/MM HH:mm') }
                        $text = Get-AgentViewText -Key 'notify.resets' -Args @($limit, $when)
                    }
                    [void]$list.Add(@{ Key = ('{0}|low{1}' -f $key, $lowest); Provider = $row.Provider; Window = $w[0]; Kind = 'low'; Remaining = $remaining; Threshold = [int]$lowest
                        Title = (Get-AgentViewText -Key 'notify.low' -Args @($display, $remaining)); Text = $text })
                }
            }
            if ($null -ne $high -and $remaining -le $high) { $entry.low = $true }
            $entry.r = $remaining; $entry.t = $nowText
            $windows[$slot] = $entry
        }
    }
    return @{ Notifications = @($list.ToArray()); State = @{ v = 1; w = $windows } }
}

# File hỏng/thiếu/sai dạng ⇒ $null (caller coi như lần chạy đầu).
function Read-AgentViewNotifyState([string]$Path = (Get-AgentViewNotifyStatePath)) {
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch { return $null }
    if ($raw -isnot [pscustomobject] -or $raw.v -ne 1 -or $null -eq $raw.w -or $raw.w -isnot [pscustomobject]) { return $null }
    $windows = @{}
    foreach ($p in $raw.w.PSObject.Properties) {
        $e = $p.Value
        if ($e -isnot [pscustomobject] -or $e.k -isnot [string] -or $e.r -isnot [ValueType]) { continue }
        $t = ConvertTo-AgentViewNotifyUtc $e.t
        if ($null -eq $t) { continue }
        $windows[$p.Name] = @{ k = $e.k; r = [int]$e.r; n = @(@($e.n) | Where-Object { $_ -is [ValueType] } | ForEach-Object { [int]$_ }); low = [bool]$e.low
            t = $t.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
    }
    return @{ v = 1; w = $windows }
}

# Ghi nguyên tử (tạm rồi Move). Không ném.
function Save-AgentViewNotifyState($State, [string]$Path = (Get-AgentViewNotifyStatePath)) {
    if ($null -eq $State) { return }
    $w = [ordered]@{}
    if ($State.w -is [System.Collections.IDictionary]) {
        foreach ($name in @($State.w.Keys | Sort-Object)) {
            $e = $State.w[$name]
            if ($null -eq $e) { continue }
            $w[[string]$name] = [ordered]@{ k = [string]$e.k; r = [int]$e.r; n = @(@($e.n) | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ }); low = [bool]$e.low; t = [string]$e.t }
        }
    }
    $json = ConvertTo-Json -InputObject ([ordered]@{ v = 1; w = $w }) -Depth 5 -Compress
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
    } catch {
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}
