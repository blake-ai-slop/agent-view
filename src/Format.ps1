. (Join-Path $PSScriptRoot 'I18n.ps1')
Register-AgentViewStrings -Module 'format' -Strings @{
    en = @{
        'days' = 'Sun,Mon,Tue,Wed,Thu,Fri,Sat'

        'in_m' = 'in {0}m'
        'in_h_m' = 'in {0}h {1:00}m'
        'in_d_h' = 'in {0}d {1}h'
        'just_now' = 'just now'
        'min_ago' = '{0} min ago'
        'h_ago' = '{0}h ago'
        'comfortable' = 'Comfortable'
        'slow_down' = 'Slow down'
        'running_low' = 'Running low'
        'unknown' = 'Unknown'
        'week' = 'Week'
        '5_hours' = '5 hours'
    }
    vi = @{
        'days' = 'CN,T2,T3,T4,T5,T6,T7'

        'in_m' = 'còn {0}p'
        'in_h_m' = 'còn {0}g {1:00}p'
        'in_d_h' = 'còn {0} ngày {1}g'
        'just_now' = 'vừa xong'
        'min_ago' = '{0} phút trước'
        'h_ago' = '{0} giờ trước'
        'comfortable' = 'Thoải mái'
        'slow_down' = 'Nên chậm lại'
        'running_low' = 'Sắp cạn'
        'unknown' = 'Không rõ'
        'week' = 'Tuần'
        '5_hours' = '5 giờ'
    }
}
# Emit individual rows; callers capture the pipeline with @(...).
function ConvertTo-QuotaRows($Result) {
    if ($null -eq $Result) { return }
    if ($Result -is [System.Collections.IEnumerable] -and $Result -isnot [string] -and $Result -isnot [System.Collections.IDictionary]) {
        foreach ($child in $Result) { ConvertTo-QuotaRows $child }
    } else { $Result }
}
function Get-QuotaRemaining($Row) {
    $values = @($Row.FiveHourUsed, $Row.WeekUsed | Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    return [int](100 - ($values | Measure-Object -Maximum).Maximum)
}
function Get-QuotaLevel($Remaining) {
    if ($null -eq $Remaining) { return 'unk' }
    if ($Remaining -gt 30) { return 'ok' }
    if ($Remaining -gt 10) { return 'warn' }
    return 'crit'
}
function Format-QuotaResetRelative($At, [datetime]$Now = (Get-Date)) {
    if ($null -eq $At) { return $null }
    $minutes = [int][math]::Floor([math]::Max(0, (([datetime]$At)-$Now).TotalMinutes))
    if ($minutes -lt 60) { return (T 'format.in_m' -Args @($minutes)) }
    if ($minutes -lt 1440) { return ((T 'format.in_h_m') -f [math]::Floor($minutes/60),($minutes%60)) }
    return ((T 'format.in_d_h') -f [math]::Floor($minutes/1440),[math]::Floor(($minutes%1440)/60))
}
function Format-QuotaResetAbsolute($At, [datetime]$Now = (Get-Date)) {
    if ($null -eq $At) { return $null }
    $date = [datetime]$At
    if ($date.Date -eq $Now.Date) { return $date.ToString('HH:mm') }
    return (((T 'format.days') -split ',')[[int]$date.DayOfWeek] + ' ' + $date.ToString('dd/MM HH:mm'))
}
function Format-QuotaAgo($FetchedAt, [datetime]$Now = (Get-Date)) {
    if ($null -eq $FetchedAt) { return $null }
    $seconds = [math]::Max(0, ($Now-([datetime]$FetchedAt)).TotalSeconds)
    if ($seconds -lt 45) { return (T 'format.just_now') }
    if ($seconds -lt 3600) { return ((T 'format.min_ago') -f [math]::Max(1,[math]::Floor($seconds/60))) }
    return ((T 'format.h_ago') -f [math]::Floor($seconds/3600))
}
function Get-QuotaStatusText($Level) {
    switch ($Level) { ok { (T 'format.comfortable') } warn { (T 'format.slow_down') } crit { (T 'format.running_low') } default { (T 'format.unknown') } }
}
function Get-QuotaTightestWindow($Row) {
    if ($null -eq $Row.FiveHourUsed) { if ($null -ne $Row.WeekUsed) { return (T 'format.week') }; return $null }
    if ($null -eq $Row.WeekUsed) { return (T 'format.5_hours') }
    if ($Row.FiveHourUsed -ge $Row.WeekUsed) { return (T 'format.5_hours') }
    return (T 'format.week')
}
