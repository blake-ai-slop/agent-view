# Dùng Theme/Format/Tray THẬT (Tray.ps1 dot-source Theme, Format, Popup, Ring) — không stub.
. "$PSScriptRoot/../src/Tray.ps1"

Set-AgentViewLanguage vi
$script:now = [datetime]'2026-11-07T14:32:00'
function New-TestRow([string]$Provider = 'claude', $Five = 24, $Week = 12, [bool]$Ok = $true, [string]$Err = $null) {
    $name = @{ claude = 'Claude Code'; codex = 'Codex' }[$Provider]
    [pscustomobject]@{ Provider = $Provider; Name = $name; Ok = $Ok; Error = $Err; FiveHourUsed = $Five; WeekUsed = $Week
        FiveHourResetsAt = $script:now.AddMinutes(135); WeekResetsAt = $script:now.AddMinutes(3 * 1440 + 250); FetchedAt = $script:now.AddMinutes(-1) }
}
function Reset-PopupState { Close-AgentViewPopup -Force; [AppDomain]::CurrentDomain.SetData('agent-view.popup', $null) }

Describe 'Popup pure helpers' {
    It 'anchors the popup 12px from the work area corner including shadow margins' {
        $p = Get-AgentViewPopupPlacement ([pscustomobject]@{ Right = 1920; Bottom = 1032 }) 480
        $p.Left | Should Be 1520      # 1920 − 12 − 360 − 28
        $p.Top | Should Be 584        # 1032 − 12 + 44 − 480
        $p.Width | Should Be 416
    }
    It 'builds an ok card model' {
        $m = Get-AgentViewCardModel (New-TestRow) -Now $script:now
        $m.State | Should Be 'ok'; $m.Value | Should Be 76; $m.Level | Should Be 'ok'
        $m.Name | Should Be 'Claude Code'
        $m.Sub | Should Be 'Giới hạn sát nhất: 5 giờ'
        $m.NumText | Should Be '76'
        $m.Five.ValueText | Should Be '76%'; $m.Five.Level | Should Be 'ok'
        $m.Five.Rel | Should Be 'còn 2g 15p'; $m.Five.Abs | Should Be '· 16:47'
        $m.Week.ValueText | Should Be '88%'
        $m.Week.Rel | Should Be 'còn 3 ngày 4g'; $m.Week.Abs | Should Match '^· T\d 1\d/11 '
    }
    It 'colors each window by its own remaining value' {
        $m = Get-AgentViewCardModel (New-TestRow 'codex' 75 40) -Now $script:now
        $m.Level | Should Be 'warn'; $m.Five.Level | Should Be 'warn'; $m.Week.Level | Should Be 'ok'
        $m.Five.Remaining | Should Be 25
        (Get-AgentViewCardModel (New-TestRow 'codex' 120 $null) -Now $script:now).Five.Remaining | Should Be 0
        (Get-AgentViewCardModel (New-TestRow 'codex' 50 $null) -Now $script:now).Week.ValueText | Should Be '–'
    }
    It 'builds error and loading models' {
        $m = Get-AgentViewCardModel (New-TestRow 'codex' 39 19 $false 'Hết thời gian chờ') -Now $script:now.AddMinutes(11)
        $m.State | Should Be 'error'; $m.NumText | Should Be '–'; $m.Level | Should Be 'unk'
        $m.Sub | Should Be 'Không có số liệu mới'
        $m.ErrDetail | Should Be 'Hết thời gian chờ'
        $m.Stale | Should Be 'Số liệu cuối: còn 61% · 12 phút trước'
        $m = Get-AgentViewCardModel (New-TestRow 'codex' $null $null $false 'Chưa đăng nhập') -Now $script:now
        $m.Stale | Should Be $null
        (Get-AgentViewCardModel (New-TestRow 'claude' $null $null $true) -Now $script:now).State | Should Be 'error'
        $m = Get-AgentViewCardModel (New-TestRow) -Loading -Now $script:now
        $m.State | Should Be 'loading'; $m.NumText | Should Be '00'; $m.Sub | Should Be 'Đang đọc quota…'
        $m.Five.ValueText | Should Be '76%'
    }
    It 'picks the status chip from the worst readable provider' {
        $rows = @((New-TestRow), (New-TestRow 'codex' 92 20))
        (Get-AgentViewStatusModel $rows).Text | Should Be 'Sắp cạn'
        (Get-AgentViewStatusModel @((New-TestRow), (New-TestRow 'codex' 50 50 $false 'x'))).Level | Should Be 'ok'
        (Get-AgentViewStatusModel @((New-TestRow 'codex' 50 50 $false 'x'))).Text | Should Be 'Không rõ'
        (Get-AgentViewStatusModel $rows -Loading).Text | Should Be 'Đang tải…'
    }
    It 'builds the footer from the newest fetch and flags errors' {
        $rows = @((New-TestRow), (New-TestRow 'codex'))
        $rows[1].FetchedAt = $script:now.AddSeconds(-10)
        (Get-AgentViewFooterModel $rows -Now $script:now).Text | Should Be 'Cập nhật vừa xong'
        $rows[1].Ok = $false
        $f = Get-AgentViewFooterModel $rows -Now $script:now.AddMinutes(5)
        $f.Text | Should Be 'Cập nhật 5 phút trước · có lỗi'; $f.Stale | Should Be $true
        (Get-AgentViewFooterModel $rows -Loading -Now $script:now).Text | Should Be 'Đang cập nhật…'
    }
    It 'expands theme tokens in XAML' {
        Expand-AgentViewXaml 'a="@@av-bg@@" b="@@crit-hi@@"' (Get-AgentViewTheme) | Should Be 'a="#12151C" b="#FF9E94"'
        (Get-AgentViewPopupXaml) | Should Not Match '\$\('
    }
}

Describe 'Popup window (không hiện cửa sổ)' {
    BeforeEach { Reset-PopupState }
    AfterEach { Reset-PopupState }
    It 'builds the window with required chrome' {
        $w = New-AgentViewPopupWindow
        $w.WindowStyle | Should Be 'None'
        $w.AllowsTransparency | Should Be $true
        $w.ShowInTaskbar | Should Be $false
        $w.Topmost | Should Be $true
        $w.Width | Should Be 416
        $st = Get-AgentViewPopupState
        foreach ($k in $st.Ui.Keys) { ($null -ne $st.Ui[$k]) | Should Be $true }
        $st.Ui.Shell.Effect.BlurRadius | Should Be 32
        Test-AgentViewPopupOpen | Should Be $false
    }
    It 'renders ok and error cards with text and bars' {
        [void](New-AgentViewPopupWindow)
        $st = Get-AgentViewPopupState
        $st.Rows = @((New-TestRow), (New-TestRow 'codex' 39 19 $false 'Hết thời gian chờ'))
        Update-AgentViewPopupView 'static'
        $st.Order -join ',' | Should Be 'claude,codex'
        $st.Ui.Cards.Children.Count | Should Be 2
        $c = $st.Cards['claude']
        $c.BigNum.Text | Should Be '76'
        $c.NameText.Text | Should Be 'Claude Code'
        $c.FiveValue.Text | Should Be '76%'
        $c.FiveFill.Width | Should Be (306 * 0.76)
        $c.ErrBox.Visibility | Should Be 'Collapsed'
        $c.Ring.Tag.Value | Should Be 76
        $x = $st.Cards['codex']
        $x.ErrBox.Visibility | Should Be 'Visible'
        $x.Meters.Visibility | Should Be 'Collapsed'
        $x.BigNum.Text | Should Be '–'
        $x.ErrDetail.Text | Should Be 'Hết thời gian chờ'
        $x.RetryBtn.Tag | Should Be 'codex'
        $x.Ring.Tag.State | Should Be 'error'
        $st.Ui.StatusText.Text | Should Be 'Thoải mái'
        $st.Ui.FootText.Text | Should Match 'có lỗi$'
    }
    It 'renders loading with shimmer and keeps card order stable on update' {
        [void](New-AgentViewPopupWindow)
        $st = Get-AgentViewPopupState
        $st.Rows = @((New-TestRow), (New-TestRow 'codex' 50 70)); $st.Loading = $true
        Update-AgentViewPopupView 'static'
        $c = $st.Cards['claude']
        $c.Ring.Tag.State | Should Be 'loading'
        $c.NumWrap.Background | Should Be $st.Shimmer.Brush
        $c.FiveFill.Visibility | Should Be 'Hidden'
        $st.Ui.StatusText.Text | Should Be 'Đang tải…'
        $st.Ui.FootText.Text | Should Be 'Đang cập nhật…'
        $st.Shimmer.Running | Should Be $false     # cửa sổ chưa hiện → không chạy vòng lặp
        $st.Rows = @((New-TestRow 'codex' 50 70)); $st.Loading = $false
        Update-AgentViewPopupView 'static'
        $st.Order -join ',' | Should Be 'codex'
        $st.Cards.ContainsKey('claude') | Should Be $false
        $st.Cards['codex'].BigNum.Text | Should Be '30'
    }
    It 'only stores rows when updating a closed popup' {
        Update-AgentViewPopup -Rows @((New-TestRow)) -Loading
        $st = Get-AgentViewPopupState
        $st.Window | Should Be $null
        $st.Loading | Should Be $true
        @($st.Rows).Count | Should Be 1
        Hide-AgentViewPopup
        Test-AgentViewPopupOpen | Should Be $false
    }
}


Describe 'Optional windows in live popup layout' {
    It 'collapses missing meters and restores them on refresh while open' {
        try {
            $row=New-TestRow
            Show-AgentViewPopup -Rows @($row)
            $st=Get-AgentViewPopupState
            $c=$st.Cards.claude
            Set-AgentViewCard $c (Get-AgentViewCardModel $row) 'static'
            $c.Root.Measure((New-Object Windows.Size 332,1000))
            $both=$c.Root.DesiredSize.Height
            foreach ($mode in 'week','five','both') {
                $row.FiveHourUsed=$(if($mode -ne 'week'){24}else{$null})
                $row.WeekUsed=$(if($mode -ne 'five'){12}else{$null})
                Update-AgentViewPopup -Rows @(ConvertTo-QuotaRows (,@($row)))
                $c.Root.Measure((New-Object Windows.Size 332,1000))
                $c.FiveBlock.Visibility | Should Be $(if($mode -eq 'week'){'Collapsed'}else{'Visible'})
                $c.WeekBlock.Visibility | Should Be $(if($mode -eq 'five'){'Collapsed'}else{'Visible'})
                $c.MeterGap.Visibility | Should Be $(if($mode -eq 'both'){'Visible'}else{'Collapsed'})
                if ($mode -ne 'both') { $c.Root.DesiredSize.Height | Should BeLessThan $both }
                $model=Get-AgentViewCardModel $row
                $model.Sub | Should Be $(switch($mode){week {'Chỉ giới hạn tuần'} five {'Chỉ giới hạn 5 giờ'} both {'Giới hạn sát nhất: 5 giờ'}})
            }
        } finally { Reset-PopupState; $st.Window | Should BeNullOrEmpty }
    }
}
