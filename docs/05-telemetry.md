# 05 — Telemetry and observability

**Research date:** 2026-09-10. **Scope:** what each harness lets you measure about its own token
consumption, in what format, and what each one refuses to tell you.

**The premise most comparisons get wrong:** "Claude Code has OpenTelemetry and Copilot does not" is
false as of 2026. Copilot ships OTel in VS Code and an enterprise path, and by some measures its
*trace* model is better designed. The real asymmetry is elsewhere.

---

## 0. TL;DR

1. **Both ship OTel.** Copilot's is newer and follows the OTel **GenAI semantic conventions**; Claude
   Code's lives in a bespoke `claude_code.*` namespace and its tracing is still beta.
2. Copilot's **span hierarchy is cleaner** — `invoke_agent` → `chat` / `execute_tool` / `execute_hook`,
   with context propagating into subagents. Claude Code has no equivalent published hierarchy.
3. Claude Code wins decisively on **cache-specific** observability: a cost metric in USD, a `/usage`
   cache panel, statusline fields, raw API body capture, and — uniquely — **miss-cause attribution**.
4. Copilot's telemetry had a documented **implementation gap**: `cacheReadTokens` / `cacheWriteTokens`
   were defined and documented but hardcoded to `0.0` across all providers. Now closed.
5. For **chargeback**, Copilot's per-user and per-token data live in two different systems that cannot
   be joined. Claude Code emits both dimensions on the same data point.

---

## 1. Claude Code: cost instrumentation in a bespoke namespace

### 1.1 Metrics

Enabled with `CLAUDE_CODE_ENABLE_TELEMETRY=1`. Per
[Claude Code: monitoring usage, fetched 2026-09-10](https://code.claude.com/docs/en/monitoring-usage):

<details>
<summary><strong>Claude Code metrics catalog (7 rows)</strong></summary>

| Metric | Unit | Notes |
|---|---|---|
| `claude_code.token.usage` | tokens | `type` ∈ `input`, `output`, **`cacheRead`**, **`cacheCreation`** |
| `claude_code.cost.usage` | **USD** | A real currency figure, not a credit abstraction |
| `claude_code.session.count` | — | |
| `claude_code.active_time.total` | s | |
| `claude_code.lines_of_code.count` | — | |
| `claude_code.commit.count` / `pull_request.count` | — | |
| `claude_code.code_edit_tool.decision` | — | Permission decisions |

</details>

**Metrics with changelog evidence but absent from that docs page.** `claude_code.llm_request` and
`claude_code.active_time.total` shipped in
[v2.1.139](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md#21139),
`claude_code.tool` spans in
[v2.1.145](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md#21145),
and `claude_code.assistant_response` in
[v2.1.193](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md#21193).

> [!WARNING]
> **Metrics with no public evidence at all — treat as unconfirmed.** `claude_code.compaction`,
> `claude_code.mcp.rpc`, `claude_code.subagent.spawn`, and `claude_code.tool.execution` appear **neither
> on the docs page nor anywhere in the changelog**. Our only basis for them is string inspection of the
> v2.1.220 binary, which establishes that the names exist in the shipped artifact — not that the metrics
> are emitted, nor what their attributes are. **Do not build a dashboard on these without confirming
> they emit in your own environment.** Downgraded accordingly in [`../GAPS.md`](../GAPS.md) §1.

The same caveat applies wherever this repo cites `claude_code.compaction`'s `trigger` attribute
(track 03 §2.6) or `claude_code.mcp.rpc` (track 04 §4).

**Attributes** on the token metric: `type, model, query_source, speed, effort, agent.name, skill.name,
plugin.name, marketplace.name, mcp_server.name, mcp_tool.name`. Two are worth calling out:

- `query_source` ∈ `main` | `subagent` | `auxiliary` — lets you separate main-loop spend from subagent
  fan-out, which is the first question anyone asks when a bill looks wrong.
- `mcp_server.name` — per-server token attribution, which makes track 04's audit mechanical rather
  than inferential.

### 1.2 Events

`claude_code.user_prompt`, `assistant_response`, `api_request`, `api_error`, `api_refusal`,
`tool_result`, `tool_decision`, `permission_mode_changed`, `auth`, `mcp_server_connection`.

The one with no counterpart anywhere in Copilot:

```sh
OTEL_LOG_RAW_API_BODIES=file:<dir>    # full Messages API request + response JSON to disk
```

This is the difference between *observing* a cache miss and *proving* what caused it. With two
consecutive request bodies you byte-diff the prefix and find the invalidator directly. Nothing else in
either product answers that question empirically.

It is also the largest privacy and disk-space liability in either product — full prompts, file
contents, and absolute paths on disk. This repo treats it as opt-in behind an explicit flag and never
writes it inside the repository. See [`../METHODOLOGY.md`](../METHODOLOGY.md).

### 1.3 In-product surfaces

| Surface | Shows | Shipped |
|---|---|---|
| per-session prompt-cache line | hit ratio, misses, tokens re-cached, warm/cold | [v2.1.251](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L423) |
| …with `likely cause: …` | **cause of the last miss** | [v2.1.260](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L193) |
| statusline `prompt_cache` object | same numbers, live | v2.1.251 |
| `current_usage` in statusline | per-turn `cache_read_input_tokens` / `cache_creation_input_tokens` | — |
| `claude -p … --output-format json` | `usage.cache_creation.ephemeral_{5m,1h}_input_tokens` | — |

Miss-cause attribution is the capability with no equivalent in any competing harness we are aware of.

Anthropic's docs describe this panel under `/usage`; the changelog entry that shipped it says `/cost`.
Both are correct — `/cost` and `/stats` became tabs inside `/usage` in v2.1.118 — but **search the
changelog for `/cost`**, not `/usage`. Same note in [track 02 §7](02-prompt-caching.md).

> [!NOTE]
> **A caveat we could not resolve.** On the v2.1.220 binary available to us, the miss-cause emitter
> appears to be present but gated behind a feature flag defaulting off, with no environment-variable
> override — unlike neighbouring flags that do have one. We could not test v2.1.260+, so we cannot say
> whether the documented version floor is sufficient on its own or whether server-side enablement is
> also required. Recorded in [`../GAPS.md`](../GAPS.md) §1 rather than asserted either way.

### 1.4 Cardinality controls

`OTEL_METRICS_INCLUDE_SESSION_ID` (default true), `_VERSION` (false), `_ACCOUNT_UUID` (true),
`_ENTRYPOINT` (false), `_RESOURCE_ATTRIBUTES` (true). Copilot exposes no equivalent, which matters at
fleet scale where session-id cardinality is what makes a metrics bill explode.

## 2. Copilot: GenAI semantic conventions, cleanly applied

### 2.1 VS Code

**Shipped in VS Code 1.119, 2026-05-06** — and the release note is unusually specific, which makes this
one of the best-evidenced claims in the repo
([notes](https://code.visualstudio.com/updates/v1_119)):

> Copilot Chat agent sessions, including the local agent, the Copilot CLI background agent, and the
> Claude agent, now emit OpenTelemetry traces, metrics, and events that follow the GenAI semantic
> conventions… Each user request produces an `invoke_agent` root span (for example, `invoke_agent
> claude`) with nested `chat`, `execute_tool`, and `execute_hook` child spans. Subagent invocations are
> automatically parented to the calling agent's `execute_tool` span… **Spans report model and token
> usage, including cache read and cache creation breakdowns.**

Hardened across three subsequent releases: **1.121** (2026-05-20) added a Grafana dashboard, **1.122**
(2026-05-28) a canonical `github.copilot.*` attribute namespace, **1.128** (2026-07-08) enterprise-managed
export. The correctly-named cache attributes reached the CLI in **v1.0.64** (2026-06-23) — that entry
notes the previous names were wrong, so telemetry captured before that date used non-conforming keys.

Field-level detail below is from
[Monitor agent usage with OpenTelemetry, fetched 2026-09-10](https://code.visualstudio.com/docs/agents/guides/monitoring-agents):

**Spans** — `invoke_agent` (wraps the whole orchestration) → `chat` (one per model call),
`execute_tool` (one per invocation), `execute_hook` (one per hook). Trace context propagates into
subagents, so a subagent's `invoke_agent` appears as a child of the parent's `execute_tool`.

**Token attributes** on `invoke_agent` and `chat`:

```text
gen_ai.usage.input_tokens
gen_ai.usage.output_tokens
gen_ai.usage.cache_read.input_tokens        # "when available"
gen_ai.usage.cache_creation.input_tokens    # "when applicable"
```

**Metrics** — `gen_ai.client.token.usage` (histogram), `copilot_chat.tool.call.count` (counter),
`copilot_chat.agent.invocation.duration` (histogram).

**Settings** — `github.copilot.chat.otel.enabled` (default `false`), `.otlpEndpoint` (default
`http://localhost:4318`), `.exporterType`, `.captureContent` (default `false`). Env overrides:
`COPILOT_OTEL_ENABLED`, `OTEL_EXPORTER_OTLP_ENDPOINT`.

**This is a genuinely good design.** GenAI semconv compliance means an existing OTel GenAI dashboard
works unmodified; the span hierarchy models an agent run correctly; subagent propagation is handled.
Claude Code's tracing is beta and its metrics are in a vendor namespace, so on *standards alignment*
Copilot is ahead.

### 2.2 Enterprise

[OpenTelemetry for agent monitoring, fetched 2026-09-10](https://docs.github.com/en/copilot/concepts/enterprise/opentelemetry)
describes traces and metrics exported to an OTLP backend across an enterprise. The page does not
enumerate metric names, span names, attributes, or state whether cache tokens are included — so the VS
Code documentation above is the authoritative source for field names.

### 2.3 The gap that was there

[github/copilot-sdk#1073](https://github.com/github/copilot-sdk/issues/1073), filed 2026-04-14 against
SDK v0.2.2: `assistant.usage.cacheReadTokens` and `cacheWriteTokens` were defined and documented, but
always `0.0` — the CLI never extracted `cache_read_input_tokens` / `cache_creation_input_tokens` from
Anthropic responses or `prompt_tokens_details.cached_tokens` from OpenAI's.

**It was closed the same day it was filed — by assertion, not by a fix you can inspect.** The closing
artifact is a maintainer comment: *"This has been fixed and will be available in the next release."*
There is **no linked PR, no commit, and no named version**, because the root cause was in the
closed-source Copilot CLI server rather than the SDK. Graded **C** in [`../TIMELINE.md`](../TIMELINE.md).

The nearest dated public confirmation that cache tokens actually flow is the CLI changelog: **v1.0.51**
(2026-05-20) `Ensure input token usage includes cached`, then **v1.0.60** (2026-06-05) `Show cache write
tokens alongside cache read tokens in /usage`.

Practical consequence: **Copilot telemetry captured before roughly 2026-05-20 reports cache tokens
unreliably**, and before v1.0.64 (2026-06-23) the OTel attribute names themselves were non-conforming.
Any historical cost analysis over that window is measuring an instrument that was broken.

Worth citing not as a live defect but as evidence of maturity ordering: Copilot's cache telemetry was
specified before it was implemented, and for a period the fields returned confident zeros. Anyone with
historical Copilot telemetry from that window should treat cache figures in it as unreliable.

### 2.4 Copilot CLI

> [!IMPORTANT]
> **Correcting an earlier claim.** This document previously stated that Copilot CLI had no prompt
> caching and that [#3808](https://github.com/github/copilot-cli/issues/3808) sat unanswered. Both were
> wrong.

The issue was **split**. Its `cache_control` half became
[#4256](https://github.com/github/copilot-cli/issues/4256), **closed completed 2026-08-09** — Claude
requests now mark the static prefix (system prompt and tool definitions) with ephemeral `cache_control`
breakpoints by default, observable in the `Tokens` line of the session summary from **v1.0.78**
(2026-08-03). Note the evidence grade: that fact exists **only in the closing comment**; a grep of the
entire 3,083-line CLI changelog for `cache_control|breakpoint|ttl` returns zero hits.

The **1-hour TTL half remains open**, with substantial production data attached — see
[track 02 §3.3](02-prompt-caching.md) for the idle-gap decay table that came out of it.

The CLI also runs ahead of the VS Code extension on some telemetry: per-model token totals in `/usage`
(v1.0.64, 2026-06-23) predate the equivalent VS Code footer breakdown (1.135, 2026-08-26) by two
months, and cache-write display (v1.0.60) predates the usage report's by over two. **The CLI and the
extension are separate implementations and conclusions about one do not transfer** — in either
direction.

## 3. Head to head

| Capability | Claude Code | Copilot |
|---|---|---|
| OTel metrics | ✅ `claude_code.*` namespace | ✅ `gen_ai.*` semconv |
| OTel traces | ⚠️ beta | ✅ GA, clean hierarchy |
| GenAI semconv compliance | ❌ bespoke | ✅ |
| Cache read/creation tokens | ✅ metric dimension | ✅ span attribute |
| Cost in **USD** | ✅ `claude_code.cost.usage` | ❌ credits, computed downstream |
| Per-turn cache stats **in the UI** | ✅ `/usage`, statusline | ❌ |
| **Miss-cause attribution** | ✅ (version/flag caveat) | ❌ |
| Raw request/response capture | ✅ `OTEL_LOG_RAW_API_BODIES` | ❌ (`captureContent` is prompt text only) |
| Per-MCP-server attribution | ✅ `mcp_server.name` | ❌ |
| Cardinality controls | ✅ five env vars | ❌ |
| Subagent trace propagation | ⚠️ beta | ✅ |
| Org rollup latency | real time | **~2 days** |

**Fair reading.** Copilot built the better *tracing* model. Claude Code built the better *cost*
instrumentation. If you are standardising on OTel GenAI conventions across many tools, Copilot's shape
fits better. If you are trying to work out why a bill is high, Claude Code is the only one that will
tell you.

## 4. Chargeback: the join problem

For "which team spent what," Copilot splits the data across two systems:

| | Where | Granularity | Lag |
|---|---|---|---|
| Per-**user** spend | Metrics API NDJSON export, `ai_credits_used` | one number per user; **no token breakdown** | ~2 days |
| Per-**token** breakdown | Billing AI usage report | input / cached / output **per model** | daily |

**These cannot be joined.** You can know that a user spent 412 credits, or that GPT-5.4 consumed N
cached tokens org-wide, but not that a given user's spend was cache-inefficient. There are also no
team-level endpoints; team metrics must be derived by resolving membership via the Teams API.

Claude Code emits `user.id`, `session.id`, `model`, and `type=cacheRead` **on the same data point**, so
one query answers both. For an organisation doing internal chargeback this is the largest practical
difference in the entire comparison — larger than any caching detail.

Per-model token breakdown reached Copilot's usage report on
[2026-08-11, fetched 2026-09-10](https://github.blog/changelog/2026-08-11-per-model-token-breakdown-in-the-usage-report/) —
recent, and a real improvement on what preceded it.

## 5. What we could not determine

- Whether Copilot's enterprise OTel export includes cache-token fields (docs do not enumerate them).
- Copilot's telemetry with a paid seat and extension installed — neither was available on the test
  machine, so §2.1 is documentation-derived, not observed.
- Whether Claude Code's miss-cause attribution requires only a version bump or also server-side
  enablement.

See [`../GAPS.md`](../GAPS.md).

## Sources

- [Claude Code: monitoring usage, fetched 2026-09-10](https://code.claude.com/docs/en/monitoring-usage)
- [How Claude Code uses prompt caching, fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)
- [VS Code: Monitor agent usage with OpenTelemetry, fetched 2026-09-10](https://code.visualstudio.com/docs/agents/guides/monitoring-agents)
- [GitHub Docs: OpenTelemetry for agent monitoring, fetched 2026-09-10](https://docs.github.com/en/copilot/concepts/enterprise/opentelemetry)
- [GitHub Docs: Copilot usage metrics, fetched 2026-09-10](https://docs.github.com/en/copilot/reference/copilot-usage-metrics/copilot-usage-metrics)
- [Changelog: per-model token breakdown, fetched 2026-09-10](https://github.blog/changelog/2026-08-11-per-model-token-breakdown-in-the-usage-report/)
- [github/copilot-sdk#1073, fetched 2026-09-10](https://github.com/github/copilot-sdk/issues/1073)
- [github/copilot-cli#3808, fetched 2026-09-10](https://github.com/github/copilot-cli/issues/3808)
- [Elastic: Claude Code monitoring with OTel, fetched 2026-09-10](https://www.elastic.co/security-labs/blog/claude-code-cowork-monitoring-otel-elastic)

---

← [04 — Tool and MCP loading](04-tool-and-mcp-loading.md) · [Index](../README.md) · [06 — Billing and cost anatomy](06-billing-cost-anatomy.md) →
