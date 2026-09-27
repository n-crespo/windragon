param(
  [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
  [string[]]$Files
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

# P/Invoke for native Win10/11 window polish: rounded corners + dark title bar.
# Silently no-ops on Windows versions that don't support these attributes.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeWindow {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@

function Get-FileThumbnail
{
  param([string]$Path)
  $imageExts = '.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tiff'
  $ext = [System.IO.Path]::GetExtension($Path).ToLower()

  if ($imageExts -contains $ext)
  {
    try
    {
      $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
      $bmp.BeginInit()
      $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
      $bmp.UriSource = New-Object System.Uri($Path)
      $bmp.DecodePixelWidth = 160
      $bmp.EndInit()
      $bmp.Freeze()
      return $bmp
    } catch
    { 
    }
  }

  # Fall back to the file's associated shell icon (works for any file type)
  try
  {
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
    if ($icon)
    {
      $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
        $icon.Handle,
        [System.Windows.Int32Rect]::Empty,
        [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
      )
      $src.Freeze()
      return $src
    }
  } catch
  { 
  }

  return $null
}

$charcoal = New-Object System.Windows.Media.SolidColorBrush(
  [System.Windows.Media.Color]::FromRgb(0x20, 0x20, 0x20)
)

$window = New-Object System.Windows.Window
$window.Title = "Drag Target"
$window.Topmost = $true
$window.WindowStartupLocation = "CenterScreen"
$window.ResizeMode = "NoResize"
$window.SizeToContent = "WidthAndHeight"
$window.MinWidth = 220
$window.MinHeight = 160
$window.Background = $charcoal
$window.Foreground = [System.Windows.Media.Brushes]::White
$window.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
$window.UseLayoutRounding = $true
$window.SnapsToDevicePixels = $true

# Rounded corners (DWMWCP_ROUND) + immersive dark title bar, best-effort.
$window.Add_SourceInitialized({
    try
    {
      $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
      $round = 2
      [NativeWindow]::DwmSetWindowAttribute($hwnd, 33, [ref]$round, 4) | Out-Null
      $dark = 1
      [NativeWindow]::DwmSetWindowAttribute($hwnd, 20, [ref]$dark, 4) | Out-Null
    } catch
    { 
    }
  })

# Escape always closes the window, in either mode.
$window.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape)
    { $window.Close() 
    }
  })
$window.Add_Loaded({ $window.Focus() | Out-Null })

if ($Files)
{
  # ---------- Drag Source: dragging file(s) OUT to external apps ----------
  try
  {
    $resolvedPaths = [string[]]@(
      $Files | ForEach-Object { (Resolve-Path -LiteralPath $_ -ErrorAction Stop).ProviderPath }
    )
  } catch
  {
    Write-Error "Could not resolve one or more files: $_"
    exit 1
  }

  $firstFile = $resolvedPaths[0]
  $thumbnail = Get-FileThumbnail -Path $firstFile

  $stack = New-Object System.Windows.Controls.StackPanel
  $stack.Margin = "24"
  $stack.HorizontalAlignment = "Center"
  $stack.VerticalAlignment = "Center"

  if ($thumbnail)
  {
    $imgBorder = New-Object System.Windows.Controls.Border
    $imgBorder.Width = 96
    $imgBorder.Height = 96
    $imgBorder.CornerRadius = 12
    $imgBorder.HorizontalAlignment = "Center"
    $imgBorder.ClipToBounds = $true

    $imageBrush = New-Object System.Windows.Media.ImageBrush($thumbnail)
    $imageBrush.Stretch = "UniformToFill"
    $imgBorder.Background = $imageBrush

    $stack.Children.Add($imgBorder) | Out-Null
    $window.Icon = $thumbnail
  }

  $nameText = if ($resolvedPaths.Count -eq 1)
  {
    [System.IO.Path]::GetFileName($firstFile)
  } else
  {
    "$($resolvedPaths.Count) files selected"
  }

  $nameBlock = New-Object System.Windows.Controls.TextBlock
  $nameBlock.Text = $nameText
  $nameBlock.FontSize = 13
  $nameBlock.TextWrapping = "Wrap"
  $nameBlock.TextAlignment = "Center"
  $nameBlock.MaxWidth = 220
  $nameBlock.Margin = "0,12,0,0"
  $stack.Children.Add($nameBlock) | Out-Null

  $hintBlock = New-Object System.Windows.Controls.TextBlock
  $hintBlock.Text = "Drag to move  ·  Esc to cancel"
  $hintBlock.FontSize = 11
  $hintBlock.Foreground = [System.Windows.Media.Brushes]::Gray
  $hintBlock.HorizontalAlignment = "Center"
  $hintBlock.Margin = "0,8,0,0"
  $stack.Children.Add($hintBlock) | Out-Null

  $window.Content = $stack

  $script:dragStartPoint = $null

  # Attach to the window itself (not just the stack) so the whole surface is draggable.
  $window.Add_MouseLeftButtonDown({
      param($sender, $e)
      $script:dragStartPoint = $e.GetPosition($window)
    })

  $window.Add_MouseMove({
      param($sender, $e)
      if ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed -and $script:dragStartPoint)
      {
        $currentPos = $e.GetPosition($window)
        $deltaX = [Math]::Abs($currentPos.X - $script:dragStartPoint.X)
        $deltaY = [Math]::Abs($currentPos.Y - $script:dragStartPoint.Y)

        if ($deltaX -gt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance -or
          $deltaY -gt [System.Windows.SystemParameters]::MinimumVerticalDragDistance)
        {

          $dataObject = New-Object System.Windows.DataObject(
            [System.Windows.DataFormats]::FileDrop, $resolvedPaths
          )
          [System.Windows.DragDrop]::DoDragDrop($window, $dataObject, [System.Windows.DragDropEffects]::Copy)
          $window.Close()
        }
      }
    })
} else
{
  # ---------- Drop Target: dropping a file IN, path returned to the terminal ----------
  $window.AllowDrop = $true
  $window.MinWidth = 240
  $window.MinHeight = 200

  $grid = New-Object System.Windows.Controls.Grid

  $dashRect = New-Object System.Windows.Shapes.Rectangle
  $dashRect.Stroke = [System.Windows.Media.Brushes]::Gray
  $dashRect.StrokeThickness = 1.5
  $dashArray = New-Object System.Windows.Media.DoubleCollection
  $dashArray.Add(4); $dashArray.Add(3)
  $dashRect.StrokeDashArray = $dashArray
  $dashRect.RadiusX = 12
  $dashRect.RadiusY = 12
  $dashRect.Margin = "16"
  $grid.Children.Add($dashRect) | Out-Null

  $dropStack = New-Object System.Windows.Controls.StackPanel
  $dropStack.HorizontalAlignment = "Center"
  $dropStack.VerticalAlignment = "Center"
  $dropStack.Margin = "36"

  $arrow = New-Object System.Windows.Controls.TextBlock
  $arrow.Text = [char]0x2B07
  $arrow.FontSize = 30
  $arrow.Foreground = [System.Windows.Media.Brushes]::Gray
  $arrow.HorizontalAlignment = "Center"
  $dropStack.Children.Add($arrow) | Out-Null

  $dropLabel = New-Object System.Windows.Controls.TextBlock
  $dropLabel.Text = "Drop Here"
  $dropLabel.FontSize = 16
  $dropLabel.Foreground = [System.Windows.Media.Brushes]::White
  $dropLabel.HorizontalAlignment = "Center"
  $dropLabel.Margin = "0,8,0,0"
  $dropStack.Children.Add($dropLabel) | Out-Null

  $hintLabel = New-Object System.Windows.Controls.TextBlock
  $hintLabel.Text = "Esc to cancel"
  $hintLabel.FontSize = 11
  $hintLabel.Foreground = [System.Windows.Media.Brushes]::Gray
  $hintLabel.HorizontalAlignment = "Center"
  $hintLabel.Margin = "0,6,0,0"
  $dropStack.Children.Add($hintLabel) | Out-Null

  $grid.Children.Add($dropStack) | Out-Null
  $window.Content = $grid

  $window.Add_DragEnter({
      param($sender, $e)
      $e.Effects = if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop))
      {
        [System.Windows.DragDropEffects]::Copy
      } else
      {
        [System.Windows.DragDropEffects]::None
      }
      $e.Handled = $true
    })

  $window.Add_DragOver({
      param($sender, $e)
      $e.Effects = [System.Windows.DragDropEffects]::Copy
      $e.Handled = $true
    })

  $window.Add_Drop({
      param($sender, $e)
      if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop))
      {
        $droppedFiles = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        foreach ($f in $droppedFiles)
        { Write-Output $f 
        }
      }
      $window.Close()
    })
}

$null = $window.ShowDialog()
