<#
  让 Windows Terminal 把 IDEA 用到的组合键原样交给 tmux / Neovim：
    * Ctrl+Shift+字母（V、C 除外，保留为终端的粘贴 / 复制）改为发送扩展按键编码 ESC [ <小写字母编码> ; 6 u，
      否则终端里 Ctrl+Shift+F 和 Ctrl+F 是同一个按键
    * Alt+Enter 不再切换全屏（IDEA 的意图操作）
  用法（不需要管理员）：powershell -ExecutionPolicy Bypass -File windows\wt-keys.ps1
  修改前会备份为 settings.json.bak-时间；改完 Windows Terminal 会自动重新加载设置。
#>
param([string]$SettingsPath)
$ErrorActionPreference = 'Stop'

$candidates = @($SettingsPath | Where-Object { $_ }) + @(
  "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
  "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
  "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
$path = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $path) { Write-Host '未找到 Windows Terminal 的 settings.json，请先打开一次 Windows Terminal' -ForegroundColor Yellow; exit 1 }

$letters = 'ABDEFGHIJKLMNOPQRSTUWXYZ'.ToCharArray()
$new = @()
foreach ($l in $letters) {
  $code = [int][char]$l + 32
  $new += [pscustomobject]@{
    command = [pscustomobject]@{ action = 'sendInput'; input = "$([char]27)[$code;6u" }
    keys    = "ctrl+shift+$("$l".ToLower())"
  }
}
$new += [pscustomobject]@{ command = 'unbound'; keys = 'alt+enter' }

$text = [IO.File]::ReadAllText($path)
try {
  $json = $text | ConvertFrom-Json
} catch {
  # 含注释的 settings.json 无法安全解析，改为提示手动粘贴
  Write-Host "settings.json 里有注释，无法自动修改。请在 Windows Terminal 设置 -> 打开 JSON 文件，把下面内容加入 ""actions"" 数组：" -ForegroundColor Yellow
  ($new | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 }) -join ",`n"
  exit 1
}

if (-not ($json.PSObject.Properties.Name -contains 'actions')) {
  $json | Add-Member -NotePropertyName actions -NotePropertyValue @()
}
$ourKeys = $new | ForEach-Object { $_.keys }
# 去掉旧的同名按键设置（包括以前运行本脚本加的），再加入新的
$kept = @($json.actions | Where-Object { -not ($_.PSObject.Properties.Name -contains 'keys' -and $ourKeys -contains $_.keys) })
$json.actions = $kept + $new
# 新版 Windows Terminal 把按键单独放在 keybindings 里，同名按键也要去掉，否则会和上面冲突
if ($json.PSObject.Properties.Name -contains 'keybindings') {
  $json.keybindings = @($json.keybindings | Where-Object { -not ($ourKeys -contains $_.keys) })
}

Copy-Item $path "$path.bak-$(Get-Date -Format yyyyMMddHHmmss)"
$out = $json | ConvertTo-Json -Depth 32
[IO.File]::WriteAllText($path, $out, (New-Object Text.UTF8Encoding($false)))
Write-Host "已更新 $path" -ForegroundColor Green
Write-Host '现在 Windows Terminal 里 Ctrl+Shift+F 等 IDEA 快捷键可以直接用了（Ctrl+Shift+V / C 仍是粘贴 / 复制）'
