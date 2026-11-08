. "$PSScriptRoot/../src/Tray.ps1"
Set-AgentViewLanguage vi
function New-TestRow($Five, $Week, $Ok=$true) {
    [pscustomobject]@{Provider='claude';Name='Claude Code';Ok=$Ok;Error='không có dữ liệu';FiveHourUsed=$Five;WeekUsed=$Week;FiveHourResetsAt=[datetime]'2026-11-07T18:30:00';WeekResetsAt=[datetime]'2026-11-10T08:15:00';FetchedAt=[datetime]'2026-11-07T17:00:00'}
}
Describe 'Quota display rules' {
    It 'uses the most constrained window including zero remaining' {
        Get-QuotaRemaining (New-TestRow 28 5) | Should Be 72
        Get-QuotaRemaining (New-TestRow 100 5) | Should Be 0
        Get-QuotaRemaining (New-TestRow 0 0) | Should Be 100
    }
    It 'supports one or no window' {
        Get-QuotaRemaining (New-TestRow $null 25) | Should Be 75
        Get-QuotaRemaining (New-TestRow 40 $null) | Should Be 60
        ($null -eq (Get-QuotaRemaining (New-TestRow $null $null))) | Should Be $true
    }
    It 'honors every level boundary' {
        Get-QuotaLevel 31 | Should Be 'ok'
        Get-QuotaLevel 30 | Should Be 'warn'
        Get-QuotaLevel 11 | Should Be 'warn'
        Get-QuotaLevel 10 | Should Be 'crit'
        Get-QuotaLevel 0 | Should Be 'crit'
        Get-QuotaLevel $null | Should Be 'unk'
    }
    It 'formats provider tooltip and limits length' {
        $codex = New-TestRow 5 0; $codex.Provider='codex'; $codex.Name='Codex'
        Format-QuotaTooltip @((New-TestRow 28 0),$codex) | Should Be "agent-view`nClaude 72%`nCodex 95%"
        $bad = New-TestRow $null $null $false; $bad.Error='x'*100
        (Format-QuotaTooltip @($bad)).Length | Should Be 63
        Format-QuotaTooltip @($bad) | Should Match 'Claude : '
    }

}

Describe 'Tray settings and notification helpers' {
    It 'filters hidden providers and keeps order' {
        $codex = New-TestRow 5 0; $codex.Provider='codex'; $codex.Name='Codex'
        $rows = @((New-TestRow 28 0), $codex)
        @(Select-AgentViewVisibleRows $rows ([pscustomobject]@{HiddenProviders=@('claude')})).Count | Should Be 1
        @(Select-AgentViewVisibleRows $rows ([pscustomobject]@{HiddenProviders=@('claude')}))[0].Provider | Should Be 'codex'
        @(Select-AgentViewVisibleRows $rows ([pscustomobject]@{WidgetEnabled=$false})).Count | Should Be 2
        @(Select-AgentViewVisibleRows (,@($rows)) $null).Count | Should Be 2
    }
    It 'merges notifications into one balloon and picks warning at the low threshold' {
        Get-AgentViewBalloon @() $null | Should Be $null
        $low = @{ Kind='low'; Remaining=25; Title='Claude Code: còn 25%'; Text='Giới hạn 5 giờ' }
        $b = Get-AgentViewBalloon @($low) $null
        $b.Title | Should Be 'Claude Code: còn 25%'; $b.Text | Should Be 'Giới hạn 5 giờ'; $b.Icon | Should Be 'Info'
        $crit = @{ Kind='low'; Remaining=8; Title='Codex: còn 8%'; Text='Giới hạn tuần' }
        $reset = @{ Kind='reset'; Remaining=100; Title='Codex'; Text='Codex: giới hạn 5 giờ đã đầy lại' }
        $b = Get-AgentViewBalloon @($low, $crit, $reset) $null
        $b.Count | Should Be 3; $b.Icon | Should Be 'Warning'; $b.Title | Should Be 'agent-view'
        $b.Text | Should Be "Claude Code: còn 25% · Giới hạn 5 giờ`nCodex: còn 8% · Giới hạn tuần`nCodex: giới hạn 5 giờ đã đầy lại"
        (Get-AgentViewBalloon @($low) ([pscustomobject]@{NotifyThresholds=@(40,25)})).Icon | Should Be 'Warning'
    }
}

Describe 'Bezel tray layout' {
    It 'uses the specified strokes and font sizes' {
        $sizes=@(16,20,24,32); $strokes=@(2,2,2.5,3); $fonts=@(9,11,13,17)
        for ($i=0;$i -lt 4;$i++) {
            $layout=Get-QuotaIconLayout $sizes[$i] 76
            $layout.Stroke | Should Be $strokes[$i]
            $layout.FontSize | Should Be $fonts[$i]
            $layout.Label | Should Be '76'
        }
        (Get-QuotaIconLayout 16 100).Label | Should Be '✓'
        (Get-QuotaIconLayout 20 100).Label | Should Be '✓'
        (Get-QuotaIconLayout 24 100).Label | Should Be '100'
        (Get-QuotaIconLayout 16 $null).Label | Should Be '?'
        (Get-QuotaIconLayout 16 $null -Loading).Label | Should Be ''
    }
}
