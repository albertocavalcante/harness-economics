# 02 — Prompt caching

**Research date:** 2026-09-10. **Scope:** the caching mechanism both harnesses sit on, how each one
engineers its prefix around it, what invalidates a cache in each, and how to observe hit rate.

This is the track that drives most of the cost difference in track 06. Everything here reduces to one
invariant, stated once and then applied repeatedly.

---

## 0. TL;DR

1. **Prompt caching is a prefix match on exact bytes.** A change at position *N* invalidates everything
   at position ≥ *N*. There is no per-file, per-segment, or semantic caching.
2. Cache reads cost roughly **10% of input rate** on both vendors' pricing. Cache *writes* cost more
   than uncached input — 1.25× at 5-minute TTL, 2× at 1-hour.
3. Break-even is **one reuse** at 5m TTL, **two** at 1h. The longer TTL is not free.
4. Claude Code publishes an exhaustive invalidation catalogue and gives you TTL controls. Copilot
   publishes neither and gives you none.
5. Copilot has one lever Claude Code structurally cannot match: OpenAI's **24-hour** cache retention.
6. Claude Code's cache is scoped **per machine and per directory** — narrower than most users assume.

---

## 1. The mechanism

The API caches by matching the **start** of each request — the prefix — against content it recently
processed. Per
[Anthropic's prompt caching docs, fetched 2026-09-10](https://platform.claude.com/docs/en/build-with-claude/prompt-caching),
the match is exact, and render order is `tools` → `system` → `messages`.

Claude Code's own documentation states the consequence bluntly: "The match is exact, so a change
anywhere in the prefix recomputes everything after it. There is no per-file or per-segment caching."
([Claude Code prompt caching, fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching))

This single property explains essentially every design decision in both harnesses.

### 1.1 Pricing

| Token class | Anthropic API rate | Copilot AI-credit rate |
|---|---|---|
| Cache read | ~0.1× input | 10% of input rate |
| Cache write, 5m TTL | 1.25× input | +25% on input (Anthropic + GPT-5.6/6 models) |
| Cache write, 1h TTL | 2.0× input | not exposed as a separate lever |
| Uncached input | 1.0× | 1.0× |

Copilot rates from
[Models and pricing for GitHub Copilot, fetched 2026-09-10](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing);
older OpenAI models there carry **no cache write cost** at all.

**Break-even.** At 5m TTL, two requests over the same prefix cost `1.25 + 0.1 = 1.35×` versus `2×`
uncached — ahead after a single reuse. At 1h TTL the write is `2×`, so `2.0 + 0.2 = 2.2×` versus `3×`
— you need two reads. A 1-hour TTL on short bursts that never idle past five minutes is a straight
loss: you pay the higher write rate and never use the longer lifetime.

### 1.2 Minimum cacheable prefix — and it is not monotonic

Below the model's minimum, a `cache_control` marker silently does nothing. No error;
`cache_creation_input_tokens` simply comes back `0`.

| Model | Minimum |
|---|---|
| Claude Opus 5, Fable 5, Mythos 5 | 512 tokens |
| Opus 4.8, Sonnet 5, Sonnet 4.6, Sonnet 4.5, Opus 4.1 | 1024 tokens |
| Opus 4.7, Mythos Preview, Haiku 3.5 | 2048 tokens |
| Opus 4.6, Opus 4.5, Haiku 4.5 | 4096 tokens |

Source: [Anthropic prompt caching, fetched 2026-09-10](https://platform.claude.com/docs/en/build-with-claude/prompt-caching).
Note the shape: **newer is not always lower**. A 3k-token prefix caches on Opus 5 and silently does not
on Haiku 4.5. Anyone routing a cheap sub-task to Haiku to save money may be paying full input rate on
every turn without any signal that it is happening.

## 2. Breakpoints

**Anthropic — explicit, budget of 4.** The caller places `cache_control` markers. Claude Code places
them for you; Copilot places them on its Anthropic path at end-of-tools, end-of-system, and two rolling
anchors on recent messages
([VS Code, fetched 2026-09-10](https://code.visualstudio.com/blogs/2026/06/17/improving-token-efficiency-in-github-copilot)).

**OpenAI — automatic.** No breakpoints; the provider infers the reusable prefix. The caller controls
only prefix stability.

**The lookback window.** Each breakpoint walks backward a bounded number of content blocks to find a
prior entry. A turn that emits many tool-call blocks can push the previous entry outside that window,
producing a silent miss on an otherwise-unchanged prefix. Copilot's two rolling anchors are a direct
mitigation. This is the least-known cache failure mode in agentic loops, and it gets worse the more
parallel tool calls a turn makes.

## 3. TTL

Cached prefixes expire after **inactivity**, and every cache hit resets the timer — so an actively-used
session stays warm indefinitely. The cost lands on the first turn back after a break.

| | Claude Code | Copilot |
|---|---|---|
| Default TTL | 1h on a Claude subscription within plan usage; **5m** on API key, cloud provider, or once on usage credits | Provider default (OpenAI 5–10 min) |
| User control | `promptCacheTtl` / `subagentPromptCacheTtl` (`5m` or `1h`), env vars, `FORCE_PROMPT_CACHING_5M` | **None** |
| Longest available | 1 hour | **24 hours** on OpenAI models |

### 3.1 Claude Code's two buckets

Claude Code splits every request into one of two TTL buckets:

- **Main conversation** — interactive turns, `-p` runs, Agent SDK turns, and inline helpers.
- **Everything else** — subagents, workflows, teammates, forks, compaction, session titles.

Precedence, first match wins
([Claude Code prompt caching, fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)):

```
1. FORCE_PROMPT_CACHING_5M=1                      # both buckets, debugging override
2. CLAUDE_CODE_{,SUBAGENT_}PROMPT_CACHE_TTL       # env, per bucket
3. promptCacheTtl / subagentPromptCacheTtl        # settings.json, per bucket
4. subagent frontmatter experimental.cacheTtl
5. ENABLE_PROMPT_CACHING_1H=1                     # both buckets
6. bucket default
```

The asymmetry matters: **subagents get 5 minutes even on a subscription** unless you set the second
bucket explicitly. A fan-out of subagents that idles briefly is re-reading cold.

**Version floor, verified.** These settings require Claude Code **v2.1.242+**. We confirmed they are
genuinely absent from the v2.1.220 binary — the setting is not merely undocumented there, it does not
exist. Anyone reading a blog post that says "just set `promptCacheTtl`" on an older build will find
nothing happens. See [`../GAPS.md`](../GAPS.md) §2.

### 3.2 Copilot's 24-hour retention

Copilot enables `prompt_cache_retention: "24h"` on OpenAI models, which moves cache state from GPU
memory to GPU-local storage. Measured cache-hit-rate improvement after 40–60 minutes of inactivity, per
[VS Code, fetched 2026-09-10](https://code.visualstudio.com/blogs/2026/06/17/improving-token-efficiency-in-github-copilot):

| Model | Hit-rate improvement |
|---|---|
| GPT-5.4 | +919% |
| GPT-5.2 | +338% |
| GPT-5.3-Codex | +279% |

This is the single largest cache lever either product has shipped, and it is **structurally
unavailable** to Claude Code — Anthropic's maximum TTL is one hour. For a workflow with long idle gaps
(overnight runs, a session resumed after lunch), Copilot on an OpenAI model has an advantage Claude
Code cannot configure its way to.

### 3.3 Copilot's open 5-minute problem

[microsoft/vscode#321551, fetched 2026-09-10](https://github.com/microsoft/vscode/issues/321551) —
reported 2026-06-16, **open**, in the "Backlog Candidates" milestone — reports that the cache silently
expires during active agent sessions when consecutive model calls are more than ~5 minutes apart:
waiting on a long terminal command, a large file read, or on the user. The reporter measures **3–5× on
the affected turn and 8–15× cumulative** on long sessions, and estimates a 30–60% per-session saving if
fixed with a keepalive ping.

Treat those figures as a **user report, not a vendor measurement** — they are one reporter's estimate
and we have not reproduced them. What is not in question is the mechanism, or that Copilot exposes no
setting that would let a user work around it. Claude Code's answer to precisely this scenario is the
1-hour TTL.

## 4. What invalidates the cache

### 4.1 Claude Code — documented exhaustively

Anthropic publishes a full catalogue. Condensed
([fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)):

| Action | Effect | Notes |
|---|---|---|
| Switching models | Full re-read | Each model has its own cache. Confirms before switching while warm |
| Changing effort level | Full re-read | Exception: Fable 5.1 on API key/subscription keeps cache (v2.1.260+) |
| Enabling fast mode | Full re-read, once per conversation | Header is part of the cache key; billed at fast-mode rates |
| MCP server connect/disconnect | Full re-read **only if** tools load into the prefix | Free when tool search defers them — see track 04 |
| Plugin enable/disable | Depends on components | Skills/commands/agents/hooks append and are free; MCP-providing plugins follow the MCP rule |
| Bare tool deny rule (`Bash`, `*`) | Full re-read | Removes the definition from the prefix. Scoped rules like `Bash(rm *)` do not |
| Output style switch | Free on subscription; full re-read on Bedrock/GCP/Foundry | Depends on whether the style ships as a message or in the system prompt |
| `/compact` | Conversation layer by design | System prompt preserved; project context re-read from disk |
| Image accumulation | Partial re-read | Oldest images evicted in batches when limits are hit |
| Upgrading Claude Code | Full re-read | **Resuming a long session after an upgrade is the most expensive request in the product** |

Cache-**safe** actions worth knowing: editing repo files, editing `CLAUDE.md` mid-session (it also
does not take effect until `/clear` or restart), permission-mode changes, invoking skills and commands,
`/recap`, spawning a subagent, and — the useful one — **`/rewind`**, which truncates back to a prefix
that is already warm. When abandoning a line of work, rewinding is strictly cheaper than compacting.

### 4.2 Copilot — inferred, not published

GitHub does not publish an equivalent catalogue. What can be established from its own posts:

- **Model switching invalidates**, which is why routing is constrained to cache boundaries
  ([track 03 §3](03-context-management.md)).
- **Compaction resets the prefix** — explicitly described as a boundary where re-routing is safe.
- **Deferred tools do not invalidate**, because they are appended rather than placed in the prefix.

Everything else is unknown from outside. This is a genuine asymmetry in what a user can reason about,
independent of which product caches better.

## 5. Prefix engineering as architecture

Anthropic's [engineering post, fetched 2026-09-10](https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything)
documents three decisions made *for* the cache:

- **Plan mode is a tool, not a mode.** Swapping the tool set would rewrite position 0. Instead the
  model is instructed to use read-only tools and calls `ExitPlanMode` itself. The prefix never moves.
- **Deferred tool loading.** Tool stubs stay "in the same order"; full schemas load only when selected.
- **Compaction reuses the parent prefix.** The summarisation call sends the same system prompt, tools,
  and history plus one appended instruction — so a warm `/compact` reads almost everything from cache
  and spends its time generating, not reprocessing.

Copilot's equivalents, from the VS Code post: tool search with client-side embedding-guided selection
over a curated core toolset (**11–18% fewer prompt and total tokens per session** on Anthropic models,
8.6–9.8% on OpenAI), and compaction as a deliberate re-routing boundary.

Reported cache hit rate on Copilot's Anthropic path for dense agentic turn sequences: **~94%**. There is
no published Claude Code equivalent to compare against — Anthropic states it alerts on the metric but
does not publish the number.

## 6. Cache scope

**Claude Code** is effectively scoped to **one machine and one directory**, because the system prompt
embeds working directory, platform, shell, OS version, and memory paths. Worktrees of the same repo do
not share. Sequential sessions in one directory share only if the git status snapshot matches. Parallel
sessions in the same directory do share
([fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)).

The underlying API cache is broader — isolated between organizations, and on some providers between
workspaces, but shared by any two requests with the same model and prefix inside those bounds.

**Copilot's** cache scope is not documented.

### 6.1 The gateway trap

If requests pass through an LLM gateway or a custom `ANTHROPIC_BASE_URL`, three outcomes:

1. Gateway **forwards `cache_control` unchanged** → caches normally.
2. Gateway **rejects with a 400 naming `cache_control`** → Claude Code moves the marker and continues.
3. Gateway **strips the markers and returns 200** → the entire conversation bills as uncached input on
   every turn, **with no error**.

Case 3 is the expensive one precisely because it is silent. A gateway that converts block-form system
content to a plain string drops the marker the same way. If you front either harness with a proxy,
verify `cache_read_input_tokens` is non-zero before trusting the setup.

## 7. Observing it

| Surface | Claude Code | Copilot |
|---|---|---|
| Per-turn counters | `cache_read_input_tokens`, `cache_creation_input_tokens` | via OTel span attributes only |
| In-product view | `/usage` → `Prompt cache (main)`: hit ratio, miss count, warm/cold (v2.1.251+) | none |
| Miss cause attribution | `likely cause: tool definitions changed` (v2.1.260+) | none |
| Live per-turn | statusline `prompt_cache` object | none |
| Programmatic | `claude -p … --output-format json` → `usage.cache_creation.{ephemeral_5m,ephemeral_1h}_input_tokens` | OTLP collector required |

**Field shape, verified 2026-09-10:** `usage.cache_creation` is an object with
`ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens`, and these are **nullable**;
`cache_creation_input_tokens` is derived as their sum and may be absent. Any script parsing this must
handle null rather than assuming a number — ours does, in
[`../measure/lib/emit.sh`](../measure/lib/emit.sh).

This repo's measurements of real hit rate under controlled conditions live in
[`../measurements/`](../measurements/); the protocol is in [`../METHODOLOGY.md`](../METHODOLOGY.md).

## 8. What we could not determine

Recorded in full in [`../GAPS.md`](../GAPS.md); the caching-specific items:

- Anthropic's server-side cache internals — real eviction policy, exact TTL clock, cross-session
  sharing behaviour within an org.
- Copilot's system prompt and tool-definition byte counts. Closed, and its spans carry no content.
- Copilot's full invalidation catalogue.
- Whether the 3–5× / 8–15× figures in vscode#321551 reproduce.

## Sources

- [Anthropic prompt caching, fetched 2026-09-10](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [How Claude Code uses prompt caching, fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)
- [Anthropic: Prompt caching is everything, fetched 2026-09-10](https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything)
- [VS Code: Improving token efficiency in GitHub Copilot, fetched 2026-09-10](https://code.visualstudio.com/blogs/2026/06/17/improving-token-efficiency-in-github-copilot)
- [Models and pricing for GitHub Copilot, fetched 2026-09-10](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
- [microsoft/vscode#321551 — cache expires mid-session, fetched 2026-09-10](https://github.com/microsoft/vscode/issues/321551)
- [GitHub: Getting more from each token, fetched 2026-09-10](https://github.blog/ai-and-ml/github-copilot/getting-more-from-each-token-how-copilot-improves-context-handling-and-model-routing/)

---

← [01 — Request lifecycle](01-request-lifecycle.md) · [Index](../README.md) · [03 — Context management](03-context-management.md) →
