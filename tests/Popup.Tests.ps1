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
function New-AgTestRow([string]$Group, $Five, $Week) {
    $r = [pscustomobject]@{ Provider = "antigravity-$($Group.ToLowerInvariant() -replace '[^a-z0-9]+','-')"; Name = "Antigravity · $Group"; Ok = $true; Error = $null
        FiveHourUsed = $Five; WeekUsed = $Week; FiveHourResetsAt = $script:now.AddMinutes(90); WeekResetsAt = $script:now.AddDays(2); FetchedAt = $script:now }
    $r | Add-Member -NotePropertyMembers @{ Family = 'antigravity'; Group = $Group }
    $r
}
function Set-TestPresence($Families) {
    $state = [hashtable]::Synchronized(@{})
    if ($null -ne $Families) { $state['Families'] = [string[]]@($Families) }
    [AppDomain]::CurrentDomain.SetData('agent-view.ProviderPresence', $state)
}
$script:savedPresence = [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence')

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
        $c.MiniFiveValue.Text | Should Be '76%'
        $c.MiniFiveFill.Width | Should Be (56 * 0.76)
        $c.MiniWeekValue.Text | Should Be '88%'
        $c.Detail.Visibility | Should Be 'Collapsed'      # 2 row ⇒ chưa mở row nào
        $c.NameText.Text | Should Be 'Claude Code'
        $c.FiveValue.Text | Should Be '76%'
        $c.FiveFill.Width | Should Be (306 * 0.76)
        $c.ErrBox.Visibility | Should Be 'Collapsed'
        $c.Ring.Tag.Value | Should Be 76
        $x = $st.Cards['codex']
        $x.ErrBox.Visibility | Should Be 'Visible'
        $x.Meters.Visibility | Should Be 'Collapsed'
        $x.MiniFive.Visibility | Should Be 'Hidden'
        $x.MiniWeek.Visibility | Should Be 'Hidden'
        $x.SubText.Text | Should Be 'Không có số liệu mới'
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
        $c.MiniFiveTrack.Background | Should Be $st.Shimmer.Brush
        $c.MiniFiveFill.Visibility | Should Be 'Hidden'
        $c.FiveFill.Visibility | Should Be 'Hidden'
        $st.Ui.StatusText.Text | Should Be 'Đang tải…'
        $st.Ui.FootText.Text | Should Be 'Đang cập nhật…'
        $st.Shimmer.Running | Should Be $false     # cửa sổ chưa hiện → không chạy vòng lặp
        $st.Rows = @((New-TestRow 'codex' 50 70)); $st.Loading = $false
        Update-AgentViewPopupView 'static'
        $st.Order -join ',' | Should Be 'codex'
        $st.Cards.ContainsKey('claude') | Should Be $false
        $st.Cards['codex'].MiniFiveValue.Text | Should Be '50%'
        $st.Expanded | Should Be 'codex'                  # chỉ còn một row ⇒ luôn mở
        $st.Cards['codex'].Detail.Visibility | Should Be 'Visible'
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


Describe 'Popup kiểu B: nhóm, mở rộng, trạng thái trống' {
    BeforeEach { Reset-PopupState; Set-TestPresence @('claude','codex','antigravity') }
    AfterEach { Reset-PopupState; [AppDomain]::CurrentDomain.SetData('agent-view.ProviderPresence', $script:savedPresence) }
    It 'groups rows by family keeping first-seen order' {
        $rows = @((New-AgTestRow 'Gemini' 40 3), (New-TestRow), (New-AgTestRow 'Argon' $null 10), (New-TestRow 'codex'))
        $g = @(Get-AgentViewFamilyGroups $rows)
        ($g | ForEach-Object Family) -join ',' | Should Be 'antigravity,claude,codex'
        (@($g[0].Rows) | ForEach-Object Group) -join ',' | Should Be 'Gemini,Argon'
        Get-AgentViewFamilyName 'antigravity' | Should Be 'Antigravity'
        Get-AgentViewFamilyName 'zzz' | Should Be 'zzz'
    }
    It 'builds no-data rows only for detected, visible families in registry order' {
        $rows = @(Get-AgentViewEmptyRows @('antigravity','claude'))
        ($rows | ForEach-Object Provider) -join ',' | Should Be 'claude,antigravity'
        $rows[1].Name | Should Be 'Antigravity'; $rows[1].Error | Should Be 'Chưa có dữ liệu'; $rows[1].Family | Should Be 'antigravity'
        $view = @{ Detected = [string[]]@('claude','codex'); Hidden = [string[]]@('codex'); NoAgent = $false }
        (@(Get-AgentViewDisplayRows @() $view) | ForEach-Object Provider) -join ',' | Should Be 'claude'
        @(Get-AgentViewDisplayRows @() @{ Detected = [string[]]@(); Hidden = [string[]]@(); NoAgent = $true }).Count | Should Be 0
        @(Get-AgentViewDisplayRows @((New-TestRow)) $view).Count | Should Be 1
    }
    It 'keeps one expanded row and auto-expands a single row' {
        Get-AgentViewPopupExpandedKey $null ([string[]]@('claude')) | Should Be 'claude'
        Get-AgentViewPopupExpandedKey 'codex' ([string[]]@('claude','codex')) | Should Be 'codex'
        Get-AgentViewPopupExpandedKey 'gone' ([string[]]@('claude','codex')) | Should Be $null
        Get-AgentViewPopupExpandedKey $null ([string[]]@()) | Should Be $null
    }
    It 'caps the shell height to the work area minus both gaps' {
        Get-AgentViewPopupMaxHeight ([pscustomobject]@{ Height = 440 }) | Should Be 416
        Get-AgentViewPopupMaxHeight ([pscustomobject]@{ Height = 100 }) | Should Be 160
        (Get-AgentViewStatusModel @() -NoAgent).Text | Should Be 'Chưa phát hiện'
        (Get-AgentViewFooterModel @() -NoAgent).Text | Should Be 'Chưa có agent để theo dõi'
    }
    It 'renders five compact rows with an Antigravity header and toggles one row at a time' {
        [void](New-AgentViewPopupWindow)
        $st = Get-AgentViewPopupState
        $st.Rows = @((New-TestRow), (New-TestRow 'codex' 92 20), (New-AgTestRow 'Gemini' 92 3), (New-AgTestRow 'Claude/GPT' 0 0), (New-AgTestRow 'Argon' $null 10))
        Update-AgentViewPopupView 'static'
        $st.Order -join ',' | Should Be 'claude,codex,antigravity-gemini,antigravity-claude-gpt,antigravity-argon'
        $st.Ui.Cards.Children.Count | Should Be 6             # 5 row + tiêu đề Antigravity
        $st.Headers.ContainsKey('antigravity') | Should Be $true
        $st.Ui.Cards.Children.IndexOf($st.Headers['antigravity'].Root) | Should Be 2
        $st.Cards['antigravity-gemini'].NameText.Text | Should Be 'Gemini'
        $st.Cards['claude'].NameText.Text | Should Be 'Claude Code'
        $st.Cards['antigravity-argon'].MiniFive.Visibility | Should Be 'Hidden'
        $st.Cards['antigravity-argon'].MiniWeekValue.Text | Should Be '90%'
        $st.Cards['codex'].MiniFiveValue.Text | Should Be '8%'
        $st.Cards['antigravity-gemini'].Ring.Tag.Icon | Should Not BeNullOrEmpty
        $st.Expanded | Should Be $null
        $click = { param($card)
            $e = New-Object System.Windows.Input.MouseButtonEventArgs ([System.Windows.Input.Mouse]::PrimaryDevice), 0, ([System.Windows.Input.MouseButton]::Left)
            $e.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $card.Summary.RaiseEvent($e) }
        & $click $st.Cards['antigravity-gemini']
        $st.Expanded | Should Be 'antigravity-gemini'
        $st.Cards['antigravity-gemini'].Detail.Visibility | Should Be 'Visible'
        & $click $st.Cards['codex']
        $st.Expanded | Should Be 'codex'
        @($st.Cards.Values | Where-Object { $_.Detail.Visibility -eq 'Visible' }).Count | Should Be 1
        & $click $st.Cards['codex']
        $st.Expanded | Should Be $null
        # Cập nhật giữ row đang mở; row biến mất ⇒ đóng.
        & $click $st.Cards['antigravity-gemini']
        Update-AgentViewPopupView 'static'
        $st.Expanded | Should Be 'antigravity-gemini'
        & $click $st.Cards['antigravity-argon']
        $st.Rows = @($st.Rows | Select-Object -First 4); Update-AgentViewPopupView 'static'
        $st.Expanded | Should Be $null
        $st.Ui.Cards.Children.Count | Should Be 5
        # Chỉ còn một nhóm Antigravity ⇒ không tiêu đề, tên đầy đủ.
        $st.Rows = @((New-TestRow), (New-AgTestRow 'Gemini' 92 3)); Update-AgentViewPopupView 'static'
        $st.Headers.Count | Should Be 0
        $st.Cards['antigravity-gemini'].NameText.Text | Should Be 'Antigravity · Gemini'
    }
    It 'shows no-data rows per detected family while the first refresh has no rows' {
        Set-TestPresence @('codex','antigravity')
        [void](New-AgentViewPopupWindow)
        $st = Get-AgentViewPopupState
        $st.Rows = @(); Update-AgentViewPopupView 'static'
        $st.Order -join ',' | Should Be 'codex,antigravity'
        $st.Cards['antigravity'].SubText.Text | Should Be 'Không có số liệu mới'
        $st.Cards['antigravity'].ErrDetail.Text | Should Be 'Chưa có dữ liệu'
    }
    It 'shows the no-agent guide with a working rescan button' {
        Set-TestPresence @()
        $hits = @{ n = 0 }
        [void](New-AgentViewPopupWindow)
        $st = Get-AgentViewPopupState
        $st.OnRescan = { $hits.n++ }.GetNewClosure()
        $st.Rows = @(); Update-AgentViewPopupView 'static'
        $st.NoAgent | Should Be $true
        $st.Order.Count | Should Be 0
        $st.Ui.Cards.Children.Count | Should Be 1
        $st.Empty.EmptyTitle.Text | Should Be 'Chưa phát hiện agent nào'
        $st.Empty.EmptyList.Text | Should Be 'Claude Code · Codex · Antigravity'
        $st.Empty.RescanBtn.Visibility | Should Be 'Visible'
        $st.Ui.StatusText.Text | Should Be 'Chưa phát hiện'
        $st.Empty.RescanBtn.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        $hits.n | Should Be 1
        $st.Empty.EmptyNote.Text | Should Be 'Đang quét…'
        $st.Loading = $true; Update-AgentViewPopupView 'static'
        $st.Empty.EmptyNote.Text | Should Be 'Đang quét…'
        $st.Loading = $false; Update-AgentViewPopupView 'static'
        $st.Empty.EmptyNote.Text | Should Be 'Vẫn chưa phát hiện agent nào.'
        # Chưa quét xong (không có cache) ⇒ thẻ "đang tìm", không có nút.
        [AppDomain]::CurrentDomain.SetData('agent-view.ProviderPresence', $null)
        Update-AgentViewPopupView 'static'
        $st.NoAgent | Should Be $false
        $st.Empty.RescanBtn.Visibility | Should Be 'Collapsed'
        $st.Empty.EmptyTitle.Text | Should Be 'Đang tìm agent…'
    }
    It 'falls back to Invoke-AgentViewProviderRescan with the tray captured by OnRefresh' {
        Set-TestPresence @()
        $tray = @{ State = @{ Worker = 'busy'; RescanQueued = $false } }
        $refresh = { Start-AgentViewRefresh $tray -Manual }.GetNewClosure()
        [void](New-AgentViewPopupWindow)
        $st = Get-AgentViewPopupState
        $st.OnRefresh = $refresh; $st.OnRescan = $null
        Invoke-AgentViewPopupRescan
        $tray.State.RescanQueued | Should Be $true      # refresh đang chạy ⇒ xếp hàng quét lại
        [AppDomain]::CurrentDomain.GetData('agent-view.ProviderPresence').ContainsKey('Families') | Should Be $false
    }
    It 'limits the live popup to the work area with a scroll viewer' {
        try {
            $rows = @(foreach ($i in 1..14) { New-AgTestRow "G$i" 10 20 })
            Show-AgentViewPopup -Rows $rows
            $st = Get-AgentViewPopupState
            $st.Ui.Shell.MaxHeight | Should Be (Get-AgentViewPopupMaxHeight ([System.Windows.SystemParameters]::WorkArea))
            $st.Ui.Scroll.VerticalScrollBarVisibility | Should Be 'Auto'
            $st.Window.UpdateLayout()
            $st.Ui.Shell.ActualHeight | Should Not BeGreaterThan ($st.Ui.Shell.MaxHeight + 0.5)
        } finally { Reset-PopupState }
    }
}
