# 版本矩阵 / Support matrix

## 已验证

| Harness | 插件 | 补丁表 | 结果 |
|---|---|---|---|
| `0.2.1-rc.2` | 1.1.90 | 上游原版 | 78/86 cleaned, 0 pending |
| `0.2.1-rc.5` | 1.1.90 | 上游原版 | 上游声明支持 |
| `0.2.2-rc.5` | 1.1.90 + `core-022.js` | 重定位 | 72/86 cleaned, 0 pending, 6 漂移 |

## 未验证

| Harness | 说明 |
|---|---|
| `0.2.2-rc.1` ~ `rc.4` | 与 rc.5 同属 0.2.2，锚点大概率一致，未实测 |
| `0.2.3+` | 需重新做一遍 `docs/REFIT-022.md` 的流程 |
| `0.1.x` | 不支持（上游老版本覆盖，本仓库不带） |
| 社区 Electron（DS Bot） | 不维护 |

## 数字怎么读

`/purge status` 输出的四类状态：

| 状态 | 含义 | 要不要管 |
|---|---|---|
| `applied`（✓ 已清洗） | 补丁已写入 | 不用 |
| `already`（- 已是最新） | 文件已处于期望状态（含官方自己改好的） | 不用 |
| `missing_file`（⚠ 文件缺失） | 目标文件在这套布局里不存在（hooks、可选包、desktop-shell 变体） | 多数不用，属 by-design `na` |
| `drifted`（! 漂移） | 原文改了、锚点没对上，引擎**拒绝乱改** | 想修就看 REFIT 文档 |
| `pending`（✗ 待清洗） | 应该打但没打上 | **必须清零** |

判断收口的标准只有一条：**`待清洗 = 0`**。漂移不阻塞使用，它只意味着那几条补丁没生效。

## 0.2.2 上放弃的 5 条

| id | 名称 | 原因 |
|---|---|---|
| 54 | DELIVERABLE_DO_NOT | 文案已不在 `dsh-client-ui-deliverables` |
| 60 | OFFICIAL_RUN_CODE_APPROVAL_NEUTRAL | 工具描述改由 `dsh-sandbox` 生成，`dsh-tools` 里已无对应字符串 |
| 62 | OFFICIAL_TOOL_ASK_FAILOPEN | `dsh-tools` 整目录已无 `kind: "deny"` / `approval === undefined`，审批判定迁走 |
| 56 | REWIND_HIDE_CUT_ONLY | `client.js` 重新打包，`isRewindMarker` 等函数名消失 |
| 77 | REWIND_DROP_SENT_ON_APPEND | 同上，`append()` 结构重写 |

这 5 条要在 0.2.2 上恢复，属于**在新位置重写逻辑**，不是改锚点。欢迎 PR。
