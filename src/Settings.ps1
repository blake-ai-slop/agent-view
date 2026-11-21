# Family hợp lệ lấy từ registry Providers.ps1; bản sao tạm lúc gỡ cài (chỉ chép Settings.ps1) dùng danh sách cũ.
if (-not (Test-Path function:Get-AgentProviders) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Providers.ps1'))) { . (Join-Path $PSScriptRoot 'Providers.ps1') }
function Get-AgentViewSettingsFamilies {
    if (Test-Path function:Get-AgentProviders) { return @(Get-AgentProviders | ForEach-Object { $_.Family }) }
    return @('claude','codex')
}
function Get-AgentViewSettings([string]$Path = (Join-Path $env:LOCALAPPDATA 'agent-view/settings.json')) {
    $s = [pscustomobject]@{WidgetEnabled=$false;WidgetEdge='right';WidgetOffset=$null;WidgetScreen=$null;Language='auto';RefreshSeconds=120;NotifyEnabled=$true;NotifyThresholds=@(30,10);NotifyReset=$true;UpdateCheck=$true;HiddenProviders=@();KnownProviders=@()}
    try {
        $v = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (($v.RefreshSeconds -is [int] -or $v.RefreshSeconds -is [long]) -and $v.RefreshSeconds -in @(60,120,300)) { $s.RefreshSeconds=[int]$v.RefreshSeconds }
        foreach ($key in @('UpdateCheck','NotifyEnabled','NotifyReset','WidgetEnabled')) {
            if ($v.$key -is [bool]) { $s.$key = $v.$key }
        }
        if ($v.NotifyThresholds -is [array] -and $v.NotifyThresholds.Count -eq 2) {
            $valid = @($v.NotifyThresholds | Where-Object { ($_ -is [int] -or $_ -is [long]) -and $_ -ge 5 -and $_ -le 90 })
            if ($valid.Count -eq 2 -and $valid[0] -gt $valid[1]) { $s.NotifyThresholds=@([int]$valid[0],[int]$valid[1]) }
        }
        $families = @(Get-AgentViewSettingsFamilies)
        if ($v.HiddenProviders -is [array]) {
            # id = Family hoặc <family>-<group>; mục nào sai ⇒ bỏ cả danh sách; không được ẩn hết mọi Family.
            $hidden = @($v.HiddenProviders | Where-Object { $_ -is [string] -and $_ -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -and $families -ccontains ($_ -split '-')[0] } | Select-Object -Unique)
            $all = @($families | Where-Object { $hidden -ccontains $_ }).Count -eq $families.Count
            if (-not $all -and $hidden.Count -eq $v.HiddenProviders.Count) { $s.HiddenProviders=$hidden }
        }
        if ($v.KnownProviders -is [array]) {
            $known = @($v.KnownProviders | Where-Object { $_ -is [string] -and $families -ccontains $_ } | Select-Object -Unique)
            if ($known.Count -eq $v.KnownProviders.Count) { $s.KnownProviders=$known }
        }
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
