function Get-AgentViewSettings([string]$Path = (Join-Path $env:LOCALAPPDATA 'agent-view/settings.json')) {
    $s = [pscustomobject]@{WidgetEnabled=$false;WidgetEdge='right';WidgetOffset=$null;WidgetScreen=$null;Language='auto';RefreshSeconds=120;NotifyEnabled=$true;NotifyThresholds=@(30,10);NotifyReset=$true;UpdateCheck=$true;HiddenProviders=@()}
    try {
        $v = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (($v.RefreshSeconds -is [int] -or $v.RefreshSeconds -is [long]) -and $v.RefreshSeconds -in @(60,120,300)) { $s.RefreshSeconds=[int]$v.RefreshSeconds }
        if ($v.UpdateCheck -is [bool]) { $s.UpdateCheck=$v.UpdateCheck }
        if ($v.NotifyEnabled -is [bool]) { $s.NotifyEnabled=$v.NotifyEnabled }
        if ($v.NotifyReset -is [bool]) { $s.NotifyReset=$v.NotifyReset }
        if ($v.NotifyThresholds -is [array] -and $v.NotifyThresholds.Count -eq 2) {
            $valid = @($v.NotifyThresholds | Where-Object { ($_ -is [int] -or $_ -is [long]) -and $_ -ge 5 -and $_ -le 90 })
            if ($valid.Count -eq 2 -and $valid[0] -gt $valid[1]) { $s.NotifyThresholds=@([int]$valid[0],[int]$valid[1]) }
        }
        if ($v.HiddenProviders -is [array]) {
            $hidden = @($v.HiddenProviders | Where-Object { $_ -is [string] -and $_ -cin @('claude','codex') } | Select-Object -Unique)
            if ($hidden.Count -lt 2 -and $hidden.Count -eq $v.HiddenProviders.Count) { $s.HiddenProviders=$hidden }
        }
        if ($v.WidgetEnabled -is [bool]) { $s.WidgetEnabled=$v.WidgetEnabled }
        if ($v.Language -in @('auto','vi','en')) { $s.Language=$v.Language }
        if ($v.WidgetEdge -in @('right','left','top')) { $s.WidgetEdge=$v.WidgetEdge }
        if ($null -ne $v.WidgetOffset -and $v.WidgetOffset -is [ValueType] -and -not [double]::IsNaN([double]$v.WidgetOffset) -and -not [double]::IsInfinity([double]$v.WidgetOffset)) { $s.WidgetOffset=[double]$v.WidgetOffset }
        if ($v.WidgetScreen -is [string]) { $s.WidgetScreen=$v.WidgetScreen }
    } catch { }
    $s
}
function Save-AgentViewSettings($Settings, [string]$Path = (Join-Path $env:LOCALAPPDATA 'agent-view/settings.json')) {
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
        [IO.File]::WriteAllText($temp, ($Settings | ConvertTo-Json), (New-Object Text.UTF8Encoding $true))
        Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
