# Claude Code — levers and settings

## TTL

`promptCacheTtl` selects the 1-hour cache. It shipped in **v2.1.243** — note that
Anthropic's own documentation is off by one and says v2.1.242, which **has no
changelog section at all**.

```json
{ "promptCacheTtl": "1h" }
```

**Do not enable it reflexively.** The 1-hour TTL writes at **2.0×** base input versus
**1.25×** for 5 minutes, so it needs **two** reuses to break even where the default
needs one. It pays only when your turns are genuinely spaced 5–60 minutes apart —
long builds, human review gaps, slow test suites. For back-to-back agent turns it is
strictly worse.

TTL selection follows a **6-level precedence order**, and the main conversation is
bucketed separately from everything else (subagents, background tasks). Track 02 has
the full order.

## Deferred tool loading

MCP tool schemas are the single largest always-loaded cost in most sessions. Claude
Code defers them behind `MCPSearch` / `ToolSearch`: only the tool *names* load at
startup, and full schemas are fetched on demand.

- `alwaysLoad` — pin specific tools into the prefix when they are used nearly every
  turn. Pinning is a cost decision: it trades per-turn prefix bytes against a
  round-trip.
- `auto:N` — defer once the server exposes more than N tools.

> `defer_loading` is **not** a Claude Code settings key. Earlier editions of this
> repo said it was; the feature is the `MCPSearch` → `ToolSearch` mechanism.

**The highest-value audit available:** list your configured MCP servers and remove
the ones you do not use. Unused servers cost bytes on every single turn.

## Observability

| Surface | What it gives you |
|---|---|
| `claude_code.token.usage{type=cacheRead\|cacheCreation}` | Per-type token counts — the metric to build a hit-rate dashboard on |
| `OTEL_LOG_RAW_API_BODIES=file:` | **Raw request bodies.** The only way to diff two consecutive prefixes and see which bytes moved |
| `/cost` | Session cost panel, including the prompt-cache breakdown |
| `--output-format json` → `total_cost_usd` | Per-run dollar figure |

`OTEL_LOG_RAW_API_BODIES` is the definitive instrument for Rule 1 violations. Diff
turn *N* against turn *N−1*; the first differing byte is your cache break. Keep it
opt-in — raw bodies contain your source code, so write them outside any repo.

> [!WARNING]
> `total_cost_usd` under `--bare` is a **real API-key dollar figure**, not what a Max
> subscriber pays. It is the right number for relative comparisons and the wrong
> number to quote as "what this cost me."

## Prefix stability decays — budget for it

Roughly **70 changelog entries** touch prompt caching, and most are fixes for
invalidation regressions rather than features. A sample of what broke:

| Version | What invalidated the cache |
|---|---|
| 2.1.42 | The **date** in the system prompt |
| 2.1.72 | SDK `query()` — *"reducing input token costs up to 12x"* |
| 2.1.89 | Tool schema bytes changing mid-session |
| 2.1.181 | A per-request attestation token on custom `ANTHROPIC_BASE_URL` / Foundry |
| 2.1.235 | A **language server reconnecting** |
| 2.1.248 | Tool definitions re-rendered after **OAuth refresh** — a miss roughly once an hour |
| 2.1.267 | `/model` switch still re-sending every tool definition |

The lesson is not that the product is unreliable — it is that **prefix stability
decays silently**, in a product whose vendor treats hit rate as a production SLO.
Two implications: **stay current**, and **re-measure after upgrading** rather than
assuming a prior number still holds.

> **Gateway trap.** Any proxy that injects a per-request header, attestation token,
> or trace ID **into the request body** ahead of the breakpoint destroys caching
> silently. Version 2.1.181 fixed exactly this. If you run through a corporate
> gateway or LiteLLM, verify cache reads are non-zero before trusting any figure.

## Known gaps on older builds

- **Cache-miss cause attribution** is statsig-gated (`tengu_prompt_cache_diagnostics`,
  default off) with **no environment override**. On builds where it is dark it is
  unreachable — a hard gap, not an upgrade away.
- `cache_creation_input_tokens` is **nullable**, derived as the sum of
  `ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens`. Parsers must handle
  null or they will crash or silently read zero.

## Skills

Claude Code truncates the combined `description` + `when_to_use` at **1,536
characters** in the skill listing, explicitly *"to reduce context usage"*. That is an
order of magnitude tighter than VS Code's 15,000-character catalog budget, so **a
skill set tuned for VS Code may silently truncate in Claude Code.**

Claude Code supports the largest frontmatter set of any harness (14+ fields including
`paths`, `hooks`, `model`, `effort`, `shell`, `agent`). Those are **extensions, not
spec** — other hosts reject or warn on them. Keep portable skills to the open-standard
fields; see [`copilot.md`](copilot.md) for the divergence table.

## Not a cost lever

**Routing.** I initially advised that routing destroys cache locality. Measured data
says the opposite: **routing plus caching is 37–69% cheaper than caching alone.** The
correction is recorded in [`GAPS.md`](../../../GAPS.md) §7b.
