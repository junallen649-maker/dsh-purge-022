# dsh-purge-022

A **DeepSeek Harness 0.2.2.x compatibility build** for the `dsh-purge` patch set.

> Not the original project. `dsh-purge` by **YuJunZhiXue** stopped updating and
> was removed from GitHub. This repo is built on the mirror
> `mmparko/dsh-purge` (1.1.90) and adds the 0.2.2 anchor re-fit plus a one-shot
> installer. Attribution and terms: [NOTICE.md](NOTICE.md). License: [AGPL-3.0](LICENSE) (upstream `dsh-purge` 1.1.90: [MIT](LICENSE-MIT)).

## Why

Every patch in dsh-purge is a literal/regex anchor against one specific harness
build. Going `0.2.1 -> 0.2.2` broke them:

- escalation errors became `SandboxEscalationError(..., "CODE")`
- `editIntent()` was refactored into `requirePresent(target, actor, "edit")`
- `systemPrompt.assemble()` switched to an options object
- `dsh-tool-subagent-control/list-agents` merged away and
  `dsh-workflow-worker-thread` was removed, so the red-team preset failed to load

## Support

| Build | Patch table | Status |
|---|---|---|
| `0.2.1-rc.2`, `0.2.1-rc.5` | upstream 1.1.90 | verified (selected automatically) |
| `0.2.2.x` | `payload/core-022.js` | verified: 72/86 cleaned, 0 pending |
| anything else | — | refused (`-ForceVersion` to override) |

## Install

### Windows (official desktop build)

1. Download this repo as ZIP and extract
2. **Quit the harness completely** (tray too)
3. Double-click `install.cmd`

It locates the install, picks the matching patch table, backs up what it
touches, mounts the plugin into `profiles\desktop` + `profiles\web`, unpacks
`app.asar` when the build is sealed, applies the patches, trims the preset on
0.2.2, verifies, and relaunches.

Success looks like:

```
      applied=8 already=54 missing_file=18 failed=0
      dsh-purge: 72/86 cleaned
      pending 0
```

### macOS / Linux (`dsh web`)

```bash
chmod +x install.sh
./install.sh                 # profile web
./install.sh --profile desktop
```

### Flags

`-HarnessDir <dir>` · `-DshHome <dir>` · `-SkipApply` · `-SkipPreset` ·
`-NoUnpack` · `-NoKill` · `-Probe` · `-ForceVersion`

## Verify

In a chat:

```
/purge status
```

Expect `72/86 已清洗, 0 待清洗` and your build version. Then create a session and
pick the red-team preset — it should load.

## Rollback

`%USERPROFILE%\.dsh.bak-<timestamp>\` holds everything the installer replaced.
Each patched file also keeps a `<file>.dshpurge.bak` original.

## Layout

```
install.cmd / install.ps1   Windows installer
install.sh                  macOS/Linux installer
payload/plugin/             dsh-purge 1.1.90 (upstream, unmodified)
payload/core-022.js         0.2.2 re-fitted patch table
payload/profiles/           profile manifests
payload/preset/             red-team preset template
docs/                       support matrix, re-fit log, troubleshooting
```

## Attribution & License

This repository is licensed under **GNU AGPL-3.0** ([LICENSE](LICENSE)): any modified versions, derivative works, or network-accessible services built on it must also be open-sourced under AGPL-3.0.
Upstream **dsh-purge** by **YuJunZhiXue** is [MIT](LICENSE-MIT). Attribution is required for any reuse of the name, ideas, code or prompts; reselling is prohibited. See [NOTICE.md](NOTICE.md).

## Legal

For **authorized** security testing, CTF, teaching and your own environments
only. You are responsible for staying within the law and your scope.
