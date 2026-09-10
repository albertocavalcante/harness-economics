# Changelog

Research log. Newest first.

---

## 2026-09-10 — Copilot release-note evidence, and two retractions

Added [`TIMELINE.md`](TIMELINE.md): every capability anchored to a dated shipping artifact, with an
**A–E evidence grade**. Sources: VS Code release notes read as raw markdown from `microsoft/vscode-docs`,
the `github/copilot-cli` changelog, the GitHub Changelog, and the GitHub API for issue state.

**Retracted**

| Was | Now |
|---|---|
| Copilot's 24-hour OpenAI retention is "the single largest cache lever either product has shipped" | **Grade D — blog only.** Zero hits for `prompt_cache_retention` or `24h` across VS Code v1.107–v1.138 and the CLI changelog. The architectural asymmetry is real; the claim Copilot operationalised it is not evidenced |
| "Copilot exposes no setting that would let a user work around mid-session expiry" | **False.** `longToolCallCachePreservation` shipped in VS Code 1.123 (PR #316277, merged 2026-05-30) — keep-alive probes every ~4 min. Experimental, default-off, **zero release-note coverage** |
| "Copilot CLI has no prompt caching" | **False** since v1.0.78 (2026-08-03) — `cache_control` breakpoints default-on for Claude |
| "Whether users can invoke Copilot's compaction manually is undocumented" | **False** — VS Code 1.110 documents `/compact` |
| Copilot uses "two rolling anchors on recent messages" | That is an **opt-in setting**. The default placement is end of system prompt, end of tools, end of most recent tool turn, and conversation turn boundaries |

**Newly evidenced (grade A)**

- OTel in VS Code — **1.119, 2026-05-06**, with a release note naming the span hierarchy *and* stating
  spans carry cache read/creation breakdowns
- Breakpoint placement and **">93% of each request is reused from cache"** — **1.118, 2026-04-29**
- Tool search: Anthropic **1.109** (2026-02-04), OpenAI **1.118**, with ~30 core tools covering ~88% of
  calls and "up to 20% token savings"
- Compaction **1.110**; cache-friendly compaction reusing the main agent's cached context **1.118**
- Cache-token OTel attributes emitted correctly from **CLI v1.0.64** (2026-06-23) — previous names were
  non-conforming
- Billing: announced 2026-04-27, **live 2026-06-01**

**New findings**

- **The TTL cliff, quantified.** Production data on `copilot-cli#3808`: 240 s → 3.5% of prefix
  rewritten, 300 s → 32%, 330 s → 100%. The best cache-decay data either vendor has published, buried
  in an issue comment.
- **Copilot has never shipped a 1-hour TTL on its Anthropic path.** Its checkpoint type carries no
  lifetime field, and production data shows only the 1.25× cache-write price, never the 2×.
- **Copilot telemetry before ~2026-05-20 reports cache tokens unreliably**, and before v1.0.64 the OTel
  attribute names were wrong. Historical cost analysis over that window measured a broken instrument.
- Both harnesses independently arrived at running compaction against the parent's cached prefix.

---

## 2026-09-10 — Changelog-anchored evidence pass

Version-anchored claims previously rested on documentation pages asserting "requires vX". Each is now
tied to the changelog entry that shipped it, or explicitly marked as unevidenced. Source: the
`anthropics/claude-code` CHANGELOG at commit `9cdc2a4`, 390 versions, latest **v2.1.267**.

**Corrected**

| Was | Now |
|---|---|
| `promptCacheTtl` requires v2.1.242 (per Anthropic docs) | Shipped in **v2.1.243**. **There is no v2.1.242 section in the changelog** — it skips 2.1.241 → 2.1.243. The docs are off by one. Verified directly |
| `/usage` shows the prompt-cache panel | The shipping entry says **`/cost`**. Both are true — `/cost` became a tab inside `/usage` in v2.1.118 — but the citable name is `/cost` |
| Four undocumented metrics "verified present in v2.1.220" | Downgraded to **unconfirmed**. Absent from docs *and* changelog; a string in a binary is not proof a metric is emitted |
| `defer_loading` is Claude Code's deferral key | Not in the changelog at all. The feature shipped as `MCPSearch` (v2.1.7), renamed `ToolSearch` (~v2.1.20, never announced); user-facing controls are `alwaysLoad` and `auto:N` |

**Newly evidenced**

- `ENABLE_PROMPT_CACHING_1H` + `FORCE_PROMPT_CACHING_5M` + the `_BEDROCK` deprecation — all one line, **v2.1.108**
- `OTEL_LOG_RAW_API_BODIES` — **v2.1.111**
- `--bare` forcing `ANTHROPIC_API_KEY` — **v2.1.81**, confirming the caveat on every cost figure this repo reports
- Miss-cause attribution — **v2.1.260**, matching the docs
- Effort change keeping the cache on Fable 5.1 — **v2.1.260**
- Subagent `experimental.cacheTtl` — **v2.1.248**
- Tool search default-on — **v2.1.7**

**New finding**

Roughly **70 changelog entries touch prompt caching**, and most are *fixes for cache-invalidation
regressions* rather than features — including a timestamp in the system prompt (v2.1.42), a 12×
cost multiplier from one SDK bug (v2.1.72), an OAuth refresh breaking the prefix hourly (v2.1.248),
and a `/model` switch still re-sending every tool definition as of **v2.1.267**. Written up in
`docs/02` §5.1. It is the strongest evidence in the repo that prefix stability decays and must be
measured rather than reasoned about.

**New conflicts recorded in `GAPS.md`**

- Docs and changelog disagree on mid-session output-style switching (§2b).
- Fable 5.1 ships `$0.25/Mtok` cache reads against a `$10/Mtok` input rate — **2.5%, not the ~10%**
  this repo quotes as the general multiplier. Verified verbatim; unexplained (§2c).

---

## 2026-09-10 — Initial compilation

**Added**

- Six track documents covering request lifecycle, prompt caching, context management, tool and MCP
  loading, telemetry, and billing.
- `SYNTHESIS.md` — ten cross-cutting findings, where each product is genuinely ahead, and the five
  changes that would invalidate the conclusions.
- `METHODOLOGY.md` — sourcing rules, measurement protocol, source hierarchy, known method limits.
- `GAPS.md` — what could not be determined, with a confidence legend and a ranked follow-up queue.
- A measurement harness under `measure/`: deterministic generated fixture pinned by hash, read-only
  verified tasks, cold/warm cache modes, and an interleaved A/B runner for single-variable isolation.

**Verified directly against the local Claude Code binary (v2.1.220)**

These checks changed claims that would otherwise have been wrong:

| Claim as first drafted | Corrected to |
|---|---|
| `promptCacheTtl` is a setting you can use today | **Absent from v2.1.220.** Documented as v2.1.242+; not merely undocumented on older builds — it does not exist |
| Miss-cause attribution needs only a version bump to v2.1.260+ | Emitter appears present in 2.1.220 but feature-flag gated with no env override. Could not test 2.1.260+, so the question is **left open** in `GAPS.md` §1 rather than answered |
| `cache_creation_input_tokens` is always a number | **Nullable**, and derived from `ephemeral_5m_input_tokens` + `ephemeral_1h_input_tokens`, either of which may be null or absent. The harness handles this |
| Claude Code's documented metric list is complete | Also emits `claude_code.compaction` (with `trigger: auto\|manual`, `message_count`), `claude_code.mcp.rpc`, `claude_code.subagent.spawn`, `claude_code.tool.execution` — none on the public docs page, and directly useful for tracks 03 and 04 |

**Corrected before publication**

| Widely repeated | Actually |
|---|---|
| "Copilot has no OpenTelemetry" | Ships OTel in VS Code plus an enterprise path, following GenAI semantic conventions. Its trace model is arguably better designed than Claude Code's |
| "Prompt caching saves ~90%" | Cache *reads* cost ~10% of input; cache *writes* cost 25–100% **more** than uncached input. Net saving depends on reuse count — break-even is one reuse at 5m TTL, two at 1h |
| "Cached input on Copilot costs 25% of input" | 25% is the **cache write** markup. Cached *reads* are 10% of input, matching Anthropic |
| "The minimum cacheable prefix falls with each model generation" | Not monotonic — 512 tokens on Opus 5, but 4096 on Opus 4.6 and Haiku 4.5 |

**Flagged as low confidence**

- The 3–5× per-turn and 8–15× cumulative cost figures in microsoft/vscode#321551 are one user's
  estimate on an open issue with no vendor confirmation. The *mechanism* is not in doubt; the
  magnitude is unreproduced. Labelled inline in `docs/02` §3.3, not just in `GAPS.md`.
- All Copilot vendor-reported metrics (~94% hit rate, +919%/+338%/+279% retention gains, 11–18% tool
  search savings) are cited with methodology unpublished and are labelled as vendor claims.

**Known incomplete**

- **No Copilot seat, extension, or billing scope** on the research machine. Every Copilot claim is
  documentation-derived. This is the largest limitation of this edition and the top item in the
  follow-up queue.
- No measurement runs recorded yet — the harness ships before its first dated results.
- Claude Code claims are pinned to v2.1.220; several documented features postdate it.
