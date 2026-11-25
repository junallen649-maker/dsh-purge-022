#requires -Version 5.1
<#
  install.ps1  --  one-shot installer: dsh-purge for DeepSeek Harness 0.2.1 / 0.2.2
                    (Windows desktop; for `dsh web` on macOS/Linux use install.sh)

  Everything is local: no npm, no pnpm, no network. The plugin body, the
  re-fitted 0.2.2 patch table and the red-team preset all live in payload\.

  What it does
    1. locate the harness (process / registry / shortcuts / Programs / disk walk)
    2. read its build  -> pick the matching patch table (0.2.1 original, 0.2.2 re-fit)
    3. close the harness (sessions are on disk, safe)
    4. back up every path it is about to touch
    5. install the plugin + mount it into profiles\desktop and profiles\web
    6. unpack resources\app.asar if the build is sealed, move the archive aside
    7. apply the patch table with the harness's own Electron (node mode)
    8. on 0.2.2: drop preset entries the build no longer ships, then verify

  Switches
    -HarnessDir <dir>  install dir when it is not in a standard location
    -DshHome <dir>     alternate dsh home (default %USERPROFILE%\.dsh)
    -SkipApply         restore files only, never patch @deepseek-ai
    -SkipPreset        do not touch .agent-presets\redteam
    -NoUnpack          never unpack / move app.asar
    -NoKill            do not close a running harness
    -ForceVersion      proceed on an untested build
    -Probe             locate the harness and exit
#>
[CmdletBinding()]
param(
    [string]$HarnessDir,
    [string]$DshHome,
    [switch]$SkipApply,
    [switch]$SkipPreset,
    [switch]$NoUnpack,
    [switch]$NoKill,
    [switch]$ForceVersion,
    [switch]$Probe
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$payload = Join-Path $root 'payload'
if (-not (Test-Path -LiteralPath $payload)) { throw "payload missing next to install.ps1: $payload" }
if (-not $DshHome) { $DshHome = Join-Path $env:USERPROFILE '.dsh' }

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}
function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}
function Test-ReparsePoint([string]$Path) {
    try { $i = Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return $false }
    return [bool]($i.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}
function Get-HarnessState([string]$Dir, [switch]$AllowAnyName) {
    if (-not $Dir) { return $null }
    if (Test-Path -LiteralPath (Join-Path $Dir 'resources\app\package.json')) { return 'dir' }
    $asar = Join-Path $Dir 'resources\app.asar'
    if (-not (Test-Path -LiteralPath $asar)) { return $null }
    if ($AllowAnyName) { return 'asar' }
    $leaf = Split-Path -Leaf $Dir
    if ($leaf -match 'deepseek|harness|dsh') { return 'asar' }
    $e = Get-ChildItem -LiteralPath $Dir -Filter '*.exe' -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -match 'deepseek|harness|dsh' } | Select-Object -First 1
    if ($e) { return 'asar' }
    return $null
}

# ===========================================================================
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  dsh-purge installer  (DeepSeek Harness 0.2.1 / 0.2.2)' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------- [1/8] host
Write-Host '[1/8] locating harness ...' -ForegroundColor Cyan
$hits = New-Object System.Collections.ArrayList
$seen = @{}
$tried = New-Object System.Collections.ArrayList
function Add-Hit([string]$Dir, [string]$Src, [switch]$Trust) {
    if (-not $Dir) { return }
    $full = $null
    try { $full = (Resolve-Path -LiteralPath $Dir -ErrorAction Stop).Path } catch { return }
    $k = $full.ToLower()
    if ($seen.ContainsKey($k)) { return }
    $st = Get-HarnessState $full -AllowAnyName:$Trust
    if (-not $st) { return }
    $seen[$k] = $true
    [void]$hits.Add([pscustomobject]@{ Dir = $full; Source = $Src; State = $st })
}
if ($HarnessDir) { [void]$tried.Add("-HarnessDir $HarnessDir"); Add-Hit $HarnessDir '-HarnessDir' -Trust }
[void]$tried.Add('running processes')
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'deepseek|harness|dsh' } | ForEach-Object {
    if ($_.Path) { Add-Hit (Split-Path -Parent $_.Path) ('process ' + $_.ProcessName) }
}
foreach ($p in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'),
        (Join-Path $env:ProgramFiles 'DeepSeek Harness'),
        (Join-Path ${env:ProgramFiles(x86)} 'DeepSeek Harness'),
        'E:\harness', 'D:\harness'
    )) { [void]$tried.Add($p); Add-Hit $p 'standard path' }
[void]$tried.Add('%LOCALAPPDATA%\Programs\*')
foreach ($p in @($env:LOCALAPPDATA + '\Programs', ${env:ProgramFiles(x86)} + '\Programs')) {
    if ($p -and (Test-Path -LiteralPath $p)) {
        Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (Get-HarnessState $_.FullName) { Add-Hit $_.FullName 'Programs scan' }
        }
    }
}
[void]$tried.Add('registry Uninstall keys')
foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
    Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'DeepSeek|Harness|dsh' } | ForEach-Object {
            if ($_.InstallLocation) { Add-Hit $_.InstallLocation 'registry' }
            if ($_.DisplayIcon) {
                $icon = ($_.DisplayIcon -replace ',\s*-?\d+\s*$', '').Trim('"')
                if (Test-Path -LiteralPath $icon -PathType Leaf) { Add-Hit (Split-Path -Parent $icon) 'registry' }
            }
        }
}
[void]$tried.Add('shortcuts')
try {
    $sh = New-Object -ComObject WScript.Shell
    foreach ($d in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
                     (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
                     (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'))) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        Get-ChildItem -LiteralPath $d -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'deepseek|harness|dsh' } | ForEach-Object {
                try { $t = $sh.CreateShortcut($_.FullName).TargetPath; if ($t) { Add-Hit (Split-Path -Parent $t) 'shortcut' } } catch { }
            }
    }
} catch { }

$install = $null
if ($hits.Count -gt 0) {
    $dirHits = @($hits | Where-Object { $_.State -eq 'dir' })
    $ordered = @($dirHits) + @($hits | Where-Object { $_.State -ne 'dir' })
    foreach ($h in $ordered) { Write-Host ("      hit: {0}  [{1}, {2}]" -f $h.Dir, $h.Source, $h.State) }
    $install = $ordered[0].Dir
} else {
    Write-Host '      nothing found. checked:' -ForegroundColor Yellow
    foreach ($t in $tried) { Write-Host ('        - ' + $t) }
}
if ($Probe) { return }
if (-not $install) {
    throw "DeepSeek Harness not found. Start it once, or pass -HarnessDir 'E:\harness'."
}

$exe = Join-Path $install 'DeepSeek Harness.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    $exe = Get-ChildItem -LiteralPath $install -Filter '*.exe' -File | Sort-Object Length -Descending |
           Select-Object -First 1 -ExpandProperty FullName
}
if (-not $exe) { throw "no .exe inside $install" }
$exeName = [System.IO.Path]::GetFileNameWithoutExtension($exe)
$appDir = Join-Path $install 'resources\app'
$aiBase = Join-Path $appDir 'dsh\node_modules\@deepseek-ai'

# ------------------------------------------------------------- [2/8] version
Write-Host '[2/8] reading build ...' -ForegroundColor Cyan
$appPkg = Join-Path $appDir 'package.json'
$ver = if (Test-Path $appPkg) { (Read-Json $appPkg).version } else { $null }
if (-not $ver) { Write-Host '      app.asar is still sealed -- version unknown until step 6' -ForegroundColor Yellow }
else { Write-Host ("      host {0}" -f $ver) }

$kind = 'other'
if ($ver -match '^0\.2\.2') { $kind = '022' }
elseif ($ver -match '^0\.2\.1') { $kind = '021' }
elseif ($ver) { $kind = 'other' }

if ($kind -eq 'other' -and $ver -and -not $ForceVersion) {
    Write-Host ''
    Write-Host ("  This build ({0}) has not been tested with these patch tables." -f $ver) -ForegroundColor Yellow
    Write-Host '  Tested: 0.2.1-rc.2 / 0.2.1-rc.5 (original) and 0.2.2.x (re-fit).' -ForegroundColor Yellow
    Write-Host '  Rerun with -ForceVersion to try anyway.' -ForegroundColor Yellow
    throw 'untested build'
}
Write-Host ("      patch table: {0}" -f $(if ($kind -eq '022') { 're-fit for 0.2.2' } else { 'original 1.1.90' }))

# ---------------------------------------------------------------- [3/8] stop
Write-Host '[3/8] stopping harness ...' -ForegroundColor Cyan
if ($NoKill) { Write-Host '      -NoKill: left running' -ForegroundColor Yellow }
else {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq $exeName -and $_.Path -eq $exe }
    if ($procs) {
        Write-Host ("      {0} process(es); closing in 3s (Ctrl+C to abort) ..." -f @($procs).Count)
        Start-Sleep -Seconds 3
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Host '      closed' -ForegroundColor Green
    } else { Write-Host '      not running' }
}

# -------------------------------------------------------------- [4/8] backup
Write-Host '[4/8] backing up ...' -ForegroundColor Cyan
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $env:USERPROFILE ('.dsh.bak-' + $stamp)
$touched = 0
foreach ($rel in @('plugins\dsh-purge', 'profiles', '.agent-presets', 'redteam', 'dsh-purge')) {
    $p = Join-Path $DshHome $rel
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $d = Join-Path $backup $rel
    New-Item -ItemType Directory -Path (Split-Path $d -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $p -Destination $d -Recurse -Force
    $touched++
}
if ($touched) { Write-Host ("      {0} path(s) -> {1}" -f $touched, $backup) } else { Write-Host '      fresh machine, nothing to back up' }

# ------------------------------------------------------------- [5/8] install
Write-Host '[5/8] installing plugin ...' -ForegroundColor Cyan
function Install-Tree([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From)) { return }
    if (Test-Path -LiteralPath $To) {
        $it = Get-Item -LiteralPath $To -Force
        if ((Test-ReparsePoint $To) -or -not $it.PSIsContainer) { Remove-Item -LiteralPath $To -Force -Recurse }
    }
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    Get-ChildItem -LiteralPath $From -Force | ForEach-Object {
        $d = Join-Path $To $_.Name
        if (Test-Path -LiteralPath $d) {
            $it = Get-Item -LiteralPath $d -Force
            if ((Test-ReparsePoint $d) -or -not $it.PSIsContainer) { Remove-Item -LiteralPath $d -Force -Recurse }
        }
        Copy-Item -LiteralPath $_.FullName -Destination $d -Recurse -Force
    }
}

$plugSrc = Join-Path $payload 'plugin'
$plugDst = Join-Path $DshHome 'plugins\dsh-purge'
Install-Tree $plugSrc $plugDst
Write-Host ("      plugin -> {0}" -f $plugDst)

if ($kind -eq '022') {
    $refit = Join-Path $payload 'core-022.js'
    if (-not (Test-Path -LiteralPath $refit)) { throw "payload\core-022.js missing" }
    Copy-Item -LiteralPath $refit -Destination (Join-Path $plugDst 'lib\core.js') -Force
    Write-Host '      core.js -> 0.2.2 re-fit table' -ForegroundColor Green
}

# profile manifests + a real plugin copy (no pnpm needed)
$profiles = Join-Path $payload 'profiles'
foreach ($p in @('desktop', 'web')) {
    $dstProf = Join-Path $DshHome "profiles\$p"
    New-Item -ItemType Directory -Path $dstProf -Force | Out-Null
    if (Test-Path -LiteralPath (Join-Path $profiles "$p\package.json")) {
        Copy-Item -LiteralPath (Join-Path $profiles "$p\package.json") -Destination (Join-Path $dstProf 'package.json') -Force
        Copy-Item -LiteralPath (Join-Path $profiles "$p\cordis.patch.yml") -Destination (Join-Path $dstProf 'cordis.patch.yml') -Force
        Copy-Item -LiteralPath (Join-Path $profiles "$p\pnpm-workspace.yaml") -Destination (Join-Path $dstProf 'pnpm-workspace.yaml') -Force -ErrorAction SilentlyContinue
    } else {
        # payload has no profiles\ -> build the two files inline
        $pj = [ordered]@{
            name = "dsh-profile-$p"
            private = $true
            dependencies = [ordered]@{ 'dsh-purge' = 'file:../../plugins/dsh-purge' }
            dsh = [ordered]@{ profile = [ordered]@{ bundles = @('@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', 'dsh-purge') } }
        }
        Write-Utf8NoBom (Join-Path $dstProf 'package.json') ($pj | ConvertTo-Json -Depth 8)
        $patch = @'
# dsh-purge mount point (generated by install.ps1)
- insert:
    - id: dsh-purge
      name: dsh-purge
      inject: [systemPrompt, tools]
      config:
        enabled: true
        stripMnemon: true
        capabilityProtocol: true
        hooksDenyBypass: true
'@
        Write-Utf8NoBom (Join-Path $dstProf 'cordis.patch.yml') $patch
        Write-Utf8NoBom (Join-Path $dstProf 'pnpm-workspace.yaml') "packages:`n  - .`n`nnodeLinker: hoisted`nautoInstallPeers: false`n`nallowBuilds:`n  dsh-purge: true`n"
    }
    $nm = Join-Path $dstProf 'node_modules'
    New-Item -ItemType Directory -Path $nm -Force | Out-Null
    foreach ($junk in @('.modules.yaml', '.pnpm-workspace-state-v1.json')) {
        $jp = Join-Path $nm $junk
        if (Test-Path -LiteralPath $jp) { Remove-Item -LiteralPath $jp -Force }
    }
    $pd = Join-Path $nm 'dsh-purge'
    if (Test-Path -LiteralPath $pd) { Remove-Item -LiteralPath $pd -Recurse -Force }
    Install-Tree $plugDst $pd
    Write-Host ("      profile {0}: mounted" -f $p)
}

# stamps from another machine would make the host believe patches are applied
foreach ($f in @('applied.json', 'installed-rev', 'override-state.json', 'unpacked-asar.json',
                 'version-history.json', 'auto-update-guard.json', 'settle-restart.guard',
                 'last-cwd.txt', 'channel.json')) {
    $fp = Join-Path $DshHome ('dsh-purge\' + $f)
    if (Test-Path -LiteralPath $fp) { Remove-Item -LiteralPath $fp -Force }
}

# ------------------------------------------------------------- [6/8] unpack
Write-Host '[6/8] sealed asar check ...' -ForegroundColor Cyan
$asarPath = Join-Path $install 'resources\app.asar'
$hasApp = Test-Path -LiteralPath $appDir

if ($NoUnpack) { Write-Host '      -NoUnpack: skipped' -ForegroundColor Yellow }
elseif ((Test-Path -LiteralPath $asarPath) -and $hasApp) {
    $bak = "$asarPath.dsh-purge-bak"
    try {
        if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force }
        Move-Item -LiteralPath $asarPath -Destination $bak -Force
        Write-Host ("      app.asar -> {0} (unpacked dir takes over)" -f (Split-Path -Leaf $bak)) -ForegroundColor Green
    } catch {
        Write-Warning ("could not move app.asar aside: {0}" -f $_.Exception.Message)
    }
} elseif ((Test-Path -LiteralPath $asarPath) -and -not $hasApp) {
    Write-Host '      sealed archive, unpacking ...'
    $env:ELECTRON_RUN_AS_NODE = '1'
    $env:DSH_HOME = $DshHome
    $mjs = Join-Path $DshHome 'dsh-purge\unpack-host.mjs'
    New-Item -ItemType Directory -Path (Split-Path $mjs -Parent) -Force | Out-Null
    $coreUrl = ([System.Uri]::new((Join-Path $plugDst 'lib\core.js'))).AbsoluteUri
    $asarUrl = ([System.Uri]::new((Join-Path $plugDst 'lib\extract-asar.js'))).AbsoluteUri
    $body = @"
import * as core from '$coreUrl';
import { renameAsarAside } from '$asarUrl';
const out = { ok: false };
try {
  const r = await core.openSealedDesktopHost({ forApply: true });
  out.appDir = r.appDir; out.aiBase = r.aiBase;
  if (!out.aiBase) throw new Error('no @deepseek-ai under ' + String(r.appDir || '?'));
  const h = core.sealedAsarHandoff();
  if (h && h.asar) out.asarMoved = renameAsarAside(h.asar);
  out.ok = true;
} catch (e) { out.error = String((e && e.message) || e); }
console.log('UNPACK ' + JSON.stringify(out));
"@
    Write-Utf8NoBom $mjs $body
    $uout = & $exe --expose-internals $mjs 2>&1 | Out-String -Width 400
    $um = [regex]::Match($uout, 'UNPACK\s+(\{.*\})')
    if ($um.Success -and ($um.Groups[1].Value | ConvertFrom-Json).ok) {
        Write-Host '      unpacked' -ForegroundColor Green
        if ((Test-Path -LiteralPath $asarPath) -and (Test-Path -LiteralPath $appDir)) {
            Move-Item -LiteralPath $asarPath -Destination "$asarPath.dsh-purge-bak" -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Warning 'unpack failed -- open the host once and use the panel -> Apply'
    }
} else {
    Write-Host '      already unpacked'
}

# -------------------------------------------------------------- [7/8] apply
Write-Host '[7/8] applying patches ...' -ForegroundColor Cyan
$cli = Join-Path $plugDst 'bin\dsh-purge.js'
$logDir = Join-Path $DshHome 'dsh-purge'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logPath = Join-Path $logDir ('install-' + $stamp + '.log')

if ($SkipApply) { Write-Host '      -SkipApply: skipped' -ForegroundColor Yellow }
elseif (-not (Test-Path -LiteralPath $aiBase)) {
    Write-Host '      @deepseek-ai not found -- start the host, then panel -> Apply' -ForegroundColor Yellow
} else {
    $env:ELECTRON_RUN_AS_NODE = '1'
    $env:DSH_SURFACE = 'desktop'
    $env:DSH_BASE = $aiBase
    $env:DSH_HOME = $DshHome
    $out = & $exe --expose-internals $cli --apply 2>&1 | Out-String -Width 400
    Set-Content -LiteralPath $logPath -Value $out -Encoding UTF8
    $a = ([regex]::Matches($out, '✓ 已清洗')).Count
    $b = ([regex]::Matches($out, '- 已是最新')).Count
    $m = ([regex]::Matches($out, '⚠ 文件缺失')).Count
    $f = ([regex]::Matches($out, '✗')).Count
    Write-Host ("      applied={0} already={1} missing_file={2} failed={3}" -f $a, $b, $m, $f)
    Write-Host ("      log: {0}" -f $logPath) -ForegroundColor DarkGray
}

# ------------------------------------------------------------- [8/8] preset
Write-Host '[8/8] preset + verify ...' -ForegroundColor Cyan
$presetYml = Join-Path $DshHome '.agent-presets\redteam\agent.cordis.yml'

if ($kind -eq '022' -and -not $SkipPreset -and (Test-Path -LiteralPath $presetYml)) {
    $raw = [IO.File]::ReadAllText($presetYml)
    $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"
    $removed = New-Object System.Collections.ArrayList
    foreach ($id in @('tool-subagent-list-agents', 'workflow-worker-thread')) {
        $out = New-Object System.Collections.ArrayList
        $i = 0
        $hit = 0
        while ($i -lt $lines.Count) {
            $mm = [regex]::Match($lines[$i], '^(\s*)-\s+id:\s*' + [regex]::Escape($id) + '\s*$')
            if (-not $mm.Success) { [void]$out.Add($lines[$i]); $i++; continue }
            $ind = $mm.Groups[1].Value.Length
            $i++; $hit++
            while ($i -lt $lines.Count) {
                $l = $lines[$i]
                if ($l.Trim() -eq '') { $i++; continue }
                $cur = $l.Length - $l.TrimStart().Length
                if ($cur -gt $ind) { $i++; continue }
                if ($cur -eq $ind -and $l.TrimStart().StartsWith('#')) { $i++; continue }
                break
            }
        }
        if ($hit) { $lines = @($out); [void]$removed.Add($id) }
    }
    if ($removed.Count) {
        $bak = $presetYml + '.bak-' + $stamp
        Copy-Item -LiteralPath $presetYml -Destination $bak -Force
        Write-Utf8NoBom $presetYml ($lines -join $nl)
        Write-Host ("      preset: removed {0}" -f ($removed -join ', ')) -ForegroundColor Green
    } else {
        Write-Host '      preset: already clean'
    }
}

if (Test-Path -LiteralPath $aiBase) {
    $status = & $exe --expose-internals $cli --status 2>&1 | Out-String -Width 400
    $m1 = [regex]::Match($status, '(\d+)\s*/\s*(\d+)\s*已清洗')
    $m2 = [regex]::Match($status, '(\d+)\s*待清洗')
    if ($m1.Success) { Write-Host ("      dsh-purge: {0}/{1} cleaned" -f $m1.Groups[1].Value, $m1.Groups[2].Value) }
    if ($m2.Success) {
        $pend = [int]$m2.Groups[1].Value
        if ($pend -gt 0) { Write-Warning ("still {0} pending -- open the panel and press Apply" -f $pend) }
        else { Write-Host '      pending 0' -ForegroundColor Green }
    }
    if (Test-Path -LiteralPath (Join-Path $install 'resources\app.asar')) {
        Write-Warning 'resources\app.asar still present -- Electron loads it instead of resources\app'
    }
}

# ---------------------------------------------------------------- relaunch
if (-not $NoKill) {
    foreach ($v in @('ELECTRON_RUN_AS_NODE', 'DSH_SURFACE', 'DSH_BASE', 'DSH_HOME')) {
        Remove-Item -Path ("Env:\" + $v) -ErrorAction SilentlyContinue
    }
    Start-Process -FilePath $exe -WorkingDirectory $install | Out-Null
    Write-Host 'harness started' -ForegroundColor Cyan
}

Write-Host ''
Write-Host 'DONE.' -ForegroundColor Green
if ($touched) { Write-Host ("Rollback: copy {0}\* back over {1}" -f $backup, $DshHome) -ForegroundColor DarkGray }
Write-Host 'Check inside the host:  /purge status' -ForegroundColor DarkGray
