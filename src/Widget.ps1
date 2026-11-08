. (Join-Path $PSScriptRoot 'I18n.ps1')
Register-AgentViewStrings -Module 'widget' -Strings @{
    en = @{
        'title' = 'agent-view widget'
        'five' = '5h {0}'
        'week' = 'Week {0}'
        'runout' = 'out ~{0}'
    }
    vi = @{
        'title' = 'agent-view widget'
        'five' = '5h {0}'
        'week' = 'Tuần {0}'
        'runout' = 'hết ~{0}'
    }
}
# Floating Bezel widget, created lazily on the tray STA thread.
. (Join-Path $PSScriptRoot 'Ring.ps1')
. (Join-Path $PSScriptRoot 'Settings.ps1')
. (Join-Path $PSScriptRoot 'Popup.ps1')
function Get-AgentViewWidgetDetailText($Model, [datetime]$Now = (Get-Date)) {
    $parts = @()
    if ($null -ne $Model.Five.Remaining) { $parts += (T 'widget.five' -Args @($Model.Five.ValueText)) }
    if ($null -ne $Model.Week.Remaining) { $parts += (T 'widget.week' -Args @($Model.Week.ValueText)) }
    $text = $parts -join ' · ' 
    $primary=$Model.Five; $fallback=$Model.Week
    if($null -eq $primary.Remaining -or ($null -ne $fallback.Remaining -and $fallback.Remaining -lt $primary.Remaining)) {
        $primary=$Model.Week; $fallback=$Model.Five
    }
    $reset=$primary.Rel
    if(-not $reset){$reset=$fallback.Rel}
    if($reset){$text+=" · ↺ $reset"}
    # Dự báo chỉ cho cửa sổ sát nhất và chỉ khi sẽ hết trước reset.
    if($primary.ForecastKind -eq 'runout' -and $null -ne $primary.ForecastAt){
        $at=[datetime]$primary.ForecastAt
        $when=$(if($at.Date -eq $Now.Date){$at.ToString('HH:mm')}else{Format-QuotaResetAbsolute $at $Now})
        $text+=' · '+(T 'widget.runout' -Args @($when))
    }
    $text
}
function Get-AgentViewWidgetEdge($Area, [double]$X, [double]$Y) {
    $d=@{left=[math]::Abs($X-$Area.Left);right=[math]::Abs($Area.Right-$X);top=[math]::Abs($Y-$Area.Top)}
    @('right','left','top') | Sort-Object { $d[$_] } | Select-Object -First 1
}
function Get-AgentViewWidgetPlacement($Area, [string]$Edge, $Offset, [double]$Width, [double]$Height, [double]$Scale=1) {
    $l=$Area.Left/$Scale; $t=$Area.Top/$Scale; $r=$Area.Right/$Scale; $b=$Area.Bottom/$Scale
    $length=$b-$t-$Height-24; if ($Edge -eq 'top') { $length=$r-$l-$Width-24 }
    if ($null -eq $Offset) { $Offset=$length/2 }
    $o=[math]::Max(0,[math]::Min([math]::Max(0,$length),[double]$Offset))
    $x=$r-$Width-12; $y=$t+12+$o
    if ($Edge -eq 'left') { $x=$l+12 }
    if ($Edge -eq 'top') { $x=$l+12+$o; $y=$t+12 }
    [pscustomobject]@{Left=$x;Top=$y;Offset=$o}
}
function Get-AgentViewWidgetState {
    $s=[AppDomain]::CurrentDomain.GetData('agent-view.widget')
    if (-not $s) { $s=@{Window=$null;Cards=@();Settings=(Get-AgentViewSettings);Screen=$null;Scale=1;Expanded=$false;DockTimer=$null;CloseTimer=$null;OnOpenPopup=$null}; [AppDomain]::CurrentDomain.SetData('agent-view.widget',$s) }
    $s
}
function Test-AgentViewWidgetVisible { $s=Get-AgentViewWidgetState; return ($null -ne $s.Window -and $s.Window.IsVisible) }
function Set-AgentViewWidgetDock([switch]$Animate) {
    $s=Get-AgentViewWidgetState; $w=$s.Window
    $s.List.Orientation=$(if ($s.Settings.WidgetEdge -eq 'top') {'Horizontal'} else {'Vertical'})
    $grip=$w.FindName('Grip')
    $grip.Height=10;$grip.Width=[double]::NaN
    if($s.Settings.WidgetEdge -eq 'top'){$grip.Height=[double]::NaN;$grip.Width=10;$grip.VerticalAlignment='Center'}
    foreach ($c in $s.Cards) {
        if($c.Edge -ne $s.Settings.WidgetEdge){
            $c.Detail.BeginAnimation([Windows.FrameworkElement]::MaxWidthProperty,$null)
            $c.Detail.BeginAnimation([Windows.FrameworkElement]::MaxHeightProperty,$null)
            $c.Detail.MaxWidth=0; $c.Detail.MaxHeight=[double]::PositiveInfinity
            if($s.Settings.WidgetEdge -eq 'top'){$c.Detail.MaxWidth=230;$c.Detail.MaxHeight=0}
            $c.Edge=$s.Settings.WidgetEdge
        }
        $c.Panel.Orientation=$(if ($s.Settings.WidgetEdge -eq 'top') {'Vertical'} else {'Horizontal'})
        $c.Panel.Margin=$(if($s.Settings.WidgetEdge -eq 'top'){'4,0,4,0'}else{'0,4,0,4'})
        $c.Panel.FlowDirection=$(if ($s.Settings.WidgetEdge -eq 'right') {'RightToLeft'} else {'LeftToRight'})
        $c.Detail.FlowDirection='LeftToRight'
        $alignment=switch($s.Settings.WidgetEdge){right {'Right'} left {'Left'} top {'Center'}}
        $c.Name.TextAlignment=$alignment
        $c.Line.TextAlignment=$alignment
        $c.Compact.Orientation=$(if($s.Settings.WidgetEdge -eq 'top'){'Horizontal'}else{'Vertical'})
        $c.Compact.Width=$(if($s.Settings.WidgetEdge -eq 'top'){[double]::NaN}else{48})
        $c.Label.VerticalAlignment='Center'
        $c.Label.Margin=$(if($s.Settings.WidgetEdge -eq 'top'){'7,0,4,0'}else{'0,3,0,0'})
    }
    $w.UpdateLayout()
    $p=Get-AgentViewWidgetPlacement $s.Screen.WorkingArea $s.Settings.WidgetEdge $s.Settings.WidgetOffset ($w.ActualWidth-56) ($w.ActualHeight-60) $s.Scale
    $x=$p.Left-28; $y=$p.Top-20
    if ($s.DockTimer) { $s.DockTimer.Stop(); $s.DockTimer=$null }
    if (-not $Animate) { $w.Left=$x; $w.Top=$y; return }
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[timespan]::FromMilliseconds(15)
    $timer.Tag=@{W=$w;X=$w.Left;Y=$w.Top;TX=$x;TY=$y;Clock=[Diagnostics.Stopwatch]::StartNew()}
    $timer.Add_Tick({$v=$this.Tag; $k=[math]::Min(1,$v.Clock.Elapsed.TotalMilliseconds/240); $e=1-[math]::Pow(1-$k,3); $v.W.Left=$v.X+($v.TX-$v.X)*$e; $v.W.Top=$v.Y+($v.TY-$v.Y)*$e; if($k -ge 1){$this.Stop();$this.Tag=$null}})
    $s.DockTimer=$timer; $timer.Start()
}
function Set-AgentViewWidgetExpanded([bool]$Expanded) {
    $s=Get-AgentViewWidgetState; $s.Expanded=$Expanded
    foreach($c in $s.Cards) {
        $top=$s.Settings.WidgetEdge -eq 'top'
        $c.Detail.Margin=$(if(-not $Expanded){'0'}elseif($top){'0,6,0,0'}else{'6,0,8,0'})
        $property=[Windows.FrameworkElement]::MaxWidthProperty; $target=230
        if($top){$property=[Windows.FrameworkElement]::MaxHeightProperty;$target=44}
        $duration=160; if($Expanded){$duration=220}
        $a=New-Object Windows.Media.Animation.DoubleAnimation
        $a.To=$(if($Expanded){$target}else{0}); $a.Duration=[timespan]::FromMilliseconds($duration)
        $ease=New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode='EaseOut';$a.EasingFunction=$ease
        $c.Detail.BeginAnimation($property,$a)
        $o=New-Object Windows.Media.Animation.DoubleAnimation; $o.To=[double][int]$Expanded; $o.Duration=[timespan]::FromMilliseconds(160)
        $c.Detail.BeginAnimation([Windows.UIElement]::OpacityProperty,$o)
    }
}
function New-AgentViewWidgetWindow {
    Initialize-AgentViewWpf
    $s=Get-AgentViewWidgetState
    $x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="$(T 'widget.title')" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" ShowActivated="False" Topmost="True" ResizeMode="NoResize" SizeToContent="WidthAndHeight" FontFamily="Segoe UI" Foreground="@@av-text@@">
<Border x:Name="Shell" Margin="28,20,28,40" Padding="8" CornerRadius="14" BorderBrush="@@av-stroke@@" BorderThickness="1">
<Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="@@av-bg-top@@" Offset="0"/><GradientStop Color="@@av-bg@@" Offset="1"/></LinearGradientBrush></Border.Background>
<Border.Effect><DropShadowEffect BlurRadius="28" ShadowDepth="10" Opacity="0.5"/></Border.Effect>
<StackPanel x:Name="List"><TextBlock x:Name="Grip" Text="⠿" Foreground="@@av-text-3@@" HorizontalAlignment="Center" Cursor="SizeAll" Height="14"/></StackPanel>
</Border></Window>
'@
    $x=$x.Replace("`$(T 'widget.title')", (T 'widget.title'))
    $w=[Windows.Markup.XamlReader]::Parse((Expand-AgentViewXaml $x (Get-AgentViewTheme)));$s.Window=$w;$s.List=$w.FindName('List')
    [Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($w)
    $w.Add_SourceInitialized({
        if(-not ('AgentView.WidgetNative' -as [type])) { Add-Type 'using System;using System.Runtime.InteropServices;namespace AgentView { public static class WidgetNative { [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h,int n); [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h,int n,int v); }}' }
        $h=(New-Object Windows.Interop.WindowInteropHelper $this).Handle
        [void][AgentView.WidgetNative]::SetWindowLong($h,-20,([AgentView.WidgetNative]::GetWindowLong($h,-20) -bor 0x08000080))
    })
    $w.FindName('Grip').Add_MouseLeftButtonDown({
        $s=Get-AgentViewWidgetState; Set-AgentViewWidgetExpanded $false
        $shadow=$s.Window.FindName('Shell').Effect
        $shadow.BlurRadius=40;$shadow.ShadowDepth=18;$shadow.Opacity=0.6
        try{$s.Window.DragMove()}finally{$shadow.BlurRadius=28;$shadow.ShadowDepth=10;$shadow.Opacity=0.5}
        $pt=[Windows.Forms.Cursor]::Position; $s.Screen=[Windows.Forms.Screen]::FromPoint($pt)
        $s.Scale=[Windows.PresentationSource]::FromVisual($s.Window).CompositionTarget.TransformToDevice.M11
        $s.Settings.WidgetEdge=Get-AgentViewWidgetEdge $s.Screen.WorkingArea $pt.X $pt.Y
        $s.Settings.WidgetScreen=$s.Screen.DeviceName
        $offset=($s.Window.Top+20)-$s.Screen.WorkingArea.Top/$s.Scale-12
        if($s.Settings.WidgetEdge -eq 'top'){$offset=($s.Window.Left+28)-$s.Screen.WorkingArea.Left/$s.Scale-12}
        $s.Settings.WidgetOffset=$offset; Set-AgentViewWidgetDock -Animate
        $p=Get-AgentViewWidgetPlacement $s.Screen.WorkingArea $s.Settings.WidgetEdge $offset ($s.Window.ActualWidth-56) ($s.Window.ActualHeight-60) $s.Scale
        $s.Settings.WidgetOffset=$p.Offset; Save-AgentViewSettings $s.Settings
    })
    $s.CloseTimer=New-Object Windows.Threading.DispatcherTimer; $s.CloseTimer.Interval=[timespan]::FromMilliseconds(150)
    $s.CloseTimer.Add_Tick({$this.Stop(); Set-AgentViewWidgetExpanded $false})
    $w.Add_MouseEnter({$s=Get-AgentViewWidgetState;$s.CloseTimer.Stop();Set-AgentViewWidgetExpanded $true})
    $w.Add_MouseLeave({(Get-AgentViewWidgetState).CloseTimer.Start()})
    $w.Add_SizeChanged({$s=Get-AgentViewWidgetState;if($s.Screen){Set-AgentViewWidgetDock}})
}
function Update-AgentViewWidget {
    param($Rows,[switch]$Loading)
    $s=Get-AgentViewWidgetState; if(-not (Test-AgentViewWidgetVisible)){return}
    $rowsFlat=@(ConvertTo-QuotaRows $Rows)
    if(-not $rowsFlat.Count){$rowsFlat=@(Get-AgentViewEmptyRows)}
    if($s.Cards.Count -ne $rowsFlat.Count){
        foreach($c in $s.Cards){Suspend-AgentRing $c.Ring}
        while($s.List.Children.Count -gt 1){$s.List.Children.RemoveAt(1)}
        $s.Cards=@()
        foreach($r in $rowsFlat){
            $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='0,4,0,4'
            $compact=New-Object Windows.Controls.StackPanel; $compact.Width=48;$compact.FlowDirection='LeftToRight'
            $ring=New-AgentRing -Size 40 -Stroke 4 -Icon $r.Provider -IconSize 18
            $ring.HorizontalAlignment='Center'; [void]$compact.Children.Add($ring)
            $label=New-Object Windows.Controls.TextBlock; $label.FontSize=12;$label.FontWeight='SemiBold';$label.HorizontalAlignment='Center';[void]$compact.Children.Add($label)
            $detail=New-Object Windows.Controls.StackPanel; $detail.VerticalAlignment='Center';$detail.MaxWidth=0;$detail.Opacity=0;$detail.ClipToBounds=$true
            $name=New-Object Windows.Controls.TextBlock;$name.TextTrimming='CharacterEllipsis';$name.FontSize=12.5;$name.FontWeight='SemiBold'
            $line=New-Object Windows.Controls.TextBlock;$line.TextTrimming='CharacterEllipsis';$line.FontSize=11.5;$line.Foreground=ConvertTo-AgentViewBrush (Get-AgentViewTheme)['av-text-2']
            [void]$detail.Children.Add($name);[void]$detail.Children.Add($line)
            [void]$panel.Children.Add($compact);[void]$panel.Children.Add($detail);[void]$s.List.Children.Add($panel)
            $panel.Add_MouseLeftButtonUp({$s=Get-AgentViewWidgetState;if($s.OnOpenPopup){& $s.OnOpenPopup}})
            $s.Cards+=@{Panel=$panel;Compact=$compact;Detail=$detail;Name=$name;Line=$line;Label=$label;Ring=$ring}
        }
    }
    $history=Get-AgentViewPopupHistory; $now=Get-Date
    for($i=0;$i -lt $rowsFlat.Count;$i++){
        $r=$rowsFlat[$i];$c=$s.Cards[$i];$m=Get-AgentViewCardModel $r -Loading:$Loading -Now $now -History $history
        $c.Name.Text=$m.Name; $c.Line.Text=$m.ErrDetail
        if($m.State -eq 'ok'){$c.Line.Text=Get-AgentViewWidgetDetailText $m $now}
        $c.Label.Text=$(if($Loading){'…'}elseif($m.State -eq 'error'){'?'}else{"$($m.Value)%"})
        $c.Label.Foreground=ConvertTo-AgentViewBrush (Get-AgentViewTheme)[$m.Level]
        $label=$c.Label
        $tick={param($v)$label.Text=([string][int][math]::Round($v))+'%'}.GetNewClosure()
        Set-AgentRing -Ring $c.Ring -State $m.State -Value $m.Value -DurationMs 450 -OnTick $tick
    }
    Set-AgentViewWidgetDock
}
function Show-AgentViewWidget {
    param($Rows,[switch]$Loading,[scriptblock]$OnOpenPopup)
    $s=Get-AgentViewWidgetState; if($OnOpenPopup){$s.OnOpenPopup=$OnOpenPopup}
    if(-not $s.Window){New-AgentViewWidgetWindow}
    $s.Screen=@([Windows.Forms.Screen]::AllScreens | Where-Object DeviceName -eq $s.Settings.WidgetScreen) | Select-Object -First 1
    if(-not $s.Screen){$s.Screen=[Windows.Forms.Screen]::PrimaryScreen;$s.Settings.WidgetOffset=$null}
    $s.Window.Show();$s.Scale=[Windows.PresentationSource]::FromVisual($s.Window).CompositionTarget.TransformToDevice.M11
    Update-AgentViewWidget -Rows $Rows -Loading:$Loading
    foreach($c in $s.Cards){Resume-AgentRing $c.Ring}
}
function Hide-AgentViewWidget {
    $s=Get-AgentViewWidgetState
    if($s.CloseTimer){$s.CloseTimer.Stop()};if($s.DockTimer){$s.DockTimer.Stop()}
    foreach($c in $s.Cards){Suspend-AgentRing $c.Ring;if($c.Ring.Tag.Timer){$c.Ring.Tag.Timer.Stop();$c.Ring.Tag.Timer=$null}}
    if($s.Window){$s.Window.Close();$s.Window=$null;$s.Cards=@()}
}
