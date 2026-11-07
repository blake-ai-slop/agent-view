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
    if ($minutes -lt 60) { return "còn ${minutes}p" }
    if ($minutes -lt 1440) { return ('còn {0}g {1:00}p' -f [math]::Floor($minutes/60),($minutes%60)) }
    return ('còn {0} ngày {1}g' -f [math]::Floor($minutes/1440),[math]::Floor(($minutes%1440)/60))
}
function Format-QuotaResetAbsolute($At, [datetime]$Now = (Get-Date)) {
    if ($null -eq $At) { return $null }
    $date = [datetime]$At
    if ($date.Date -eq $Now.Date) { return $date.ToString('HH:mm') }
    return (@('CN','T2','T3','T4','T5','T6','T7')[[int]$date.DayOfWeek] + ' ' + $date.ToString('dd/MM HH:mm'))
}
function Format-QuotaAgo($FetchedAt, [datetime]$Now = (Get-Date)) {
    if ($null -eq $FetchedAt) { return $null }
    $seconds = [math]::Max(0, ($Now-([datetime]$FetchedAt)).TotalSeconds)
    if ($seconds -lt 45) { return 'vừa xong' }
    if ($seconds -lt 3600) { return ('{0} phút trước' -f [math]::Max(1,[math]::Floor($seconds/60))) }
    return ('{0} giờ trước' -f [math]::Floor($seconds/3600))
}
function Get-QuotaStatusText($Level) {
    switch ($Level) { ok { 'Thoải mái' } warn { 'Nên chậm lại' } crit { 'Sắp cạn' } default { 'Không rõ' } }
}
function Get-QuotaTightestWindow($Row) {
    if ($null -eq $Row.FiveHourUsed) { if ($null -ne $Row.WeekUsed) { return 'Tuần' }; return $null }
    if ($null -eq $Row.WeekUsed) { return '5 giờ' }
    if ($Row.FiveHourUsed -ge $Row.WeekUsed) { return '5 giờ' }
    return 'Tuần'
}
