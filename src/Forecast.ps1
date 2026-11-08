# Dự báo hết quota từ lịch sử (thuần). Mẫu theo History.ps1: p, w, u, t (ISO UTC), r (ISO UTC | null).
if (Get-Command Register-AgentViewStrings -ErrorAction SilentlyContinue) {
    Register-AgentViewStrings -Module 'forecast' -Strings @{
        en = @{ runout = 'Runs out ~{0}'; enough = 'Enough until reset'; unknown = 'Not enough data yet' }
        vi = @{ runout = 'Hết lúc ~{0}'; enough = 'Đủ tới lúc reset'; unknown = 'Chưa đủ dữ liệu' }
    }
}

function ConvertTo-AgentViewForecastUtc($Value) {
    if ($null -eq $Value -or '' -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    try { return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } catch { return $null }
}

# => @{ Kind = 'runout'|'enough'|'unknown'; At = [datetime] giờ địa phương | $null; RatePerHour = %/giờ | $null }
function Get-AgentViewForecast($Samples, $Used, $ResetsAt, [ValidateSet('5h','week')][string]$Window = '5h', [datetime]$Now = (Get-Date)) {
    if ($null -ne $Used -and [double]$Used -ge 100) { return @{ Kind = 'runout'; At = $Now; RatePerHour = $null } }
    $unknown = @{ Kind = 'unknown'; At = $null; RatePerHour = $null }
    if ($null -eq $Used) { return $unknown }
    $nowUtc = $Now.ToUniversalTime()
    $resetUtc = ConvertTo-AgentViewForecastUtc $ResetsAt
    $lookback = if ($Window -eq '5h') { $nowUtc.AddMinutes(-60) } else { $nowUtc.AddHours(-24) }
    $xs = New-Object System.Collections.Generic.List[double]
    $ys = New-Object System.Collections.Generic.List[double]
    # Chuỗi chuẩn yyyy-MM-ddTHH:mm:ssZ (History.ps1): so chuỗi để bỏ nhanh mẫu ngoài khung, ParseExact thay Parse; resets_at lặp lại ⇒ nhớ.
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $fmt = 'yyyy-MM-ddTHH:mm:ssZ'
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $fromText = $lookback.ToString($fmt, $inv); $toText = $nowUtc.AddSeconds(1).ToString($fmt, $inv)
    $d = [datetime]::MinValue
    $rCache = @{}
    foreach ($s in @($Samples)) {
        if ($null -eq $s -or $null -eq $s.u) { continue }
        $tv = $s.t
        if ($tv -is [string] -and $tv.Length -eq 20 -and $tv[10] -eq 'T' -and $tv[19] -eq 'Z' -and $tv[4] -eq '-') {
            if ([string]::CompareOrdinal($tv, $fromText) -lt 0 -or [string]::CompareOrdinal($tv, $toText) -gt 0) { continue }
            if ([datetime]::TryParseExact($tv, $fmt, $inv, $styles, [ref]$d)) { $t = $d } else { $t = ConvertTo-AgentViewForecastUtc $tv }
        } else { $t = ConvertTo-AgentViewForecastUtc $tv }
        if ($null -eq $t -or $t -lt $lookback -or $t -gt $nowUtc) { continue }
        $rv = $s.r
        if ($rv -is [string]) {
            if ($rCache.ContainsKey($rv)) { $r = $rCache[$rv] } else { $r = ConvertTo-AgentViewForecastUtc $rv; $rCache[$rv] = $r }
        } else { $r = ConvertTo-AgentViewForecastUtc $rv }
        # Cùng chu kỳ: cùng resets_at (cho lệch ≤2 phút vì provider có thể làm tròn khác nhau giữa các lần đọc), hoặc cùng null.
        if ($null -eq $resetUtc) { if ($null -ne $r) { continue } }
        elseif ($null -eq $r -or [math]::Abs(($r - $resetUtc).TotalMinutes) -gt 2) { continue }
        $xs.Add(($t - $nowUtc).TotalHours); $ys.Add([double]$s.u)
    }
    $n = $xs.Count
    if ($n -lt 3) { return $unknown }
    $min = [double]::MaxValue; $max = [double]::MinValue; $mx = 0.0; $my = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        if ($xs[$i] -lt $min) { $min = $xs[$i] }
        if ($xs[$i] -gt $max) { $max = $xs[$i] }
        $mx += $xs[$i]; $my += $ys[$i]
    }
    if (($max - $min) * 60 -lt 10) { return $unknown }
    $mx /= $n; $my /= $n
    $sxy = 0.0; $sxx = 0.0
    for ($i = 0; $i -lt $n; $i++) { $sxy += ($xs[$i] - $mx) * ($ys[$i] - $my); $sxx += ($xs[$i] - $mx) * ($xs[$i] - $mx) }
    $rate = $sxy / $sxx
    if ($rate -le 0) { return @{ Kind = 'unknown'; At = $null; RatePerHour = $rate } }
    $hours = (100 - [double]$Used) / $rate
    $limit = if ($null -ne $resetUtc) { $resetUtc } else { $nowUtc.AddDays(7) }
    if ($hours -ge ($limit - $nowUtc).TotalHours) { return @{ Kind = 'enough'; At = $null; RatePerHour = $rate } }
    return @{ Kind = 'runout'; At = $nowUtc.AddHours($hours).ToLocalTime(); RatePerHour = $rate }
}

# Chuỗi hiển thị qua Get-AgentViewText. Cùng ngày ⇒ HH:mm; khác ngày ⇒ Format-QuotaResetAbsolute (Format.ps1).
function Format-AgentViewForecast($Forecast, [datetime]$Now = (Get-Date)) {
    $kind = if ($null -ne $Forecast) { $Forecast.Kind } else { 'unknown' }
    if ($kind -eq 'runout' -and $null -ne $Forecast.At) {
        $at = [datetime]$Forecast.At
        if ($at.Kind -eq [DateTimeKind]::Utc) { $at = $at.ToLocalTime() }
        if ($at.Date -eq $Now.Date) { $text = $at.ToString('HH:mm') }
        elseif (Get-Command Format-QuotaResetAbsolute -ErrorAction SilentlyContinue) { $text = Format-QuotaResetAbsolute $at $Now }
        else { $text = $at.ToString('dd/MM HH:mm') }
        return (Get-AgentViewText -Key 'forecast.runout' -Args @($text))
    }
    if ($kind -eq 'enough') { return (Get-AgentViewText -Key 'forecast.enough') }
    return (Get-AgentViewText -Key 'forecast.unknown')
}
