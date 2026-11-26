# dsh-purge-022

[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](LICENSE)
[![DeepSeek Harness](https://img.shields.io/badge/DeepSeek%20Harness-0.2.2.x%20%7C%200.2.1-green.svg)](docs/SUPPORT.md)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)](#一键安装)
[![GitHub Stars](https://img.shields.io/github/stars/junallen649-maker/dsh-purge-022?style=social)](https://github.com/junallen649-maker/dsh-purge-022)

**简体中文** | [English](README.md)

DeepSeek Harness **0.2.2.x 适配版** —— 让 `dsh-purge` 在 0.2.2（含 `0.2.2-rc.5`）上继续可用，支持一键安装与红队预设修复。

> 这不是原项目。原项目 **dsh-purge**（作者 **YuJunZhiXue**）已停止更新并从 GitHub 删除。
> 本仓库基于镜像 `mmparko/dsh-purge`（1.1.90），补上 0.2.2 的锚点适配与一键安装。
> 署名与使用条款见 [NOTICE.md](NOTICE.md)，本仓库许可证 [AGPL-3.0](LICENSE)（上游原版 [MIT](LICENSE-MIT)）。

---

## 为什么需要这个东西

dsh-purge 的补丁表是对着**具体 build** 写死的字符串/正则锚点。DeepSeek Harness 从 `0.2.1` 升到 `0.2.2` 后：

- 提权错误类从 `Error` 改成 `SandboxEscalationError(..., "CODE")`
- `editIntent()` 被抽成 `requirePresent(target, actor, "edit")`
- `systemPrompt.assemble()` 的参数从位置参数改成对象
- 官方把 `dsh-tool-subagent-control/list-agents` 子入口合并、`dsh-workflow-worker-thread` 整包删除
- 于是 86 条补丁大面积 `pattern_not_found`，红队预设直接「加载失败」

本仓库把这些重定位做完，并把「装插件 → 解 asar → 应用 → 修预设」串成一次执行。

---

## 支持矩阵

| Harness build | 补丁表 | 状态 |
|---|---|---|
| `0.2.1-rc.2`, `0.2.1-rc.5` | 上游原版 1.1.90 | 已验证（安装器自动选用） |
| `0.2.2.x` | `payload/core-022.js` 重定位表 | 已验证：72/86 已清洗、0 待清洗 |
| 其它 build | — | 安装器拒绝（`-ForceVersion` 可强推，不保证） |
| `0.1.x` | — | 不支持 |

详见 [docs/SUPPORT.md](docs/SUPPORT.md)。

---

## 一键安装

### Windows（官方桌面版）

1. 下载本仓库（`Code → Download ZIP`）并解压
2. **完全退出 harness**（托盘也要退）
3. 双击 `install.cmd`

脚本会依次：定位安装目录 → 读 build 选补丁表 → 备份 → 装插件并挂到 `profiles\desktop`+`profiles\web` → 按需解包 `app.asar` → 应用补丁 → 0.2.2 上修剪预设 → 校验 → 启动。

输出最后三行是关键：

```
      applied=8 already=54 missing_file=18 failed=0
      dsh-purge: 72/86 cleaned
      pending 0
```

`pending 0` = 收口。

### macOS / Linux（`dsh web`）

```bash
chmod +x install.sh
./install.sh            # 默认 profile web
./install.sh --profile desktop
```

### 可选参数

| 参数 | 作用 |
|---|---|
| `-HarnessDir <dir>` | 安装目录不在标准位置时指定（如 `E:\harness`） |
| `-DshHome <dir>` | 换 dsh 用户目录（默认 `%USERPROFILE%\.dsh`） |
| `-SkipApply` | 只铺文件，不打补丁 |
| `-SkipPreset` | 不动 `.agent-presets\redteam` |
| `-NoUnpack` | 不碰 `app.asar` |
| `-NoKill` | 不自动关闭宿主 |
| `-Probe` | 只探测宿主位置后退出 |
| `-ForceVersion` | 未验证的 build 也继续 |

---

## 装完验证

聊天里发：

```
/purge status
```

要看到两行：

```
补丁 72/86 已清洗, 0 待清洗
宿主版本 / host  0.2.2-rc.5
```

然后新建会话选「红队模式」——应当能加载。

---

## 排障（都是实际踩过的）

| 现象 | 原因 | 处理 |
|---|---|---|
| `DeepSeek Harness not found` | 装在非标准路径 | `install.cmd -HarnessDir "E:\harness"`，或先 `-Probe` |
| `bad option: --no-sandbox` | 继承了我们设的 `ELECTRON_RUN_AS_NODE=1` | 已修；若手动跑过 CLI，先 `set ELECTRON_RUN_AS_NODE=` |
| 补丁全部 `pattern_not_found` | 补丁表与 build 不匹配 | 看 `[2/8]` 那行选的哪张表 |
| `resources\app.asar` 还在 | Electron 优先加载 asar，`app` 目录里的补丁失效 | 关闭宿主后 `ren app.asar app.asar.dsh-purge-bak` |
| 红队模式「加载失败」 + `tool-subagent-list-agents ... never started` | 0.2.2 删了该子入口 | 安装器已自动修剪；手动用 `docs/TROUBLESHOOTING.md` 里的脚本 |
| 面板「应用」提示「清洗没有写进全部宿主，已取消重启」 | 面板遇错会放弃并保持旧状态 | 用安装器的 CLI 路径，它逐条打、照实报告 |

更多见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

---

## 回滚

安装器每次运行都会把将被覆盖的路径备份到 `%USERPROFILE%\.dsh.bak-<时间戳>\`：

```powershell
copy "C:\Users\<你>\.dsh.bak-20261125-160000\*" "C:\Users\<你>\.dsh\" -Recurse -Force
# 再还原代码层（每个被改文件都有 .dshpurge.bak）
```

预设单独回滚：`agent.cordis.yml.bak-<时间戳>` 覆盖回去。

---

## 目录结构

```
install.cmd / install.ps1     Windows 一键（版本分支 + asar + apply + 预设）
install.sh                    macOS/Linux 一键（dsh web）
payload/
  plugin/                     dsh-purge 1.1.90 完整副本（上游原样）
  core-022.js                 0.2.2 重定位补丁表
  profiles/{desktop,web}/     profile 清单与挂载点
  preset/redteam/             红队预设模板（备用恢复）
docs/
  SUPPORT.md                  版本矩阵
  REFIT-022.md                8 条重定位记录（改了哪个锚点）
  TROUBLESHOOTING.md          排障手册
```

---

## 它到底改了什么

补丁只落在 `resources\app\dsh\node_modules\@deepseek-ai\**` 下的官方文件，每个被改文件先备份为 `<file>.dshpurge.bak`；以及 `%USERPROFILE%\.dsh\` 下的插件、profile、预设。不改系统目录、不装驱动、不开端口。

---

## 署名与开源协议

本仓库采用 **GNU AGPL-3.0** 协议（见 [LICENSE](LICENSE)）：任何基于本仓库的修改、衍生开发或提供网络服务的部署，均须同样以 AGPL-3.0 开源。
上游 **dsh-purge** by **YuJunZhiXue** 采用 [MIT](LICENSE-MIT) 协议，详见 [NOTICE.md](NOTICE.md)。
借用名称、思路、代码或提示词必须署名并注明来源；**禁止倒卖与收费分发**。

## 合规

仅用于**已获授权**的安全测试、CTF、教学与自有环境研究。使用者自行承担合规责任。
