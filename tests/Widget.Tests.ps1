. "$PSScriptRoot/../src/Tray.ps1"
. "$PSScriptRoot/../src/Quota.ps1"
Set-AgentViewLanguage vi
Describe 'Widget rows and docking' {
    AfterEach {
        Hide-AgentViewWidget
        Close-AgentViewPopup -Force
        [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Windows.Threading.DispatcherPriority]::ContextIdle, [Action]{})
        (Get-AgentViewWidgetState).Window | Should BeNullOrEmpty
    }
    It 'uses the tightest reset with fallback and omits absent reset text' {
        $now=[datetime]'2026-11-07T12:00:00'
        $r=[pscustomobject]@{Provider='claude';Name='Claude';Ok=$true;FiveHourUsed=0;WeekUsed=6;FiveHourResetsAt=$now.AddHours(1);WeekResetsAt=$now.AddHours(2)}
        $m=Get-AgentViewCardModel $r -Now $now
        Get-AgentViewWidgetDetailText $m | Should Be "5h 100% · Tuần 94% · ↺ $($m.Week.Rel)"
        $r.WeekResetsAt=$null
        $m=Get-AgentViewCardModel $r -Now $now
        Get-AgentViewWidgetDetailText $m | Should Be "5h 100% · Tuần 94% · ↺ $($m.Five.Rel)"
        $r.FiveHourResetsAt=$null
        Get-AgentViewWidgetDetailText (Get-AgentViewCardModel $r -Now $now) | Should Be '5h 100% · Tuần 94%'
        $r.FiveHourUsed=20;$r.WeekUsed=5;$r.FiveHourResetsAt=$now.AddHours(1);$r.WeekResetsAt=$now.AddHours(2)
        $m=Get-AgentViewCardModel $r -Now $now
        Get-AgentViewWidgetDetailText $m | Should Be "5h 80% · Tuần 95% · ↺ $($m.Five.Rel)"
        $r.FiveHourResetsAt=$null
        $m=Get-AgentViewCardModel $r -Now $now
        Get-AgentViewWidgetDetailText $m | Should Be "5h 80% · Tuần 95% · ↺ $($m.Week.Rel)"
    }
    It 'adds the run-out time only for the tightest window when it runs out' {
        $now=[datetime]'2026-11-07T12:00:00'
        $r=[pscustomobject]@{Provider='claude';Name='Claude';Ok=$true;FiveHourUsed=60;WeekUsed=20;FiveHourResetsAt=$now.AddHours(2);WeekResetsAt=$now.AddDays(2)}
        $hist=@(-20,-10,0 | ForEach-Object { [pscustomobject]@{p='claude';w='5h';u=(60+$_);t=$now.AddMinutes($_).ToUniversalTime().ToString('o');r=$r.FiveHourResetsAt.ToUniversalTime().ToString('o')} })
        $m=Get-AgentViewCardModel $r -Now $now -History $hist
        $m.Five.ForecastKind | Should Be 'runout'
        Get-AgentViewWidgetDetailText $m $now | Should Be "5h 40% · Tuần 80% · ↺ $($m.Five.Rel) · hết ~12:40"
        # Cửa sổ sát nhất là tuần (không đủ dữ liệu) ⇒ không thêm dù 5h sẽ hết.
        $r.WeekUsed=70
        $m=Get-AgentViewCardModel $r -Now $now -History $hist
        Get-AgentViewWidgetDetailText $m $now | Should Not Match 'hết ~'
    }
    It 'aligns both providers detail text for every dock edge' {
        $rows=@([pscustomobject]@{Provider='claude';Name='Claude Code';Ok=$true;FiveHourUsed=0;WeekUsed=6;FiveHourResetsAt=$null;WeekResetsAt=$null},[pscustomobject]@{Provider='codex';Name='Codex';Ok=$true;FiveHourUsed=30;WeekUsed=5;FiveHourResetsAt=$null;WeekResetsAt=$null})
        try {
            Show-AgentViewWidget -Rows $rows
            $s=Get-AgentViewWidgetState
            foreach($edge in @('right','left','top')) {
                $s.Settings.WidgetEdge=$edge;Set-AgentViewWidgetDock
                $expected=switch($edge){right {'Right'} left {'Left'} top {'Center'}}
                foreach($card in $s.Cards){
                    $card.Name.TextAlignment | Should Be $expected
                    $card.Line.TextAlignment | Should Be $expected
                    $card.Line.Text | Should Not Match '↺'
                }
            }
        } finally {Hide-AgentViewWidget}
    }
    It 'selects only left right or top even near the bottom' {
        $a=[pscustomobject]@{Left=0;Top=0;Right=1920;Bottom=1080}
        Get-AgentViewWidgetEdge $a 1910 1000 | Should Be 'right'
        Get-AgentViewWidgetEdge $a 4 500 | Should Be 'left'
        Get-AgentViewWidgetEdge $a 900 3 | Should Be 'top'
    }
    It 'scales 150 percent work areas and clamps saved offsets' {
        $a=[pscustomobject]@{Left=1920;Top=0;Right=3840;Bottom=1620}
        $p=Get-AgentViewWidgetPlacement $a right 9999 80 180 1.5
        $p.Left | Should Be 2468
        $p.Top | Should Be 888
        $p=Get-AgentViewWidgetPlacement $a top -100 200 80 1.5
        $p.Left | Should Be 1292
        $p.Top | Should Be 12
        $a=[pscustomobject]@{Left=-1920;Top=-200;Right=0;Bottom=880}
        (Get-AgentViewWidgetPlacement $a left 0 80 180).Left | Should Be -1908
    }
    It 'creates updates and closes actual WPF windows repeatedly' {
        $row=[pscustomobject]@{Provider='claude';Name='Claude Code';Ok=$true;FiveHourUsed=28;WeekUsed=5;FiveHourResetsAt=$null;WeekResetsAt=$null}
        try {
            for($i=0;$i -lt 3;$i++) {
                Show-AgentViewWidget -Rows (,@($row))
                Test-AgentViewWidgetVisible | Should Be $true
                (Get-AgentViewWidgetState).Cards.Count | Should Be 1
                Update-AgentViewWidget -Rows $row -Loading
                (Get-AgentViewWidgetState).Cards[0].Label.Text | Should Be '…'
                $s=Get-AgentViewWidgetState
                $s.Settings.WidgetEdge='top';Set-AgentViewWidgetDock
                $s.Cards[0].Compact.Orientation | Should Be Horizontal
                $s.Cards[0].Detail.MaxHeight | Should Be 0
                $s.Cards[0].Compact.FlowDirection | Should Be LeftToRight
                Hide-AgentViewWidget
                Test-AgentViewWidgetVisible | Should Be $false
            }
        } finally {Hide-AgentViewWidget}
    }
    It 'falls back to the primary monitor when a saved screen disappears' {
        $s=Get-AgentViewWidgetState;$s.Settings.WidgetScreen='missing-screen';$s.Settings.WidgetOffset=999999
        try {
            Show-AgentViewWidget -Rows $null
            $s.Screen.DeviceName | Should Be ([Windows.Forms.Screen]::PrimaryScreen.DeviceName)
            ($null -eq $s.Settings.WidgetOffset) | Should Be $true
        } finally {Hide-AgentViewWidget}
    }
}

Describe 'Optional widget window detail' {
    It 'omits absent windows through the shared row boundary and tooltip' {
        foreach($mode in 'week','five') {
            $row=[pscustomobject]@{Provider='claude';Name='Claude Code';Ok=$true;FiveHourUsed=$null;WeekUsed=42}
            if($mode -eq 'five'){$row.FiveHourUsed=0;$row.WeekUsed=$null}
            $rows=@(ConvertTo-QuotaRows (,@($row)))
            $m=Get-AgentViewCardModel $rows[0]
            Get-AgentViewWidgetDetailText $m | Should Be $(if($mode -eq 'week'){'Tuần 58%'}else{'5h 100%'})
            Format-QuotaTooltip $rows | Should Match $(if($mode -eq 'week'){'Claude 58%'}else{'Claude 100%'})
            Get-QuotaTightestWindow $rows[0] | Should Be $(if($mode -eq 'week'){'Tuần'}else{'5 giờ'})
        }
    }
}

Describe 'Widget per family (v0.3.0)' {
    $savedPresence = [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence')
    function Set-WPresence($Families) {
        $state = [hashtable]::Synchronized(@{})
        if ($null -ne $Families) { $state['Families'] = [string[]]@($Families) }
        [AppDomain]::CurrentDomain.SetData('agent-view.ProviderPresence', $state)
    }
    function New-WAg([string]$Group, $Five, $Week) {
        $r = [pscustomobject]@{ Provider = "antigravity-$($Group.ToLowerInvariant())"; Name = "Antigravity · $Group"; Ok = $true; FiveHourUsed = $Five; WeekUsed = $Week; FiveHourResetsAt = $null; WeekResetsAt = $null }
        $r | Add-Member -NotePropertyMembers @{ Family = 'antigravity'; Group = $Group }
        $r
    }
    AfterEach {
        Hide-AgentViewWidget
        [AppDomain]::CurrentDomain.SetData('agent-view.ProviderPresence', $savedPresence)
        [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Windows.Threading.DispatcherPriority]::ContextIdle, [Action]{})
    }
    It 'takes the tightest group for the family ring and lists every group' {
        $g = [pscustomobject]@{ Family = 'antigravity'; Rows = @((New-WAg 'Gemini' 8 3), (New-WAg 'Argon' $null 92), (New-WAg 'Claude/GPT' 0 0)) }
        $m = Get-AgentViewWidgetFamilyModel $g
        $m.Name | Should Be 'Antigravity'
        $m.State | Should Be 'ok'; $m.Value | Should Be 8; $m.Level | Should Be 'crit'; $m.Label | Should Be '8%'
        @($m.Lines).Count | Should Be 3
        $m.Lines[0] | Should Be 'Gemini · 5h 92% · Tuần 97%'
        $m.Lines[1] | Should Be 'Argon · Tuần 8%'
        (Get-AgentViewWidgetFamilyModel $g -Loading).Label | Should Be '…'
        $single = Get-AgentViewWidgetFamilyModel ([pscustomobject]@{ Family = 'antigravity'; Rows = @((New-WAg 'Gemini' 8 3)) })
        $single.Name | Should Be 'Antigravity · Gemini'
        $single.Lines[0] | Should Be '5h 92% · Tuần 97%'
        $bad = [pscustomobject]@{ Provider = 'codex'; Name = 'Codex'; Ok = $false; Error = 'Chưa đăng nhập'; FiveHourUsed = $null; WeekUsed = $null }
        $e = Get-AgentViewWidgetFamilyModel ([pscustomobject]@{ Family = 'codex'; Rows = @($bad) })
        $e.State | Should Be 'error'; $e.Label | Should Be '?'; $e.Lines[0] | Should Be 'Chưa đăng nhập'
    }
    It 'shows one 40px ring per family with official logos' {
        Set-WPresence @('claude','antigravity')
        $rows = @([pscustomobject]@{ Provider = 'claude'; Name = 'Claude Code'; Ok = $true; FiveHourUsed = 30; WeekUsed = 10 }, (New-WAg 'Gemini' 8 3), (New-WAg 'Argon' $null 50))
        Show-AgentViewWidget -Rows $rows
        $s = Get-AgentViewWidgetState
        $s.Cards.Count | Should Be 2
        ($s.Cards | ForEach-Object { $_.Family }) -join ',' | Should Be 'claude,antigravity'
        $s.Cards[1].Label.Foreground.Color.ToString() | Should Be '#FF3DD68C'   # số % tween từ 0; màu theo mức nhóm sát nhất (50% ⇒ ok)
        $s.Cards[1].Name.Text | Should Be 'Antigravity'
        $s.Cards[1].LineCount | Should Be 2
        ($s.Cards[1].Ring.Tag.Icon -is [System.Windows.Controls.Image]) | Should Be $true
        $s.Cards[0].Ring.Width | Should Be 40
        Update-AgentViewWidget -Rows @($rows[0])
        $s.Cards.Count | Should Be 1
    }
    It 'shows a gray no-agent ring when nothing is detected' {
        Set-WPresence @()
        Show-AgentViewWidget -Rows @()
        $s = Get-AgentViewWidgetState
        $s.Cards.Count | Should Be 1
        $s.Cards[0].Label.Text | Should Be '–'
        $s.Cards[0].Line.Text | Should Be 'Chưa có agent'
        $s.Cards[0].Ring.Tag.State | Should Be 'error'
        $s.Cards[0].Ring.Tag.Icon | Should Be $null
    }
}
