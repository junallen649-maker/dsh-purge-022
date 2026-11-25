# NOTICE — 来源与署名 / Attribution

**This repository is not the original project.** It is a mirror plus a
compatibility layer, published so that people running DeepSeek Harness
`0.2.2.x` can keep using the patch set.

| 项目 | 内容 |
|---|---|
| 原项目 | **dsh-purge —— DeepSeek Harness 破甲**（让所有模型都能破甲，不同模型可换不同提示词） |
| 原作者 | **YuJunZhiXue** — https://github.com/YuJunZhiXue |
| 原仓库 | https://github.com/YuJunZhiXue/dsh-purge （**已删除 / deleted**） |
| 本文档 `payload/plugin/` 的来源镜像 | https://github.com/mmparko/dsh-purge |
| 镜像版本 | dsh-purge **1.1.90**（镜像记录：上游 `master` 快照 `6c1d638`） |
| 原许可 | MIT（上游原许可保留于 [`LICENSE-MIT`](LICENSE-MIT)） |
| 本仓库许可 | **GNU AGPL-3.0**（见 [`LICENSE`](LICENSE)，基于本仓库的修改、二次开发及网络服务分发均须以 AGPL-3.0 开源） |

名称、思路、代码、提示词的一切权利与署名均归原作者。
本仓库不主张任何原创性，只承担两件事：**存档分发** 与 **0.2.2 兼容适配**。

## 本仓库新增的部分

仅以下内容是新的，其余均为上游原样：

- `payload/core-022.js` —— 针对 DeepSeek Harness `0.2.2` 重新定位锚点的补丁表
  （见 `docs/REFIT-022.md`，覆盖 8 条、其余走 by-design 判定）
- `install.ps1` / `install.cmd` —— 一键安装器（版本分支、asar 解包、应用、预设修剪）
- `docs/**` —— 版本矩阵、适配记录、排障

## 使用条款（沿用上游）

按上游 README〈署名要求〉章节：

- **借用本项目的名称、思路、代码或提示词，必须署名，并写明来源仓库。**
- 任何基于本仓库的二次开发、分发、集成，都必须保留本 `NOTICE.md` 与原仓库链接。
- 上游的非盈利条款同样沿用：**不得用于卖课、卖插件、卖 token、倒卖等收费行为。**

## 法律与合规

本项目仅用于**已获授权的安全测试、CTF、教学与自有环境研究**。使用者须自行确保其行为符合所在地法律法规及目标系统授权范围。作者不对任何滥用行为负责。
