# Changelog

Research log. Newest first.

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
