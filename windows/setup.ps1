<#
  tmux-nvim-kit 的 Windows 端设置。在 PowerShell 里运行：
    powershell -ExecutionPolicy Bypass -File windows\setup.ps1 [-Port 7681] [-PrivateNetwork] [-AllowPublic] [-SkipFont] [-SkipWslConfig]

  做的事情：
    1. 为当前用户安装 JetBrainsMono Nerd Font（终端显示图标需要，无需管理员）
    2. 把 WSL 网络设为镜像模式（WSL 可直接用 Windows 的代理，内网能访问 WSL 里的服务）
    3. 防火墙放行浏览器访问端口（需要管理员，会弹出 UAC 确认）
    4. -PrivateNetwork：把当前连接的网络设为"专用网络"（公用网络下防火墙规则不生效，别人的电脑打不开）
       -AllowPublic   ：不改网络类型，让规则在公用网络也生效（仅限同一网段）
#>
param(
  [int]$Port = 7681,
  [switch]$PrivateNetwork,
  [switch]$AllowPublic,
  [switch]$SkipFont,
  [switch]$SkipWslConfig
)
$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "    $msg" }
function Warn($msg) { Write-Host "[注意] $msg" -ForegroundColor Yellow }

# ------------------------------------------------------------- 1. 字体
if (-not $SkipFont) {
  Step "安装 JetBrainsMono Nerd Font（当前用户）"
  $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
  $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
  $styles = [ordered]@{ 'Regular' = ''; 'Bold' = ' Bold'; 'Italic' = ' Italic'; 'BoldItalic' = ' Bold Italic' }
  $missing = $styles.Keys | Where-Object { -not (Test-Path (Join-Path $fontDir "JetBrainsMonoNerdFontMono-$_.ttf")) }
  if ($missing) {
    $tmp = Join-Path $env:TEMP "jbmono-$(Get-Random)"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'JetBrainsMono.zip'
    Info "下载中（约 100MB，如很慢请先打开代理）..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip' -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force $fontDir | Out-Null
    Add-Type -Namespace KitFont -Name Gdi -MemberDefinition '[DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResource(string f);'
    foreach ($s in $styles.Keys) {
      $file = "JetBrainsMonoNerdFontMono-$s.ttf"
      Copy-Item (Join-Path $tmp $file) (Join-Path $fontDir $file) -Force
      New-ItemProperty -Path $regPath -Name "JetBrainsMono Nerd Font Mono$($styles[$s]) (TrueType)" -Value (Join-Path $fontDir $file) -PropertyType String -Force | Out-Null
      [KitFont.Gdi]::AddFontResource((Join-Path $fontDir $file)) | Out-Null
    }
    Remove-Item -Recurse -Force $tmp
    Info "已安装。请在 Windows Terminal 设置 -> 默认值 -> 外观 -> 字体 选择 'JetBrainsMono Nerd Font Mono'"
  } else {
    Info "已安装过，跳过"
  }
}

# ------------------------------------------------------------- 2. WSL 镜像网络
if (-not $SkipWslConfig) {
  Step "WSL 网络设为镜像模式（%USERPROFILE%\.wslconfig）"
  $cfg = Join-Path $env:USERPROFILE '.wslconfig'
  $want = [ordered]@{ networkingMode = 'mirrored'; autoProxy = 'true'; dnsTunneling = 'true'; firewall = 'true' }
  if (-not (Test-Path $cfg)) {
    $lines = @('[wsl2]') + ($want.Keys | ForEach-Object { "$_=$($want[$_])" })
    Set-Content -Path $cfg -Value $lines -Encoding ascii
    Info "已创建 $cfg"
  } else {
    $text = Get-Content $cfg -Raw
    $toAdd = $want.Keys | Where-Object { $text -notmatch "(?m)^\s*$_\s*=" }
    if ($toAdd) {
      Copy-Item $cfg "$cfg.bak" -Force
      $lines = Get-Content $cfg
      $add = $toAdd | ForEach-Object { "$_=$($want[$_])" }
      $idx = [Array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -match '^\s*\[wsl2\]\s*$' })
      if ($idx -ge 0) { $lines = $lines[0..$idx] + $add + $(if ($idx + 1 -lt $lines.Count) { $lines[($idx + 1)..($lines.Count - 1)] }) }
      else { $lines = $lines + @('', '[wsl2]') + $add }
      Set-Content -Path $cfg -Value $lines -Encoding ascii
      Info "已补充: $($toAdd -join ', ')（原文件备份为 .wslconfig.bak）"
    } else {
      Info "已是镜像模式，跳过"
    }
  }
  Warn "修改后需执行 wsl --shutdown 再打开 Ubuntu 才生效（会关闭所有 WSL 程序）"
}

# ------------------------------------------------------------- 3/4. 防火墙与网络类型（管理员）
Step "防火墙放行端口 $Port（需要管理员权限，请在弹出的 UAC 窗口点'是'）"
$profiles = if ($AllowPublic) { 'Any' } else { 'Domain,Private' }
$remote = if ($AllowPublic) { 'LocalSubnet' } else { 'Any' }
$admin = @"
`$ErrorActionPreference = 'Stop'
`$name = 'tmux-web $Port'
Get-NetFirewallRule -DisplayName `$name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName `$name -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile $profiles -RemoteAddress $remote | Out-Null
# WSL 镜像网络下入站连接还要经过 Hyper-V 防火墙
`$vm = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
Get-NetFirewallHyperVRule -Name "tmux-web-$Port" -ErrorAction SilentlyContinue | Remove-NetFirewallHyperVRule
New-NetFirewallHyperVRule -Name "tmux-web-$Port" -DisplayName `$name -Direction Inbound -VMCreatorId `$vm -Protocol TCP -LocalPorts $Port -Action Allow | Out-Null
$(if ($PrivateNetwork) { "Get-NetConnectionProfile | Where-Object { `$_.IPv4Connectivity -ne 'Disconnected' -and `$_.InterfaceAlias -notmatch 'Clash|vEthernet|WSL|Loopback' } | Set-NetConnectionProfile -NetworkCategory Private" })
"@
$p = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $admin
if ($p.ExitCode -eq 0) { Info "防火墙规则已添加" } else { Warn "管理员操作未完成（退出码 $($p.ExitCode)），可重新运行本脚本" }

# ------------------------------------------------------------- 检查
Step "检查"
$nets = Get-NetConnectionProfile | Where-Object { $_.InterfaceAlias -notmatch 'Clash|vEthernet|WSL|Loopback' }
foreach ($n in $nets) {
  $ip = (Get-NetIPAddress -InterfaceAlias $n.InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
  Info ("{0}: {1}  网络类型: {2}" -f $n.InterfaceAlias, $ip, $n.NetworkCategory)
  if ($ip) { Info "  内网访问地址: http://${ip}:$Port" }
  if ($n.NetworkCategory -eq 'Public' -and -not $AllowPublic) {
    Warn "$($n.InterfaceAlias) 是'公用网络'，别人的电脑会被防火墙挡住。可加 -PrivateNetwork 重新运行，或在 Windows 设置里把该网络改为'专用网络'"
  }
}
Write-Host ""
