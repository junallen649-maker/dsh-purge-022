# 0.2.2 重定位记录 / Re-fit log

`payload/core-022.js` 在 `ALL_PATCHES` 之后追加了一个覆盖层：

```js
const HOST_REFIT_022 = [ { id, replacements: [...] }, ... ];
for (const refit of HOST_REFIT_022) {
  const target = ALL_PATCHES.find((p) => p.id === refit.id);
  if (target) target.replacements = refit.replacements;
}
```

只替换上表中的 id，其余 78 条保持上游定义。安装器在 build `0.2.2.x` 时才拷这份
`core.js`，`0.2.1` 用原版表，互不影响。

## 改了哪 8 条

### #13 ESCALATION_WIDENING_EXEMPT
0.2.1 锚点：`throw new Error(\`sandbox escalation to ... is not strictly wider...\`)`
0.2.2：错误类变 `SandboxEscalationError`，且多一个 code 参数
`"SANDBOX_ESCALATION_INVALID_ARGUMENT"`。三条并列的 `throw` 全改。
→ 正则放宽为 `throw new \w+\(`，吞掉整段，替换成禁用注释。

### #14 ESCALATION_GRANT_UNCONDITIONAL
0.2.1：`displayReason: { en: ..., zh: ... }` 内联对象。
0.2.2：`displayReason: escalationDisplayReason(mode, justification)` 函数调用。
→ 正则改成可选 `displayReason` 行，替换体保留该字段并加
`approver/agent === undefined ? "allowed-once"` 分支。

### #17 FS_OBSERVATION_INTENT_FREE
0.2.1：`writeIntent` / `editIntent` 各自实现版本守卫。
0.2.2：`editIntent(target, actor) { return this.requirePresent(target, actor, "edit"); }`
→ 新锚点直接匹配这一行，改为 `return void 0`。（`writeIntent` 部分 0.2.2 已命中，未动。）

### #18 REPEAT_TOOL_REMINDER_DISABLED
0.2.1：`tools/post-execute` 里有 `kind === "block"` 分支。
0.2.2：该分支删除，直接 `return { ...downstream, additionalContexts }`。
→ 锚点改为新结构，整段（含 `agent/pre-step` 的 chains.delete）替换为失效注释。

### #35 ESCALATION_NEVER_REJECT
0.2.2：`case "cancelled"` 之前多了一行 `approval.signal?.throwIfAborted();`。
→ 正则把这一行设为可选，仍整体替换为 `case "allowed-once": default: return mode;`。

### #40 COMPLETE_PROMPT_KEEP_INJECT
0.2.1：`if (completeSection === void 0 && !runtimeContextSuppressed) return transformed;`
0.2.2：改成 `return { ...transformed, tools };`，且末尾 `return { ...transformed, tools, sections, contexts }`。
→ 重写为：先算 `dshPurgeSections` / `dshPurgeRest`，两处 return 都把 purge 段拼回去，
保证 complete-prompt 模式下注入不被丢掉。

### #67 AGENT_LOOP_MESSAGES_GUARD
0.2.1：`if (turnEnds && decision.messages.length === 0) break;`
0.2.2：逻辑没变，但缩进层级从 4 tab 变成 5 tab（多包了一层 `try`）。
→ 缩进改用 `[\t ]*` 捕获，replace 用 `$1` 回填。

### #74 ASSEMBLE_BEFORE_PRESTEP
0.2.1：`assemble(assembleContextFor(this, signal))`
0.2.2：`assemble({ ...assembleContextFor(this, signal), modelSelection: selection, toolSet })`
→ 锚点改成 `const assembly = await ... .assemble({`，在其前插入
`globalThis.__dshPurgePrepareAssemble` 钩子调用。

## 复现这套流程（换 build 时）

1. 收集源码：用 `collect-targets.ps1` 那种方式，把 `--status` 报出来的目标文件原样打包
2. 铺成伪 `resources\app` 树，`aiBase` 指过去
3. 用 `applyPatches(aiBase, ALL_PATCHES, { preserveClientBundles: false })` 做 dry-run
4. 看 `status`：`drifted` 就是要改的，`missing_file` 先判断是不是布局问题
5. 对照新源码写 pattern，加进 `HOST_REFIT_xxx` 覆盖层
6. 重跑 dry-run，直到 `drifted` 归零或剩下的确认属于「逻辑搬走」
