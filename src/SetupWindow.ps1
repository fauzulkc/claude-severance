<#
  Claude Severance Setup: the setup window (WPF).
  The look is "the severed floor": a quiet mid-century office by day (light) and an old phosphor terminal by night
  (dark). One vertical seam splits the window into two halves, the work floor and the outside, and a band of light
  travels down it in the colour of the moment:
    waiting   deciding (update, uninstall)   working   removing or stopped   done
  Type is IBM Plex Sans with Plex Mono for labels and numbers; cards and buttons have 8 px corners.
  -Mode auto|install|update|manage|uninstall   -Preview (changes nothing)   -Theme system|light|dark   -Screen <name> (preview)
#>
param(
    [string]$Mode = 'auto',
    [switch]$Preview,
    [ValidateSet('system', 'light', 'dark')][string]$Theme = 'system',
    [string]$Screen = '',
    [string]$Capture = '',
    [int]$CaptureDelay = 1600
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
Import-Module (Join-Path $PSScriptRoot 'Severance.psm1') -Force

$DOT = [string][char]0x00B7
$ELL = [string][char]0x2026
$ARR = [string][char]0x2192
$INV = [Globalization.CultureInfo]::InvariantCulture

# ======================================================================================== tokens
# Floor is the left half of the window (the work floor); Canvas is the right half (the outside).
# Each moment is @(seam light, text and numbers in that moment's colour).
$Tokens = @{
    light = @{
        Canvas = '#F3F4F1'; Floor = '#ECEFEA'; Surface = '#FBFCFA'; Surface2 = '#E4E8E3'; Ink = '#13201C'; Muted = '#55625D'; Subtle = '#6F7B76'
        Faint = '#A3ADA8'; Hairline = '#D7DCD6'; Signal = '#2F5D4F'; SignalHover = '#244A3F'; SignalInk = '#F3F4F1'; Neg = '#B4442E'
        Tile = '#2F5D4F'; TileInk = '#F3F4F1'; DigitOp = 0.11; FieldBg = '#EDF0EB'
        waiting = @('#8C9A94', '#55625D'); deciding = @('#C1912F', '#94691A'); working = @('#3A9A94', '#2A7A75')
        removing = @('#C4533B', '#A63E2A'); done = @('#4E8A68', '#3A7254')
    }
    dark  = @{
        Canvas = '#06141A'; Floor = '#08191F'; Surface = '#0B1E25'; Surface2 = '#12303A'; Ink = '#CFEDEA'; Muted = '#82A9A6'; Subtle = '#638B88'
        Faint = '#3D5E5E'; Hairline = '#17323A'; Signal = '#7FD8CF'; SignalHover = '#A3E6DF'; SignalInk = '#06141A'; Neg = '#F0806A'
        Tile = '#CFEDEA'; TileInk = '#06141A'; DigitOp = 0.17; FieldBg = '#10272F'
        waiting = @('#5F8784', '#82A9A6'); deciding = @('#E0B25A', '#E0B25A'); working = @('#7FD8CF', '#7FD8CF')
        removing = @('#F0806A', '#F0806A'); done = @('#8FD3A6', '#8FD3A6')
    }
}
$ShineMs = @{ waiting = 7000; deciding = 7000; working = 3200; removing = 3200; done = 5600 }

function Get-SystemTheme {
    try {
        $v = Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'
        if ($v -eq 0) { return 'dark' }
    } catch { }
    return 'light'
}
$ThemeName = $Theme
if ($ThemeName -eq 'system') { $ThemeName = Get-SystemTheme }
$P = $Tokens[$ThemeName]

function C([string]$Hex, [double]$Alpha = 1) {
    $c = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($Hex)
    return [Windows.Media.Color]::FromArgb([byte][math]::Round(255 * $Alpha), $c.R, $c.G, $c.B)
}
function B([string]$Hex, [double]$Alpha = 1) { return (New-Object Windows.Media.SolidColorBrush (C $Hex $Alpha)) }

# ======================================================================================== window markup
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Severance Setup" Width="520" Height="640" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" ShowInTaskbar="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType"
        UseLayoutRounding="True" SnapsToDevicePixels="True" FocusVisualStyle="{x:Null}">
  <Window.Resources>
    <ControlTemplate x:Key="PillTemplate" TargetType="Button">
      <Grid>
        <Border x:Name="Focus" CornerRadius="11" Margin="-3" BorderThickness="2" BorderBrush="{DynamicResource Focus}" Visibility="Collapsed"/>
        <Border x:Name="B" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </Grid>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter TargetName="B" Property="Background" Value="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}"/>
        </Trigger>
        <Trigger Property="IsKeyboardFocused" Value="True">
          <Setter TargetName="Focus" Property="Visibility" Value="Visible"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Opacity" Value="0.4"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>

    <Style x:Key="Pill" TargetType="Button">
      <Setter Property="Template" Value="{StaticResource PillTemplate}"/>
      <Setter Property="FontFamily" Value="{DynamicResource FontText}"/>
      <Setter Property="FontWeight" Value="Medium"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="Padding" Value="18,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Pill}">
      <Setter Property="Background" Value="{DynamicResource Signal}"/>
      <Setter Property="Foreground" Value="{DynamicResource SignalInk}"/>
      <Setter Property="Tag" Value="{DynamicResource SignalHover}"/>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Pill}">
      <Setter Property="Background" Value="{DynamicResource Frost}"/>
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Hairline}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Tag" Value="{DynamicResource GhostHover}"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Pill}">
      <Setter Property="Background" Value="{DynamicResource Frost}"/>
      <Setter Property="Foreground" Value="{DynamicResource Neg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource NegLine}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Tag" Value="{DynamicResource NegSoft}"/>
    </Style>
    <Style x:Key="GhostSmall" TargetType="Button" BasedOn="{StaticResource Ghost}">
      <Setter Property="Height" Value="30"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="FontSize" Value="12.5"/>
    </Style>

    <!-- A colour choice in the tile picker: a disc, ringed when chosen or focused -->
    <Style x:Key="Swatch" TargetType="Button">
      <Setter Property="Width" Value="26"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Ellipse x:Name="Ring" Stroke="{TemplateBinding BorderBrush}" StrokeThickness="2"/>
              <Ellipse Margin="4" Fill="{TemplateBinding Background}"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Ring" Property="Stroke" Value="{DynamicResource Focus}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- An account's tile, clickable to open its colour and logo picker -->
    <Style x:Key="TileBtn" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="Focus" CornerRadius="9" Margin="-3" BorderThickness="2" BorderBrush="{DynamicResource Focus}" Visibility="Collapsed"/>
              <ContentPresenter x:Name="C"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="C" Property="Opacity" Value="0.82"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Focus" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Link" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="FontFamily" Value="{DynamicResource FontText}"/>
      <Setter Property="FontWeight" Value="Medium"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent" Padding="{TemplateBinding Padding}" BorderThickness="0,0,0,1" BorderBrush="Transparent">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="B" Property="BorderBrush" Value="{DynamicResource Ink}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Win" TargetType="Button">
      <Setter Property="Width" Value="32"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent" CornerRadius="16">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="{DynamicResource Etch}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="B" Property="Background" Value="{DynamicResource Etch}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Tag" Value="{DynamicResource Signal}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Background="Transparent" MinHeight="48">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <ContentPresenter VerticalAlignment="Center" Margin="16,9,14,9"/>
              <Grid Grid.Column="1" Margin="0,0,16,0" VerticalAlignment="Center">
                <Border x:Name="FocusRing" Width="42" Height="26" CornerRadius="13" BorderThickness="2" BorderBrush="{DynamicResource Focus}" Visibility="Collapsed"/>
                <Border x:Name="Track" Width="36" Height="20" CornerRadius="10" Background="{DynamicResource Surface2}" BorderBrush="{DynamicResource Hairline}" BorderThickness="1">
                  <Ellipse x:Name="Knob" Width="14" Height="14" Fill="{DynamicResource Subtle}" HorizontalAlignment="Left" Margin="2,0"/>
                </Border>
              </Grid>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}"/>
                <Setter TargetName="Knob" Property="Fill" Value="{DynamicResource SignalInk}"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="FocusRing" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.45"/>
                <Setter Property="Cursor" Value="Arrow"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- A soft filled field: no box until you point at it; a ring in the signal colour while typing, in red when wrong
         (Uid="error"). The last matching trigger wins, so the error ring shows even while focused. -->
    <Style x:Key="Field" TargetType="TextBox">
      <Setter Property="Height" Value="36"/>
      <Setter Property="FontFamily" Value="{DynamicResource FontText}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource Ink}"/>
      <Setter Property="SelectionBrush" Value="{DynamicResource Ring}"/>
      <Setter Property="Background" Value="{DynamicResource FieldBg}"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Padding" Value="11,0"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <!-- WPF already applies Padding inside PART_ContentHost, so the border adds none and the hint borrows it -->
            <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1.5"
                    CornerRadius="8">
              <Grid>
                <TextBlock x:Name="Hint" Text="{TemplateBinding Tag}" Foreground="{DynamicResource Faint}" VerticalAlignment="Center"
                           Margin="{TemplateBinding Padding}" Padding="2,0,0,0" Visibility="Collapsed" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
                <ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="Center" Focusable="False"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="Text" Value="">
                <Setter TargetName="Hint" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="BorderBrush" Value="{DynamicResource Hairline}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="B" Property="BorderBrush" Value="{DynamicResource Signal}"/>
                <Setter TargetName="B" Property="Background" Value="{DynamicResource Surface}"/>
              </Trigger>
              <Trigger Property="Uid" Value="error">
                <Setter TargetName="B" Property="BorderBrush" Value="{DynamicResource Neg}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- An account's row in the list: the whole row opens or closes its details -->
    <Style x:Key="RowBtn" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Stretch"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="{DynamicResource Etch}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="B" Property="Background" Value="{DynamicResource Etch}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="6"/>
      <Setter Property="MinWidth" Value="6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border CornerRadius="3" Background="{DynamicResource Faint}" Opacity="0.7"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border x:Name="Panel" Background="{DynamicResource Canvas}" BorderBrush="{DynamicResource Hairline}" BorderThickness="1" ClipToBounds="True">
    <Border.RenderTransform><TranslateTransform x:Name="PanelShift"/></Border.RenderTransform>
    <Grid>
      <!-- the severed floor: the work half on the left, one seam down the middle, light travelling down it -->
      <Grid x:Name="Backdrop" IsHitTestVisible="False" Margin="0,44,0,0" ClipToBounds="True">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
        <Border Grid.Column="0" Background="{DynamicResource Floor}"/>
        <Canvas x:Name="Digits" Grid.ColumnSpan="2" Opacity="0">
          <Canvas.RenderTransform><TranslateTransform x:Name="DigitShift"/></Canvas.RenderTransform>
        </Canvas>
        <Rectangle Grid.ColumnSpan="2" Width="1" HorizontalAlignment="Center" Fill="{DynamicResource Hairline}"/>
        <Rectangle x:Name="SeamLight" Grid.ColumnSpan="2" Width="1" Height="150" HorizontalAlignment="Center" VerticalAlignment="Top">
          <Rectangle.RenderTransform><TranslateTransform x:Name="SeamShift" Y="-150"/></Rectangle.RenderTransform>
        </Rectangle>
      </Grid>

      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="44"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="3"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" BorderBrush="{DynamicResource Hairline}" BorderThickness="0,0,0,1" Background="Transparent">
          <Grid Margin="16,0,6,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <ContentControl x:Name="BarMark" Width="16" Height="16" VerticalAlignment="Center"/>
              <TextBlock Text="Claude Severance Setup" Margin="9,0,0,0" VerticalAlignment="Center" FontSize="12.5"
                         FontFamily="{DynamicResource FontText}" FontWeight="Medium" Foreground="{DynamicResource Muted}"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <Button x:Name="MinBtn" Style="{StaticResource Win}" ToolTip="Minimize" AutomationProperties.Name="Minimize">
                <Path Data="M0,0.5 L10,0.5" Stroke="{DynamicResource Muted}" StrokeThickness="1.2" Width="10" Height="1"/>
              </Button>
              <Button x:Name="CloseBtn" Style="{StaticResource Win}" ToolTip="Close" AutomationProperties.Name="Close">
                <Path Data="M0,0 L9,9 M9,0 L0,9" Stroke="{DynamicResource Muted}" StrokeThickness="1.2" Width="9" Height="9"/>
              </Button>
            </StackPanel>
          </Grid>
        </Border>

        <Grid Grid.Row="1" x:Name="Hero" Height="96">
          <ContentControl x:Name="MarkHost" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5">
            <ContentControl.RenderTransform><ScaleTransform x:Name="MarkScale" ScaleX="1" ScaleY="1"/></ContentControl.RenderTransform>
          </ContentControl>
        </Grid>

        <StackPanel Grid.Row="2" x:Name="CopyPanel" Margin="44,6,44,0">
          <TextBlock x:Name="Eyebrow" FontSize="11" FontFamily="{DynamicResource FontMono}" Foreground="{DynamicResource Ring}"/>
          <TextBlock x:Name="Title1" Margin="0,10,0,0" FontSize="30" FontFamily="{DynamicResource FontDisplay}" FontWeight="Medium" Foreground="{DynamicResource Ink}"
                     TextOptions.TextFormattingMode="Ideal" LineStackingStrategy="BlockLineHeight" LineHeight="35" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="Title2" FontSize="30" FontFamily="{DynamicResource FontDisplay}" Foreground="{DynamicResource Muted}"
                     TextOptions.TextFormattingMode="Ideal" LineStackingStrategy="BlockLineHeight" LineHeight="35" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="Lede" Margin="0,10,0,0" FontSize="13.5" FontFamily="{DynamicResource FontText}" Foreground="{DynamicResource Muted}"
                     TextWrapping="Wrap" LineStackingStrategy="BlockLineHeight" LineHeight="20.5"/>
        </StackPanel>

        <ContentControl Grid.Row="3" x:Name="Body" Margin="44,20,44,0" Focusable="False"/>

        <StackPanel Grid.Row="4" x:Name="Actions" Orientation="Horizontal" Margin="44,18,44,0"/>

        <TextBlock Grid.Row="5" x:Name="Meta" Margin="44,16,44,22" FontSize="12" FontFamily="{DynamicResource FontText}"
                   Foreground="{DynamicResource Subtle}" TextWrapping="Wrap"/>

        <Grid Grid.Row="6" x:Name="ProgressTrack" Opacity="0">
          <Border Background="{DynamicResource Hairline}"/>
          <Border x:Name="ProgressFill" HorizontalAlignment="Left" Width="0" Background="{DynamicResource Ring}"/>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)
$U = @{}
foreach ($n in 'Panel', 'PanelShift', 'Backdrop', 'Digits', 'DigitShift', 'SeamLight', 'SeamShift', 'BarMark', 'MinBtn', 'CloseBtn', 'Hero', 'MarkHost',
    'MarkScale', 'CopyPanel', 'Eyebrow', 'Title1', 'Title2', 'Lede', 'Body', 'Actions', 'Meta', 'ProgressTrack', 'ProgressFill') { $U[$n] = $win.FindName($n) }

# ======================================================================================== resources
# ResourceDictionary keeps whatever it is given, so unwrap the PSObject that New-Object and function output carry;
# a wrapped brush reaches WPF as an unknown object and fails as "not a valid value for property".
function Set-WinRes([string]$Key, $Value) { $win.Resources[$Key] = $Value.psobject.BaseObject }
foreach ($k in 'Canvas', 'Floor', 'Surface', 'Surface2', 'Ink', 'Muted', 'Subtle', 'Faint', 'Hairline', 'Signal', 'SignalHover', 'SignalInk', 'Neg', 'Tile', 'TileInk', 'FieldBg') {
    Set-WinRes $k (B $P[$k])
}
Set-WinRes 'Frost' (B $P.Surface)
Set-WinRes 'GhostHover' (B $P.Ink 0.06)
Set-WinRes 'Etch' (B $P.Ink 0.06)
Set-WinRes 'Focus' (B $P.Ink 0.42)
Set-WinRes 'NegLine' (B $P.Neg 0.45)
Set-WinRes 'NegSoft' (B $P.Neg 0.12)
# Ring: the moment's colour for words and numbers. It is one brush, recoloured as the moment changes.
$RingBrush = (New-Object Windows.Media.SolidColorBrush (C $P.waiting[1])).psobject.BaseObject
Set-WinRes 'Ring' $RingBrush

# IBM Plex (SIL OFL) from src\fonts. WPF groups the Sans files into one family with Regular, Medium and SemiBold weights,
# so Medium is chosen with FontWeight, not with a separate family.
$FontDir = Join-Path $PSScriptRoot 'fonts'
function New-Font([string]$File, [string]$Family, [string]$Fallback) {
    if (Test-Path (Join-Path $FontDir $File)) {
        $base = New-Object Uri ('file:///' + ($FontDir -replace '\\', '/') + '/')
        return (New-Object Windows.Media.FontFamily $base, "./#$Family, $Fallback")
    }
    return (New-Object Windows.Media.FontFamily $Fallback)
}
$sans = New-Font 'IBMPlexSans-Regular.ttf' 'IBM Plex Sans' 'Segoe UI Variable Text, Segoe UI'
Set-WinRes 'FontDisplay' $sans
Set-WinRes 'FontText' $sans
Set-WinRes 'FontTextMedium' $sans
Set-WinRes 'FontMono' (New-Font 'IBMPlexMono-Regular.ttf' 'IBM Plex Mono' 'Cascadia Mono, Consolas')

try {
    $iconPath = Join-Path $PSScriptRoot 'assets\severance.ico'
    if (-not (Test-Path $iconPath)) {
        $iconPath = Join-Path $env:TEMP 'claude-severance-setup.ico'
        if (-not (Test-Path $iconPath)) { New-SeveranceIcon $iconPath '#221F19' 'CS' }
    }
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit(); $bi.UriSource = New-Object Uri $iconPath; $bi.CacheOption = 'OnLoad'; $bi.EndInit()
    $win.Icon = $bi
} catch { }

# ======================================================================================== small builders
# Event handlers take param($snd, $ev), never ($s, $e): PowerShell names ignore case, so a handler's $s would hide the
# window's state $S from the handler and from every function it calls.
function Set-Res($El, $Prop, [string]$Key) { $El.SetResourceReference($Prop, $Key) }

function T([string]$Text, [string]$Font = 'FontText', [double]$Size = 13.5, [string]$Fg = 'Ink', [bool]$Wrap = $true) {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text
    Set-Res $t ([Windows.Controls.TextBlock]::FontFamilyProperty) $Font
    Set-Res $t ([Windows.Controls.TextBlock]::ForegroundProperty) $Fg
    if ($Font -eq 'FontTextMedium') { $t.FontWeight = [Windows.FontWeights]::Medium }
    $t.FontSize = $Size
    if ($Wrap) { $t.TextWrapping = 'Wrap' } else { $t.TextTrimming = 'CharacterEllipsis' }
    return $t
}

function Get-Style([string]$Key) { return $win.FindResource($Key) }

# The mark: one disc cut down the middle. The left half (at work) is solid; the right half (outside) is only an
# outline; the two sit a step apart. Same geometry as assets\logo.
function New-Mark([double]$Size) {
    $g = New-Object Windows.Controls.Grid
    $g.Width = $Size; $g.Height = $Size
    $tile = New-Object Windows.Controls.Border
    $tile.CornerRadius = New-Object Windows.CornerRadius ($Size * 0.22)
    Set-Res $tile ([Windows.Controls.Border]::BackgroundProperty) 'Tile'
    [void]$g.Children.Add($tile)
    $vb = New-Object Windows.Controls.Viewbox
    $cv = New-Object Windows.Controls.Canvas
    $cv.Width = 64; $cv.Height = 64
    $solid = New-Object Windows.Shapes.Path
    $solid.Data = [Windows.Media.Geometry]::Parse('M 29,14 A 18,18 0 0 0 29,50 Z')
    Set-Res $solid ([Windows.Shapes.Shape]::FillProperty) 'TileInk'
    $solid.RenderTransform = New-Object -TypeName Windows.Media.TranslateTransform -ArgumentList 0, -2
    [void]$cv.Children.Add($solid)
    $line = New-Object Windows.Shapes.Path
    $line.Data = [Windows.Media.Geometry]::Parse('M 35,15.5 A 16.5,16.5 0 0 1 35,48.5 Z')
    Set-Res $line ([Windows.Shapes.Shape]::StrokeProperty) 'TileInk'
    $line.StrokeThickness = 3
    $line.StrokeLineJoin = 'Round'
    $line.RenderTransform = New-Object Windows.Media.TranslateTransform 0, 2
    [void]$cv.Children.Add($line)
    $vb.Child = $cv
    [void]$g.Children.Add($vb)
    return $g
}

function New-Card {
    $b = New-Object Windows.Controls.Border
    Set-Res $b ([Windows.Controls.Border]::BackgroundProperty) 'Surface'
    Set-Res $b ([Windows.Controls.Border]::BorderBrushProperty) 'Hairline'
    $b.BorderThickness = New-Object Windows.Thickness 1
    $b.CornerRadius = New-Object Windows.CornerRadius 8
    $b.VerticalAlignment = 'Top'
    $sp = New-Object Windows.Controls.StackPanel
    $b.Child = $sp
    return $b
}

# Adds a row to a card, with a hairline above every row but the first
function Add-CardRow($Card, $Element) {
    $sp = $Card.Child
    $wrap = New-Object Windows.Controls.Border
    if ($sp.Children.Count -gt 0) {
        $wrap.BorderThickness = New-Object Windows.Thickness 0, 1, 0, 0
        Set-Res $wrap ([Windows.Controls.Border]::BorderBrushProperty) 'Hairline'
    }
    $wrap.Child = $Element
    [void]$sp.Children.Add($wrap)
    return $wrap
}

function New-Row([string]$Label, $Right, [string]$Hint = '') {
    $g = New-Object Windows.Controls.Grid
    $g.MinHeight = 48
    $g.Margin = New-Object Windows.Thickness 16, 0, 16, 0
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength 1, 'Star'
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = [Windows.GridLength]::Auto
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $left = New-Object Windows.Controls.StackPanel
    $left.VerticalAlignment = 'Center'
    $left.Margin = New-Object Windows.Thickness 0, 9, 12, 9
    [void]$left.Children.Add((T $Label 'FontText' 13.5 'Ink'))
    if ($Hint) { $h = T $Hint 'FontText' 12 'Subtle'; $h.Margin = New-Object Windows.Thickness 0, 2, 0, 0; [void]$left.Children.Add($h) }
    [void]$g.Children.Add($left)
    if ($Right) {
        if ($Right -is [string]) { $Right = T $Right 'FontMono' 11.5 'Muted' $false }
        $Right.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetColumn($Right, 1)
        [void]$g.Children.Add($Right)
    }
    return $g
}

function New-Switch([string]$Label, [string]$Hint, [bool]$Checked, [string]$Key, [bool]$Danger = $false, [bool]$Enabled = $true) {
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Style = Get-Style 'Switch'
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((T $Label 'FontText' 13.5 'Ink'))
    if ($Hint) { $h = T $Hint 'FontText' 12 'Subtle'; $h.Margin = New-Object Windows.Thickness 0, 2, 0, 0; [void]$sp.Children.Add($h) }
    $cb.Content = $sp
    $cb.IsChecked = $Checked
    $cb.IsEnabled = $Enabled
    $cb.Tag = $null
    if ($Danger) { Set-Res $cb ([Windows.FrameworkElement]::TagProperty) 'Neg' } else { Set-Res $cb ([Windows.FrameworkElement]::TagProperty) 'Signal' }
    $cb.Name = "sw_$Key"
    [Windows.Automation.AutomationProperties]::SetName($cb, $Label)
    $cb.Add_Checked({ param($snd, $ev) $S.Opt[$snd.Name.Substring(3)] = $true; Update-Hints })
    $cb.Add_Unchecked({ param($snd, $ev) $S.Opt[$snd.Name.Substring(3)] = $false; Update-Hints })
    return $cb
}

function New-Btn([string]$Text, [string]$Style, [scriptblock]$OnClick, [bool]$Arrow = $false, $Tag = $null) {
    $b = New-Object Windows.Controls.Button
    $b.Style = Get-Style $Style
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text
    $t.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($t)
    if ($Arrow) {
        $p = New-Object Windows.Shapes.Path
        $p.Data = [Windows.Media.Geometry]::Parse('M0,5 L11,5 M6.5,0.5 L11,5 L6.5,9.5')
        $p.StrokeThickness = 1.6
        $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'; $p.StrokeLineJoin = 'Round'
        $p.Margin = New-Object Windows.Thickness 10, 1, 0, 0
        $p.VerticalAlignment = 'Center'
        $p.SetBinding([Windows.Shapes.Shape]::StrokeProperty, (New-Object Windows.Data.Binding 'Foreground' -Property @{ Source = $b })) | Out-Null
        [void]$sp.Children.Add($p)
    }
    $b.Content = $sp
    if ($null -ne $Tag) { $b.DataContext = $Tag }
    if ($OnClick) { $b.Add_Click($OnClick) }
    [Windows.Automation.AutomationProperties]::SetName($b, $Text)
    return $b
}

function New-Tile($Account, [double]$Size = 22) {
    $b = New-Object Windows.Controls.Border
    $b.Width = $Size; $b.Height = $Size
    $b.CornerRadius = New-Object Windows.CornerRadius ($Size * 0.27)
    $hex = [string]$Account.color; if (-not $hex) { $hex = '#888888' }
    # A logo, when the account has one, fills the tile instead of the coloured shell and letter
    $logo = [string]$Account.logoView
    if ($logo -and (Test-Path -LiteralPath $logo)) {
        try {
            $bi = New-Object Windows.Media.Imaging.BitmapImage
            $bi.BeginInit(); $bi.UriSource = New-Object Uri $logo; $bi.CacheOption = 'OnLoad'; $bi.DecodePixelWidth = 96; $bi.EndInit()
            $ib = New-Object Windows.Media.ImageBrush $bi
            $ib.Stretch = 'Uniform'
            $b.Background = $ib
            $b.Child = New-Object Windows.Controls.TextBlock
            return $b
        } catch { }
    }
    $b.Background = B $hex
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = [string]$Account.label
    $t.FontSize = [math]::Max(8.5, $Size * 0.42)
    Set-Res $t ([Windows.Controls.TextBlock]::FontFamilyProperty) 'FontText'
    $t.FontWeight = [Windows.FontWeights]::SemiBold
    $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center'
    if (Test-DarkColor $hex) { $t.Foreground = B '#FFFFFF' } else { $t.Foreground = B '#000000' }
    $b.Child = $t
    return $b
}

function Short-Path([string]$Path, [int]$Max = 46) {
    if ($Path.Length -le $Max) { return $Path }
    $parts = $Path.Split('\')
    if ($parts.Count -lt 4) { return $Path.Substring(0, $Max - 1) + $ELL }
    $head = ($parts[0..1] -join '\')
    $tail = $parts[$parts.Count - 1]
    for ($i = $parts.Count - 2; $i -gt 1; $i--) {
        $next = $parts[$i] + '\' + $tail
        if ($head.Length + $next.Length + 3 -gt $Max) { break }
        $tail = $next
    }
    return "$head\$ELL\$tail"
}

# ======================================================================================== motion
$Ease = New-Object Windows.Media.Animation.QuinticEase
$Ease.EasingMode = 'EaseOut'
$Reduce = -not [Windows.SystemParameters]::ClientAreaAnimation

function Animate($Target, $Prop, [double]$From, [double]$To, [int]$Ms, [int]$Delay = 0) {
    if ($Reduce) { $Target.SetValue($Prop, $To); return }
    $a = New-Object Windows.Media.Animation.DoubleAnimation $From, $To, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($Ms)))
    $a.EasingFunction = $Ease
    $a.BeginTime = [TimeSpan]::FromMilliseconds($Delay)
    $a.FillBehavior = 'HoldEnd'
    $Target.BeginAnimation($Prop, $a)
}

# Content rises 4px and fades in, a beat apart
function Enter($Element, [int]$Delay = 0, [double]$Rise = 4) {
    if (-not $Element) { return }
    $tt = New-Object Windows.Media.TranslateTransform
    $Element.RenderTransform = $tt
    $Element.Opacity = 0
    Animate $Element ([Windows.UIElement]::OpacityProperty) 0 1 420 $Delay
    Animate $tt ([Windows.Media.TranslateTransform]::YProperty) $Rise 0 420 $Delay
}

# ---------------- the seam and its light ----------------
# A 150 px band of light travels down the seam from above the window to below it, then rests. The mark's tile sits on
# top of the seam, so the light passes behind it. While working, a faint field of digits drifts on the floor.
$SeamStops = New-Object System.Collections.ArrayList
$SeamTravel = 760
function Build-Seam {
    $lg = New-Object Windows.Media.LinearGradientBrush
    $lg.StartPoint = New-Object Windows.Point 0, 0
    $lg.EndPoint = New-Object Windows.Point 0, 1
    $s0 = New-Object Windows.Media.GradientStop (C $P.waiting[0] 0), 0
    $s1 = New-Object Windows.Media.GradientStop (C $P.waiting[0] 1), 0.72
    $s2 = New-Object Windows.Media.GradientStop (C $P.waiting[0] 0), 1
    $lg.GradientStops.Add($s0); $lg.GradientStops.Add($s1); $lg.GradientStops.Add($s2)
    [void]$SeamStops.AddRange(@($s0, $s1, $s2))
    $U.SeamLight.Fill = $lg

    # Digits: seeded, so every capture shows the same field
    # A band of four rows between the step list and the footer, fading in from the top
    $rnd = New-Object Random 1962
    $fade = New-Object Windows.Media.LinearGradientBrush
    $fade.StartPoint = New-Object Windows.Point 0, 0; $fade.EndPoint = New-Object Windows.Point 0, 1
    $fade.GradientStops.Add((New-Object Windows.Media.GradientStop (C '#000000' 0), 0.0))
    $fade.GradientStops.Add((New-Object Windows.Media.GradientStop (C '#000000' 1), 0.45))
    $fade.GradientStops.Add((New-Object Windows.Media.GradientStop (C '#000000' 1), 0.8))
    $fade.GradientStops.Add((New-Object Windows.Media.GradientStop (C '#000000' 0), 1.0))
    $band = New-Object Windows.Controls.Canvas
    $band.Width = 520; $band.Height = 104
    $band.OpacityMask = $fade
    [Windows.Controls.Canvas]::SetTop($band, 446)
    [void]$U.Digits.Children.Add($band)
    for ($row = 0; $row -lt 4; $row++) {
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = (@(1..26 | ForEach-Object { $rnd.Next(0, 10) }) -join '   ')
        Set-Res $t ([Windows.Controls.TextBlock]::FontFamilyProperty) 'FontMono'
        Set-Res $t ([Windows.Controls.TextBlock]::ForegroundProperty) 'Ring'
        $t.FontSize = 11
        [Windows.Controls.Canvas]::SetLeft($t, 22 - ($row % 3) * 9)
        [Windows.Controls.Canvas]::SetTop($t, 8 + $row * 24)
        [void]$band.Children.Add($t)
    }
}

function Start-Shine([int]$Ms) {
    $prop = [Windows.Media.TranslateTransform]::YProperty
    $tt = $U.SeamShift
    if ($Reduce) { $tt.BeginAnimation($prop, $null); $tt.Y = 150; return }
    $a = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($Ms))
    $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    [void]$a.KeyFrames.Add((New-Object -TypeName Windows.Media.Animation.DiscreteDoubleKeyFrame -ArgumentList -150, ([Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::Zero))))
    $k = New-Object Windows.Media.Animation.SplineDoubleKeyFrame $SeamTravel, ([Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($Ms * 0.78)))
    $k.KeySpline = New-Object Windows.Media.Animation.KeySpline 0.45, 0, 0.55, 1
    [void]$a.KeyFrames.Add($k)
    [void]$a.KeyFrames.Add((New-Object Windows.Media.Animation.DiscreteDoubleKeyFrame $SeamTravel, ([Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($Ms)))))
    $tt.BeginAnimation($prop, $a)
}

# The digit field shows only while work is under way
function Set-Digits([bool]$On) {
    $to = 0; if ($On) { $to = $P.DigitOp }
    Animate $U.Digits ([Windows.UIElement]::OpacityProperty) $U.Digits.Opacity $to 900
    $prop = [Windows.Media.TranslateTransform]::YProperty
    if ($On -and -not $Reduce) {
        $a = New-Object -TypeName Windows.Media.Animation.DoubleAnimation -ArgumentList 0, -10, (New-Object Windows.Duration ([TimeSpan]::FromSeconds(9)))
        $a.AutoReverse = $true
        $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $U.DigitShift.BeginAnimation($prop, $a)
    } else { $U.DigitShift.BeginAnimation($prop, $null) }
}

function Fade-Color($Target, $Prop, $To) {
    if ($Reduce) { $Target.SetValue($Prop, $To); return }
    $a = New-Object Windows.Media.Animation.ColorAnimation $To, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(700)))
    $a.EasingFunction = $Ease
    $Target.BeginAnimation($Prop, $a)
}

# The moment's colour: the light on the seam, the eyebrow, the step numbers, the progress bar
function Set-Moment([string]$Name) {
    if ($S.Moment -eq $Name) { return }
    $restart = ($ShineMs[$S.Moment] -ne $ShineMs[$Name]) -or (-not $S.Moment)
    $S.Moment = $Name
    $h = $P[$Name]
    $cp = [Windows.Media.GradientStop]::ColorProperty
    Fade-Color $SeamStops[0] $cp (C $h[0] 0)
    Fade-Color $SeamStops[1] $cp (C $h[0] 1)
    Fade-Color $SeamStops[2] $cp (C $h[0] 0)
    Fade-Color $RingBrush ([Windows.Media.SolidColorBrush]::ColorProperty) (C $h[1] 1)
    if ($restart) { Start-Shine $ShineMs[$Name] }
}

# ======================================================================================== state
if ($Preview) {
    $pm = $Mode; if ($pm -eq 'auto') { $pm = 'install' }
    $acc = @(
        [pscustomobject]@{ id = 'personal'; name = 'Personal'; label = 'P'; color = '#3E6FA3'; email = 'you@example.com'; main = $true; paths = @() },
        [pscustomobject]@{ id = 'acme'; name = 'Acme'; label = 'A'; color = '#C08A2E'; email = 'you@acme.example'; main = $false; paths = @('D:\clients\acme') },
        [pscustomobject]@{ id = 'globex'; name = 'Globex'; label = 'G'; color = '#3E7A5A'; email = 'you@globex.example'; main = $false; paths = @('D:\clients\globex'); alias = 'gx' },
        [pscustomobject]@{ id = 'initech'; name = 'Initech'; label = 'I'; color = '#6C5B9E'; email = ''; main = $false; paths = @() }
    )
    if ($pm -eq 'install') { $acc = @($acc[0]) }
    $installedV = $null; if ($pm -ne 'install') { $installedV = '1.0.0' }; if ($pm -eq 'manage') { $installedV = (Get-SeveranceVersion) }
    $Info = [pscustomobject]@{
        Version = (Get-SeveranceVersion); Installed = $installedV; Mode = $pm; Dir = (Get-SeveranceRoot); DesktopFound = $true; Winget = $true
        CodeFound = $true; Accounts = $acc; Source = 'new'; NeedsScripts = $false; ScriptsBlocked = $false; AutoSwitch = $true; DesktopShortcuts = $true; Running = $false
    }
    if ($pm -ne 'install') { $Info.Source = 'installed' }
} else {
    $Info = Get-SeveranceSetupInfo $Mode
}

$S = @{
    Info = $Info; Screen = ''; Moment = ''; Busy = $false; Kind = ''; From = ''
    Opt = @{ desktop = [bool]$Info.DesktopShortcuts; auto = [bool]$Info.AutoSwitch; installDesktop = (-not $Info.DesktopFound -and $Info.Winget); installCode = (-not $Info.CodeFound); removeData = $false }
    Edit = New-Object System.Collections.ArrayList
    Queue = $null; PS = $null; Handle = $null; WorkStart = [DateTime]::UtcNow; NextAt = [DateTime]::UtcNow; SettleAt = $null
    Shown = 0; Expected = 1; StepsPanel = $null; Pending = $null; Result = $null; Error = ''; Fields = @{}; Problem = $null
    Open = $null; Syncing = $false; Picker = $null
}
foreach ($a in @($Info.Accounts)) {
    [void]$S.Edit.Add(@{ Id = [string]$a.id; Name = [string]$a.name; Email = [string]$a.email; Paths = (@($a.paths) -join '; '); Main = [bool]$a.main
            Color = [string]$a.color; Existing = ($Info.Source -ne 'new'); Removed = $false
            Logo = [string](Get-JsonProp $a 'logo'); LogoView = [string](Get-SeveranceLogoPath $a); LogoSource = ''
            Alias = (Get-AccountAlias $a); AliasEdited = $true })
}

function Get-FreeColor {
    $used = @($S.Edit | ForEach-Object { $_.Color })
    foreach ($c in (Get-SeverancePalette)) { if ($used -notcontains $c) { return $c } }
    return (Get-SeverancePalette)[$S.Edit.Count % 8]
}
function Add-EditAccount {
    [void]$S.Edit.Add(@{ Id = ''; Name = ''; Email = ''; Paths = ''; Main = $false; Color = (Get-FreeColor); Existing = $false; Removed = $false
            Logo = ''; LogoView = ''; LogoSource = ''; Alias = ''; AliasEdited = $false })
}
# A first install starts with one empty org account to fill in
if ($Info.Mode -eq 'install' -and @($S.Edit | Where-Object { -not $_.Main }).Count -eq 0) { Add-EditAccount }
if ($Preview -and $Screen) {
    foreach ($a in $S.Edit) { if (-not $a.Main -and -not $a.Name) { $a.Name = 'Acme'; $a.Email = 'you@acme.example' } }
}
# A first install opens the empty org account, ready to fill in; later visits start with every row closed
if ($Info.Mode -eq 'install') { $S.Open = @($S.Edit | Where-Object { -not $_.Main })[0] }

$Main = @($S.Edit | Where-Object { $_.Main })[0]
function Main-Name { $m = @($S.Edit | Where-Object { $_.Main }); if ($m.Count) { return $m[0].Name }; return 'Your main account' }

# ======================================================================================== screens
function Set-Copy([string]$Eyebrow, [string]$A, [string]$Bb, [string]$Lede) {
    $U.Eyebrow.Text = $Eyebrow.ToUpperInvariant()
    $U.Title1.Text = $A
    $U.Title2.Text = $Bb
    $U.Lede.Text = $Lede
    if ($Lede) { $U.Lede.Visibility = 'Visible' } else { $U.Lede.Visibility = 'Collapsed' }
}

function Set-Hero([double]$Height, [double]$Scale) {
    $U.Hero.Height = $Height
    Animate $U.MarkScale ([Windows.Media.ScaleTransform]::ScaleXProperty) $U.MarkScale.ScaleX $Scale 420
    Animate $U.MarkScale ([Windows.Media.ScaleTransform]::ScaleYProperty) $U.MarkScale.ScaleY $Scale 420
}

function Set-Actions([array]$Buttons) {
    $U.Actions.Children.Clear()
    $first = $true
    foreach ($b in $Buttons) {
        if (-not $first) { $b.Margin = New-Object Windows.Thickness 10, 0, 0, 0 }
        [void]$U.Actions.Children.Add($b)
        $first = $false
    }
}

function Set-Meta([string[]]$Items, [string]$Key = 'Subtle') {
    $U.Meta.Inlines.Clear()
    Set-Res $U.Meta ([Windows.Controls.TextBlock]::ForegroundProperty) $Key
    $i = 0
    foreach ($it in $Items) {
        if ($i -gt 0) {
            $sep = New-Object Windows.Documents.Run "   $DOT   "
            Set-Res $sep ([Windows.Documents.TextElement]::ForegroundProperty) 'Faint'
            $U.Meta.Inlines.Add($sep)
        }
        $U.Meta.Inlines.Add((New-Object Windows.Documents.Run $it))
        $i++
    }
}

function Set-Progress([double]$Fraction) {
    $w = $U.Panel.ActualWidth - 2
    if ($w -le 0) { $w = 518 }
    # 0.0 and 1.0, not 0 and 1: with int literals PowerShell picks Math.Min(int, int) and rounds the fraction to 0 or 1
    $to = $w * [math]::Max(0.0, [math]::Min(1.0, $Fraction))
    Animate $U.ProgressFill ([Windows.FrameworkElement]::WidthProperty) $U.ProgressFill.ActualWidth $to 300
}

function Show-Screen([string]$Name) {
    $S.Screen = $Name
    $i = $S.Info
    $v = $i.Version
    $U.Body.Content = $null
    $U.ProgressTrack.Opacity = 0
    $U.CloseBtn.IsEnabled = $true
    switch ($Name) {
        'welcome' { Show-Welcome }
        'accounts' { Show-Accounts }
        'working' { Show-Working }
        'ready' { Show-Ready }
        'failed' { Show-Failed }
        'confirm' { Show-Confirm }
        'removing' { Show-Working }
        'removed' { Show-Removed }
    }
    # The digits belong to work under way, not to a colour: the failed screen shares rust with removing
    Set-Digits ($Name -in 'working', 'removing')
    Enter $U.CopyPanel 0
    Enter $U.Body 60
    Enter $U.Actions 120
    Enter $U.Meta 160
    # Priority first: BeginInvoke(delegate, 'Input') binds 'Input' as an argument to the delegate
    $win.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Input, [Action] { try { [void]$win.Focus() } catch { } }) | Out-Null
}

# ---------------- welcome: install or update ----------------
function Show-Welcome {
    $i = $S.Info
    Set-Hero 96 1
    $card = New-Card
    if ($i.Mode -eq 'update') {
        Set-Moment 'deciding'
        Set-Copy "Update $DOT v$($i.Installed) $ARR v$($i.Version)" "A new edition." 'Same floors, kept apart.' 'Updating keeps every account, login and history exactly as it is.'
        $names = @($S.Edit | ForEach-Object { $_.Name }) -join ', '
        [void](Add-CardRow $card (New-Row 'Accounts' (T $names 'FontText' 13 'Muted' $false)))
    } else {
        Set-Moment 'waiting'
        $lede = 'Each org gets its own Claude, with its own login, chats and Claude Code memory. Your personal Claude stays exactly as it is.'
        $eyebrow = "Orientation $DOT v$($i.Version)"
        if ($i.Source -eq 'kept') { $eyebrow = "Welcome back $DOT v$($i.Version)"; $lede = 'Your accounts are still here, signed in. Install again to bring back their shortcuts and commands.' }
        if ($i.Source -eq 'legacy') { $lede = 'Your ClaudeProfiles accounts come along, signed in. Your personal Claude stays exactly as it is.' }
        Set-Copy $eyebrow 'Work stays at work.' 'Personal stays yours.' $lede
    }

    # Claude Desktop and Claude Code
    if ($i.DesktopFound -and ($i.CodeFound -or -not $S.Opt.installCode)) {
        $found = 'Claude Desktop'; if ($i.CodeFound) { $found = 'Claude Desktop, Claude Code' }
        [void](Add-CardRow $card (New-Row 'Found on this PC' $found))
    }
    if (-not $i.DesktopFound) {
        if ($i.Winget) { [void](Add-CardRow $card (New-Switch 'Install Claude Desktop' 'Claude Severance needs it. Installed from winget, for you only.' $S.Opt.installDesktop 'installDesktop')) }
        else { [void](Add-CardRow $card (New-Row 'Claude Desktop' (T 'Not installed' 'FontMono' 11.5 'Neg' $false) 'Get it from claude.ai/download, then open this setup again.')) }
    }
    if (-not $i.CodeFound) {
        [void](Add-CardRow $card (New-Switch 'Install Claude Code too' 'The claude command, from Anthropic''s official installer.' $S.Opt.installCode 'installCode'))
    }
    [void](Add-CardRow $card (New-Switch 'Put shortcuts on my desktop' '' $S.Opt.desktop 'desktop'))
    $autoHint = 'Plain claude in PowerShell uses the account for that folder, and asks when it isn''t sure.'
    if ($i.NeedsScripts) { $autoHint = 'Also lets your own PowerShell scripts run (RemoteSigned, for you only).' }
    if ($i.ScriptsBlocked) { $autoHint = 'Turned off by your organization''s PowerShell policy. Use claude-<account>.' }
    [void](Add-CardRow $card (New-Switch 'Let claude pick the account by folder' $autoHint ($S.Opt.auto -and -not $i.ScriptsBlocked) 'auto' $false (-not $i.ScriptsBlocked)))
    if ($i.Mode -ne 'update') { [void](Add-CardRow $card (New-Row 'Installs to' (Short-Path $i.Dir 38))) }
    $U.Body.Content = $card

    if (-not $i.DesktopFound -and -not $i.Winget) {
        Set-Actions @(
            (New-Btn 'Get Claude Desktop' 'Primary' { Start-Process 'https://claude.ai/download' } $true),
            (New-Btn 'Not now' 'Ghost' { $win.Close() })
        )
        Set-Meta @('Install Claude Desktop, then open this setup again.')
        return
    }
    if ($i.Mode -eq 'update') {
        Set-Actions @(
            (New-Btn 'Update now' 'Primary' { Start-Install } $true),
            (New-Btn 'Change accounts' 'Ghost' { $S.From = 'welcome'; Show-Screen 'accounts' }),
            (New-Btn 'Not now' 'Link' { $win.Close() })
        )
        $U.Actions.Children[2].Margin = New-Object Windows.Thickness 16, 0, 0, 0
        $U.Actions.Children[2].VerticalAlignment = 'Center'
        Set-Meta @('Your accounts and logins stay as they are', 'Open windows can stay open')
    } else {
        Set-Actions @(
            (New-Btn 'Continue' 'Primary' { $S.From = 'welcome'; Show-Screen 'accounts' } $true),
            (New-Btn 'Not now' 'Ghost' { $win.Close() })
        )
        Set-Meta @('For you only', 'No administrator', 'Remove any time')
    }
    $U.Actions.Children[0].IsDefault = $true
}

# ---------------- accounts ----------------
function Show-Accounts {
    $i = $S.Info
    Set-Moment 'waiting'
    Set-Hero 64 0.62
    switch ($i.Mode) {
        'manage' { Set-Copy "Assignments $DOT v$($i.Version)" 'Your accounts.' 'Add, rename or remove.' '' }
        'update' { Set-Copy "Update $DOT Assignments" 'Your accounts.' 'Change them first.' '' }
        default { Set-Copy "Step 2 of 2 $DOT Assignments" 'Your accounts.' 'One floor each.' '' }
    }
    Render-Accounts

    switch ($i.Mode) {
        'manage' {
            Set-Actions @(
                (New-Btn 'Save changes' 'Primary' { Submit-Accounts } $true),
                (New-Btn 'Close' 'Ghost' { $win.Close() })
            )
        }
        'update' {
            Set-Actions @(
                (New-Btn 'Update now' 'Primary' { Submit-Accounts } $true),
                (New-Btn 'Back' 'Ghost' { Show-Screen 'welcome' })
            )
        }
        default {
            Set-Actions @(
                (New-Btn 'Install Claude Severance' 'Primary' { Submit-Accounts } $true),
                (New-Btn 'Back' 'Ghost' { Show-Screen 'welcome' })
            )
        }
    }
    $U.Actions.Children[0].IsDefault = $false
    Set-AccountsMeta
}

function Set-AccountsMeta {
    if ($S.Problem) { Set-Meta @($S.Problem) 'Neg'; return }
    $removing = @($S.Edit | Where-Object { $_.Removed })
    if ($removing.Count) { Set-Meta @('Removed accounts are backed up first, without their logins'); return }
    Set-Meta @('Click a tile for its colour or logo', 'Change these any time with severance')
}

# ---- an account's command: the alias it types in a terminal ----
# Existing accounts keep theirs. A new account's follows its name (claude-<name>) until the alias is edited by hand.
function Get-EditAlias($Acc) {
    if ($Acc.AliasEdited) { return ([string]$Acc.Alias).Trim().ToLowerInvariant() }
    if ($Acc.Id) { return (Get-DefaultAlias $Acc.Id) }
    if (-not ([string]$Acc.Name).Trim()) { return '' }
    return (Get-DefaultAlias (New-AccountId $Acc.Name @()))
}
# The other accounts as the module's alias check sees them; k<n> stands in for ids not given yet
function Get-EditOthers {
    $n = 0
    foreach ($a in $S.Edit) {
        if (-not $a.Removed) { [pscustomobject]@{ id = "k$n"; name = $a.Name; alias = (Get-EditAlias $a) } }
        $n++
    }
}
function Get-AliasProblem($Acc) {
    return (Test-SeveranceAlias (Get-EditAlias $Acc) "k$($S.Edit.IndexOf($Acc))" @(Get-EditOthers))
}
function Update-AliasStatus($Acc) {
    $st = $Acc.AliasStatus
    if (-not $st) { return }
    $why = Get-AliasProblem $Acc
    if ($why) { $st.Text = $why; Set-Res $st ([Windows.Controls.TextBlock]::ForegroundProperty) 'Neg' }
    else { $st.Text = "Free. Type $(Get-EditAlias $Acc) in any terminal."; Set-Res $st ([Windows.Controls.TextBlock]::ForegroundProperty) 'Subtle' }
}
# The row's second line: its command, then its email
function Get-RowSub($Acc) {
    $parts = @()
    $al = Get-EditAlias $Acc; if ($al) { $parts += $al }
    if ($Acc.Email) { $parts += [string]$Acc.Email }
    if (-not $parts.Count) { return 'Not set up yet' }
    return ($parts -join " $DOT ")
}

function New-Field([string]$Text, [string]$Hint, [string]$Key, $Acc) {
    $tb = New-Object Windows.Controls.TextBox
    $tb.Style = Get-Style 'Field'
    $tb.Text = $Text
    $tb.Tag = $Hint
    $tb.DataContext = @{ Acc = $Acc; Key = $Key }
    [Windows.Automation.AutomationProperties]::SetName($tb, $Hint)
    $tb.Add_TextChanged({
            param($snd, $ev)
            $ctx = $snd.DataContext
            $a = $ctx.Acc
            $a[$ctx.Key] = $snd.Text
            $snd.Uid = ''
            if ($S.Problem) { $S.Problem = $null; Set-AccountsMeta }
            if ($ctx.Key -eq 'Alias' -and -not $S.Syncing) { $a.AliasEdited = $true }
            if ($ctx.Key -eq 'Name') {
                if ($a.TileText -and -not $a.LogoView) { $a.TileText.Text = (New-AccountLabel $snd.Text) }
                if ($a.HeadName) { $a.HeadName.Text = $snd.Text }
                if (-not $a.AliasEdited -and $a.AliasBox) { $S.Syncing = $true; $a.AliasBox.Text = (Get-EditAlias $a); $S.Syncing = $false }
            }
            if ($a.HeadSub) { $a.HeadSub.Text = (Get-RowSub $a) }
            foreach ($o in $S.Edit) { Update-AliasStatus $o }
        })
    return $tb
}

function New-Label([string]$Text) {
    $l = T $Text 'FontText' 11.5 'Subtle' $false
    $l.Margin = New-Object Windows.Thickness 2, 0, 0, 5
    return $l
}

function New-IconBtn([string]$Geometry, [string]$Tip, [scriptblock]$OnClick, $Context) {
    $b = New-Object Windows.Controls.Button
    $b.Style = Get-Style 'Win'
    $b.Width = 28; $b.Height = 28
    $b.ToolTip = $Tip
    [Windows.Automation.AutomationProperties]::SetName($b, $Tip)
    $p = New-Object Windows.Shapes.Path
    $p.Data = [Windows.Media.Geometry]::Parse($Geometry)
    Set-Res $p ([Windows.Shapes.Shape]::StrokeProperty) 'Subtle'
    $p.StrokeThickness = 1.2
    $p.StrokeLineJoin = 'Round'
    $b.Content = $p
    $b.DataContext = $Context
    $b.Add_Click($OnClick)
    return $b
}

# Places Element in Grid G at Row, Col (spanning Span columns)
function Put($G, $Element, [int]$Row, [int]$Col, [int]$Span = 1) {
    [Windows.Controls.Grid]::SetRow($Element, $Row); [Windows.Controls.Grid]::SetColumn($Element, $Col)
    if ($Span -gt 1) { [Windows.Controls.Grid]::SetColumnSpan($Element, $Span) }
    [void]$G.Children.Add($Element)
}

# The accounts list: one quiet row per account (tile, name, command and email). Clicking a row opens its details
# underneath; one account is open at a time, so a long list stays readable. Any number of accounts can be added.
function Render-Accounts {
    $scroll = New-Object Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.Focusable = $false
    $card = New-Card
    $card.Padding = New-Object Windows.Thickness 4
    $S.Fields = @{}
    foreach ($acc in $S.Edit) {
        $acc.AliasStatus = $null; $acc.AliasBox = $null; $acc.HeadName = $null; $acc.HeadSub = $null
        $idx = $S.Edit.IndexOf($acc)
        if ($acc.Removed) {
            $g = New-Row "$($acc.Name) will be removed" (New-Btn 'Undo' 'Link' { param($snd, $ev) $snd.DataContext.Removed = $false; Render-Accounts; Set-AccountsMeta } $false $acc) 'Backed up first, without its login.'
            [void](Add-CardRow $card $g)
            continue
        }
        $open = [object]::ReferenceEquals($S.Open, $acc)
        $wrap = New-Object Windows.Controls.StackPanel

        # ---- the row ----
        $head = New-Object Windows.Controls.Grid
        foreach ($w in @(40, -1, 0)) {
            $cd = New-Object Windows.Controls.ColumnDefinition
            if ($w -lt 0) { $cd.Width = New-Object Windows.GridLength 1, 'Star' } elseif ($w -eq 0) { $cd.Width = [Windows.GridLength]::Auto } else { $cd.Width = New-Object Windows.GridLength $w }
            $head.ColumnDefinitions.Add($cd)
        }
        $label = New-AccountLabel $acc.Name; if (-not $acc.Name) { $label = '+' }
        $tile = New-Tile ([pscustomobject]@{ color = $acc.Color; label = $label; logoView = $acc.LogoView }) 28
        $acc.TileText = $tile.Child
        $tileBtn = New-Object Windows.Controls.Button
        $tileBtn.Style = Get-Style 'TileBtn'
        $tileBtn.Content = $tile
        $tileBtn.DataContext = $acc
        $tileBtn.VerticalAlignment = 'Center'; $tileBtn.HorizontalAlignment = 'Left'
        $tileBtn.ToolTip = 'Colour and logo'
        [Windows.Automation.AutomationProperties]::SetName($tileBtn, "Colour and logo for $($acc.Name)")
        $tileBtn.Add_Click({ param($snd, $ev) $ev.Handled = $true; Show-TilePicker $snd $snd.DataContext })
        Put $head $tileBtn 0 0

        $txt = New-Object Windows.Controls.StackPanel
        $txt.VerticalAlignment = 'Center'
        $nm = T $acc.Name 'FontTextMedium' 13.5 'Ink' $false
        if (-not $acc.Name) { $nm.Text = 'New account'; Set-Res $nm ([Windows.Controls.TextBlock]::ForegroundProperty) 'Faint' }
        $sub = T (Get-RowSub $acc) 'FontMono' 11 'Subtle' $false
        $sub.Margin = New-Object Windows.Thickness 0, 2, 0, 0
        [void]$txt.Children.Add($nm); [void]$txt.Children.Add($sub)
        $acc.HeadName = $nm; $acc.HeadSub = $sub
        Put $head $txt 0 1

        $right = New-Object Windows.Controls.StackPanel
        $right.Orientation = 'Horizontal'; $right.VerticalAlignment = 'Center'
        if ($acc.Main) {
            $pill = New-Object Windows.Controls.Border
            $pill.CornerRadius = New-Object Windows.CornerRadius 9
            $pill.BorderThickness = New-Object Windows.Thickness 1
            Set-Res $pill ([Windows.Controls.Border]::BorderBrushProperty) 'Hairline'
            $pill.Padding = New-Object Windows.Thickness 8, 1, 8, 2
            $pill.Margin = New-Object Windows.Thickness 0, 0, 10, 0
            $pill.Child = T 'main' 'FontMono' 10.5 'Subtle' $false
            $pill.ToolTip = 'Your normal Claude app. It stays as it is.'
            [void]$right.Children.Add($pill)
        }
        $chev = New-Object Windows.Shapes.Path
        $chev.Data = [Windows.Media.Geometry]::Parse('M0,0 L4.5,4.5 L9,0')
        Set-Res $chev ([Windows.Shapes.Shape]::StrokeProperty) 'Subtle'
        $chev.StrokeThickness = 1.3; $chev.StrokeStartLineCap = 'Round'; $chev.StrokeEndLineCap = 'Round'
        $chev.Width = 10; $chev.Height = 6; $chev.Margin = New-Object Windows.Thickness 0, 0, 6, 0
        $chev.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        if ($open) { $chev.RenderTransform = New-Object Windows.Media.RotateTransform 180 }
        [void]$right.Children.Add($chev)
        Put $head $right 0 2

        $rowBtn = New-Object Windows.Controls.Button
        $rowBtn.Style = Get-Style 'RowBtn'
        $rowBtn.Padding = New-Object Windows.Thickness 10, 9, 10, 9
        $rowBtn.Content = $head
        $rowBtn.DataContext = $acc
        [Windows.Automation.AutomationProperties]::SetName($rowBtn, "$($acc.Name): details")
        $rowBtn.Add_Click({
                param($snd, $ev)
                $a = $snd.DataContext
                if ([object]::ReferenceEquals($S.Open, $a)) { $S.Open = $null } else { $S.Open = $a }
                Render-Accounts; Set-AccountsMeta
            })
        [void]$wrap.Children.Add($rowBtn)

        # ---- its details ----
        if ($open) {
            $form = New-Object Windows.Controls.Grid
            $form.Margin = New-Object Windows.Thickness 50, 2, 14, 14
            foreach ($c in 1..3) {
                $cd = New-Object Windows.Controls.ColumnDefinition
                if ($c -eq 2) { $cd.Width = New-Object Windows.GridLength 10 } else { $cd.Width = New-Object Windows.GridLength 1, 'Star' }
                $form.ColumnDefinitions.Add($cd)
            }
            foreach ($r in 1..8) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = [Windows.GridLength]::Auto; $form.RowDefinitions.Add($rd) }

            Put $form (New-Label 'Name') 0 0
            Put $form (New-Label 'Email it signs in with') 0 2
            $name = New-Field $acc.Name 'Acme' 'Name' $acc
            Put $form $name 1 0
            $S.Fields["$idx-name"] = $name
            $email = New-Field $acc.Email 'you@acme.com' 'Email' $acc
            Put $form $email 1 2
            $S.Fields["$idx-email"] = $email

            $l3 = New-Label 'Command in the terminal'; $l3.Margin = New-Object Windows.Thickness 2, 12, 0, 5
            Put $form $l3 2 0 3
            $S.Syncing = $true
            $alias = New-Field (Get-EditAlias $acc) 'claude-acme' 'Alias' $acc
            $S.Syncing = $false
            $alias.FontFamily = $win.Resources['FontMono']
            $alias.FontSize = 12.5
            Put $form $alias 3 0
            $S.Fields["$idx-alias"] = $alias
            $acc.AliasBox = $alias
            $st = T '' 'FontText' 11.5 'Subtle'
            $st.VerticalAlignment = 'Center'
            $st.LineHeight = 15
            Put $form $st 3 2
            $acc.AliasStatus = $st

            $l4 = New-Label 'Project folders (optional): claude in these uses this account'; $l4.Margin = New-Object Windows.Thickness 2, 12, 0, 5
            Put $form $l4 4 0 3
            $fg = New-Object Windows.Controls.Grid
            $paths = New-Field $acc.Paths 'D:\clients\acme; D:\work\acme-site' 'Paths' $acc
            $paths.Padding = New-Object Windows.Thickness 11, 0, 38, 0
            [void]$fg.Children.Add($paths)
            $acc.PathsBox = $paths
            $browse = New-IconBtn 'M0,2 L4,2 L5.5,3.5 L11,3.5 L11,10 L0,10 Z' 'Add a folder' {
                param($snd, $ev)
                $a = $snd.DataContext
                $d = New-Object System.Windows.Forms.FolderBrowserDialog
                $d.Description = "A folder for $($a.Name). claude started in it, or below it, uses this account."
                $d.ShowNewFolderButton = $false
                if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $list = @(([string]$a.Paths) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    if ($list -notcontains $d.SelectedPath) { $list += $d.SelectedPath }
                    $a.PathsBox.Text = ($list -join '; ')
                }
            } $acc
            $browse.HorizontalAlignment = 'Right'; $browse.Margin = New-Object Windows.Thickness 0, 0, 4, 0
            [void]$fg.Children.Add($browse)
            Put $form $fg 5 0 3

            if (-not $acc.Main) {
                $rm = New-Btn 'Remove this account' 'Link' {
                    param($snd, $ev)
                    $a = $snd.DataContext
                    if ($a.Existing) { $a.Removed = $true } else { [void]$S.Edit.Remove($a) }
                    $S.Open = $null
                    Render-Accounts; Set-AccountsMeta
                } $false $acc
                Set-Res $rm ([Windows.Controls.Control]::ForegroundProperty) 'Neg'
                $rm.HorizontalAlignment = 'Left'
                $rm.Margin = New-Object Windows.Thickness 2, 12, 0, 0
                Put $form $rm 6 0 3
            }
            [void]$wrap.Children.Add($form)
            Update-AliasStatus $acc
        }
        [void](Add-CardRow $card $wrap)
    }
    # The card and "Add an account" scroll together, so the link stays right under the last account
    $list = New-Object Windows.Controls.StackPanel
    $list.Margin = New-Object Windows.Thickness 0, 0, 10, 0
    [void]$list.Children.Add($card)
    $scroll.Content = $list

    $add = New-Btn '+  Add an account' 'Link' {
        Add-EditAccount
        $S.Open = $S.Edit[$S.Edit.Count - 1]
        Render-Accounts; Set-AccountsMeta
        $win.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [Action] {
                $S.AccScroll.ScrollToBottom()
                $k = "$($S.Edit.Count - 1)-name"
                if ($S.Fields[$k]) { [void]$S.Fields[$k].Focus() }
            }) | Out-Null
    }
    $add.Margin = New-Object Windows.Thickness 2, 12, 0, 2
    $add.HorizontalAlignment = 'Left'
    [void]$list.Children.Add($add)
    $U.Body.Content = $scroll
    $S.AccScroll = $scroll
}

# A small panel under an account's tile: its base colour, and a logo to use instead of the lettered shell.
# Picking changes only the edit list; files are copied in when setup runs (and never in preview).
function Show-TilePicker($Anchor, $Acc) {
    $pop = New-Object Windows.Controls.Primitives.Popup
    $pop.PlacementTarget = $Anchor
    $pop.Placement = 'Bottom'
    $pop.VerticalOffset = 8
    $pop.StaysOpen = $false
    $pop.AllowsTransparency = $true
    $pop.PopupAnimation = 'Fade'

    $box = New-Object Windows.Controls.Border
    Set-Res $box ([Windows.Controls.Border]::BackgroundProperty) 'Surface'
    Set-Res $box ([Windows.Controls.Border]::BorderBrushProperty) 'Hairline'
    $box.BorderThickness = New-Object Windows.Thickness 1
    $box.CornerRadius = New-Object Windows.CornerRadius 8
    $box.Padding = New-Object Windows.Thickness 14, 12, 14, 10
    $box.Width = 228
    $sp = New-Object Windows.Controls.StackPanel
    $box.Child = $sp

    $h = T 'COLOUR' 'FontMono' 10.5 'Subtle' $false
    $h.Margin = New-Object Windows.Thickness 0, 0, 0, 8
    [void]$sp.Children.Add($h)
    $wrap = New-Object Windows.Controls.WrapPanel
    foreach ($hex in (Get-SeverancePalette)) {
        $sw = New-Object Windows.Controls.Button
        $sw.Style = Get-Style 'Swatch'
        $sw.Background = B $hex
        if ($hex -eq $Acc.Color -and -not $Acc.LogoView) { Set-Res $sw ([Windows.Controls.Control]::BorderBrushProperty) 'Ink' }
        $sw.DataContext = @{ Acc = $Acc; Hex = $hex; Pop = $pop }
        $sw.ToolTip = $hex
        [Windows.Automation.AutomationProperties]::SetName($sw, "Colour $hex")
        $sw.Add_Click({ param($snd, $ev) $c = $snd.DataContext; $c.Acc.Color = $c.Hex; $c.Pop.IsOpen = $false; Render-Accounts; Set-AccountsMeta })
        [void]$wrap.Children.Add($sw)
    }
    [void]$sp.Children.Add($wrap)

    $line = New-Object Windows.Controls.Border
    $line.Height = 1
    $line.Margin = New-Object Windows.Thickness 0, 4, 0, 6
    Set-Res $line ([Windows.Controls.Border]::BackgroundProperty) 'Hairline'
    [void]$sp.Children.Add($line)

    $choose = New-Btn "Choose a logo$ELL" 'Link' {
        param($snd, $ev)
        $c = $snd.DataContext
        $c.Pop.IsOpen = $false
        $d = New-Object Microsoft.Win32.OpenFileDialog
        $d.Title = "A logo for $($c.Acc.Name)"
        $d.Filter = 'Images (*.png, *.jpg, *.bmp, *.gif, *.ico)|' + ((Get-SeveranceLogoTypes | ForEach-Object { "*$_" }) -join ';')
        if ($d.ShowDialog($win)) {
            $c.Acc.LogoSource = $d.FileName
            $c.Acc.LogoView = $d.FileName
            Render-Accounts; Set-AccountsMeta
        }
    }
    $choose.DataContext = @{ Acc = $Acc; Pop = $pop }
    $choose.Padding = New-Object Windows.Thickness 0, 4, 0, 4
    [void]$sp.Children.Add($choose)
    if ($Acc.LogoView) {
        $letter = New-Btn 'Use the letter instead' 'Link' {
            param($snd, $ev)
            $c = $snd.DataContext
            $c.Acc.Logo = ''; $c.Acc.LogoSource = ''; $c.Acc.LogoView = ''
            $c.Pop.IsOpen = $false
            Render-Accounts; Set-AccountsMeta
        }
        $letter.DataContext = @{ Acc = $Acc; Pop = $pop }
        $letter.Padding = New-Object Windows.Thickness 0, 4, 0, 4
        [void]$sp.Children.Add($letter)
    }
    $note = T 'Square images work best. Shortcuts, the Start menu and this list use it.' 'FontText' 11.5 'Subtle'
    $note.Margin = New-Object Windows.Thickness 0, 6, 0, 0
    [void]$sp.Children.Add($note)

    $pop.Child = $box
    $pop.IsOpen = $true
    $S.Picker = $pop
}

function Submit-Accounts {
    $live = @($S.Edit | Where-Object { -not $_.Removed })
    $seen = @{}
    for ($n = 0; $n -lt $S.Edit.Count; $n++) {
        $a = $S.Edit[$n]
        if ($a.Removed) { continue }
        $a.Name = ([string]$a.Name).Trim()
        $a.Email = ([string]$a.Email).Trim()
        if (-not $a.Name) { return (Fail-Field "$n-name" 'Give every account a name.') }
        $key = $a.Name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return (Fail-Field "$n-name" "Two accounts are called $($a.Name). Give each its own name.") }
        $seen[$key] = $true
        if ($a.Email -and $a.Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return (Fail-Field "$n-email" "$($a.Email) doesn't look like an email address.") }
        # Each command is checked against the others and against every command already on this PC
        $why = Get-AliasProblem $a
        if ($why) { return (Fail-Field "$n-alias" $why) }
    }
    if (@($live | Where-Object { -not $_.Main }).Count -eq 0 -and $S.Info.Mode -eq 'install') {
        $S.Problem = 'Add at least one extra account: that is what Claude Severance is for.'
        Set-AccountsMeta
        return
    }
    Start-Install
}

# Opens the account the problem is in, rings the field in red and puts the cursor in it
function Fail-Field([string]$Key, [string]$Message) {
    $n = [int]($Key.Split('-')[0])
    if (-not [object]::ReferenceEquals($S.Open, $S.Edit[$n])) { $S.Open = $S.Edit[$n]; Render-Accounts }
    $S.Problem = $Message
    Set-AccountsMeta
    $f = $S.Fields[$Key]
    if ($f) {
        $f.Uid = 'error'
        $win.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Input, [Action] { [void]$f.Focus(); $f.Uid = 'error' }.GetNewClosure()) | Out-Null
    }
}

# Turns the edit list into accounts.json entries, giving new accounts their ids
function Get-FinalAccounts {
    $ids = @($S.Edit | Where-Object { $_.Id } | ForEach-Object { $_.Id })
    $out = @()
    foreach ($a in $S.Edit) {
        if ($a.Removed) { continue }
        if (-not $a.Id) { $a.Id = New-AccountId $a.Name $ids; $ids += $a.Id; $a.IsNew = $true }
        $a.Alias = Get-EditAlias $a
        $a.AliasEdited = $true
        $paths = @(([string]$a.Paths) -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
        $out += [pscustomobject]@{ id = $a.Id; name = $a.Name; label = (New-AccountLabel $a.Name); color = $a.Color; email = $a.Email; main = [bool]$a.Main; paths = $paths
            logo = [string]$a.Logo; logoSource = [string]$a.LogoSource; alias = $a.Alias }
    }
    return $out
}

# ---------------- working ----------------
function Show-Working {
    $i = $S.Info
    Set-Hero 84 0.85
    if ($S.Kind -eq 'uninstall') {
        Set-Moment 'removing'
        Set-Copy 'Reintegration in progress' 'Removing' "Claude Severance$ELL" ''
    } else {
        Set-Moment 'working'
        switch ($i.Mode) {
            'update' { Set-Copy 'Procedure in progress' 'Updating' "Claude Severance$ELL" '' }
            'manage' { Set-Copy 'Procedure in progress' 'Saving' "your accounts$ELL" '' }
            default { Set-Copy 'Procedure in progress' 'Severing' "your accounts$ELL" '' }
        }
    }
    $sp = New-Object Windows.Controls.StackPanel
    $S.StepsPanel = $sp
    $pend = New-Object Windows.Controls.Border
    $pend.Height = 6; $pend.Width = 150; $pend.CornerRadius = New-Object Windows.CornerRadius 3
    $pend.HorizontalAlignment = 'Left'
    $pend.Margin = New-Object Windows.Thickness 32, 9, 0, 9
    $pend.Opacity = 0.5
    $lg = New-Object Windows.Media.LinearGradientBrush
    $lg.StartPoint = New-Object Windows.Point 0, 0; $lg.EndPoint = New-Object Windows.Point 1, 0
    $lg.GradientStops.Add((New-Object Windows.Media.GradientStop (C $P.Hairline), 0))
    $lg.GradientStops.Add((New-Object Windows.Media.GradientStop (C $P[$S.Moment][0]), 0.5))
    $lg.GradientStops.Add((New-Object Windows.Media.GradientStop (C $P.Hairline), 1))
    $sht = New-Object -TypeName Windows.Media.TranslateTransform -ArgumentList -1, 0
    $lg.RelativeTransform = $sht
    $pend.Background = $lg
    if (-not $Reduce) {
        $a = New-Object -TypeName Windows.Media.Animation.DoubleAnimation -ArgumentList -1, 1, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(1600)))
        $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $sht.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $a)
    }
    [void]$sp.Children.Add($pend)
    $S.Pending = $pend
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Hidden'
    $sv.Content = $sp
    $S.StepsScroll = $sv
    $U.Body.Content = $sv
    Set-Actions @()
    Set-Meta @('Please keep this window open.')
    $U.CloseBtn.IsEnabled = $false
    $U.ProgressFill.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $null)
    $U.ProgressFill.Width = 0
    $U.ProgressTrack.Opacity = 1
    Set-Progress 0.06
}

function Add-Step([string]$Text) {
    $g = New-Object Windows.Controls.StackPanel
    $g.Orientation = 'Horizontal'
    $g.Margin = New-Object Windows.Thickness 0, 0, 0, 8
    # Each finished step is numbered, 01, 02, ..., in the moment's colour
    $num = T ('{0:00}' -f ($S.StepsPanel.Children.Count)) 'FontMono' 12 'Ring' $false
    $num.Width = 22
    $num.VerticalAlignment = 'Center'
    [void]$g.Children.Add($num)
    $t = T $Text 'FontText' 13.5 'Ink' $false
    $t.Margin = New-Object Windows.Thickness 10, 0, 0, 0
    $t.VerticalAlignment = 'Center'
    [void]$g.Children.Add($t)
    $sp = $S.StepsPanel
    $sp.Children.Insert($sp.Children.Count - 1, $g)
    Enter $g 0 4
    $S.StepsScroll.ScrollToBottom()
}

# ---------------- ready ----------------
function Show-Ready {
    $i = $S.Info
    $r = $S.Result
    Set-Moment 'done'
    Set-Hero 96 1
    $extras = @($S.Edit | Where-Object { -not $_.Main -and -not $_.Removed -and $_.Id })
    $new = @($extras | Where-Object { $_.IsNew -or $i.Mode -eq 'install' })
    $signIn = 'Open each new account and sign in. The sign-in link opens your main Claude: copy the code it shows, press Cancel there, then paste the code into the new window.'
    switch ($i.Mode) {
        'update' { Set-Copy 'Update complete' 'Updated.' 'All carried over.' 'Your accounts, logins and history are as they were. Open any account from here or the Start menu.' }
        'manage' {
            if ($new.Count) { Set-Copy 'Assignments saved' 'Saved.' 'Sign in to the new one.' $signIn }
            else { Set-Copy 'Assignments saved' 'Saved.' 'Your accounts are ready.' 'Shortcuts, commands and badges now match your accounts.' }
        }
        default { Set-Copy 'Procedure complete' 'Your accounts' 'are severed.' $signIn }
    }

    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $card = New-Card
    foreach ($a in $extras) {
        $left = New-Object Windows.Controls.StackPanel
        $left.Orientation = 'Horizontal'
        $tile = New-Tile ([pscustomobject]@{ color = $a.Color; label = (New-AccountLabel $a.Name); logoView = $a.LogoView }) 24
        [void]$left.Children.Add($tile)
        $txt = New-Object Windows.Controls.StackPanel
        $txt.Margin = New-Object Windows.Thickness 12, 0, 0, 0
        $txt.VerticalAlignment = 'Center'
        [void]$txt.Children.Add((T $a.Name 'FontText' 13.5 'Ink' $false))
        [void]$txt.Children.Add((T (Get-EditAlias $a) 'FontMono' 11 'Subtle' $false))
        [void]$left.Children.Add($txt)
        $open = New-Btn 'Open' 'GhostSmall' { param($snd, $ev) Open-Account $snd }
        $open.DataContext = $a
        $row = New-Object Windows.Controls.Grid
        $row.Margin = New-Object Windows.Thickness 14, 10, 12, 10
        [void]$row.Children.Add($left)
        $open.HorizontalAlignment = 'Right'; $open.VerticalAlignment = 'Center'
        [void]$row.Children.Add($open)
        [void](Add-CardRow $card $row)
    }
    if ($extras.Count -eq 0) { [void](Add-CardRow $card (New-Row 'Extra accounts' 'none yet')) }
    $sv.Content = $card
    $U.Body.Content = $sv

    if ($new.Count -gt 0) {
        $first = New-Btn "Open $($new[0].Name)" 'Primary' { param($snd, $ev) Open-Account $snd } $true
        $first.DataContext = $new[0]
        Set-Actions @($first, (New-Btn 'Done' 'Ghost' { $win.Close() }))
    } else {
        Set-Actions @((New-Btn 'Done' 'Primary' { $win.Close() } $true))
    }
    $U.Actions.Children[0].IsDefault = $true
    $notes = @(); if ($r -and $r.Notes) { $notes = @($r.Notes) }
    if ($notes.Count) { Set-Meta @($notes[0]) }
    elseif ($i.Mode -eq 'update') { Set-Meta @('Every account is in Start > Claude Severance') }
    else { Set-Meta @('Open a new terminal for the commands', 'All accounts are in the Start menu') }
    Set-Progress 1
    $U.ProgressTrack.Opacity = 1
}

function Open-Account($Button) {
    $a = $Button.DataContext
    if (-not $Preview) {
        try { Start-SeveranceDesktop $a.Id } catch { Set-Meta @("Couldn't open $($a.Name): $($_.Exception.Message)") 'Neg'; return }
    }
    $Button.IsEnabled = $false
    $c = $Button.Content
    if ($c -and $c.Children.Count) { $c.Children[0].Text = 'Opened'; if ($c.Children.Count -gt 1) { $c.Children[1].Visibility = 'Collapsed' } }
}

# ---------------- failed ----------------
function Show-Failed {
    Set-Moment 'removing'
    Set-Hero 96 1
    $what = 'finish setup.'; if ($S.Kind -eq 'uninstall') { $what = 'finish uninstalling.' }
    Set-Copy 'Procedure stopped' "Couldn't" $what $S.Error
    $U.Body.Content = $null
    Set-Actions @(
        (New-Btn 'Try again' 'Primary' { if ($S.Kind -eq 'uninstall') { Start-Uninstall } else { Start-Install } }),
        (New-Btn 'Close' 'Ghost' { $win.Close() })
    )
    Set-Meta @('Your accounts and logins are safe. Running it again picks up where it stopped.')
}

# ---------------- uninstall ----------------
function Show-Confirm {
    Set-Moment 'deciding'
    Set-Hero 96 1
    $m = Main-Name
    Set-Copy 'Reintegration' 'Bring it all' 'back together?' "Shortcuts, commands and the account badge go. $m stays your normal Claude, untouched."
    $extras = @($S.Edit | Where-Object { -not $_.Main })
    $card = New-Card
    if ($extras.Count) {
        $names = ($extras | ForEach-Object { $_.Name }) -join ', '
        [void](Add-CardRow $card (New-Switch "Also remove $names from this PC" 'Their memory and history are zipped first, without logins. Off: they stay here, signed in, in case you come back.' $S.Opt.removeData 'removeData' $true))
    } else {
        [void](Add-CardRow $card (New-Row 'Extra accounts' 'none'))
    }
    $U.Body.Content = $card
    Set-Actions @(
        (New-Btn 'Keep it' 'Ghost' { $win.Close() }),
        (New-Btn 'Uninstall' 'Danger' { Start-Uninstall })
    )
    $U.Actions.Children[0].IsCancel = $true
    Set-Meta @('Takes a few seconds', 'Desktop chats stay online in each account')
}

function Show-Removed {
    $r = $S.Result
    Set-Moment 'done'
    Set-Hero 96 1
    $m = Main-Name
    if ($r -and $r.MainName) { $m = $r.MainName }
    Set-Copy 'Reintegration complete' 'Claude Severance' 'is removed.' "$m is your single Claude again. Open a new terminal to pick up the change."
    $card = New-Card
    $rows = 0
    if ($r -and $r.Backup) {
        $show = New-Btn 'Show' 'GhostSmall' { param($snd, $ev) Start-Process explorer.exe -ArgumentList "/select,`"$($snd.DataContext)`"" }
        $show.DataContext = [string]$r.Backup
        [void](Add-CardRow $card (New-Row 'Backup, without logins' $show (Short-Path ([string]$r.Backup) 44))); $rows++
    }
    if ($r -and $r.KeptData) { [void](Add-CardRow $card (New-Row 'Extra accounts' 'kept, signed in' 'Installing again brings them back as they were.')); $rows++ }
    if ($r -and $r.Left) { [void](Add-CardRow $card (New-Row 'A few files were in use' '' 'They are removed the next time you sign in to Windows.')); $rows++ }
    if ($rows) { $U.Body.Content = $card }
    Set-Actions @((New-Btn 'Close' 'Primary' { $win.Close() }))
    $U.Actions.Children[0].IsDefault = $true
    if ($r -and $r.Backup) { Set-Meta @("To end their sessions on Anthropic's side too, log out of all devices in each account's Claude settings.") }
    elseif ($r -and $r.KeptData) { Set-Meta @('Install again any time; your accounts come back signed in') }
    else { Set-Meta @('Install again any time') }
    Set-Progress 1
    $U.ProgressTrack.Opacity = 1
}

# ======================================================================================== work in the background
$WorkScript = {
    $ErrorActionPreference = 'Stop'
    try {
        Import-Module $A.Module -Force
        $step = { param($t) [void]$Q.Add(@{ t = 'step'; text = [string]$t }) }
        $p = $A.Params
        if ($A.Preview) {
            foreach ($line in $A.Fake) { Start-Sleep -Milliseconds (Get-Random -Minimum 220 -Maximum 650); & $step $line }
            if ($A.FailPreview) { throw 'Access is denied: C:\Users\you\AppData\Local\ClaudeSeverance\bin\Severance.psm1' }
            $r = [pscustomobject]@{ Notes = @(); Backup = $A.FakeBackup; KeptData = $A.FakeKept; Left = $null; MainName = $null }
        } elseif ($A.Kind -eq 'uninstall') {
            $r = Invoke-SeveranceUninstall @p -Step $step
        } else {
            $r = Invoke-SeveranceInstall @p -Step $step
        }
        [void]$Q.Add(@{ t = 'done'; result = $r })
    } catch {
        [void]$Q.Add(@{ t = 'error'; text = $_.Exception.Message })
    }
}

function Start-Work([string]$Kind, [hashtable]$Params, [string[]]$Fake, [int]$Expected) {
    $S.Kind = $Kind
    $S.Busy = $true
    $S.Shown = 0
    $S.Expected = [math]::Max(1, $Expected)
    $S.SettleAt = $null
    $S.Queue = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    if ($Kind -eq 'uninstall') { Show-Screen 'removing' } else { Show-Screen 'working' }
    $S.WorkStart = [DateTime]::UtcNow
    $S.NextAt = $S.WorkStart.AddMilliseconds(300)

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Q', $S.Queue)
    $backupFake = $null; $keptFake = $false
    if ($Kind -eq 'uninstall') { if ($S.Opt.removeData) { $backupFake = (Join-Path (Get-SeveranceBackupDir) 'backup 2026-11-10_031500.zip') } else { $keptFake = $true } }
    $rs.SessionStateProxy.SetVariable('A', @{
            Module = (Join-Path $PSScriptRoot 'Severance.psm1'); Kind = $Kind; Params = $Params; Preview = [bool]$Preview
            Fake = $Fake; FailPreview = ($Screen -eq 'failed'); FakeBackup = $backupFake; FakeKept = $keptFake
        })
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($WorkScript)
    $S.PS = $ps
    $S.Handle = $ps.BeginInvoke()
    $Timer.Start()
}

function Update-Work {
    if (-not $S.Busy -or -not $S.Queue) { return }
    $now = [DateTime]::UtcNow
    if ($S.Queue.Count -eq 0 -or $now -lt $S.NextAt) { return }
    $item = $S.Queue[0]
    if ($item.t -eq 'step') {
        $S.Queue.RemoveAt(0)
        Add-Step $item.text
        $S.Shown++
        Set-Progress ([math]::Min(0.94, [math]::Max(0.06, $S.Shown / $S.Expected)))
        $S.NextAt = $now.AddMilliseconds(260)
        return
    }
    if (($now - $S.WorkStart).TotalMilliseconds -lt 1400) { return }
    if (-not $S.SettleAt) { $S.SettleAt = $now.AddMilliseconds(420); return }
    if ($now -lt $S.SettleAt) { return }
    $S.Queue.RemoveAt(0)
    $Timer.Stop()
    $S.Busy = $false
    try { $S.PS.EndInvoke($S.Handle) | Out-Null } catch { }
    try { $S.PS.Runspace.Close(); $S.PS.Dispose() } catch { }
    if ($item.t -eq 'done') {
        $S.Result = $item.result
        if ($S.Kind -eq 'uninstall') { Show-Screen 'removed' } else { Show-Screen 'ready' }
    } else {
        $S.Error = [string]$item.text
        Show-Screen 'failed'
    }
}

function Start-Install {
    $i = $S.Info
    $accounts = Get-FinalAccounts
    $removed = @($S.Edit | Where-Object { $_.Removed -and $_.Id } | ForEach-Object { $_.Id })
    $params = @{
        Accounts = $accounts; RemovedIds = $removed
        DesktopShortcuts = [bool]$S.Opt.desktop; AutoSwitch = ([bool]$S.Opt.auto -and -not $i.ScriptsBlocked); AllowScripts = [bool]$i.NeedsScripts
        InstallDesktopApp = ([bool]$S.Opt.installDesktop -and -not $i.DesktopFound); InstallCode = ([bool]$S.Opt.installCode -and -not $i.CodeFound)
        SourceDir = $PSScriptRoot
    }
    $fake = @()
    if ($params.InstallDesktopApp) { $fake += 'Installed Claude Desktop' }
    if ($params.InstallCode) { $fake += 'Installed Claude Code' }
    if ($i.Source -eq 'legacy') { $fake += 'Brought over your earlier ClaudeProfiles setup' }
    if ($removed.Count) { $fake += "Backed up and removed $((@($S.Edit | Where-Object { $_.Removed }) | ForEach-Object { $_.Name }) -join ', ')" }
    $fake += 'Copied Claude Severance to your PC'
    foreach ($a in $accounts) { $fake += "Set up $($a.name)" }
    if ($params.DesktopShortcuts) { $fake += 'Added Start menu entries and desktop shortcuts' } else { $fake += 'Added Start menu entries' }
    $fake += "Added each account's command, and severance"
    $fake += 'Matched Claude Code update settings across accounts'
    if ($params.AutoSwitch) { $fake += 'Turned on auto-switch for claude' }
    $fake += 'Added Claude Severance to Settings > Apps'
    Start-Work 'install' $params $fake ($fake.Count + 1)
}

function Start-Uninstall {
    $extras = @($S.Edit | Where-Object { -not $_.Main })
    $fake = @("Closed the extra accounts' windows")
    if ($S.Opt.removeData -and $extras.Count) { $fake += 'Zipped the extra accounts, without their logins' }
    $fake += 'Removed the account badge from your main Claude Code', 'Removed shortcuts and Start menu entries', 'Removed the commands and auto-switch', 'Removed Claude Severance from Settings > Apps'
    if ($S.Opt.removeData) { $fake += 'Removed the extra accounts from this PC' } else { $fake += "Removed Claude Severance's files" }
    Start-Work 'uninstall' @{ RemoveData = [bool]$S.Opt.removeData } $fake ($fake.Count + 1)
}

function Update-Hints { }

# ======================================================================================== window behaviour
$Timer = New-Object Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(50)
$Timer.Add_Tick({ Update-Work })

function Test-Interactive($El) {
    while ($El) {
        if ($El -is [Windows.Controls.Primitives.ButtonBase] -or $El -is [Windows.Controls.TextBox] -or $El -is [Windows.Controls.Primitives.ScrollBar]) { return $true }
        if ($El -is [Windows.Media.Visual] -or $El -is [Windows.Media.Media3D.Visual3D]) { $El = [Windows.Media.VisualTreeHelper]::GetParent($El) }
        else { $El = [Windows.LogicalTreeHelper]::GetParent($El) }
    }
    return $false
}

$win.Add_MouseLeftButtonDown({
        param($snd, $ev)
        if (-not (Test-Interactive $ev.OriginalSource)) { try { $win.DragMove() } catch { } }
    })
$U.MinBtn.Add_Click({ $win.WindowState = 'Minimized' })
$U.CloseBtn.Add_Click({ if (-not $S.Busy) { $win.Close() } })
$win.Add_KeyDown({
        param($snd, $ev)
        if ($ev.Key -ne 'Escape') { return }
        if ($S.Picker -and $S.Picker.IsOpen) { $S.Picker.IsOpen = $false; $ev.Handled = $true; return }
        if (-not $S.Busy) { $win.Close() }
    })
$win.Add_Closing({ param($snd, $ev) if ($S.Busy) { $ev.Cancel = $true } })

$U.BarMark.Content = New-Mark 16
$U.MarkHost.Content = New-Mark 64
Build-Seam

if (-not $Reduce) { $U.Panel.Opacity = 0 }
$win.Add_Loaded({
        if ($Reduce) { return }
        Animate $U.Panel ([Windows.UIElement]::OpacityProperty) 0 1 520
        Animate $U.PanelShift ([Windows.Media.TranslateTransform]::YProperty) 6 0 520
    })

# ---- first screen ----
$first = 'welcome'
if ($S.Info.Mode -eq 'manage') { $first = 'accounts' }
if ($S.Info.Mode -eq 'uninstall') { $first = 'confirm' }
if ($Preview -and $Screen) {
    switch ($Screen) {
        'working' { $first = $null; Start-Install }
        'removing' { $first = $null; Start-Uninstall }
        'failed' { $first = $null; Start-Install }
        'ready' { $first = $null; [void](Get-FinalAccounts); foreach ($a in $S.Edit) { $a.IsNew = $true }; Show-Screen 'ready' }
        'removed' { $first = $null; $S.Opt.removeData = $true; $S.Result = [pscustomobject]@{ Backup = (Join-Path (Get-SeveranceBackupDir) 'backup 2026-11-10_031500.zip'); KeptData = $false; Left = $null; MainName = 'Personal' }; Show-Screen 'removed' }
        default { $first = $Screen }
    }
}
if ($first) { Show-Screen $first }

# ---- capture: render this screen to a PNG at 2x and close (used to make the docs' screenshots) ----
function Save-Capture([string]$Path) {
    $root = $win.Content
    $w = [int][math]::Ceiling($root.ActualWidth); $h = [int][math]::Ceiling($root.ActualHeight)
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ($w * 2), ($h * 2), 192, 192, ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($root)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    $fs = [IO.File]::Create($Path)
    try { $enc.Save($fs) } finally { $fs.Close() }
}
if ($Capture) {
    $win.WindowStartupLocation = 'Manual'
    $win.Left = -4000; $win.Top = -4000
    $win.ShowInTaskbar = $false
    $win.ShowActivated = $false
    $S.CapTimer = New-Object Windows.Threading.DispatcherTimer
    $S.CapTimer.Interval = [TimeSpan]::FromMilliseconds($CaptureDelay)
    $S.CapTimer.Add_Tick({
            $S.CapTimer.Stop()
            try { Save-Capture $Capture } catch { Set-Content -Path "$Capture.error.txt" -Value $_.Exception.ToString() }
            $S.Busy = $false
            $win.Close()
        })
    $win.Add_ContentRendered({ $S.CapTimer.Start() })
}

# Anything unexpected in a click is logged and said in the window, never a silent crash
$win.Dispatcher.Add_UnhandledException({
        param($snd, $ev)
        $ev.Handled = $true
        $msg = $ev.Exception.Message
        try { Add-Content -Path (Join-Path $env:TEMP 'claude-severance-setup.log') -Value ("{0:s}  ui: {1}`r`n{2}" -f (Get-Date), $msg, $ev.Exception.ToString()) } catch { }
        try { Set-Meta @("Something went wrong: $msg") 'Neg' } catch { }
    })

[void]$win.ShowDialog()
if ($Capture) { [Environment]::Exit(0) }
