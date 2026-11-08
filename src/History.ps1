# Lịch sử % đã dùng cho dự báo. Dot-source không side effect.
# Mẫu: { p = provider; w = '5h'|'week'; u = % đã dùng; t = ISO UTC; r = resets_at ISO UTC | null }. Không lưu gì khác.
# v0.2.2: giữ trong bộ nhớ (cache theo path, nạp lại khi mtime/độ dài file đổi), thêm mẫu tại chỗ,
# ghi đĩa tối đa 1 lần/5 phút (Save-AgentViewHistory khi thoát). Mỗi provider+cửa sổ một danh sách theo thời gian.
function Get-AgentViewHistoryPath { Join-Path $env:LOCALAPPDATA 'agent-view\history.json' }

$script:AgentViewHistoryFormat = 'yyyy-MM-ddTHH:mm:ssZ'
$script:AgentViewHistoryStyles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
if ($null -eq $script:AgentViewHistoryCache) { $script:AgentViewHistoryCache = @{} }
$script:AgentViewHistoryWriteEvery = [TimeSpan]::FromMinutes(5)

function ConvertTo-AgentViewUtcText($Value) {
    if ($null -eq $Value -or '' -eq $Value) { return $null }
    $d = ConvertFrom-AgentViewUtcText $Value
    if ($null -eq $d) { return $null }
    return $d.ToString($script:AgentViewHistoryFormat, [Globalization.CultureInfo]::InvariantCulture)
}
# Chuỗi ISO (PS 5.1) hoặc [datetime] (pwsh 7 tự đổi khi ConvertFrom-Json) ⇒ [datetime] UTC. Lạ ⇒ $null.
# Đúng dạng yyyy-MM-ddTHH:mm:ssZ ⇒ ParseExact (nhanh); dạng khác ⇒ DateTimeOffset.Parse như cũ.
function ConvertFrom-AgentViewUtcText($Value) {
    if ($null -eq $Value -or '' -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    $text = [string]$Value
    $d = [datetime]::MinValue
    if ($text.Length -eq 20 -and [datetime]::TryParseExact($text, $script:AgentViewHistoryFormat, [Globalization.CultureInfo]::InvariantCulture, $script:AgentViewHistoryStyles, [ref]$d)) { return $d }
    try { return [DateTimeOffset]::Parse($text, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } catch { return $null }
}
# Chuỗi chuẩn yyyy-MM-ddTHH:mm:ssZ: giữ nguyên (không tạo DateTime); khác ⇒ chuẩn hóa; lạ ⇒ $null.
function ConvertTo-AgentViewCanonicalUtc($Value) {
    if ($Value -is [string] -and $Value.Length -eq 20) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParseExact($Value, $script:AgentViewHistoryFormat, [Globalization.CultureInfo]::InvariantCulture, $script:AgentViewHistoryStyles, [ref]$d)) { return $Value }
    }
    return (ConvertTo-AgentViewUtcText $Value)
}

function Get-AgentViewHistoryStamp([string]$Path) {
    try {
        $fi = New-Object IO.FileInfo $Path
        if (-not $fi.Exists) { return 'none' }
        return ('{0}|{1}' -f $fi.LastWriteTimeUtc.Ticks, $fi.Length)
    } catch { return 'none' }
}

function New-AgentViewHistorySeries { @{ Items = (New-Object 'System.Collections.Generic.List[object]'); Frags = (New-Object 'System.Collections.Generic.List[string]'); Aged = 0 } }

# Đọc + kiểm từng mẫu. Trả OrderedDictionary 'p|w' ⇒ series (theo thời gian, 1 mẫu/phút).
# Mẫu cũ hơn (mẫu mới nhất − 2 giờ) đã thưa 1/10 phút ngay khi nạp (theo nội dung file, không theo đồng hồ).
function Read-AgentViewHistoryFile([string]$Path) {
    $series = New-Object System.Collections.Specialized.OrderedDictionary
    $raw = $null
    try {
        if (-not [IO.File]::Exists($Path)) { return ,$series }
        $text = [IO.File]::ReadAllText($Path)
        try {
            Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
            $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $js.MaxJsonLength = [int]::MaxValue
            $raw = $js.DeserializeObject($text)
        } catch [System.ArgumentException] { return ,$series } catch [System.InvalidOperationException] { return ,$series } catch {
            $raw = $text | ConvertFrom-Json -ErrorAction Stop   # pwsh 7: không có System.Web.Extensions
        }
    } catch { return ,$series }
    if ($null -eq $raw) { return ,$series }
    if ($raw -is [Collections.IDictionary] -or $raw -isnot [Collections.IEnumerable] -or $raw -is [string]) { $raw = ,$raw }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $fmt = $script:AgentViewHistoryFormat; $styles = $script:AgentViewHistoryStyles
    $d = [datetime]::MinValue
    $rCache = @{}
    $groups = @{}; $order = New-Object 'System.Collections.Generic.List[string]'; $max = ''
    foreach ($s in $raw) {
        if ($null -eq $s -or -not ($s -is [Collections.IDictionary] -or $s -is [pscustomobject])) { continue }
        if ($s -is [Collections.IDictionary]) { $p = $s['p']; $w = $s['w']; $u = $s['u']; $t = $s['t']; $r = $s['r'] }
        else { $p = $s.p; $w = $s.w; $u = $s.u; $t = $s.t; $r = $s.r }
        if ($p -isnot [string] -or ($w -ne '5h' -and $w -ne 'week') -or $null -eq $u -or $u -isnot [ValueType]) { continue }
        if (-not ($t -is [string] -and $t.Length -eq 20 -and [datetime]::TryParseExact($t, $fmt, $inv, $styles, [ref]$d))) {
            $t = ConvertTo-AgentViewUtcText $t
            if ($null -eq $t) { continue }
        }
        if ($null -ne $r) {
            if ($r -is [string]) {
                if ($rCache.ContainsKey($r)) { $r = $rCache[$r] }
                else { $key = $r; $r = ConvertTo-AgentViewCanonicalUtc $r; $rCache[$key] = $r }
            } else { $r = ConvertTo-AgentViewCanonicalUtc $r }
        }
        $k = $p + '|' + $w
        $g = $groups[$k]
        if ($null -eq $g) { $g = @{ T = (New-Object 'System.Collections.Generic.List[string]'); S = (New-Object 'System.Collections.Generic.List[object]'); Sorted = $true }; $groups[$k] = $g; $order.Add($k) }
        if ($g.T.Count -gt 0 -and [string]::CompareOrdinal($t, $g.T[$g.T.Count - 1]) -lt 0) { $g.Sorted = $false }
        $g.T.Add($t); $g.S.Add(@($p, $w, [double]$u, $t, $r))
        if ([string]::CompareOrdinal($t, $max) -gt 0) { $max = $t }
    }
    $boundary = ''
    $md = ConvertFrom-AgentViewUtcText $max
    if ($null -ne $md) { $boundary = $md.AddHours(-2).ToString($fmt, $inv) }
    foreach ($k in $order) {
        $g = $groups[$k]
        $ts = $g.T.ToArray(); $ss = $g.S.ToArray()
        if (-not $g.Sorted) { [Array]::Sort([Array]$ts, [Array]$ss, [Collections.IComparer][StringComparer]::Ordinal) }   # ép overload không generic (bản generic chép mảng items)
        $one = New-AgentViewHistorySeries
        $lastMinute = ''; $lastBucket = ''
        for ($i = 0; $i -lt $ts.Length; $i++) {
            $t = $ts[$i]
            if ([string]::CompareOrdinal($t, $boundary) -lt 0) {
                $b = $t.Substring(0, 15)   # ô 10 phút: yyyy-MM-ddTHH:m
                if ($b -eq $lastBucket) { continue }
                $lastBucket = $b; $lastMinute = $t.Substring(0, 16); $one.Aged++
            } else {
                $m = $t.Substring(0, 16)
                if ($m -eq $lastMinute) { continue }
                $lastMinute = $m
            }
            $x = $ss[$i]
            $one.Items.Add([pscustomobject]@{ p = $x[0]; w = $x[1]; u = $x[2]; t = $x[3]; r = $x[4] }); $one.Frags.Add($null)
        }
        $series[$k] = $one
    }
    return ,$series
}

# Cache cho path: tạo/nạp lại khi file đổi ngoài app (mtime/độ dài khác lần đọc/ghi cuối).
function Get-AgentViewHistoryEntry([string]$Path) {
    $stamp = Get-AgentViewHistoryStamp $Path
    $e = $script:AgentViewHistoryCache[$Path]
    if ($null -ne $e -and $e.Stamp -eq $stamp) { return $e }
    $loads = 1; $written = $false; $lastWrite = $null
    if ($null -ne $e) { $loads = $e.Loads + 1; $written = $e.Written; $lastWrite = $e.LastWrite }
    $e = @{ Series = (Read-AgentViewHistoryFile $Path); Stamp = $stamp; Dirty = $false; Written = $written; LastWrite = $lastWrite; Loads = $loads }
    $script:AgentViewHistoryCache[$Path] = $e
    return $e
}

function Get-AgentViewHistory([string]$Path = (Get-AgentViewHistoryPath)) {
    $e = Get-AgentViewHistoryEntry $Path
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($one in $e.Series.Values) { $out.AddRange($one.Items) }
    return $out.ToArray()
}
# Cho popup/widget: hashtable 'provider|cửa sổ' ⇒ mảng mẫu (theo thời gian). Không đọc file nếu không đổi.
function Get-AgentViewHistoryIndex([string]$Path = (Get-AgentViewHistoryPath)) {
    $e = Get-AgentViewHistoryEntry $Path
    $index = @{}
    foreach ($k in $e.Series.Keys) { $index[$k] = $e.Series[$k].Items.ToArray() }
    return $index
}
# Số lần đã parse file cho path (test cache).
function Get-AgentViewHistoryLoadCount([string]$Path = (Get-AgentViewHistoryPath)) {
    $e = $script:AgentViewHistoryCache[$Path]
    if ($null -eq $e) { return 0 }
    return $e.Loads
}
# Bỏ cache (test hoặc khi cần đọc lại từ đầu).
function Clear-AgentViewHistoryCache { $script:AgentViewHistoryCache = @{} }

function ConvertTo-AgentViewJsonString([string]$Text) {
    if ($Text -notmatch '[\\"\x00-\x1f]') { return '"' + $Text + '"' }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($c in $Text.ToCharArray()) {
        if ($c -eq '"') { [void]$sb.Append('\"') }
        elseif ($c -eq '\') { [void]$sb.Append('\\') }
        elseif ([int]$c -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Ghi cache ra đĩa: chuỗi JSON tự dựng (mảnh mỗi mẫu dựng 1 lần), nguyên tử (tạm rồi Move). Không ném.
# Mặc định chỉ ghi khi có thay đổi chưa lưu; -Force ⇒ ghi kể cả khi không đổi. Trả $true khi đã ghi.
function Save-AgentViewHistory([string]$Path = (Get-AgentViewHistoryPath), [switch]$Force, [datetime]$Now = (Get-Date)) {
    $e = $script:AgentViewHistoryCache[$Path]
    if ($null -eq $e) { return $false }
    if (-not $Force -and -not $e.Dirty -and $e.Stamp -ne 'none') { return $false }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($one in $e.Series.Values) {
        $items = $one.Items; $frags = $one.Frags; $head = $null
        # Mảnh chưa dựng = '' (PowerShell đổi $null thành ''); chỉ dựng các ô đó (IndexOf chạy native), rồi nối cả danh sách.
        $i = $frags.IndexOf('')
        while ($i -ge 0) {
            $s = $items[$i]
            if ($null -eq $head) { $head = '{"p":' + (ConvertTo-AgentViewJsonString $s.p) + ',"w":"' + $s.w + '","u":' }
            $r = 'null'; if ($null -ne $s.r) { $r = '"' + $s.r + '"' }
            $frags[$i] = $head + ([double]$s.u).ToString('R', $inv) + ',"t":"' + $s.t + '","r":' + $r + '}'
            if ($i + 1 -ge $frags.Count) { break }
            $i = $frags.IndexOf('', $i + 1)
        }
        $parts.AddRange($frags)
    }
    $json = '[' + [string]::Join(',', $parts) + ']'
    $e.LastWrite = $Now.ToUniversalTime()
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $ok = $false
    try {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
        $e.Stamp = Get-AgentViewHistoryStamp $Path; $e.Dirty = $false; $e.Written = $true; $ok = $true
    } catch {
    } finally {
        if ([IO.File]::Exists($temp)) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    return $ok
}

# Thêm mẫu cho mỗi row Ok và mỗi cửa sổ có số; bỏ mẫu > 8 ngày; ≤2 giờ gần nhất 1 mẫu/phút/cửa sổ,
# cũ hơn 1 mẫu/10 phút/provider+cửa sổ (giữ mẫu đầu mỗi ô). Ghi đĩa: lần đầu trong phiên ngay, sau đó tối đa 1 lần/5 phút
# (theo -Now); còn lại để Save-AgentViewHistory lúc thoát. File hỏng ⇒ bắt đầu lại rỗng. Không ném.
function Add-AgentViewHistory($Rows, [datetime]$Now = (Get-Date), [string]$Path = (Get-AgentViewHistoryPath)) {
    $e = Get-AgentViewHistoryEntry $Path
    $nowUtc = $Now.ToUniversalTime()
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $fmt = $script:AgentViewHistoryFormat
    $nowText = $nowUtc.ToString($fmt, $inv)
    $boundary = $nowUtc.AddHours(-2).ToString($fmt, $inv)
    $cutoff = $nowUtc.AddDays(-8).ToString($fmt, $inv)
    # 1) Mẫu vừa quá 2 giờ: thưa 1/10 phút (dồn tại chỗ, chỉ đoạn mới quá hạn). 2) Cắt > 8 ngày ở đầu danh sách.
    foreach ($one in $e.Series.Values) {
        $items = $one.Items; $frags = $one.Frags
        $wr = $one.Aged; $i = $one.Aged
        $lastBucket = ''; if ($wr -gt 0) { $lastBucket = $items[$wr - 1].t.Substring(0, 15) }
        while ($i -lt $items.Count -and [string]::CompareOrdinal($items[$i].t, $boundary) -lt 0) {
            $b = $items[$i].t.Substring(0, 15)
            if ($b -ne $lastBucket) {
                if ($wr -ne $i) { $items[$wr] = $items[$i]; $frags[$wr] = $frags[$i] }
                $wr++; $lastBucket = $b
            }
            $i++
        }
        if ($i -gt $wr) { $items.RemoveRange($wr, $i - $wr); $frags.RemoveRange($wr, $i - $wr); $e.Dirty = $true }
        $one.Aged = $wr
        $c = 0
        while ($c -lt $items.Count -and [string]::CompareOrdinal($items[$c].t, $cutoff) -lt 0) { $c++ }
        if ($c -gt 0) { $items.RemoveRange(0, $c); $frags.RemoveRange(0, $c); $one.Aged = [math]::Max(0, $one.Aged - $c); $e.Dirty = $true }
    }
    $minute = $nowText.Substring(0, 16)
    foreach ($row in @($Rows)) {
        if ($null -eq $row -or $row.Ok -ne $true -or $row.Provider -isnot [string]) { continue }
        foreach ($w in @(@('5h','FiveHourUsed','FiveHourResetsAt'), @('week','WeekUsed','WeekResetsAt'))) {
            $u = $row.($w[1])
            if ($null -eq $u -or $u -isnot [ValueType]) { continue }
            $k = $row.Provider + '|' + $w[0]
            $one = $e.Series[$k]
            if ($null -eq $one) { $one = New-AgentViewHistorySeries; $e.Series[$k] = $one }
            if ($one.Items.Count -gt 0 -and $one.Items[$one.Items.Count - 1].t.Substring(0, 16) -eq $minute) { continue }
            $one.Items.Add([pscustomobject]@{ p = $row.Provider; w = $w[0]; u = [double]$u; t = $nowText; r = (ConvertTo-AgentViewUtcText $row.($w[2])) })
            $one.Frags.Add($null)
            $e.Dirty = $true
        }
    }
    if (-not $e.Dirty -and $e.Stamp -ne 'none') { return }
    if ($null -ne $e.LastWrite -and [math]::Abs(($nowUtc - $e.LastWrite).TotalMinutes) -lt $script:AgentViewHistoryWriteEvery.TotalMinutes) { return }
    [void](Save-AgentViewHistory -Path $Path -Now $Now -Force)
}
