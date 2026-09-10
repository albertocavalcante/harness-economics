# Known issues

Cache-, cost-, and accounting-affecting defects in both harnesses. Organised by **what kind of lie each
one tells**, because the question a reader arrives with is "why did my bill spike?" or "can I trust
this number?" — not "what's open?"

**All states verified via the GitHub API on 2026-09-10.** Issue state rots faster than anything else in
this repo; re-check before relying on any row.

> [!CAUTION]
> **The most important finding here is not any single bug.** It is that Copilot's cost meter has been
> wrong **in both directions, at the same time, in different surfaces** — and that the biggest cost
> variable in an agent session, whether the prefix cache survived, is invisible in the transcript.

## Provenance — where the bugs actually live

[`microsoft/vscode-copilot-release`](https://github.com/microsoft/vscode-copilot-release) is
**archived** (`"archived": true`, last push 2025-12-12). **267 issues are frozen permanently in `open`
state** and can never be closed or commented on again. Nearly every billing report there was closed by
`vs-code-engineering[bot]` with `state_reason: not_planned`, redirected to a meta issue, with **zero
human triage**.

The substantive corpus is `microsoft/vscode`. Everything below is from there unless marked.

---

## Tier 1 — the meter reports the wrong number

These make your instrument wrong. A measurement built on them is invalid, not merely noisy.

| # | What it does | State |
|---|---|---|
| [#331438](https://github.com/microsoft/vscode/pull/331438) | Subagent credits **double-counted** in turn telemetry — *"summing `billedNanoAiu` across events double-counted nested usage"* | ✅ fixed **1.135.0** |
| [#323424](https://github.com/microsoft/vscode/issues/323424) | The session hover was **missing** subagent credits — total *"off by exactly the number of credits the subagent consumed"* | ✅ fixed **1.131.0** |
| [#309207](https://github.com/microsoft/vscode/issues/309207) → [#291100](https://github.com/microsoft/vscode/issues/291100) | `ExtensionContributedChatEndpoint` **hardcoded** `usage` to `{prompt_tokens: 0, cached_tokens: 0}` for every non-Copilot provider | ✅ fixed **1.120.0** |
| [#308370](https://github.com/microsoft/vscode/issues/308370) | OpenAI/CustomOAI BYOK never reads `prompt_tokens_details.cached_tokens`. Maintainer's own eval: **282 instances, all 0% cached** | 🔴 **open**, `Backlog` |
| [#329657](https://github.com/microsoft/vscode/issues/329657) | Debug-log `main.jsonl` logs `cachedTokens` (read) but **not** `cacheCreationTokens` (write) | 🔴 **open**, zero response |
| [#317837](https://github.com/microsoft/vscode/issues/317837) | OTLP **metrics** omit cached input tokens; only **traces** carry them | 🔴 **open**, blocked on OTel spec |
| [#298900](https://github.com/microsoft/vscode/issues/298900) | CAPI under-reports `max_prompt_tokens` — your context-utilisation **denominator** is wrong | 🔴 **open**, `On Deck` |

> [!WARNING]
> **The same spend was simultaneously over- and under-reported.** `#331438` inflated turn telemetry with
> double-counted subagent cost until **1.135.0**; `#323424` under-reported the same cost in the session
> hover until **1.131.0**. **Never cross-compare a pre-1.131 hover figure with post-1.135 telemetry** —
> they were wrong in opposite directions.

Three consequences worth internalising:

- **Any BYOK cost measurement before 1.120.0 reads exactly zero** and looks like a spectacular frugality
  result. It is a hardcoded literal, not an estimate.
- **If you measure cache-hit rate on an OpenAI-compatible BYOK path you will conclude caching is broken
  when it may be working perfectly** (`#308370`). This is the trap most likely to produce a confidently
  wrong blog post.
- **Any cost model built from Copilot's own debug logs structurally underestimates spend** (`#329657`),
  and does so worst on exactly the cache-thrashing sessions you most want to measure.

Also still open by design: [#322822](https://github.com/microsoft/vscode/pull/322822) /
[#323187](https://github.com/microsoft/vscode/issues/323187) — **cancelled-turn credits are knowingly
undercounted.** Maintainer, verbatim: *"there are still unflushed credits from the proxy that we aren't
including here."* If your harness cancels on timeout, your cost floor is fiction.

## Tier 2 — real cost, wrong payer

Your BYOK control arm was contaminated for roughly four months.

| # | Leak path | Fixed |
|---|---|---|
| [#319650](https://github.com/microsoft/vscode/issues/319650) | `runSubagentTool.ts` pattern-matched the name `Explore` and routed to a **CAPI Claude-Haiku** model — one reporter saw 66.7 credits on a "0×" BYOK turn | 1.125.0 |
| [#320171](https://github.com/microsoft/vscode/issues/320171) | Built-in agents ship a hardcoded `model:`; user `.agent.md` edits **silently reverted on restart** | 1.125.0 |
| [#324268](https://github.com/microsoft/vscode/issues/324268) | `chat.utilityModel` **defaulted to Copilot models** in BYOK sessions | 1.129.0 — `chat.byokUtilityModelDefault: None` |
| [#330582](https://github.com/microsoft/vscode/issues/330582) | Agent-host subagent spawn fell back to `claude-sonnet-5`, ignoring the BYOK session model | 1.135.0 |

> [!IMPORTANT]
> **If you ran a BYOK-versus-Copilot cost comparison between roughly 2026-04 and 2026-08, the BYOK arm
> was leaking spend onto the Copilot meter.** The setting that stops it, `chat.byokUtilityModelDefault`,
> **did not exist before 1.128**.

**Your idle baseline is also not zero.** [#321346](https://github.com/microsoft/vscode/issues/321346) —
plain <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd> search billed model calls because
`search.searchView.keywordSuggestions` was **on by default**.

## Tier 3 — cost is non-reproducible run to run

You measure the same workload twice and get different numbers for reasons invisible in the transcript.

### 3.1 The three unacknowledged prefix busts

The most valuable finding in this catalogue, because the reporter instrumented a forward proxy and
**proved these are structural, not TTL**: in `#323641`, **94% of the full-prefix rewrites happened
within five minutes of the prior turn.**

| # | Mechanism | Measured impact |
|---|---|---|
| [#323668](https://github.com/microsoft/vscode/issues/323668) | A debug-log **UUID path sits inside the cached system block**, ahead of its lone breakpoint, and rotates **2–9× per conversation** | **29.5% of turns are cold writes — ~95% of all cache-creation tokens.** No setting disables it |
| [#323641](https://github.com/microsoft/vscode/issues/323641) | Workspace directory tree regenerated each turn at **byte ~800** of a 669 KB body, ahead of a ~270K-token prefix | **~22% of turns fully rewritten.** Any `mkdir` at depth ≤2 — *a build writing `artifacts/`* — cold-rewrites everything. `files.exclude` does **not** help |
| [#323642](https://github.com/microsoft/vscode/issues/323642) | Anthropic caps at 4 breakpoints; the renderer injects a **synthetic whitespace anchor** that appears and disappears, so re-anchoring is a *rewrite* not an *extension* | **~8.4% of turns**, up to ~560K tokens at 1.25× |

Reported cache reuse factors: **2.2×, ~4×, ~7.9×** against a well-tuned baseline of **20–25×**.

> [!CAUTION]
> **All three are open with zero maintainer response**, despite decompiled root causes and measured cost
> impact. They affect the BYOK-Anthropic path.

### 3.2 Byte-level churn from things that are not your prompt

Every one of these is invisible in a transcript:

- **Mode switch `Plan` ↔ `Ask`** rewrites one line inside a 9.7k-token system block ([#316182](https://github.com/microsoft/vscode/issues/316182))
- **An async-resolved experiment flag** flips a gated skill into `<skills>` mid-conversation ([#315408](https://github.com/microsoft/vscode/issues/315408)) — meaning **your A/B bucket changes your cost**
- **Switching to autopilot mid-session** injects into the middle of the system prompt: `cached_tokens` measured **359,296 (99.9%) → 3,328 (~1%)** ([#334432](https://github.com/microsoft/vscode/issues/334432), open, filed six days ago)
- **A Stop hook** silently drops `thinking` and `effort`, and *"`cache_read_input_tokens` drops to 0 exactly on the Stop-hook follow-up"* ([#333252](https://github.com/microsoft/vscode/issues/333252), open, zero response)
- **Enabling or disabling any tool.** bhavyaus [COLLABORATOR]: *"Cache will also break when users enable/disable tools etc."*

Mitigation for the first two is `github.copilot.chat.freezeCustomizationsIndex` — **experimental,
default-off** ([PR #316191](https://github.com/microsoft/vscode/pull/316191), 1.121.0).

### 3.3 The 5-minute TTL

[#321551](https://github.com/microsoft/vscode/issues/321551), still open, milestone `Backlog Candidates`.
Any wall-clock gap over ~300 s — a build, a test suite, an unanswered question — converts the whole
prefix from 0.1× to 1.0× **plus** a 1.25× write. **Cost becomes a function of how fast your machine is
and how quickly you answer prompts.**

> [!IMPORTANT]
> **Correction to an earlier edition.** We described `longToolCallCachePreservation`
> ([PR #316277](https://github.com/microsoft/vscode/pull/316277), 1.123.0) as the workaround without
> stating its scope. Per its author it is **scoped to `execution_subagent` calls only**, sends **3
> probes maximum**, every **4 minutes**. It does not cover a long build in your main loop.

The reporter's own workaround, if you miss the window: **start a new chat rather than continue** — you
pay full input plus full cache-write either way.

### 3.4 Compaction is a paid, non-deterministic event

It fires on a threshold derived from a possibly-wrong denominator (`#298900`); has fired at 72%
([#319048](https://github.com/microsoft/vscode/issues/319048)) and with the context still 50% full
([#299810](https://github.com/microsoft/vscode/issues/299810)); has looped
([#310703](https://github.com/microsoft/vscode/issues/310703), open, zero response); the summariser's
own calls ran at **0% cache hit rate** for two distinct reasons
([#309696](https://github.com/microsoft/vscode/pull/309696) orphaned tool results — **closed with no
milestone**; [#311851](https://github.com/microsoft/vscode/pull/311851) `enableThinking` mismatch —
fixed 1.118.0); and it can **replay tool calls and duplicate real side effects** — one reporter had a
GitHub comment posted twice ([#307817](https://github.com/microsoft/vscode/issues/307817), open).

## What the maintainers have said

GitHub documents almost nothing about Copilot's caching. **Engineers explaining it in issue threads are
currently the best primary source that exists.**

> **lramos15 [MEMBER], 2026-06-02** ([#319403](https://github.com/microsoft/vscode/issues/319403)):
> *"Hovering each model in the model picker will give you the cost of each model broken down by input,
> output, and cache read tokens. **We eat the cost of cache writes.**"*

> **bhavyaus [COLLABORATOR]**, maintainer-authored COGS issue
> [#322775](https://github.com/microsoft/vscode/issues/322775), still open, `Priority: P0`:
> *"**5-minute TTL (default): cache write = 1.25× base input. 1-hour TTL (extended): cache write = 2.0×
> base input.**"* … *"**Telemetry gap:** Anthropic returns `ephemeral_5m_input_tokens` and
> `ephemeral_1h_input_tokens` separately, but **we only capture the combined total.**"*

> [!WARNING]
> **Those two statements are in tension.** One maintainer says Copilot absorbs cache-write cost; another
> maintainer's own cost-modelling issue prices cache writes at 1.25×/2.0× of base input. We have not
> reconciled them and do not assert either. If you are modelling Copilot cost, **this is the single
> most load-bearing unknown.**

On what breaks the cache, from [PR #323594](https://github.com/microsoft/vscode/pull/323594) (1.128.0):

> *"**The prompt cache is keyed on the request prefix, so changing the model, reasoning effort, context
> size, mode, or enabled tool set between turns of the same session invalidates the cache the previous
> turn warmed up.** Previously there was no signal to the user that a change carried this cost."*

That warning ships as `chat.cacheBreakHint.enabled` — **experimental, default-off.**

On why compaction exists at all:

> **roblourens [MEMBER], 2025-08-07**: *"Yes, **and to attempt to preserve the prompt cache during the
> agent loop**"*

## The one with 106 reactions and no reply

[#292452](https://github.com/microsoft/vscode/issues/292452) — *"Billing can be bypassed using a
combination of subagents … resulting in unlimited free premium requests."* Premium cost is billed on the
**initiating** model; subagent tool calls consume nothing. Start on a cheap model, `runSubagent` into an
`.agent.md` pinned to an expensive one.

**106 reactions, 33 comments, open since 2026-02-03 — and not one maintainer comment.** Bot-closed
within minutes of filing, silently reopened by a maintainer two days later, nothing since.

We include it not as advice — it is an exploit, not a user-facing cost — but because it is the clearest
single data point about **how the billing model attributes cost**, and because a defect with that much
engagement and no response says something about the triage pipeline that no changelog line does.

## The one instrument you can trust

[PR #313620](https://github.com/microsoft/vscode/pull/313620) (1.119.0) added a **Cache Explorer** to
the chat debug panel that **diffs the current request against the previous one in a session.**

Every bug in Tier 3 is ultimately "some bytes moved that shouldn't have." The Cache Explorer shows you
exactly which bytes moved. It is the closest Copilot equivalent to Claude Code's
`OTEL_LOG_RAW_API_BODIES`, and it is the right first stop for any unexplained cost spike.

---

# The CLI and SDK are a separate catalogue

Per [`COPILOT-SURFACES.md`](COPILOT-SURFACES.md), these are different repositories on different release
trains. **None of the VS Code fixes above apply to them.**

> [!CAUTION]
> **`cache_control`, `prompt caching`, `ephemeral`, and `breakpoint` appear _nowhere_ in the CLI's
> 3,083-line changelog, across all 170 versions.** The caching feature that GitHub says ships on by
> default has **zero** changelog entries. Everything we know about CLI cache behaviour comes from issue
> threads and one user's packet capture.

## The one to act on today

| # | What | State |
|---|---|---|
| [cli#4720](https://github.com/github/copilot-cli/issues/4720) | **v1.0.82 BYOK silently disables prompt caching** | 🔴 **open**, filed 2026-09-04 |

The reporter's measurement, same machine, same model, 150 requests:

| Version | Cache hit rate | Session cost |
|---|---|---|
| **1.0.80** BYOK | 97.7% | **$28.92** |
| **1.0.82** BYOK | **0%** | **$61.21** |

`cached_tokens = 0` **and** `cache_write = 0` on every request — the declaration is simply absent from
the BYOK request builder. **Workaround: downgrade to 1.0.80**, or use subscription mode.

The structural point is sharper than the bug: *"tested 1.0.82 in GitHub-subscription mode on the same
machine → caching works."* **The BYOK and subscription request builders are different code paths with
different cache behaviour inside one binary.** If paths diverge inside a single CLI, cross-surface
divergence needs no further argument.

## Startup cost regressions

| # | What | State |
|---|---|---|
| [cli#4613](https://github.com/github/copilot-cli/issues/4613) | MCP schemas eagerly injected on 1.0.80+: first-request tokens **49,084 → 403,209**. *"A fresh copilot cli session with a simple 'hi' greeting costs more than 200 AIC"* | 🔴 **open**; a member calls it a dup with *"a fix in progress"* — **no version cited** |
| [cli#4588](https://github.com/github/copilot-cli/issues/4588) | Tool deferral is gated by a **server-managed** flag that only returns true for Claude. `"hi"` costs **21.6k** on sonnet-4.6, **47.6k** on gpt-5.4, **61.9k** on grok-4.6 | ✅ closed — **zero comments, no version** |
| [cli#4189](https://github.com/github/copilot-cli/issues/4189) | `/context` reports the *un-deferred* MCP footprint — **~20× overstatement** (98.8k vs ~5k real) | ✅ closed, no version |

> [!IMPORTANT]
> `cli#4588` is the cleanest evidence in this repo that **token cost is set by a server-side rollout the
> client cannot influence.** Client-side `toolSearch: true` reports `None` on all 23 models. Two users
> on the same version, same prompt, different model can differ **3×** on startup tokens for reasons
> absent from any changelog.

## Billed work that reclaims nothing

| # | What | State |
|---|---|---|
| [cli#4663](https://github.com/github/copilot-cli/issues/4663) | Failed compaction is **retried unchanged every turn** — no backoff, no fallback. **38 consecutive billed calls, 0 tokens reclaimed**, +158k context growth. Silent: only `success: false` in `events.jsonl` | 🔴 **open**, unchanged on 1.0.82 |
| [cli#3886](https://github.com/github/copilot-cli/issues/3886) | `/restart`, `/resume`, `/update` consume a fixed **~174 AI credits (~$1.74)** with **zero prompts submitted** | 🔴 **open** |
| [cli#2421](https://github.com/github/copilot-cli/issues/2421) | HTTP/2 `GOAWAY` race → 5 retries against the **same corrupted connection pool**, each billed | 🔴 **open**, **19 reactions** |
| [cli#1614](https://github.com/github/copilot-cli/issues/1614) | Post-compaction cache miss: 80,135 tokens at `cache_read_tokens: 0`, **475 s versus 3.4 s on a hit** — a 100×+ latency outlier, no client timeout | ❌ closed `not_planned` — **the reporter could no longer reproduce** |

## Two real overbilling incidents

Both are confirmed against actual billing, not just a client display.

**[cli#351](https://github.com/github/copilot-cli/issues/351)** — one prompt burned 29–220 premium
requests. Fixed server-side in `0.0.345`, and the changelog carries **the only refund admission in the
entire file**:

> *"Fixed a bug where premium requests were being overcounted for some users. **If you were affected, we
> are working on refunding your overcharged premium requests!**"*

**[cli#2591](https://github.com/github/copilot-cli/issues/2591)** — **13 reactions, 32 comments.** Six
prompts consumed 87 premium requests. Root cause was **an experimental server-side flag flighted to a
small percentage of users**.

> [!WARNING]
> **No client release fixed `#2591` — the flag was switched off server-side, and there is no changelog
> entry for it.** A billing defect affecting real money is entirely absent from the versioned record.
> Users were still asking for refunds when it was closed. **You cannot audit Copilot cost history from
> release notes**, because the most expensive class of defect never appears there.

## SDK — the accounting trap

> **Stephen Toub [COLLABORATOR]**, [`copilot-sdk#1160`](https://github.com/github/copilot-sdk/issues/1160), 2026-04-30:
> *"**Input tokens is the total covering all kinds of input, including cached.** Similarly output tokens
> is the total covering all kinds of output, including reasoning."*

> [!CAUTION]
> **This is the single most load-bearing accounting statement in either tracker.** Anyone computing
> `(input_tokens + cache_read_tokens) × price` **double-counts**, because cache reads are already inside
> `input_tokens`. Anthropic's API does the opposite — `input_tokens` there **excludes** cached tokens.
> **The two vendors' fields share a name and mean different things.**

Two more SDK items worth carrying:

- **[sdk#613](https://github.com/github/copilot-sdk/issues/613)** is the *real* root cause of the
  better-known `#1073`, filed **six weeks earlier**, opened with a **$400-in-one-hour** burn: the
  Anthropic BYOK response mapper never maps `cache_read_input_tokens`. Bulk-closed as a backlog trim. A
  maintainer's reply is worth reading in full as a lesson in how a correct root-cause analysis gets
  deflected: *"you're suggesting we need to fix the usage reporting, but that will have no impact on
  your actual API usage costs."*
- **[sdk#1296](https://github.com/github/copilot-sdk/issues/1296)** — SDK 0.3.0 began injecting
  **mutating per-turn state** (`sqlTables`, `todoStatus`, `addedTools`, `previousModel`…) into a
  `<system_reminder>` inside **every user message**; in 0.2.2 that block was static. A Microsoft
  engineer measured hit rate falling **~89% → ~80%** sustained, and **~1.67× input-token spend**. Closed
  `not_planned`, labelled `enhancement`, on the basis of *"offline discussion"* with no public record.
  His rebuttal is the right standard: *"**We can plan around documented behavior; we can't around
  silent behavior change.**"*

## Where the CLI's breakpoints actually go

The best primary source on CLI cache internals is not documentation — it is **a user's Fiddler capture**
on [`cli#4185`](https://github.com/github/copilot-cli/issues/4185), which enumerates all five blocks:

| # | Section | Block | Present when |
|---|---|---|---|
| 1 | `system` | Base CLI system prompt | always |
| 2 | `system` | Main `<environment_context>` + instructions | always |
| 3 | `system` | **Second** `<environment_context>` — "additional directories" | **`--add-dir` only** |
| 4 | `messages` | Last user message | **subagent path only** |
| 5 | `tools` | End of the `tools` array | always |

Anthropic caps breakpoints at **4 across system + messages + tools**. So `--add-dir` plus a subagent
dispatch is **5** → HTTP 400. Fixed in **v1.0.73**; the workaround was to launch at the repo root.

> [!NOTE]
> *"Root Claude requests carry one fewer breakpoint than the sub-agent path."* That asymmetry is
> undocumented anywhere else, and it means **subagent turns have a structurally smaller cache-write
> budget** than main-loop turns.

## Does the CLI bill differently from the extension?

The best single item — and it has **never been triaged**:

**[cli#2068](https://github.com/github/copilot-cli/issues/2068)**, open since 2026-03-16, 5 reactions,
**0 comments**: *"The VS Code extension handles compaction/summarization without consuming premium
requests. It uses a **caller-controlled boolean** to mark requests as agent-initiated. The CLI's
compaction appears to be incorrectly classified as user-initiated. **Session naming (also a background
operation in CLI) does NOT consume a premium request — only compaction does.**"*

Note the inconsistency *inside* the CLI: two background operations, two billing classifications.

> [!IMPORTANT]
> **Evidence cuts both ways, and the honest claim is narrower than "separate implementations."** A VS
> Code stack trace on [`cli#2496`](https://github.com/github/copilot-cli/issues/2496) resolves to
> `github.copilot-chat-0.42.3/node_modules/@github/copilot/sdk/index.js` — **the extension bundles the
> same SDK**. The defensible statement: *the CLI and the extension share the `@github/copilot` SDK core
> but differ in the request-classification and billing-annotation layer above it.*

## Two corrections to this repo

> [!WARNING]
> **`examon` is a bot.** [`TIMELINE.md`](../TIMELINE.md) grades the CLI's `cache_control` support **C**
> — "maintainer comment" — on the strength of the closing comment on
> [`cli#4256`](https://github.com/github/copilot-cli/issues/4256). That account is a Microsoft
> `site_admin`, but **every one of its comments carries a trailing `<!-- copilot-reply:NNNN -->` marker:
> it is an agentic auto-close bot posting under a staff account.** We verified its two factual version
> claims against the changelog and both match exactly — but a bot assertion is **not** a maintainer
> statement, and the grade is being revised to **D**.

> [!NOTE]
> **`author_association` is unreliable for GitHub staff.** Three separate Microsoft employees with
> `site_admin: true` appear as `author_association: NONE` — including `joheredi`, whose idle-gap
> measurements (240 s → 3.5% miss, 300 s → 32%, 330 s → 100%) this repo cites in
> [track 02 §3.3](../docs/02-prompt-caching.md). **That data is stronger than we credited it**: it came
> from a Microsoft engineer, not an anonymous user. Verify affiliation with `gh api users/<login>`, not
> the association field.

---

## Claude Code — a different shape of problem

No comparable open cache defect. What it has instead is **volume**: roughly **70 changelog entries touch
prompt caching**, most of them fixes for invalidation regressions rather than features.

<details>
<summary><strong>Selected prompt-cache regressions, v2.1.30 → v2.1.267 (8 entries)</strong></summary>

| Version | Entry | Why it matters |
|---|---|---|
| 2.1.30 | Cache not invalidating when tool *descriptions or schemas* changed, only names | Cache keys can be too loose as well as too tight |
| 2.1.42 | `Improved prompt cache hit rates by moving date out of system prompt` | The textbook invalidator, shipped in production |
| 2.1.72 | SDK `query()` invalidation — `reducing input token costs up to 12x` | One bug, **12×** |
| 2.1.89 | Misses in long sessions from tool schema bytes changing mid-session | Byte-level instability, invisible to the user |
| 2.1.181 | Custom `ANTHROPIC_BASE_URL` / Foundry: a per-request attestation token changed every turn | The gateway trap, as a shipped defect |
| 2.1.235 | Whole-cache invalidation when a language server reconnected | An LSP restart cost a full re-read |
| 2.1.248 | Tool definitions re-rendered after OAuth refresh — a miss **roughly once an hour** | An auth event, unrelated to content, broke the prefix |
| 2.1.267 | `/model` switch still re-sending every tool definition | Being fixed in the current release |

</details>

> [!NOTE]
> The lesson is not "Claude Code is buggy." It is that **prefix stability decays** — in a product whose
> vendor treats hit rate as a production SLO. Note the symmetry with Copilot: `#298554` found a VS Code
> tool-set change shifting **39 of 64 tool positions**, and Claude Code's 2.1.89 fixed the same class of
> defect. Neither vendor has this solved.

## Two rules that fall out

1. **Never compare cost numbers across VS Code versions.** The meter changed under you at 1.120.0,
   1.121.0, 1.125.0, 1.128.0, 1.129.0, 1.131.0, 1.135.0, and 1.137.0.
2. **Treat the transcript as insufficient.** The biggest cost variable is whether the prefix survived,
   and that is sensitive to wall-clock time, to `mkdir`, to a rotating debug UUID, and to which A/B
   bucket you landed in. Use the Cache Explorer, or Claude Code's raw-body capture, or measure nothing.

---

[Index](../README.md) · [Settings](SETTINGS.md) · [Copilot surfaces](COPILOT-SURFACES.md) · [Timeline](../TIMELINE.md)
