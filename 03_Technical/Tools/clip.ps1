<#
.SYNOPSIS
    网页剪藏：URL -> defuddle 抽正文 -> 清理导航噪音 -> knap 套模板 -> 落盘 00_Inbox/剪藏/
.EXAMPLE
    ./clip.ps1 -Url "https://example.com/article"
#>
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Vault = "D:\Workspace\Obsidian_Vault"
)

$ErrorActionPreference = 'Stop'
$env:Path = "$env:Path;$env:APPDATA\npm"
$Template = Join-Path $Vault "05_Templates\剪藏模板.md"
$OutDir = Join-Path $Vault "00_Inbox\剪藏"
$today = Get-Date -Format 'yyyy-MM-dd'
$gid = [guid]::NewGuid().ToString("N")
$rawJson = Join-Path $env:TEMP "clip_raw_$gid.json"
$modJson = Join-Path $env:TEMP "clip_mod_$gid.json"
$encNoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Get-Command defuddle -ErrorAction SilentlyContinue)) { throw "缺少 defuddle，请先 npm i -g defuddle" }
if (-not (Get-Command knap -ErrorAction SilentlyContinue)) { throw "缺少 knap，请先 npm i -g knap" }
if (-not (Test-Path $Template)) { throw "模板不存在: $Template" }

# ---------- 1. 抽取 ----------
& defuddle parse $Url --md --json -o $rawJson | Out-Null
if (-not (Test-Path $rawJson)) { throw "defuddle 抽取失败（页面可能需要登录或为纯 JS 渲染）: $Url" }

# ---------- 2. 清理导航噪音 ----------
function Remove-NavNoise([string]$text) {
    $lines = $text -split "`r?`n"
    $orig = $lines.Count
    $linkOnly = '^\s*[-*]\s*\[[^\]]*\]\([^)]*\)\s*$'

    # 去掉开头连续「纯链接列表」（典型顶部导航）
    $start = 0
    while ($start -lt $lines.Count) {
        $l = $lines[$start]
        if ([string]::IsNullOrWhiteSpace($l)) { $start++; continue }
        if ($l -match $linkOnly) { $start++; continue }
        break
    }
    if ($start -gt 0 -and $start -lt $lines.Count) { $lines = $lines[$start..($lines.Count - 1)] }

    # 去掉纯 HTML 标签行（iframe / img / div 等，含广告容器）
    $lines = @($lines | Where-Object { $_ -notmatch '^\s*<(iframe|div|script|style|ins|img|video|figure|aside|amp-ad|form)\b' })

    # 去掉全文的纯链接列表项（正文里的链接都带说明文字，纯链接项基本都是导航）
    $lines = @($lines | Where-Object { $_ -notmatch $linkOnly })

    # 连续空行压成一个
    $compact = New-Object System.Collections.Generic.List[string]
    $blank = 0
    foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { $blank++; if ($blank -gt 1) { continue } }
        else { $blank = 0 }
        $compact.Add($l)
    }

    # 去掉尾部「热点推荐/相关阅读/免责声明」等板块（仅在靠后位置才切）
    $tailMark = '^(热点推荐|相关阅读|相关文章|相关推荐|免责声明|版权声明|责任编辑|编辑[:：])'
    $lines = $compact
    for ($i = $lines.Count - 1; $i -ge [int]($lines.Count * 0.6); $i--) {
        if ($lines[$i] -match $tailMark) { $lines = $lines[0..($i - 1)]; break }
    }

    $out = ($lines -join "`n").Trim()
    # 清理过度时回退
    if ($out.Length -lt 200) { return $text }
    return $out
}

$j = [System.IO.File]::ReadAllText($rawJson, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ($j.content) { $j.content = Remove-NavNoise ([string]$j.content) }

# ---------- 3. 补字段（defuddle 不返回 url） ----------
$j | Add-Member -NotePropertyName url -NotePropertyValue $Url -Force
$j | Add-Member -NotePropertyName created -NotePropertyValue $today -Force
if (-not $j.domain) { $j | Add-Member -NotePropertyName domain -NotePropertyValue ([uri]$Url).Host -Force }
foreach ($k in 'title', 'author', 'published', 'domain') {
    if ($null -eq $j.$k) { $j | Add-Member -NotePropertyName $k -NotePropertyValue "" -Force }
}

# ---------- 4. 文件名安全化 ----------
$safe = ([string]$j.title) -replace '[\\/:*?"<>|\r\n\t]', '_'
$safe = $safe.Trim().TrimEnd('.')
if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "未命名剪藏" }
if ($safe.Length -gt 60) { $safe = $safe.Substring(0, 60) }
$j | Add-Member -NotePropertyName safe_title -NotePropertyValue $safe -Force

[System.IO.File]::WriteAllText($modJson, ($j | ConvertTo-Json -Depth 30 -Compress), $encNoBom)

# ---------- 5. 渲染 ----------
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
$outFile = Join-Path $OutDir "$today $safe.md"
if (Test-Path $outFile) { throw "目标已存在，避免覆盖: $outFile" }
& knap render $Template --data $modJson -o $outFile | Out-Null

Remove-Item $rawJson, $modJson -Force -ErrorAction SilentlyContinue
if (-not (Test-Path $outFile)) { throw "渲染失败: $outFile" }

$size = (Get-Item $outFile).Length
Write-Output "OK $outFile ($size B)"
