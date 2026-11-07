function Get-AgentViewSettings([string]$Path = (Join-Path $env:LOCALAPPDATA 'agent-view/settings.json')) {
    $s = [pscustomobject]@{WidgetEnabled=$false;WidgetEdge='right';WidgetOffset=$null;WidgetScreen=$null}
    try {
        $v = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($v.WidgetEnabled -is [bool]) { $s.WidgetEnabled=$v.WidgetEnabled }
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
