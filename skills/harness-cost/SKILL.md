---
name: harness-cost
description: >-
  Cut token and dollar cost in Claude Code and GitHub Copilot (VS Code, Copilot
  CLI) sessions. Use on a cost spike, a low cache hit rate, cache_read tokens
  reading zero, credit/AIC burn, run-to-run cost variance, a cost meter you
  cannot trust, or when placing MCP servers, tools, and skills so the cached
  prefix stays stable. Covers prefix invalidation, the 5-minute TTL, and
  deferred tool loading. For CLAUDE.md and MEMORY.md hygiene use
  claude-code-optimize; to author a SKILL.md use agentskills-spec.
license: CC0-1.0
metadata:
  author: albertocavalcante
  source: https://github.com/albertocavalcante/harness-economics
  tags: cost, tokens, prompt-cache, claude-code, copilot, otel, billing
---

# Harness cost

## The cost model

Every turn re-sends the whole conversation. You pay **0.1×** for prefix bytes the
vendor serves from cache, and **1.0× plus a write surcharge** for the rest.
Anthropic's write is 1.25× (5-minute TTL) or 2.0× (1-hour); Copilot's is disputed —
see [`references/measuring.md`](references/measuring.md).

Optimise byte stability, not length. Ask one question per spike: **did the prefix
match byte-for-byte up to the breakpoint?**

## Diagnose a spike

Cheapest first — each step rules out a class.

1. **Did the meter change?** Compare harness versions and auth mode between runs.
   Never compare Copilot cost across VS Code 1.120, 1.121, 1.125, 1.128, 1.129,
   1.131, 1.135, 1.137 — the meter changed at each.
2. **Was there an idle gap over 5 minutes?** Check turn timestamps. This explains
   most 10× spikes.
3. **Did the request shape change?** Model, reasoning effort, mode, tool set, MCP
   server added.
4. **Did bytes move that you didn't move?** Diff two consecutive raw request
   bodies. Definitive, and the only way to catch Rule 1.
5. **Is compaction looping?** Look for consecutive compaction turns reclaiming ~0
   tokens ([copilot-cli#4663][i4663] saw 38 in a row with no backoff). Restart the
   session; it will not recover.

## Rule 1 — nothing mutating ahead of a breakpoint

Render order is `tools` → `system` → `messages`. Anything that changes between turns
invalidates everything after it.

**Check the prefix for, in priority order:** timestamps and dates · session or
request UUIDs · a directory tree · "files changed since last turn" · git status ·
token or credit counters · anything derived from wall-clock time.

Receipts:

| What moved | Cost |
|---|---|
| A rotating debug-log UUID inside the system block | **~95% of all cache-creation tokens** ([#323668][i323668]) |
| A workspace tree at byte ~800 of a 669 KB body | `mkdir` at depth ≤2 cold-rewrote a **270K-token** prefix ([#323641][i323641]) |
| The date, in Claude Code's system prompt | fixed in [v2.1.42][cc-changelog] |

**Act:** set `OTEL_LOG_RAW_API_BODIES=file:` to a path outside any repo, diff turn
*N* against *N−1*, and move anything on that list below the last breakpoint — into
the latest user message, never the system block.

> **Your build can invalidate your cache.** Write build outputs to `/tmp` or to a
> directory that already existed at session start; never create a top-level
> directory mid-session. This is structural, not TTL — in `#323641`, **94% of full
> rewrites happened within five minutes of the prior turn.**

## Rule 2 — do not change the request shape mid-session

From [PR #323594][pr323594]:

> *"The prompt cache is keyed on the request prefix, so changing the model,
> reasoning effort, context size, mode, or enabled tool set between turns of the
> same session invalidates the cache the previous turn warmed up."*

Pick the model before the expensive turns. Enable the tools you need at the start.
Switching a Copilot session to autopilot mid-conversation measured `cached_tokens`
**359,296 → 3,328** ([#334432][i334432]).

If you must switch, start a new session rather than continue — you pay full input
plus a full write either way; a new session at least starts clean.

## Rule 3 — the 5-minute cliff is a wall-clock race

The default TTL runs from the **last** request. Measured decay ([#3808][i3808],
posted by a Microsoft engineer):

| Idle gap | Requests that missed |
|---|---|
| 240 s | 3.5% |
| 300 s | 32% |
| 330 s | **100%** |

Batch tool calls into one turn rather than trickling them. Answer inside 4 minutes.
If a long build is unavoidable, accept the miss.

Do not rely on Copilot's `longToolCallCachePreservation` keep-alive: it is scoped to
`execution_subagent` calls, **3 probes maximum, every 4 minutes**. It does not cover
a long build in your main loop.

## Rule 4 — always-loaded catalogs are the largest fixed cost

Assume every installed tool, MCP schema, and skill description bills on **every**
turn. Count them before optimising anything else.

- Copilot CLI 1.0.80+ regressed MCP deferral: first-request tokens went
  **49,084 → 403,209**, and *"a fresh session with a simple 'hi' greeting costs more
  than 200 AIC"* ([#4613][i4613]).
- Deferral is **server-gated per model**, enabled only for Claude: `"hi"` costs
  **21.6k** tokens on sonnet-4.6, **47.6k** on gpt-5.4, **61.9k** on grok-4.6
  ([#4588][i4588]).

**Act:** audit installed MCP servers and remove unused ones — usually the single
biggest win available. On Copilot, prefer a Claude model when tool count is high,
since deferral is switched off for `gpt-*` and `grok-*`; otherwise cut the tool set.

> [!WARNING]
> **CLI 1.0.80 is both a fix and a regression.** It repairs the BYOK cache bug that
> 1.0.82 carries ([#4720][i4720]) *and* ships the MCP-deferral regression above.
> Pick your poison, or run subscription mode on 1.0.82.

## Rule 5 — skills and instructions sit in the cached prefix

Every installed skill's `name` and `description` render into the system prompt and
bill on every turn ([#328870][i328870]). Bodies load on activation.

| Harness | Observed limit |
|---|---|
| Claude Code | **1,536 chars** — `description` + `when_to_use`, truncated in the listing |
| VS Code | **15,000 chars** — whole catalog, then degrades to a name list |

Budget ≤500 chars of `description`, and an uninvoked skill at ~100 tokens. Paths,
frontmatter divergence, and the caveats on those numbers:
[`references/copilot.md`](references/copilot.md).

> A `when`-gated skill becoming visible mid-conversation invalidated the prefix
> ([#315408][i315408]) — **fixed in VS Code 1.123**. On older builds, prefer
> unconditional skills.

## Rule 6 — verify the meter before trusting a number

Three checks before any figure counts: **(1)** harness version identical between
runs; **(2)** auth mode identical; **(3)** `cache_read` non-zero on turn 2 of a warm
session. Any "no" → diff raw bodies instead of reading counters.

Two traps that bite hardest — full catalogue in
[`references/measuring.md`](references/measuring.md):

- **`input_tokens` means opposite things.** Copilot's **includes** cached tokens;
  Anthropic's **excludes** them. `input + cache_read` is correct arithmetic for one
  vendor and double-counting for the other.
- **Zero is not evidence of zero.** Several Copilot paths hardcoded or never read
  cache fields.

## Instruments

| Harness | Tool |
|---|---|
| Claude Code | `OTEL_LOG_RAW_API_BODIES` for raw bodies; `claude_code.token.usage{type=cacheRead\|cacheCreation}` |
| Copilot | **Cache Explorer** in the chat debug panel — diffs the current request against the previous one ([PR #313620][pr313620], VS Code 1.119.0) |

## References

- [`references/claude-code.md`](references/claude-code.md) — Claude Code levers and settings
- [`references/copilot.md`](references/copilot.md) — Copilot by surface; skills paths; frontmatter divergence
- [`references/measuring.md`](references/measuring.md) — which meter fields lie, and when
- Full analysis: [track 02][t02] · [track 04][t04] · [known issues][ki]

[t02]: ../../docs/02-prompt-caching.md
[t04]: ../../docs/04-tool-and-mcp-loading.md
[ki]: ../../reference/KNOWN-ISSUES.md
[cc-changelog]: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
[i323668]: https://github.com/microsoft/vscode/issues/323668
[i323641]: https://github.com/microsoft/vscode/issues/323641
[i334432]: https://github.com/microsoft/vscode/issues/334432
[i328870]: https://github.com/microsoft/vscode/issues/328870
[i315408]: https://github.com/microsoft/vscode/issues/315408
[i4613]: https://github.com/github/copilot-cli/issues/4613
[i4588]: https://github.com/github/copilot-cli/issues/4588
[i4663]: https://github.com/github/copilot-cli/issues/4663
[i4720]: https://github.com/github/copilot-cli/issues/4720
[i3808]: https://github.com/github/copilot-cli/issues/3808
[pr323594]: https://github.com/microsoft/vscode/pull/323594
[pr313620]: https://github.com/microsoft/vscode/pull/313620
