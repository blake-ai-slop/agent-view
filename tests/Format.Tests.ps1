. "$PSScriptRoot/../src/Format.ps1"
Describe 'Shared quota formatting' {
    It 'formats relative boundaries and clamps the past' {
        $now=[datetime]'2026-11-07T12:00:00'
        Format-QuotaResetRelative ($now.AddMinutes(45)) $now | Should Be 'còn 45p'
        Format-QuotaResetRelative ($now.AddMinutes(135)) $now | Should Be 'còn 2g 15p'
        Format-QuotaResetRelative ($now.AddMinutes(125)) $now | Should Be 'còn 2g 05p'
        Format-QuotaResetRelative ($now.AddHours(76)) $now | Should Be 'còn 3 ngày 4g'
        Format-QuotaResetRelative ($now.AddSeconds(-1)) $now | Should Be 'còn 0p'
        ($null -eq (Format-QuotaResetRelative $null $now)) | Should Be $true
    }
    It 'formats dates and elapsed times' {
        $now=[datetime]'2026-11-07T12:00:00'
        Format-QuotaResetAbsolute $now $now | Should Be '12:00'
        Format-QuotaResetAbsolute ([datetime]'2026-11-12T09:00:00') $now | Should Be 'T5 12/11 09:00'
        ($null -eq (Format-QuotaResetAbsolute $null $now)) | Should Be $true
        Format-QuotaAgo ($now.AddSeconds(-44)) $now | Should Be 'vừa xong'
        Format-QuotaAgo ($now.AddSeconds(-45)) $now | Should Be '1 phút trước'
        Format-QuotaAgo ($now.AddMinutes(-59)) $now | Should Be '59 phút trước'
        Format-QuotaAgo ($now.AddHours(-2)) $now | Should Be '2 giờ trước'
    }
    It 'names statuses and the tightest complete window' {
        Get-QuotaStatusText ok | Should Be 'Thoải mái'
        Get-QuotaStatusText warn | Should Be 'Nên chậm lại'
        Get-QuotaStatusText crit | Should Be 'Sắp cạn'
        Get-QuotaStatusText unk | Should Be 'Không rõ'
        Get-QuotaTightestWindow ([pscustomobject]@{FiveHourUsed=50;WeekUsed=50}) | Should Be '5 giờ'
        Get-QuotaTightestWindow ([pscustomobject]@{FiveHourUsed=10;WeekUsed=50}) | Should Be 'Tuần'
        Get-QuotaTightestWindow ([pscustomobject]@{FiveHourUsed=$null;WeekUsed=50}) | Should Be 'Tuần'
    }
}

. "$PSScriptRoot/../src/Tray.ps1"
Describe 'Shared row boundary through real popup widget and tray' {
    It 'preserves count order and display values for eight input shapes' {
        $first=[pscustomobject]@{Provider='claude';Name='Claude Code';Ok=$true;FiveHourUsed=24;WeekUsed=12}
        $second=[pscustomobject]@{Provider='codex';Name='Codex';Ok=$true;FiveHourUsed=75;WeekUsed=40}
        $worker=[PowerShell]::Create()
        try {
            $collection=$worker.AddScript({param($a,$b) ,@($a,$b)}).AddArgument($first).AddArgument($second).Invoke()
            $cases=@(
                @{Rows=@($first,$second);Order='claude,codex';Count=2},
                @{Rows=(,@($first,$second));Order='claude,codex';Count=2},
                @{Rows=(,@($null,(,@($first,$null,(,@($second))))));Order='claude,codex';Count=2},
                @{Rows=$collection;Order='claude,codex';Count=2},
                @{Rows=@(ConvertTo-QuotaRows @($first,$second));Order='claude,codex';Count=2},
                @{Rows=$second;Order='codex';Count=1},
                @{Rows=@();Order='';Count=0},
                @{Rows=$null;Order='';Count=0}
            )
            foreach($case in $cases) {
                $rows=@(ConvertTo-QuotaRows $case.Rows)
                $rows.Count | Should Be $case.Count
                (($rows | ForEach-Object {$_.Provider}) -join ',') | Should Be $case.Order
                foreach($row in $rows) {
                    $model=Get-AgentViewCardModel $row
                    $model.Value | Should Be (Get-QuotaRemaining $row)
                    Get-AgentViewWidgetDetailText $model | Should Match $model.Five.ValueText
                }
                $tooltip=Format-QuotaTooltip $rows
                foreach($row in $rows) { $tooltip | Should Match ([string](Get-QuotaRemaining $row)+'%') }
                try {
                    [void](New-AgentViewPopupWindow)
                    $state=Get-AgentViewPopupState
                    $state.Rows=$case.Rows
                    Update-AgentViewPopupView 'static'
                    Show-AgentViewWidget -Rows $case.Rows
                    $widget=Get-AgentViewWidgetState
                    $expected=$case.Count
                    if(-not $expected){$expected=2}
                    $state.Order.Count | Should Be $expected
                    $widget.Cards.Count | Should Be $expected
                    for($i=0;$i -lt $rows.Count;$i++) {
                        $state.Order[$i] | Should Be $rows[$i].Provider
                        $value=[string](Get-QuotaRemaining $rows[$i])
                        $state.Cards[$rows[$i].Provider].BigNum.Text | Should Be $value
                        $widget.Cards[$i].Line.Text | Should Be (Get-AgentViewWidgetDetailText (Get-AgentViewCardModel $rows[$i]))
                    }
                } finally {
                    Hide-AgentViewWidget
                    $state=Get-AgentViewPopupState
                    Close-AgentViewPopup -Force
                    [AppDomain]::CurrentDomain.SetData('agent-view.popup',$null)
                }
            }
        } finally { $worker.Dispose() }
    }
    It 'accepts actual quota output from a background runspace' {
        $worker=[PowerShell]::Create()
        try {
            [void]$worker.AddScript({param($path)
                . $path
                Get-AgentQuotas -Ops @{ReadText={param($p)$null};Find={param($n)$null};Run={throw 'CLI must not run'}}
            }).AddArgument((Join-Path $PSScriptRoot '../src/Quota.ps1'))
            $pending=$worker.BeginInvoke()
            $rows=@(ConvertTo-QuotaRows ($worker.EndInvoke($pending)))
            $rows.Count | Should Be 2
            ($rows.Provider -join ',') | Should Be 'claude,codex'
            Format-QuotaTooltip $rows | Should Match 'Codex'
        } finally {$worker.Dispose()}
    }
}
