# 校验 editor 的 i18n 覆盖率。
#
# 硬性失败：源码引用的键在两份翻译里缺失 / zh 与 en 键集不一致 / 存在空值 /
# 翻译里有源码从不引用的多余键（避免文件腐化）。
#
# 用法：& .\tool\check_translations.ps1
# 退出码 0 = 通过；1 = 有问题。
#
# 注意：本文件含中文注释，必须保存为 UTF-8 with BOM，
# 否则 Windows PowerShell 5.1 会按 ANSI 解码而解析失败。
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$lib = Join-Path $root 'lib'
$dartFiles = @(Get-ChildItem $lib -Recurse -Filter *.dart)

function Read-Translation([string]$path) {
  $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $obj = ConvertFrom-Json -InputObject $text
  $map = @{}
  foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }
  return $map
}

# UI 命名空间白名单：首段命中即认为是翻译键。
$namespaces = @('about', 'app', 'blend', 'canvas', 'common', 'dialog', 'edit',
  'engine', 'interp', 'keyform', 'menu', 'motion', 'notice', 'panel',
  'progress', 'settings', 'shortcut', 'start', 'stat', 'status', 'time',
  'tool', 'ui')

# 虽落在 UI 命名空间内、但实际是 doc 操作名 / 动作 id 的字面量，不算翻译键。
$excluded = @(
  # keyform 操作
  'keyform.record', 'keyform.remove', 'keyform.delete',
  'keyform.set_blend_type', 'keyform.set_value',
  # motion 操作
  'motion.create', 'motion.delete', 'motion.load', 'motion.remove_key',
  'motion.set_curve', 'motion.set_key', 'motion.set_meta',
  'motion.record.begin', 'motion.record.writes', 'motion.record.end',
  # 文档级操作
  'settings.set',
  # 停靠区动作 id（其翻译键是 menu.panel.* / shortcut.panel.*）
  'panel.left', 'panel.right', 'panel.bottom', 'panel.fullscreenCanvas'
)

# 两段式且尾段是文件扩展名 → 是文件名（如 app.dart），不是翻译键。
$fileExtensions = @('dart', 'json', 'dll', 'so', 'dylib', 'png', 'jpg', 'md',
  'yaml', 'yml', 'toml', 'txt', 'amproj')

# diagnostics.stats 的字段名会被拼成 stat.<field>。
# 必须同时覆盖内置引擎与真实引擎两套字段。
$statFields = @(
  # 内置引擎
  'nodes', 'drawables', 'vertices', 'triangles', 'warp_deformers',
  'rotation_deformers', 'deformer_control_points', 'parameters', 'motions',
  'expressions', 'physics_settings', 'textures', 'atlas_bytes', 'frame_ms',
  'fallback',
  # 真实引擎
  'physics', 'revision', 'dirty', 'frame'
)

$used = New-Object System.Collections.Generic.HashSet[string]
# 动态拼接的键前缀，例如 'blend.${mode.wire}'、'settings.theme.${mode.name}'：
# 这些键无法逐字提取，改为「同前缀即视为被引用」。
$dynamicPrefixes = New-Object System.Collections.Generic.HashSet[string]
$literalPattern = "'([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)'"
$dynamicPattern = "'([a-z][A-Za-z0-9_.]*)\.\`$"
foreach ($f in $dartFiles) {
  $t = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  foreach ($m in [regex]::Matches($t, $literalPattern)) {
    $key = $m.Groups[1].Value
    $parts = $key.Split('.')
    $head = $parts[0]
    if ($excluded -contains $key) { continue }
    if ($parts.Count -eq 2 -and $fileExtensions -contains $parts[-1]) { continue }
    if ($namespaces -contains $head) { [void]$used.Add($key) }
  }
  foreach ($m in [regex]::Matches($t, $dynamicPattern)) {
    [void]$dynamicPrefixes.Add($m.Groups[1].Value)
  }
  if ($t.Contains("'stat.`${")) {
    foreach ($field in $statFields) { [void]$used.Add("stat.$field") }
  }
}

function Test-Used([string]$key) {
  if ($used.Contains($key)) { return $true }
  foreach ($prefix in $dynamicPrefixes) {
    if ($key.StartsWith("$prefix.")) { return $true }
  }
  return $false
}

$zh = Read-Translation (Join-Path $root 'assets\translations\zh-CN.json')
$en = Read-Translation (Join-Path $root 'assets\translations\en-US.json')

$missingZh = @($used | Where-Object { -not $zh.ContainsKey($_) } | Sort-Object)
$missingEn = @($used | Where-Object { -not $en.ContainsKey($_) } | Sort-Object)
$onlyZh = @($zh.Keys | Where-Object { -not $en.ContainsKey($_) } | Sort-Object)
$onlyEn = @($en.Keys | Where-Object { -not $zh.ContainsKey($_) } | Sort-Object)
$emptyZh = @($zh.Keys | Where-Object { $zh[$_] -eq '' } | Sort-Object)
$emptyEn = @($en.Keys | Where-Object { $en[$_] -eq '' } | Sort-Object)
$extraZh = @($zh.Keys | Where-Object { -not (Test-Used $_) } | Sort-Object)
$extraEn = @($en.Keys | Where-Object { -not (Test-Used $_) } | Sort-Object)

Write-Output "used=$($used.Count) zh=$($zh.Count) en=$($en.Count)"
Write-Output "missingInZh=$($missingZh.Count) missingInEn=$($missingEn.Count)"
Write-Output "onlyInZh=$($onlyZh.Count) onlyInEn=$($onlyEn.Count)"
Write-Output "emptyZh=$($emptyZh.Count) emptyEn=$($emptyEn.Count)"
Write-Output "extraZh=$($extraZh.Count) extraEn=$($extraEn.Count)"
if ($missingZh.Count) { Write-Output "MISSING_ZH: $($missingZh -join ', ')" }
if ($missingEn.Count) { Write-Output "MISSING_EN: $($missingEn -join ', ')" }
if ($onlyZh.Count) { Write-Output "ONLY_ZH: $($onlyZh -join ', ')" }
if ($onlyEn.Count) { Write-Output "ONLY_EN: $($onlyEn -join ', ')" }
if ($emptyZh.Count) { Write-Output "EMPTY_ZH: $($emptyZh -join ', ')" }
if ($emptyEn.Count) { Write-Output "EMPTY_EN: $($emptyEn -join ', ')" }
if ($extraZh.Count) { Write-Output "EXTRA_ZH: $($extraZh -join ', ')" }
if ($extraEn.Count) { Write-Output "EXTRA_EN: $($extraEn -join ', ')" }

$bad = $missingZh.Count + $missingEn.Count + $onlyZh.Count + $onlyEn.Count +
  $emptyZh.Count + $emptyEn.Count + $extraZh.Count + $extraEn.Count
if ($bad -gt 0) {
  Write-Output 'RESULT: FAIL'
  exit 1
}
Write-Output 'RESULT: OK'
exit 0
