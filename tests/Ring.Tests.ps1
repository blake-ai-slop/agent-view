. "$PSScriptRoot/../src/Ring.ps1"
# Ring.ps1 tự nạp Theme.ps1/Format.ps1 thật cùng thư mục.
function Test-Near($A, $B) { [math]::Abs([double]$A - [double]$B) -lt 0.001 }

Describe 'Ring geometry' {
    It 'computes radius leaving room for ticks' {
        (Get-AgentRingRadius 60 5 -Ticks).Radius | Should Be 24.5
        (Get-AgentRingRadius 60 5 -Ticks).Center | Should Be 30
        (Get-AgentRingRadius 40 4).Radius | Should Be 18
    }
    It 'places points clockwise from 12 o clock' {
        $p = Get-AgentArcPoint 30 24.5 0;  (Test-Near $p.X 30) | Should Be $true; (Test-Near $p.Y 5.5) | Should Be $true
        $p = Get-AgentArcPoint 30 24.5 25; (Test-Near $p.X 54.5) | Should Be $true; (Test-Near $p.Y 30) | Should Be $true
        $p = Get-AgentArcPoint 30 24.5 50; (Test-Near $p.X 30) | Should Be $true; (Test-Near $p.Y 54.5) | Should Be $true
        $p = Get-AgentArcPoint 30 24.5 75; (Test-Near $p.X 5.5) | Should Be $true; (Test-Near $p.Y 30) | Should Be $true
    }
    It 'plans arc segments with IsLargeArc only past half' {
        $plan = Get-AgentArcPlan 30 24.5 0
        @($plan.Segments).Count | Should Be 0; $plan.Visible | Should Be $false
        $plan = Get-AgentArcPlan 30 24.5 30
        @($plan.Segments).Count | Should Be 1; $plan.Segments[0].IsLargeArc | Should Be $false; $plan.Visible | Should Be $true
        (Get-AgentArcPlan 30 24.5 50).Segments[0].IsLargeArc | Should Be $false
        (Get-AgentArcPlan 30 24.5 51).Segments[0].IsLargeArc | Should Be $true
        (Get-AgentArcPlan 30 24.5 0.3).Visible | Should Be $false
    }
    It 'splits a full ring into two half arcs ending at the start' {
        foreach ($v in 100, 140) {
            $plan = Get-AgentArcPlan 30 24.5 $v
            @($plan.Segments).Count | Should Be 2
            (Test-Near $plan.Segments[0].Point.Y 54.5) | Should Be $true
            (Test-Near $plan.Segments[1].Point.X $plan.Start.X) | Should Be $true
            (Test-Near $plan.Segments[1].Point.Y $plan.Start.Y) | Should Be $true
        }
        @((Get-AgentArcPlan 30 24.5 -5).Segments).Count | Should Be 0
    }
    It 'draws ticks 1px outside the stroke and 2.5 long' {
        $t = Get-AgentRingTickLine 30 24.5 5 30
        $r1 = [math]::Sqrt([math]::Pow($t.X1 - 30, 2) + [math]::Pow($t.Y1 - 30, 2))
        $r2 = [math]::Sqrt([math]::Pow($t.X2 - 30, 2) + [math]::Pow($t.Y2 - 30, 2))
        (Test-Near $r1 28) | Should Be $true
        (Test-Near $r2 30.5) | Should Be $true
        ($t.X1 -gt 30 -and $t.Y1 -gt 30) | Should Be $true   # 30% nằm ngay dưới 3 giờ
        $t = Get-AgentRingTickLine 30 24.5 5 10
        ($t.X1 -gt 30 -and $t.Y1 -lt 30) | Should Be $true
    }
    It 'sizes the error dash in stroke units' {
        $d = Get-AgentRingDash 24.5 5
        $d.Count | Should Be 2
        $seg = 2 * [math]::PI * 24.5 / 14
        (Test-Near $d[0] ($seg * 0.55 / 5)) | Should Be $true
        (Test-Near $d[1] ($seg * 0.45 / 5)) | Should Be $true
        (Get-AgentRingDash 2 4).Count | Should Be 2
    }
}

Describe 'Ring style' {
    It 'maps level colors and breathing glow only for warn and crit' {
        $s = Get-AgentRingStyle 'ok' 76
        $s.Level | Should Be 'ok'; $s.Lv | Should Be '#3DD68C'; $s.Hi | Should Be '#9AF2C6'; $s.Glow | Should Be $false
        $s = Get-AgentRingStyle 'ok' 25
        $s.Level | Should Be 'warn'; $s.Glow | Should Be $true; $s.GlowHalfMs | Should Be 1200
        $s = Get-AgentRingStyle 'ok' 8
        $s.Level | Should Be 'crit'; $s.GlowHalfMs | Should Be 700; $s.Lv | Should Be '#F2555A'
    }
    It 'styles loading and error states' {
        $s = Get-AgentRingStyle 'loading' $null
        $s.Spin | Should Be $true; $s.TicksVisible | Should Be $false; $s.Level | Should Be 'unk'; $s.Glow | Should Be $false
        $s = Get-AgentRingStyle 'error' 50
        $s.Dashed | Should Be $true; $s.Track | Should Be '#3A4152'; $s.CenterOpacity | Should Be 0.55; $s.Glow | Should Be $false
        (Get-AgentRingStyle 'ok' 50).Track | Should Be '#2A3040'
    }
}

Describe 'Ring WPF element' {
    It 'builds a 60px ring with ticks and icon' {
        $ring = New-AgentRing -Size 60 -Stroke 5 -Ticks -Icon claude -IconSize 26
        ($ring -is [System.Windows.Controls.Grid]) | Should Be $true
        $ring.Width | Should Be 60
        $ring.Tag.Ticks.Count | Should Be 2
        $ring.Tag.Icon.Width | Should Be 26
        $ring.Tag.State | Should Be 'error'
        (New-AgentRing -Size 40 -Stroke 4 -Icon codex -IconSize 18).Tag.Ticks.Count | Should Be 0
        (New-AgentRing -Size 16 -Stroke 2.5).Tag.Icon | Should Be $null
    }
    It 'rebuilds arc segments and reports ticks immediately without duration' {
        $ring = New-AgentRing -Size 60 -Stroke 5 -Ticks
        $script:seen = @()
        Set-AgentRing -Ring $ring -State ok -Value 76 -DurationMs 0 -OnTick { param($v) $script:seen += $v }
        $ring.Tag.Figure.Segments.Count | Should Be 1
        $ring.Tag.Figure.Segments[0].IsLargeArc | Should Be $true
        $ring.Tag.Value | Should Be 76
        $script:seen[-1] | Should Be 76
        Set-AgentRing -Ring $ring -State ok -Value 100 -DurationMs 0
        $ring.Tag.Figure.Segments.Count | Should Be 2
        $ring.Tag.Arc.Opacity | Should Be 1
        $ring.Tag.Track.StrokeDashArray | Should Be $null
    }
    It 'shows dashed track for error and spinning quarter for loading' {
        $ring = New-AgentRing -Size 60 -Stroke 5 -Ticks
        Set-AgentRing -Ring $ring -State ok -Value 50 -DurationMs 0
        Set-AgentRing -Ring $ring -State error
        $ring.Tag.Track.StrokeDashArray.Count | Should Be 2
        $ring.Tag.Arc.Opacity | Should Be 0
        $ring.Tag.Value | Should Be 0
        $ring.Tag.CenterHost.Opacity | Should Be 0.55
        Set-AgentRing -Ring $ring -State loading
        $ring.Tag.Ticks[0].Visibility | Should Be 'Collapsed'
        $ring.Tag.Figure.Segments.Count | Should Be 1
        $ring.Tag.Rotate.HasAnimatedProperties | Should Be $true
        Set-AgentRing -Ring $ring -State ok -Value 60 -DurationMs 0
        $ring.Tag.Rotate.HasAnimatedProperties | Should Be $false
        $ring.Tag.Ticks[0].Visibility | Should Be 'Visible'
    }
    It 'treats ok without value as error' {
        $ring = New-AgentRing -Size 40 -Stroke 4
        Set-AgentRing -Ring $ring -State ok -Value $null -DurationMs 0
        $ring.Tag.State | Should Be 'error'
    }
    It 'runs the glow loop only for warn/crit and stops it when suspended' {
        $ring = New-AgentRing -Size 60 -Stroke 5 -Ticks
        Set-AgentRing -Ring $ring -State ok -Value 80 -DurationMs 0
        $ring.Tag.Glow.HasAnimatedProperties | Should Be $false
        Set-AgentRing -Ring $ring -State ok -Value 20 -DurationMs 0
        $ring.Tag.Glow.HasAnimatedProperties | Should Be $true
        Suspend-AgentRing $ring
        $ring.Tag.Glow.HasAnimatedProperties | Should Be $false
        Set-AgentRing -Ring $ring -State ok -Value 5 -DurationMs 0
        $ring.Tag.Glow.HasAnimatedProperties | Should Be $false
        Resume-AgentRing $ring
        $ring.Tag.Glow.HasAnimatedProperties | Should Be $true
        $ring.Tag.Style.GlowHalfMs | Should Be 700
        Set-AgentRing -Ring $ring -State ok -Value 90 -DurationMs 0
        $ring.Tag.Glow.HasAnimatedProperties | Should Be $false
    }
    It 'starts a tween from the given value' {
        $ring = New-AgentRing -Size 60 -Stroke 5
        Set-AgentRing -Ring $ring -State ok -Value 70 -DurationMs 450 -From 0
        $ring.Tag.Timer | Should Not Be $null
        $ring.Tag.Value | Should Be 0
        Set-AgentRing -Ring $ring -State ok -Value 40 -DurationMs 0
        $ring.Tag.Timer | Should Be $null
        $ring.Tag.Value | Should Be 40
    }
}
