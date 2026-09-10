# Timeline

Dated, linkable shipping evidence for every capability this repo describes. A documentation page that
says "requires vX" is a vendor assertion; a changelog entry or release note is evidence. Where only the
former exists, this file says so.

**Compiled 2026-09-10.** Claude Code evidence is from the
[`anthropics/claude-code` CHANGELOG](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md)
at commit `9cdc2a4` (390 versions, latest v2.1.267). Copilot evidence is from VS Code release notes,
the [`github/copilot-cli` changelog](https://github.com/github/copilot-cli/blob/main/changelog.md), the
GitHub Changelog, and the GitHub API for issue state.

> **A cadence note that affects citation.** VS Code moved from **monthly to weekly releases in March
> 2026**. v1.110 (2026-03-04) was the last monthly build titled "February 2026"; v1.111 onward are
> weekly and titled by number only. Latest at compile time: **v1.137 (2026-09-09)**.

---

## 1. Claude Code

| Version | Capability | Evidence |
|---|---|---|
| 2.1.7 | Tool search default-on as `MCPSearch` when MCP descriptions exceed 10% of the window | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L5098) |
| 2.1.9 | `auto:N` deferral threshold syntax | changelog |
| ~2.1.20 | `MCPSearch` renamed `ToolSearch` — **never announced**, simply appears | — |
| 2.1.81 | `--bare`; requires `ANTHROPIC_API_KEY`, disables OAuth/keychain, auto-memory off | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L4038) |
| 2.1.108 | `ENABLE_PROMPT_CACHING_1H`, `FORCE_PROMPT_CACHING_5M`, `_BEDROCK` deprecated | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L3472) |
| 2.1.111 | `OTEL_LOG_RAW_API_BODIES` | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L3413) |
| 2.1.118 | `/cost` and `/stats` merged into `/usage` as tabs | changelog |
| 2.1.121 | Per-server deferral opt-out via `alwaysLoad` | changelog |
| 2.1.238 | `/model` and `/effort` cache warning suppressed once the cache has expired | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L804) |
| **2.1.243** | **`promptCacheTtl` / `subagentPromptCacheTtl` settings** | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L656) |
| 2.1.248 | Subagent `experimental.cacheTtl` frontmatter | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L499) |
| 2.1.251 | Per-session prompt-cache line in `/cost`; `prompt_cache` statusline object | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L423) |
| **2.1.260** | **Miss-cause attribution** (`likely cause: …`); effort change keeps cache on Fable 5.1 | [changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L193) |
| 2.1.267 | `/model` switch no longer re-sends every tool definition | changelog |

**Anthropic's docs are off by one on the TTL settings.** They say v2.1.242. The changelog says v2.1.243,
and **no v2.1.242 section exists** — the file goes 2.1.241 → 2.1.243. Verified directly.

**Claimed in docs, absent from the changelog:** `CLAUDE_CODE_PROMPT_CACHE_TTL` and
`CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL`; OpenTelemetry support itself (never announced — the OTel
history begins mid-stream at v1.0.28 with an attribute addition); `claude_code.cost.usage` as a metric
introduction; the `cacheRead`/`cacheCreation` `type` values; and all four of
`claude_code.{compaction,mcp.rpc,subagent.spawn,tool.execution}`.

## 2. GitHub Copilot

| Date | Release | Capability | Evidence |
|---|---|---|---|
| 2026-02-04 | VS Code 1.109 | Tool search tool for Anthropic models; `…anthropic.toolSearchTool.enabled` | [notes](https://code.visualstudio.com/updates/v1_109) |
| 2026-03-04 | VS Code 1.110 | Context compaction, incl. **manual `/compact`** | [notes](https://code.visualstudio.com/updates/v1_110) |
| 2026-04-14 | — | `copilot-sdk#1073` filed **and closed the same day** | [issue](https://github.com/github/copilot-sdk/issues/1073) |
| 2026-04-27 | — | Blog: usage-based billing announced for 2026-06-01 | [blog](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/) |
| **2026-04-29** | **VS Code 1.118** | **Breakpoint placement audit — ">93% of each request is reused from cache"**; cache-stable tool ordering; cache-friendly compaction; tool search → OpenAI | [notes](https://code.visualstudio.com/updates/v1_118) |
| **2026-05-06** | **VS Code 1.119** | **OTel ships**: GenAI semconv, `invoke_agent`/`chat`/`execute_tool`/`execute_hook`, cache read/creation breakdowns | [notes](https://code.visualstudio.com/updates/v1_119) |
| 2026-05-20 | — | Auto routing "along natural cache boundaries" | [changelog](https://github.blog/changelog/2026-05-20-auto-model-selection-now-routes-based-on-your-task-in-vs-code/) |
| 2026-05-20 | CLI v1.0.51 | "Ensure input token usage includes cached" | [CLI changelog](https://github.com/github/copilot-cli/blob/main/changelog.md) |
| 2026-05-28 | VS Code 1.122 | Usage-based billing in the UI; `github.copilot.*` OTel attribute namespace | [notes](https://code.visualstudio.com/updates/v1_122) |
| **2026-06-01** | — | **AI-credit billing live for all plans** | [changelog](https://github.blog/changelog/2026-06-01-updates-to-github-copilot-billing-and-plans/) |
| **2026-06-03** | **VS Code 1.123** | **`longToolCallCachePreservation` — cache keep-alive probes. Shipped silently: no release note, experimental, default-off** | [PR #316277](https://github.com/microsoft/vscode/pull/316277) |
| 2026-06-05 | CLI v1.0.60 | Cache **write** tokens shown alongside cache read in `/usage` | CLI changelog |
| 2026-06-16 | — | `microsoft/vscode#321551` filed — 5-minute mid-session cache expiry | [issue](https://github.com/microsoft/vscode/issues/321551) |
| 2026-06-17 | — | Two blog posts: VS Code token efficiency, GitHub "Getting more from each token" | blogs |
| **2026-06-23** | **CLI v1.0.64** | **`gen_ai.usage.cache_read.input_tokens` / `cache_creation.input_tokens` emitted** (previously wrong names) | CLI changelog |
| 2026-07-08 | VS Code 1.128 | Enterprise-managed OTel export | [changelog](https://github.blog/changelog/2026-07-08-enterprise-managed-opentelemetry-export-for-vs-code-and-cli/) |
| 2026-08-03 | CLI v1.0.78 | `cache_control` breakpoints confirmed default-on for Claude | [#4256 comment](https://github.com/github/copilot-cli/issues/4256#issuecomment-5228950771) |
| **2026-08-11** | — | **Per-model input/output/cache-read/cache-write breakdown in the usage report** | [changelog](https://github.blog/changelog/2026-08-11-per-model-token-breakdown-in-the-usage-report/) |
| 2026-08-26 | VS Code 1.135 | Per-model input / cached-input / output breakdown in the chat footer | [notes](https://code.visualstudio.com/updates/v1_135) |

### 2.1 What Copilot's breakpoints actually are

Superseding the "two rolling anchors" description this repo carried before. VS Code 1.118, verbatim:

> **Strategic cache breakpoint placement.** We audited where cache breakpoints are set so they are used
> efficiently and placed at stable boundaries: end of system prompt, end of tools, end of the most
> recent tool turn, and conversation turn boundaries. As a result, once an agent session is underway,
> more than 93% of each request is reused from cache instead of being charged as new input.

The rolling-anchor variant is real but is **an opt-in setting**, not the default:
`github.copilot.chat.anthropic.cacheBreakpoints.lastTwoMessages`.

Note the figure: the release note says **>93%**; the June blog says ~94%. Prefer the release note.

## 3. Evidence grading

Not every claim in this repo is equally well supported. Ranked strongest to weakest:

| Grade | Meaning | Examples |
|---|---|---|
| **A — Release-note or changelog evidence** | A dated, versioned entry from the vendor | Claude Code TTL settings (2.1.243), miss-cause (2.1.260); Copilot OTel (1.119), breakpoint placement (1.118), billing (2026-06-01) |
| **B — Code evidence, no release note** | Merged PR with description, but never announced | `longToolCallCachePreservation` (PR #316277, shipped 1.123) |
| **C — Maintainer statement only** | A comment on an issue; no PR, commit, or changelog | `copilot-sdk#1073`'s fix; `cache_control` in Copilot CLI v1.0.78 |
| **D — Vendor blog only** | A blog sentence with no corresponding shipping artifact | `prompt_cache_retention: "24h"`; the routing mechanism's detail |
| **E — Third-party report, unreproduced** | A user's issue with no vendor confirmation | vscode#321551's 3–5× / 8–15× cost multipliers |

### Grade D — claims that rest on a blog post alone

**`prompt_cache_retention: "24h"`.** This repo previously called it "the single largest cache lever
either product has shipped." That was **overstated**. The OpenAI *parameter* is documented by OpenAI,
but the claim that Copilot *sets* it rests on one sentence in the 2026-06-17 VS Code blog. A grep of VS
Code release notes v1.107–v1.138 for `prompt_cache_retention` or `24h` returns **zero hits**, and there
is no `copilot-cli` changelog entry either. The +919%/+338%/+279% hit-rate figures come from the same
sentence's post. Treat as unshipped-or-undocumented, not as a shipped capability.

**The routing mechanism's detail.** That Auto "routes along natural cache boundaries" **is** in the
2026-05-20 changelog (grade A). That it routes *only* on turn one and after compaction, pinning the
model in between, appears only in the June blog and an undated docs page (grade D).

**HyDRA.** No changelog entry ever names it. Evidence is [arXiv 2605.17106](https://arxiv.org/abs/2605.17106),
which explicitly claims production deployment in VS Code Chat auto-mode, plus the GitHub blog.

### Grade B — the one that matters most

**`longToolCallCachePreservation` is the answer to vscode#321551, and almost nobody knows it exists.**
[PR #316277](https://github.com/microsoft/vscode/pull/316277) — opened 2026-05-13, merged 2026-05-30,
milestone 1.123.0 — sends periodic keep-alive probes during long tool calls to keep the server-side
prompt cache warm. From the PR body:

> "sending dummy user requests every 4 mins (up to a hardcoded number of probes; currently 3)… my PR
> resulted in more requests and more cached input tokens, but lower costs overall thanks to far fewer
> uncached tokens." — benchmark: **$29.26 with the fix vs $39.61 without**

It shipped **experimental, default-off, and with zero release-note coverage** (grepped v1.107–v1.138 for
`preservation|keepalive|longToolCall` — no hits). The reporter of #321551 found it independently on
2026-08-04: *"thanks for `github.copilot.chat.agent.longToolCallCachePreservation` will fix most of my
cold caches."*

### Grade C — closed by assertion

**`copilot-sdk#1073`** was closed 2026-04-14 by a maintainer comment — *"This has been fixed and will be
available in the next release"* — with **no linked PR, no commit, and no named version**. The bot's own
root cause: the fix belongs in the closed-source Copilot CLI server, so it is not publicly auditable.
The nearest dated public confirmation that cache tokens actually flow is CLI v1.0.51 (2026-05-20).

**`cache_control` in Copilot CLI.** A grep of the entire 3,083-line CLI changelog for
`cache_control|breakpoint|ttl` returns **zero hits**. The claim that v1.0.78 marks the static prefix
exists solely in the closing comment on [#4256](https://github.com/github/copilot-cli/issues/4256).

## 4. Open issues, current state

| Issue | State (2026-09-10) | Detail |
|---|---|---|
| [vscode#321551](https://github.com/microsoft/vscode/issues/321551) | **OPEN** | Filed 2026-06-16, last activity 2026-08-04, milestone `Backlog Candidates`, no assignee, no linked PR. Maintainer, 2026-06-22: *"some of this is expected. a longer cache ttl might help but is also expensive based on the model."* |
| [copilot-cli#3808](https://github.com/github/copilot-cli/issues/3808) | **OPEN** (TTL half) | Split: the `cache_control` half became #4256 and closed 2026-08-09. The **1-hour TTL request remains open** |
| [copilot-sdk#1073](https://github.com/github/copilot-sdk/issues/1073) | Closed 2026-04-14 | By comment, not by PR — see grade C above |

### 4.1 Measured cache decay — the best number either vendor has published

On `copilot-cli#3808`, 2026-08-10, a maintainer-adjacent commenter posted production session data
binning cache behaviour by idle gap:

| Idle gap | Prefix rewritten |
|---|---|
| 240 s | 3.5% |
| 270 s | 11.6% |
| **300 s** | **32.0%** |
| **330 s** | **100%** |
| 420 s | 100% |

That is the TTL cliff, quantified: **nothing much happens until 4 minutes, a third of the prefix is
gone at 5 minutes, and it is total by 5½.** It also confirms the mechanism behind vscode#321551
independently of that issue's disputed cost multipliers.

The same comment establishes that **Copilot has never shipped a 1-hour TTL on the Anthropic path**:

> "In the published SDK types: `declare type CacheControlCheckpoint = { type: "ephemeral" };` …**with no
> lifetime on it**. Our session data agrees the 1-hour tier has never been exercised: every Claude model
> shows exactly one cache-write price, always 1.25× base, and the 2× rate never appears."

## 5. Unverified — do not cite without checking

- **"Project HydraFusion"** (a HyDRA successor, reportedly with "cache-aware workflows"). Sourced to a
  community discussion, not to the announcement itself. Not used anywhere in this repo.
- Two GitHub Changelog entries (2026-03-20, 2026-06-19) were captured via rendered fetch rather than
  verified verbatim.
- Whether VS Code's OTel was preview-labelled at 1.119. The release note carries no such label, but
  [#316338](https://github.com/microsoft/vscode/pull/316338) (OTel trace store) merged *after* it. Best
  description: **shipped un-flagged in 1.119, hardened across 1.121–1.128.**

---

[Index](README.md) · [Gaps](GAPS.md) · [Methodology](METHODOLOGY.md)
