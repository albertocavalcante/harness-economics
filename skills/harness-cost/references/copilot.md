# Copilot — levers, traps, and skill mechanics

> [!CAUTION]
> **Name the surface and the version, or the claim is unfalsifiable.** The VS Code
> extension, the Copilot CLI, and the SDK are separate repositories on separate
> release trains. They gained caching **three months apart**. See
> [`COPILOT-SURFACES.md`](../../../reference/COPILOT-SURFACES.md).

## Settings that move cost

| Setting | Effect | Default |
|---|---|---|
| `github.copilot.chat.agent.longToolCallCachePreservation` | Keep-alive probes during long tool calls. **`execution_subagent` only, 3 probes, every 4 min** | off — VS Code 1.123+ |
| `github.copilot.chat.freezeCustomizationsIndex` | Snapshots the instructions/skills/agents index on turn 1 so it stops mutating the system block | experimental in 1.121; **always-on since 1.123** |
| `chat.cacheBreakHint.enabled` | Warns when a mid-session change breaks the cache | experimental, **off** |
| `chat.byokUtilityModelDefault: None` | Stops BYOK sessions charging Copilot credits for utility calls | **did not exist before 1.128** |
| `search.searchView.keywordSuggestions` | Plain <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd> billed model calls | **on** — turn it off |
| `github.copilot.chat.anthropic.useMessagesApi` | Disables the Messages API path | on |

## Auth mode changes cache behaviour inside one binary

[`copilot-cli#4720`][i4720] (open), same machine, same model, 150 requests:

| Mode, CLI v1.0.82 | Hit rate | Cost |
|---|---|---|
| BYOK | **0%** | **$61.21** |
| BYOK on v1.0.80 | 97.7% | **$28.92** |
| GitHub subscription | works | — |

**Workaround: downgrade to 1.0.80, or use subscription mode.** ~$49 of avoidable
spend in one session.

## Billed work that produces nothing

- **Failed compaction retries unchanged every turn** — no backoff. One report:
  **38 consecutive billed calls, 0 tokens reclaimed** ([#4663][i4663]).
- **`/restart`, `/resume`, `/update` cost ~174 AI credits** with zero prompts
  submitted ([#3886][i3886]).
- **Background compaction consumes a premium request in the CLI but not in the
  extension** ([#2068][i2068], never triaged).

---

# Skills in Copilot

## Discovery paths — verified 2026-09-10

> [!WARNING]
> **`~/.github/skills` does not exist in any harness.** It is absent from the docs
> table and from `DEFAULT_SKILL_SOURCE_FOLDERS` in VS Code's source. The user-level
> path is **`~/.copilot/skills`**. Installing to `~/.github/skills` silently does
> nothing.

| Scope | VS Code | Copilot CLI |
|---|---|---|
| **Project** | `.github/skills/`, `.claude/skills/`, `.agents/skills/` | same three |
| **Personal** | `~/.copilot/skills/`, `~/.claude/skills/`, `~/.agents/skills/` | `~/.copilot/skills/`, `~/.agents/skills/` |

**The surfaces diverge on `~/.claude/skills`.** VS Code still reads it — first-class,
not a deprecated shim. The **CLI deliberately stopped** on 2026-04-24:

> `1.0.36` — *"Custom agents, skills, and commands from `~/.claude/` are no longer
> loaded by the Copilot CLI"*

So a skill installed only to `~/.claude/skills` is visible to Claude Code and to VS
Code, and **invisible to Copilot CLI**. Install to `~/.copilot/skills` for CLI
coverage. Project-level `.claude/skills` is still read by both.

Sources: [VS Code agent-skills docs][d-vsc] · [GitHub Docs: add skills to Copilot CLI][d-cli] ·
[`promptFileLocations.ts`][src-paths]

## Timeline

| Version | Date | What |
|---|---|---|
| VS Code 1.107 | 2025-12-10 | First support — `.claude/skills` only, behind `chat.useClaudeSkills` |
| VS Code 1.108 | 2026-01-08 | "Agent Skills" branding; `.github/skills` added |
| **VS Code 1.109** | **2026-02-04** | **GA, on by default** |
| CLI 0.0.371 | 2025-12-18 | Earliest CLI skills reference |
| CLI 1.0.32 | 2026-04-17 | *"Skills that exceed the token limit are still discoverable and invocable by name"* |
| CLI 1.0.36 | 2026-04-24 | `~/.claude/` no longer loaded |
| VS Code 1.129 | 2026-07-15 | `.prompt.md` → skill migration recommended |

## The catalog budget

VS Code source constants, pinned at commit [`ef24d36`][src-budget]:

```ts
const SKILL_DESCRIPTION_CHAR_BUDGET = 15000;
const TRUNCATED_NAMES_CHAR_BUDGET = 5000;
```

Full `<skill><name><description><file></skill>` blocks are emitted until the running
total would exceed **15,000 characters**; the remainder degrade to a comma-separated
name list capped at **5,000**; past that, `... and N more`.

> [!NOTE]
> These are **source constants at one commit, not a vendor commitment**, and whether
> `copilot-cli` uses the same numbers is **unverified** — the CLI is closed source.
> No vendor documentation states a token or character cap anywhere.
>
> Do not cite "21 skills" as a designed cap. That figure comes from
> [#315350][i315350], which a maintainer called *"a known bug with the skill tool
> implementation."*

## Why this is a cache problem

Skill metadata is rendered into the **system** prompt. A maintainer, on
[#316182][i316182] — the closest thing to a vendor statement on breakpoint placement:

> *"The system-level prompt cache breakpoint sits at the end of the system block, so
> this single-line mutation invalidates the entire system prefix. The model re-pays
> the cost of caching ~9.7k tokens of otherwise-stable instructions on every turn
> that flips the active mode."*

And the mechanism, from [#315408][i315408]:

> *"The system prompt is rebuilt from scratch on every turn and includes
> extension-contributed skills filtered by their `when` clause against the live
> context-key state. When a context key flips mid-conversation … a skill can be
> inserted into the `<skills>` block on a later turn, invalidating the system-level
> prompt-cache breakpoint."*

Fixed by [PR #316191][pr316191] — `freezeCustomizationsIndex` snapshots the index on
turn 1 and communicates drift via a `<customizationsUpdate>` tag on the **latest user
message** instead of mutating the system block. Default-on 2026-05-14, always-on
2026-05-23.

> [!IMPORTANT]
> **"Skill metadata loads once at session start" is only true from VS Code 1.121.0
> (May 2026) onward.** Before that the catalog was **rebuilt every turn**. Do not
> state it as a timeless property, and do not compare cost across that boundary.

## Frontmatter divergence

| Field | Open spec | VS Code | Copilot CLI | Claude Code |
|---|---|---|---|---|
| `name` | required, ≤64 | required | required | **optional** — defaults to dir name |
| `description` | required, ≤1024 | required | required | recommended |
| `allowed-tools` | ✅ experimental | ❌ **rejected with a diagnostic** | ✅ | ✅ |
| `argument-hint` | ✗ | ✅ | ✅ since 1.0.64 | ✅ |
| `disable-model-invocation` | ✗ | ✅ | ✅ since 0.0.412 | ✅ |
| `user-invocable` | ✗ | ✅ | — | ✅ |
| `context: fork` | ✗ | ✅ experimental | — | ✅ |
| `license` / `compatibility` / `metadata` | ✅ | accepted, **not acted on** | — | accepted, **not acted on** |
| `paths`, `hooks`, `model`, `effort`, `shell`, `agent`, … | ✗ | ✗ | ✗ | ✅ (14+ fields) |

Two things worth internalising:

1. **`allowed-tools` divergence runs the unexpected way.** It is in the open spec,
   in Claude Code, and in Copilot CLI — but **VS Code refuses it**, and has since
   1.107: *"Note that the `allowed-tools` attribute is not supported in VS Code."*
   **The two Copilot surfaces disagree with each other.**
2. **Unknown fields are not silently ignored.** VS Code emits an editor diagnostic.
   The CLI warns (since 0.0.403). Silent-skip was a bug that got fixed.

VS Code's accepted set is a strict **subset** of Claude Code's — it has no fields
Claude Code lacks.

## Related but different formats

- **`.chatmode.md` is gone** — renamed to `*.agent.md`.
- **`.prompt.md` is being deprecated in favour of skills.** VS Code 1.129:
  *"For compatibility across harnesses, we recommend to migrate all prompt files to
  skills."*
- **`.instructions.md`** uses entirely different directories (`.github/instructions`,
  `.claude/rules`, `~/.copilot/instructions`) and shares no fields with `SKILL.md`.
  It is **always applied** or glob-gated via `applyTo` — so unlike a skill, it is
  not on-demand and its cost is unconditional.

[i4720]: https://github.com/github/copilot-cli/issues/4720
[i4663]: https://github.com/github/copilot-cli/issues/4663
[i3886]: https://github.com/github/copilot-cli/issues/3886
[i2068]: https://github.com/github/copilot-cli/issues/2068
[i315350]: https://github.com/microsoft/vscode/issues/315350
[i316182]: https://github.com/microsoft/vscode/issues/316182
[i315408]: https://github.com/microsoft/vscode/issues/315408
[pr316191]: https://github.com/microsoft/vscode/pull/316191
[d-vsc]: https://code.visualstudio.com/docs/agent-customization/agent-skills
[d-cli]: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills
[src-paths]: https://github.com/microsoft/vscode/blob/ef24d362f34ea1a80860e5d9720cb30a1b0c217c/src/vs/workbench/contrib/chat/common/promptSyntax/config/promptFileLocations.ts
[src-budget]: https://github.com/microsoft/vscode/blob/ef24d362f34ea1a80860e5d9720cb30a1b0c217c/src/vs/workbench/contrib/chat/common/promptSyntax/computeAutomaticInstructions.ts#L471-L472
