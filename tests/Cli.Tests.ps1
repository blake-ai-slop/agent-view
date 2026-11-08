. "$PSScriptRoot/../src/Cli.ps1"
Set-AgentViewLanguage vi
Describe 'agentview command parsing' {
    It 'defaults to help and resolves aliases' {
        (Resolve-AgentViewCommand @()).Command | Should Be 'help'
        (Resolve-AgentViewCommand @('start')).Command | Should Be 'up'
        (Resolve-AgentViewCommand @('STOP')).Command | Should Be 'down'
        (Resolve-AgentViewCommand @('--version')).Command | Should Be 'version'
        $c = Resolve-AgentViewCommand @('widget','on')
        $c.Command | Should Be 'widget'; $c.Rest[0] | Should Be 'on'
    }
    It 'rejects unknown commands with a close suggestion' {
        $c = Resolve-AgentViewCommand @('stauts')
        $c.Error | Should Be 'unknown'; $c.Suggestion | Should Be 'status'
        (Resolve-AgentViewCommand @('updat')).Suggestion | Should Be 'update'
        (Resolve-AgentViewCommand @('widgte')).Suggestion | Should Be 'widget'
        ($null -eq (Resolve-AgentViewCommand @('xyzzyq')).Suggestion) | Should Be $true
    }
    It 'returns exit code 1 for an unknown command' {
        Invoke-AgentViewCli @('nope') (Get-AgentViewPaths "$TestDrive/l" "$TestDrive/s") 6>$null | Should Be 1
    }
    It 'parses on/off and yes flags' {
        ConvertFrom-AgentViewSwitch 'on' | Should Be $true
        ConvertFrom-AgentViewSwitch 'OFF' | Should Be $false
        ($null -eq (ConvertFrom-AgentViewSwitch 'maybe')) | Should Be $true
        Test-AgentViewYesFlag @('-y') | Should Be $true
        Test-AgentViewYesFlag @() | Should Be $false
    }
}

Describe 'User PATH and shim' {
    It 'adds the bin dir once and removes it without touching other entries' {
        $p = Add-AgentViewPathEntry 'C:\a;%USERPROFILE%\b;' 'C:\x\bin'
        $p | Should Be 'C:\a;%USERPROFILE%\b;C:\x\bin'
        Add-AgentViewPathEntry $p 'c:\X\bin\' | Should Be $p
        Add-AgentViewPathEntry '' 'C:\x\bin' | Should Be 'C:\x\bin'
        Remove-AgentViewPathEntry 'C:\a;C:\X\BIN\;C:\b;C:\x\bin' 'C:\x\bin' | Should Be 'C:\a;C:\b'
        Remove-AgentViewPathEntry 'C:\a' 'C:\x\bin' | Should Be 'C:\a'
    }
    It 'edits only the injected user PATH and the process PATH' {
        $oldFile = $env:AGENT_VIEW_USER_PATH_FILE; $oldPath = $env:Path
        try {
            $env:AGENT_VIEW_USER_PATH_FILE = "$TestDrive/userpath.txt"
            Set-Content $env:AGENT_VIEW_USER_PATH_FILE 'C:\keep' -NoNewline
            Set-AgentViewUserPathEntry "$TestDrive\bin" $true | Should Be $true
            Set-AgentViewUserPathEntry "$TestDrive\bin" $true | Should Be $false
            (Get-Content $env:AGENT_VIEW_USER_PATH_FILE -Raw) | Should Be "C:\keep;$TestDrive\bin"
            ($env:Path -split ';') -contains "$TestDrive\bin" | Should Be $true
            Set-AgentViewUserPathEntry "$TestDrive\bin" $false | Should Be $true
            (Get-Content $env:AGENT_VIEW_USER_PATH_FILE -Raw) | Should Be 'C:\keep'
            ($env:Path -split ';') -contains "$TestDrive\bin" | Should Be $false
        } finally { $env:AGENT_VIEW_USER_PATH_FILE = $oldFile; $env:Path = $oldPath }
    }
    It 'builds a one-command shim that calls Cli.ps1 via Windows PowerShell' {
        $t = Get-AgentViewShimText
        $t | Should Match '^@echo off\r\n'
        $t | Should Match 'WindowsPowerShell\\v1\.0\\powershell\.exe" -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\\agent-view\\Cli\.ps1" %\*\r\n$'
        Write-AgentViewTextFile "$TestDrive/bin/agentview.cmd" $t | Should Be $true
        Write-AgentViewTextFile "$TestDrive/bin/agentview.cmd" $t | Should Be $false
    }
}

Describe 'Run state' {
    It 'prefers this install, then another holder of the mutex' {
        Resolve-AgentViewRunState @(12) $false | Should Be 'running'
        Resolve-AgentViewRunState @() $true | Should Be 'other'
        Resolve-AgentViewRunState $null $false | Should Be 'stopped'
    }
    It 'install, uninstall and CLI share one running-detection function' {
        foreach ($f in @('install.ps1','installer.ps1','uninstall.ps1')) {
            $text = Get-Content "$PSScriptRoot/../$f" -Raw
            $text | Should Not Match 'Win32_Process'
        }
    }
}

Describe 'version source' {
    It 'reads the version only from Version.ps1' {
        $text = Get-Content "$PSScriptRoot/../src/Version.ps1" -Raw
        $expected = [regex]::Match($text, "AgentViewVersion\s*=\s*'([^']+)'").Groups[1].Value
        $expected | Should Match '^\d+\.\d+\.\d+$'
        $AgentViewVersion | Should Be $expected
        (Get-Content "$PSScriptRoot/../src/Cli.ps1" -Raw) | Should Not Match ([regex]::Escape("AgentViewVersion = '$expected'"))
    }
}

Describe 'status output' {
    BeforeEach { Set-AgentViewLanguage vi }
    $now = [datetime]'2026-11-07T12:00:00'
    $app = [pscustomobject]@{ Version='0.2.0'; State='running'; Autostart=$true; Widget=$false }
    $rows = @(
        [pscustomobject]@{ Provider='claude'; Name='Claude Code'; Ok=$true; Error=$null; FiveHourUsed=28; WeekUsed=15; FiveHourResetsAt=$now.AddMinutes(130); WeekResetsAt=$now.AddDays(3); FetchedAt=$now; Email='a@b.c'; AccountUuid='u-1' },
        [pscustomobject]@{ Provider='codex'; Name='Codex'; Ok=$false; Error='chưa cài'; FiveHourUsed=$null; WeekUsed=$null; FiveHourResetsAt=$null; WeekResetsAt=$null; FetchedAt=$now })
    It 'prints app state, remaining, colour level and relative + absolute resets' {
        $lines = Format-AgentViewStatusLines $rows $app $now
        $lines[0].Text | Should Be 'agent-view 0.2.0 · đang chạy · tự chạy: bật · widget: tắt'
        $text = ($lines | ForEach-Object Text) -join "`n"
        $text | Should Match 'Claude Code\s+còn\s+72%\s+Thoải mái'
        $text | Should Match '5 giờ\s+còn\s+72%\s+reset còn 2g 10p \(14:10\)'
        $text | Should Match 'Tuần\s+còn\s+85%\s+reset còn 3 ngày 0g \(T3 10/11 12:00\)'
        $text | Should Match 'Codex\s+chưa cài'
        @($lines | Where-Object { $_.Text -match 'Claude Code' })[0].Color | Should Be 'Green'
    }
    It 'colours by level' {
        $low = [pscustomobject]@{ Provider='codex'; Name='Codex'; Ok=$true; FiveHourUsed=95; WeekUsed=20 }
        @(Format-AgentViewStatusLines @($low) $app $now | Where-Object { $_.Text -match '^Codex' })[0].Color | Should Be 'Red'
    }
    It 'hides a missing window instead of printing an empty percentage' {
        $one = [pscustomobject]@{ Provider='codex'; Name='Codex'; Ok=$true; Error=$null; FiveHourUsed=$null; WeekUsed=40; FiveHourResetsAt=$now.AddHours(1); WeekResetsAt=$now.AddDays(1); FetchedAt=$now }
        $text = (Format-AgentViewStatusLines @($one) $app $now | ForEach-Object Text) -join "`n"
        $text | Should Match 'Codex\s+còn\s+60%'
        $text | Should Match 'Tuần\s+còn\s+60%'
        $text | Should Not Match '5 giờ'
        $json = ConvertTo-AgentViewStatusJson @($one) $app | ConvertFrom-Json
        $json.quotas[0].remaining | Should Be 60
        ($null -eq $json.quotas[0].fiveHourRemaining) | Should Be $true
        ($null -eq $json.quotas[0].fiveHourResetsAt) | Should Be $true
        $json.quotas[0].weekRemaining | Should Be 60
    }
    It 'emits ASCII JSON with only whitelisted fields and no account data' {
        $json = ConvertTo-AgentViewStatusJson $rows $app
        $json | Should Not Match '[^\x00-\x7F]'
        $json | Should Not Match 'a@b\.c|u-1|Email|Account'
        $o = $json | ConvertFrom-Json
        $o.running | Should Be $true; $o.autostart | Should Be $true; $o.widget | Should Be $false
        $o.quotas.Count | Should Be 2
        $o.quotas[0].remaining | Should Be 72; $o.quotas[0].level | Should Be 'ok'; $o.quotas[0].fiveHourRemaining | Should Be 72
        $o.quotas[1].ok | Should Be $false; $o.quotas[1].error | Should Be 'chưa cài'
        @($o.quotas[0].PSObject.Properties.Name) -join ',' | Should Be 'provider,name,ok,error,remaining,level,fiveHourRemaining,weekRemaining,fiveHourResetsAt,weekResetsAt,fetchedAt'
    }
}
