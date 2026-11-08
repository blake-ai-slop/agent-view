# Lịch sử % đã dùng cho dự báo. Dot-source không side effect.
# Mẫu: { p = provider; w = '5h'|'week'; u = % đã dùng; t = ISO UTC; r = resets_at ISO UTC | null }. Không lưu gì khác.
function Get-AgentViewHistoryPath { Join-Path $env:LOCALAPPDATA 'agent-view\history.json' }

function ConvertTo-AgentViewUtcText($Value) {
    if ($null -eq $Value -or '' -eq $Value) { return $null }
    $d = ConvertFrom-AgentViewUtcText $Value
    if ($null -eq $d) { return $null }
    return $d.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
}
# Chuỗi ISO (PS 5.1) hoặc [datetime] (pwsh 7 tự đổi khi ConvertFrom-Json) ⇒ [datetime] UTC. Lạ ⇒ $null.
function ConvertFrom-AgentViewUtcText($Value) {
    if ($null -eq $Value -or '' -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    try { return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } catch { return $null }
}

function Get-AgentViewHistory([string]$Path = (Get-AgentViewHistoryPath)) {
    $raw = $null
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch { return }
    $out = New-Object System.Collections.ArrayList
    foreach ($s in @($raw)) {
        if ($s -isnot [pscustomobject]) { continue }
        $t = ConvertFrom-AgentViewUtcText $s.t
        if ($null -eq $t -or $s.w -notin @('5h','week') -or $s.p -isnot [string] -or $s.u -isnot [ValueType]) { continue }
        [void]$out.Add([pscustomobject]@{ p = $s.p; w = $s.w; u = [double]$s.u; t = (ConvertTo-AgentViewUtcText $t); r = (ConvertTo-AgentViewUtcText $s.r) })
    }
    return $out.ToArray()
}

# Ghi mẫu cho mỗi row Ok và mỗi cửa sổ có số. Tối đa 1 mẫu/phút/cửa sổ (giữ mẫu đầu), bỏ mẫu > 8 ngày.
# Ghi nguyên tử (tạm rồi Move). File hỏng ⇒ bắt đầu lại rỗng. Không ném.
function Add-AgentViewHistory($Rows, [datetime]$Now = (Get-Date), [string]$Path = (Get-AgentViewHistoryPath)) {
    $nowUtc = $Now.ToUniversalTime()
    $nowText = ConvertTo-AgentViewUtcText $nowUtc
    $cutoff = $nowUtc.AddDays(-8)
    $kept = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($s in (Get-AgentViewHistory $Path)) {
        $t = ConvertFrom-AgentViewUtcText $s.t
        if ($t -lt $cutoff) { continue }
        $key = '{0}|{1}|{2}' -f $s.p, $s.w, $t.ToString('yyyyMMddHHmm')
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$kept.Add($s)
    }
    $minute = $nowUtc.ToString('yyyyMMddHHmm')
    foreach ($row in @($Rows)) {
        if ($null -eq $row -or $row.Ok -ne $true -or $row.Provider -isnot [string]) { continue }
        foreach ($w in @(@('5h','FiveHourUsed','FiveHourResetsAt'), @('week','WeekUsed','WeekResetsAt'))) {
            $u = $row.($w[1])
            if ($null -eq $u -or $u -isnot [ValueType]) { continue }
            $key = '{0}|{1}|{2}' -f $row.Provider, $w[0], $minute
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            [void]$kept.Add([pscustomobject]@{ p = $row.Provider; w = $w[0]; u = [double]$u; t = $nowText; r = (ConvertTo-AgentViewUtcText $row.($w[2])) })
        }
    }
    $json = '[]'
    if ($kept.Count -gt 0) { $json = ConvertTo-Json -InputObject @($kept.ToArray()) -Depth 3 -Compress }
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
