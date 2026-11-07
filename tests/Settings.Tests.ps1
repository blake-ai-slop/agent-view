. "$PSScriptRoot/../src/Settings.ps1"
Describe 'Widget settings' {
    It 'defaults for absent corrupt and invalid files' {
        $p=Join-Path $TestDrive 'settings.json'
        (Get-AgentViewSettings $p).WidgetEnabled | Should Be $false
        Set-Content $p '{broken'
        (Get-AgentViewSettings $p).WidgetEdge | Should Be right
        Set-Content $p '{"WidgetEdge":"bottom","WidgetOffset":"bad","WidgetEnabled":"true"}'
        $s=Get-AgentViewSettings $p
        $s.WidgetEdge | Should Be right
        $s.WidgetEnabled | Should Be $false
        ($null -eq $s.WidgetOffset) | Should Be $true
    }
    It 'roundtrips all fields atomically without leftover temp files' {
        $p=Join-Path $TestDrive 'nested/settings.json'
        $s=Get-AgentViewSettings $p;$s.WidgetEnabled=$true;$s.WidgetEdge='top';$s.WidgetOffset=42.5;$s.WidgetScreen='DISPLAY2'
        Save-AgentViewSettings $s $p
        $r=Get-AgentViewSettings $p
        $r.WidgetEnabled | Should Be $true
        $r.WidgetEdge | Should Be top
        $r.WidgetOffset | Should Be 42.5
        $r.WidgetScreen | Should Be DISPLAY2
        @(Get-ChildItem (Split-Path $p) -Filter '*.tmp').Count | Should Be 0
    }
}
