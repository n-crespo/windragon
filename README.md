# windragon

A tiny PowerShell script that pops up a small window you can drag a file out of,
or drop a file into. Mostly built to pair with
[yazi](https://yazi-rs.github.io/), since yazi has no native drag-and-drop on
Windows. Name was inspired by [dragon](https://github.com/mwh/dragon).

## What it does

Run it with file arguments, and it shows a window with a thumbnail (or icon) and
filename that you can click and drag out into any other app (Explorer, an email,
browser, etc.):

```
.\windragon.ps1 C:\path\to\file.txt
```

Run it with no arguments, and it shows a "Drop Here" zone. Drop a file on it,
and the path is written to stdout.

```
$path = .\windragon.ps1
```

Press `Esc` at any time to cancel and close the window.

## Requirements

- Windows with PowerShell (5.1 or later should work)

## Using it with yazi

Add something like this to `keymap.toml`:

```toml
[[mgr.append_keymap]]
on = "<C-n>"
# NOTE: replace this path with a path to wherever the windragon script is ⤵
run = 'shell -- powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\dev\windragon\windragon.ps1" %s'
desc = "Drag file(s) out with windragon"
```

Select a file (or a few) in yazi, hit `Ctrl+N`, and drag the window that pops up
to wherever you want the file to go.

## Limitations

- Only shows a preview thumbnail for the first file when multiple are passed.
- First run compiles a tiny helper DLL and caches it next to the script, so it's
  a bit slower the very first time you use it.

## License

Do whatever you want with it.
