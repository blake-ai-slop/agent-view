. "$PSScriptRoot/../src/Tray.ps1"
. "$PSScriptRoot/../src/Cli.ps1"
. "$PSScriptRoot/../src/Quota.ps1"
. "$PSScriptRoot/../installer.ps1"
. "$PSScriptRoot/../uninstall.ps1"
. "$PSScriptRoot/../src/Forecast.ps1"
. "$PSScriptRoot/../src/Notify.ps1"
. "$PSScriptRoot/../src/SettingsWindow.ps1"

Describe 'Localization contract' {
    AfterEach { Set-AgentViewLanguage auto }
    It 'registers matching English and Vietnamese keys in every loaded module' {
        $tables = [AppDomain]::CurrentDomain.GetData('agent-view.strings')
        foreach ($required in 'forecast','notify','settings') { $tables.ContainsKey($required) | Should Be $true }
        foreach ($module in $tables.Keys) {
            (@($tables[$module].en.Keys | Sort-Object) -join ',') | Should Be (@($tables[$module].vi.Keys | Sort-Object) -join ',')
        }
    }
    It 'formats arguments, falls back to English and returns unknown keys safely' {
        Register-AgentViewStrings -Module 'test' -Strings @{en=@{hello='Hello {0}, {1}';fallback='English'};vi=@{hello='Chào {0}, {1}'}}
        try {
            Set-AgentViewLanguage vi
            Get-AgentViewText -Key 'test.hello' -Args @('A','B') | Should Be 'Chào A, B'
            T 'test.fallback' | Should Be 'English'
            T 'test.missing' | Should Be 'test.missing'
            T 'unknown' | Should Be 'unknown'
        } finally { [AppDomain]::CurrentDomain.GetData('agent-view.strings').Remove('test') }
    }
    It 'chooses auto language from the current Windows UI culture' {
        $old = [Threading.Thread]::CurrentThread.CurrentUICulture
        try {
            Set-AgentViewLanguage auto
            foreach ($pair in @(@('vi-VN','vi'),@('en-US','en'),@('fr-FR','en'))) {
                [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo($pair[0])
                Get-AgentViewLanguage | Should Be $pair[1]
            }
            Set-AgentViewLanguage vi
            [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo('en-US')
            Get-AgentViewLanguage | Should Be 'vi'
        } finally { [Threading.Thread]::CurrentThread.CurrentUICulture = $old }
    }
    It 'reads saved language and normalizes invalid or absent settings to auto' {
        $old = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = "$TestDrive/local"
            $path = Join-Path $env:LOCALAPPDATA 'agent-view/settings.json'
            foreach ($language in @('vi','en','invalid')) {
                $settings = Get-AgentViewSettings $path; $settings.Language = $language
                Save-AgentViewSettings $settings $path
                [AppDomain]::CurrentDomain.SetData('agent-view.language', $null)
                (Get-AgentViewSettings $path).Language | Should Be $(if ($language -eq 'invalid') {'auto'} else {$language})
                if ($language -ne 'invalid') { Get-AgentViewLanguage | Should Be $language }
            }
        } finally { $env:LOCALAPPDATA = $old }
    }
    It 'keeps Vietnamese literals inside vi tables only, excluding comments' {
        $files = @(Get-ChildItem "$PSScriptRoot/../src" -Filter '*.ps1') + @(Get-Item "$PSScriptRoot/../installer.ps1", "$PSScriptRoot/../uninstall.ps1")
        foreach ($file in $files) {
            $tokens=$null; $errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
            $viRanges = @($ast.FindAll({param($n) $n -is [Management.Automation.Language.HashtableAst]},$true) | ForEach-Object {
                foreach ($pair in $_.KeyValuePairs) { if ($pair.Item1.Value -eq 'vi') { $pair.Item2.Extent } }
            })
            foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -or $n -is [Management.Automation.Language.ExpandableStringExpressionAst]},$true)) {
                if ($node.Value -cmatch '[\u00c0-\u01ff\u1ea0-\u1ef9]') {
                    # Expandable here strings can contain nested calls: check their literal text after removing interpolations.
                    if ($node -is [Management.Automation.Language.ExpandableStringExpressionAst]) {
                        $literal=$node.Value
                        foreach ($nested in $node.NestedExpressions) { $literal=$literal.Replace($nested.Extent.Text,'') }
                        if ($literal -cnotmatch '[\u00c0-\u01ff\u1ea0-\u1ef9]') { continue }
                    }
                    @($viRanges | Where-Object { $_.StartOffset -le $node.Extent.StartOffset -and $_.EndOffset -ge $node.Extent.EndOffset }).Count | Should Be 1
                }
            }
        }
    }
    It 'renders popup widget tooltip and CLI status in both languages' {
        $now=[datetime]'2026-11-07T12:00:00'
        $app=[pscustomobject]@{Version='0.2.0';State='running';Autostart=$true;Widget=$true}
        $rows=@([pscustomobject]@{Provider='claude';Name='Claude Code';Ok=$true;Error=$null;FiveHourUsed=24;WeekUsed=12;FiveHourResetsAt=$now.AddMinutes(135);WeekResetsAt=$now.AddDays(3);FetchedAt=$now})
        foreach ($language in @('en','vi')) {
            Set-AgentViewLanguage $language
            try {
                [void](New-AgentViewPopupWindow)
                $popup=Get-AgentViewPopupState; $popup.Rows=$rows; Update-AgentViewPopupView 'static'
                $popup.Cards.claude.SubText.Text | Should Be $(if ($language -eq 'en') {'Tightest limit: 5 hours'} else {'Giới hạn sát nhất: 5 giờ'})
                (@($popup.Cards.claude.FiveLine.Inlines | ForEach-Object Text) -join '') | Should Be $(if ($language -eq 'en') {'76% left'} else {'còn 76%'})
                (@($popup.Cards.claude.WeekLine.Inlines | ForEach-Object Text) -join '') | Should Be $(if ($language -eq 'en') {'88% left'} else {'còn 88%'})
                $popup.Ui.RefreshBtn.ToolTip | Should Be $(if ($language -eq 'en') {'Refresh'} else {'Làm mới'})
                Show-AgentViewWidget -Rows $rows
                (Get-AgentViewWidgetState).Window.Title | Should Be (T 'widget.title')
                (Get-AgentViewWidgetState).Cards[0].Line.Text | Should Match $(if ($language -eq 'en') {'^5h 76% · Week 88%'} else {'^5h 76% · Tuần 88%'})
                Format-QuotaTooltip $rows | Should Be "agent-view`nClaude 76%"
                $failed=[pscustomobject]@{Provider='codex';Name='Codex';Ok=$false;Error=(T 'quota.timed_out');FiveHourUsed=$null;WeekUsed=$null}
                Format-QuotaTooltip @($failed) | Should Be $(if ($language -eq 'en') {"agent-view`nCodex: timed out"} else {"agent-view`nCodex : hết thời gian"})
                (Format-QuotaTooltip $rows).Length -le 63 | Should Be $true
                ((Format-AgentViewStatusLines $rows $app $now | ForEach-Object Text) -join ' ') | Should Match $(if ($language -eq 'en') {'Comfortable'} else {'Thoải mái'})
                if ($language -eq 'en') {
                    $status=(Format-AgentViewStatusLines $rows $app $now | ForEach-Object Text) -join ' '
                    $status | Should Match 'Claude Code\s+76% left\s+Comfortable'
                    $status | Should Match '5 hours\s+76% left\s+reset in 2h 15m'
                    $status | Should Match 'Week\s+88% left'
                    $status | Should Not Match 'left\s+\d+%'
                }
                Format-QuotaResetRelative $now.AddMinutes(135) $now | Should Be $(if ($language -eq 'en') {'in 2h 15m'} else {'còn 2g 15p'})
                Format-QuotaResetAbsolute $now.AddDays(2) $now | Should Be $(if ($language -eq 'en') {'Mon 09/11 12:00'} else {'T2 09/11 12:00'})
            } finally { Hide-AgentViewWidget; Close-AgentViewPopup -Force }
        }
    }
}

Describe 'Language CLI' {
    BeforeEach { $paths=Get-AgentViewPaths (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) "$TestDrive/startup" }
    AfterEach { Set-AgentViewLanguage auto }
    It 'shows the current language without changing settings' {
        Mock Write-Host {}
        Invoke-AgentViewCli @('lang') $paths | Should Be 0
        Test-Path $paths.Settings | Should Be $false
    }
    It 'saves the language preference' {
        Mock Write-Host {}
        Mock Get-AgentViewRunState { 'stopped' }
        Invoke-AgentViewCli @('lang','vi') $paths | Should Be 0
        (Get-AgentViewSettings $paths.Settings).Language | Should Be 'vi'
        Get-AgentViewLanguage | Should Be 'vi'
    }
    It 'restarts the running app when changing language' {
        Mock Write-Host {}
        Mock Get-AgentViewRunState { 'running' }
        Mock Stop-AgentViewApp { 1 }
        Mock Start-AgentViewApp { $true }
        Invoke-AgentViewCli @('lang','en') $paths | Should Be 0
        Assert-MockCalled Stop-AgentViewApp -Times 1 -Exactly -Scope It
        Assert-MockCalled Start-AgentViewApp -Times 1 -Exactly -Scope It
    }
    It 'leaves a stopped app stopped when changing language' {
        Mock Write-Host {}
        Mock Get-AgentViewRunState { 'stopped' }
        Mock Start-AgentViewApp { $true }
        Invoke-AgentViewCli @('lang','auto') $paths | Should Be 0
        (Get-AgentViewSettings $paths.Settings).Language | Should Be 'auto'
        Assert-MockCalled Start-AgentViewApp -Times 0 -Exactly -Scope It
    }
    It 'rejects invalid languages without creating settings' {
        Mock Write-Host {}
        Invoke-AgentViewCli @('lang','fr') $paths | Should Be 1
        Test-Path $paths.Settings | Should Be $false
    }
}

Describe 'Localization loading' {
    It 'loads the helper without reading settings or emitting output' {
        Mock Get-Content { throw 'Unexpected IO' }
        $output = . "$PSScriptRoot/../src/I18n.ps1"
        @($output).Count | Should Be 0
        Assert-MockCalled Get-Content -Times 0 -Exactly -Scope It
    }
}
