$ErrorActionPreference = 'Stop'
$root = 'F:\exeliang\Anima\editor'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-Json([string]$path) {
  $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $obj = ConvertFrom-Json -InputObject $text
  $map = @{}
  foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }
  return $map
}

$zh = Read-Json "$root\assets\translations\zh-CN.json"
$en = Read-Json "$root\assets\translations\en-US.json"
$used = @(Get-Content -LiteralPath "$root\.keys.txt" -Encoding UTF8 | Where-Object { $_ -ne '' })

$missingZh = @($used | Where-Object { -not $zh.ContainsKey($_) })
$missingEn = @($used | Where-Object { -not $en.ContainsKey($_) })
$extraZh = @($zh.Keys | Where-Object { $used -notcontains $_ })
$extraEn = @($en.Keys | Where-Object { $used -notcontains $_ })
$onlyZh = @($zh.Keys | Where-Object { -not $en.ContainsKey($_) })
$onlyEn = @($en.Keys | Where-Object { -not $zh.ContainsKey($_) })
$emptyZh = @($zh.Keys | Where-Object { $zh[$_] -eq '' })

Write-Output "used=$($used.Count) zh=$($zh.Count) en=$($en.Count)"
Write-Output "missingInZh=$($missingZh.Count) missingInEn=$($missingEn.Count)"
Write-Output "extraZh=$($extraZh.Count) extraEn=$($extraEn.Count)"
Write-Output "onlyInZh=$($onlyZh.Count) onlyInEn=$($onlyEn.Count) emptyZh=$($emptyZh.Count)"
if ($missingZh.Count) { Write-Output "MISSING_ZH: $(($missingZh | Select-Object -First 25) -join ', ')" }
if ($missingEn.Count) { Write-Output "MISSING_EN: $(($missingEn | Select-Object -First 25) -join ', ')" }
if ($onlyZh.Count) { Write-Output "ONLY_ZH: $(($onlyZh | Select-Object -First 25) -join ', ')" }
if ($onlyEn.Count) { Write-Output "ONLY_EN: $(($onlyEn | Select-Object -First 25) -join ', ')" }
if ($extraZh.Count) { Write-Output "EXTRA_ZH: $(($extraZh | Select-Object -First 25) -join ', ')" }
