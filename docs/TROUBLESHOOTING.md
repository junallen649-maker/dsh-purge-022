# 排障手册 / Troubleshooting

## 安装器找不到 harness

```
DeepSeek Harness not found. Start it once, or pass -HarnessDir 'E:\harness'.
```

先跑 `install.cmd -Probe` 看它扫了哪些位置：

```
      nothing found. checked:
        - running processes
        - C:\Users\<u>\AppData\Local\Programs\DeepSeek Harness
        - C:\Program Files\DeepSeek Harness
        ...
```

三种情况：

1. **装在别的盘**（如 `E:\harness`）→ `install.cmd -HarnessDir "E:\harness"`
2. **装了但从没启动过** → 先启动一次，让进程探测命中，再跑安装器
3. **其实是 `dsh web`**（npm 全局，没有 exe）→ 用 `install.sh`

## 版本不对

```
This build (0.2.3-rc.1) has not been tested with these patch tables.
```

按 `docs/REFIT-022.md` 的流程做一遍新 build 的锚点；应急可以 `-ForceVersion`，但命中率没保证。

## `bad option: --no-sandbox`

安装器为了跑 CLI 会设 `ELECTRON_RUN_AS_NODE=1`。如果这个变量泄漏给启动进程，
Electron 会当自己是 node，拒绝一切 Chromium 开关。

安装器已在启动前清空它。手动命令行的场景自己清：

```cmd
set ELECTRON_RUN_AS_NODE=
"E:\harness\DeepSeek Harness.exe"
```

## `app.asar` 还在 / 补丁像没生效

Electron 的加载顺序是 `resources\app.asar` 优先于 `resources\app`。两者并存时，
你写进 `app` 目录的补丁**全部不被加载**。

关闭宿主后：

```cmd
ren "E:\harness\resources\app.asar" "app.asar.dsh-purge-bak"
```

回滚：

```cmd
ren "E:\harness\resources\app.asar.dsh-purge-bak" "app.asar"
```

## 面板「应用」提示「清洗没有写进全部宿主，已取消重启」

面板遇到任何一条 patch 报错就判定失败并**放弃重启**，保持旧状态。
这是它保守的设计，不是补丁没打上。

用 CLI 路径（安装器就是这么做的），它逐条打、逐条报：

```powershell
$env:ELECTRON_RUN_AS_NODE='1'; $env:DSH_SURFACE='desktop'
$env:DSH_HOME="$env:USERPROFILE\.dsh"
$env:DSH_BASE='E:\harness\resources\app\dsh\node_modules\@deepseek-ai'
& 'E:\harness\DeepSeek Harness.exe' --expose-internals "$env:USERPROFILE\.dsh\plugins\dsh-purge\bin\dsh-purge.js" --apply
```

## 红队模式「加载失败」

报错形如：

```
agent-preset/invalid: tool-subagent-list-agents
(@deepseek-ai/dsh-tool-subagent-control/list-agents): never started
```

0.2.2 把 `list-agents` 子入口合并进主包，`dsh-workflow-worker-thread` 整包删除，
预设里还挂着它们就会整棵树校验失败。

安装器在 `[8/8]` 已自动删。手动修：

```powershell
$f="$env:USERPROFILE\.dsh\.agent-presets\redteam\agent.cordis.yml"
Copy-Item $f "$f.bak" -Force
$lines = [IO.File]::ReadAllLines($f)
# 用任意编辑器删掉这两个块（到下一个同级 "- id:" 为止）：
#   - id: tool-subagent-list-agents   name: '@deepseek-ai/dsh-tool-subagent-control/list-agents'
#   - id: workflow-worker-thread      name: '@deepseek-ai/dsh-workflow-worker-thread'
```

删完重启宿主。

## 会话开不起来，但补丁都 applied

看是不是 preset 层面的问题：先把默认预设切回 `standard` 验证宿主本身没事。

```powershell
$f="$env:USERPROFILE\.dsh\profiles\desktop\cordis.patch.yml"
$t=[IO.File]::ReadAllText($f)
$t=$t -replace 'selectedDefault:\s*redteam','selectedDefault: standard'
[IO.File]::WriteAllText($f,$t,(New-Object Text.UTF8Encoding($false)))
```

能开 → 问题在 redteam 预设，按上一条修。

## 想彻底回滚

```powershell
# 1) 用户目录
Copy-Item "C:\Users\<u>\.dsh.bak-<时间戳>\*" "C:\Users\<u>\.dsh\" -Recurse -Force
# 2) 代码层（每个被改文件都有备份）
Get-ChildItem "E:\harness\resources\app\dsh\node_modules\@deepseek-ai" -Recurse -Filter *.dshpurge.bak |
  ForEach-Object { Copy-Item $_.FullName ($_.FullName -replace '\.dshpurge\.bak$','') -Force }
```

## 收集诊断信息（提 issue 用）

```powershell
$env:ELECTRON_RUN_AS_NODE='1'; $env:DSH_SURFACE='desktop'
$env:DSH_HOME="$env:USERPROFILE\.dsh"
$env:DSH_BASE='<你的>\resources\app\dsh\node_modules\@deepseek-ai'
& '<你的>\DeepSeek Harness.exe' --expose-internals "$env:USERPROFILE\.dsh\plugins\dsh-purge\bin\dsh-purge.js" --status
```

把输出里的 `补丁 X/86 已清洗, Y 待清洗, Z 漂移` 那行、`宿主版本` 那行、以及日志
`%USERPROFILE%\.dsh\dsh-purge\install-*.log` 一起贴上。
