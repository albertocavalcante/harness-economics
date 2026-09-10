---
name: harness-cost
description: >-
  Reduce token and dollar cost in agentic coding sessions across Claude Code and
  GitHub Copilot. Use when a session costs far more than expected, when cache hit
  rate is low or cache-read tokens read zero, when deciding where MCP servers,
  tools, or skills should live so the cached prefix stays stable, when auditing
  whether a cost meter can be trusted, or when the same workload costs different
  amounts run to run. Covers prompt-cache prefix stability, TTL expiry, deferred
  tool loading, and known meter defects per harness. For Claude Code auto-memory,
  MEMORY.md, and CLAUDE.md hygiene use claude-code-optimize instead. For authoring
  a SKILL.md against the open standard use agentskills-spec.
license: CC0-1.0
metadata:
  author: albertocavalcante
  source: https://github.com/albertocavalcante/harness-economics
  tags: cost, tokens, prompt-cache, claude-code, copilot, otel, billing
---

# Harness cost — where the money actually goes

Every rule here is backed by a dated, linked artifact in this repository. Claims
without receipts have been deliberately left out.

## The model in one paragraph

An agent turn re-sends the entire conversation. You are not billed for what you
typed; you are billed for **how much of the re-sent prefix the vendor could serve
from cache**. A cache read costs ~0.1× input. A cache write costs 1.25× (5-minute
TTL) or 2.0× (1-hour TTL). So the only question that matters is: **did the prefix
match, byte for byte, from the start of the request to the cache breakpoint?**

Cost is therefore a property of **byte stability**, not of prompt length. A short
prompt with an unstable prefix costs more than a long prompt with a stable one.

## Rule 1 — nothing mutating may sit ahead of a breakpoint

Render order is `tools` → `system` → `messages`. Anything that changes between
turns invalidates everything after it.

**Disqualifying content, in priority order:** timestamps and dates · session or
request UUIDs · a directory tree · "files changed since last turn" · git status ·
token or credit counters · anything derived from wall-clock time.

Receipts — each of these shipped as a real defect:

| What moved | Cost |
|---|---|
| A rotating debug-log UUID inside the system block | **~95% of all cache-creation tokens** ([#323668][i323668]) |
| A workspace tree at byte ~800 of a 669 KB body | `mkdir` at depth ≤2 cold-rewrote a **270K-token** prefix ([#323641][i323641]) |
| The date, in Claude Code's system prompt | fixed in v2.1.42 — *"improved prompt cache hit rates by moving date out of system prompt"* |

> Corollary: **your build can invalidate your cache.** A tool call that writes
> `artifacts/` at the repo root changes the tree that was serialized ahead of the
> prefix. This is structural, not TTL — in `#323641`, **94% of full rewrites
> happened within five minutes of the prior turn.**

## Rule 2 — do not change the request shape mid-session

From [PR #323594][pr323594], verbatim:

> *"The prompt cache is keyed on the request prefix, so changing the model,
> reasoning effort, context size, mode, or enabled tool set between turns of the
> same session invalidates the cache the previous turn warmed up."*

So: pick the model **before** the expensive turns, not during. Enable the tools you
need at the start. Do not flip modes casually — switching a Copilot session to
autopilot mid-conversation measured `cached_tokens` **359,296 → 3,328** ([#334432][i334432]).

If you must switch, **start a new session instead of continuing** — you pay full
input plus a full cache write either way, and a new session at least gets a clean
prefix.

## Rule 3 — the five-minute cliff is a wall-clock race

The default TTL is 5 minutes from the **last** request. Any gap longer than that —
a build, a test suite, a question you didn't answer — converts the whole prefix
from 0.1× to 1.0×, **plus** a 1.25× write.

Measured decay, the best public numbers either vendor has ([#3808][i3808], posted by
a Microsoft engineer):

| Idle gap | Requests that missed |
|---|---|
| 240 s | 3.5% |
| 300 s | 32% |
| 330 s | **100%** |

**What to do:** batch tool calls into one turn rather than trickling them. Answer
prompts promptly or expect to pay. Do not walk away mid-session. If a long build is
unavoidable, accept the miss and plan the next turn to be worth it.

**What not to rely on:** Copilot's `longToolCallCachePreservation` keep-alive is
scoped to `execution_subagent` calls only, **3 probes maximum, every 4 minutes**. It
does not cover a long build in your main loop.

## Rule 4 — always-loaded catalogs are the largest fixed cost

Tools, MCP schemas, and **skill metadata** are rendered into the system prefix at
session start and paid for on every turn whether or not you use them.

- Copilot CLI 1.0.80+ regressed MCP deferral: first-request tokens went
  **49,084 → 403,209**, and *"a fresh session with a simple 'hi' greeting costs more
  than 200 AIC"* ([#4613][i4613]).
- Tool deferral is **server-gated per model** and only enabled for Claude, so `"hi"`
  costs **21.6k** tokens on sonnet-4.6, **47.6k** on gpt-5.4, **61.9k** on grok-4.6
  ([#4588][i4588]). The client cannot influence this.

**Actions:** audit installed MCP servers and remove unused ones — this is usually the
single biggest win available. Prefer deferred/searchable tool loading where the
harness offers it. Keep skill descriptions short (see below).

## Rule 5 — skills are prefix objects, so write them accordingly

Every installed skill's `name` and `description` load into the system prompt at
session start. The body loads only on activation. From [#328870][i328870] (open, no
maintainer response):

> *"Every installed skill's `name` + `description` is injected into the model prompt
> on **every** turn, regardless of whether any skill could apply."*

Two enforced numbers worth knowing — they differ by an order of magnitude:

| Harness | Limit | Behaviour past it |
|---|---|---|
| **Claude Code** | **1,536 chars** — `description` + `when_to_use` combined | truncated in the listing |
| **VS Code** | **15,000 chars** — whole skill catalog | degrades to a bare name list, then `... and N more` |

So: keep descriptions tight, keep the body under ~500 lines, and push encyclopedic
detail into `references/` that loads on demand. **A skill that is never invoked should
cost roughly 100 tokens, not 1,000.**

> A `when`-gated skill becoming visible mid-conversation is a documented
> cache-invalidation bug ([#315408][i315408]). Prefer unconditional skills.

Per-harness install paths and frontmatter divergence: [`references/copilot.md`](references/copilot.md).

## Rule 6 — verify the meter before trusting a number

**The most expensive mistake is optimising against an instrument that is wrong.**
Before publishing or acting on any cost figure, confirm the meter is sound for your
harness, version, and auth mode. Full catalogue in
[`references/measuring.md`](references/measuring.md); the two traps that bite hardest:

- **`input_tokens` means opposite things.** Copilot's **includes** cached tokens;
  Anthropic's **excludes** them. `input + cache_read` is correct arithmetic for one
  vendor and double-counting for the other.
- **Zero is not evidence of zero.** Several Copilot paths hardcoded or never read
  cache fields, so a broken meter reads as perfect frugality.

## Diagnosing a spike

Work in this order — it is cheapest-first, and each step rules out a whole class.

1. **Did the meter change?** Compare harness versions between the two runs. Never
   compare Copilot cost across VS Code versions; the meter changed at 1.120, 1.121,
   1.125, 1.128, 1.129, 1.131, 1.135, and 1.137.
2. **Was there an idle gap > 5 min?** Check turn timestamps. This explains most
   10× spikes.
3. **Did the shape change?** Model, effort, mode, tool set, MCP server added.
4. **Did bytes move that you didn't move?** Diff two consecutive raw request bodies.
   This is the only way to catch Rule 1 violations, and it is definitive.
5. **Is compaction firing?** It is a paid, non-deterministic event that can loop.

## Instruments

| Harness | Tool |
|---|---|
| Claude Code | `OTEL_LOG_RAW_API_BODIES` for raw bodies; `claude_code.token.usage{type=cacheRead\|cacheCreation}` |
| Copilot | **Cache Explorer** in the chat debug panel — diffs the current request against the previous one |

Every bug in Rule 1 is ultimately "bytes moved that shouldn't have." Both instruments
show you which bytes. Use one, or measure nothing.

## Anti-patterns

- **Optimising prompt length.** Length is not the cost driver; prefix stability is.
  A maintainer, on what dominates: *"The real killer tends to be output tokens."*
- **Trusting a debug log as a billing oracle.** Copilot's `main.jsonl` logs cache
  *reads* but not cache *writes*, so cost models built on it **structurally
  underestimate** ([#329657][i329657]).
- **Comparing raw token counts across vendors.** Different tokenizers. The only
  defensible units are cost per verified-completed task and within-harness cache-read
  ratio.
- **Assuming a fix shipped because an issue is closed.** Several were closed by bot,
  by "offline discussion", or by declaring the billing model obsolete.

## References

- [`references/claude-code.md`](references/claude-code.md) — Claude Code levers and settings
- [`references/copilot.md`](references/copilot.md) — Copilot by surface; skills paths; frontmatter divergence
- [`references/measuring.md`](references/measuring.md) — which meter fields lie, and when
- Full analysis: [`../../README.md`](../../README.md) · [track 02][t02] · [track 04][t04] · [known issues][ki]

[t02]: ../../docs/02-prompt-caching.md
[t04]: ../../docs/04-tool-and-mcp-loading.md
[ki]: ../../reference/KNOWN-ISSUES.md
[i323668]: https://github.com/microsoft/vscode/issues/323668
[i323641]: https://github.com/microsoft/vscode/issues/323641
[i334432]: https://github.com/microsoft/vscode/issues/334432
[i328870]: https://github.com/microsoft/vscode/issues/328870
[i315408]: https://github.com/microsoft/vscode/issues/315408
[i329657]: https://github.com/microsoft/vscode/issues/329657
[i4613]: https://github.com/github/copilot-cli/issues/4613
[i4588]: https://github.com/github/copilot-cli/issues/4588
[i3808]: https://github.com/github/copilot-cli/issues/3808
[pr323594]: https://github.com/microsoft/vscode/pull/323594
