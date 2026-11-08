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

Describe 'Preferences schema' {
    It 'defaults update checking safely and preserves a disabled choice' {
        $p=Join-Path $TestDrive 'updates.json'
        (Get-AgentViewSettings $p).UpdateCheck | Should Be $true
        foreach ($value in @('"false"','0','null','[]')) {
            Set-Content $p ('{"UpdateCheck":'+$value+'}')
            (Get-AgentViewSettings $p).UpdateCheck | Should Be $true
        }
        $s=Get-AgentViewSettings $p; $s.UpdateCheck=$false
        Save-AgentViewSettings $s $p
        (Get-AgentViewSettings $p).UpdateCheck | Should Be $false
    }
    It 'uses safe defaults for missing or mistyped fields' {
        $p=Join-Path $TestDrive 'preferences.json'
        Set-Content $p '{"RefreshSeconds":"60","NotifyEnabled":"false","NotifyReset":1,"NotifyThresholds":[10,30],"HiddenProviders":["claude","codex"]}'
        $s=Get-AgentViewSettings $p
        $s.RefreshSeconds | Should Be 120
        $s.NotifyEnabled | Should Be $true
        $s.NotifyReset | Should Be $true
        ($s.NotifyThresholds -join ',') | Should Be '30,10'
        $s.HiddenProviders.Count | Should Be 0
    }
    It 'roundtrips preferences and preserves existing widget fields' {
        $p=Join-Path $TestDrive 'preferences.json'
        $s=Get-AgentViewSettings $p
        $s.RefreshSeconds=300; $s.NotifyEnabled=$false; $s.NotifyReset=$false
        $s.NotifyThresholds=@(80,5); $s.HiddenProviders=@('claude'); $s.Language='vi'
        $s.WidgetEdge='left'; $s.WidgetOffset=27
        Save-AgentViewSettings $s $p
        $r=Get-AgentViewSettings $p
        $r.RefreshSeconds | Should Be 300
        $r.NotifyEnabled | Should Be $false
        $r.NotifyReset | Should Be $false
        ($r.NotifyThresholds -join ',') | Should Be '80,5'
        ($r.HiddenProviders -join ',') | Should Be 'claude'
        $r.Language | Should Be vi
        $r.WidgetEdge | Should Be left
        $r.WidgetOffset | Should Be 27
    }
    It 'rejects fractional, out of range, unordered and scalar thresholds' {
        $p=Join-Path $TestDrive 'invalid.json'
        foreach ($json in @('[30.5,10]','[91,10]','[30,4]','[10,10]','[5,90]','[30]','30','["30",10]')) {
            Set-Content $p ('{"NotifyThresholds":'+$json+'}')
            ((Get-AgentViewSettings $p).NotifyThresholds -join ',') | Should Be '30,10'
        }
    }
    It 'rejects invalid refresh and hidden-provider types' {
        $p=Join-Path $TestDrive 'invalid.json'
        foreach ($json in @('"claude"','["other"]','[true]','["claude","other"]','["Claude"]')) {
            Set-Content $p ('{"HiddenProviders":'+$json+',"RefreshSeconds":60.5}')
            $s=Get-AgentViewSettings $p
            $s.HiddenProviders.Count | Should Be 0
            $s.RefreshSeconds | Should Be 120
        }
    }
}
