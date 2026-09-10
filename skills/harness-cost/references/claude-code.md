# Claude Code — levers and settings

## TTL

`promptCacheTtl` selects the 1-hour cache. It shipped in **v2.1.243** ([changelog][cc-changelog]) — the
[docs][d-caching] are off by one and say v2.1.242, which has no changelog section.

```json
{ "promptCacheTtl": "1h" }
```

**Do not enable it reflexively.** The 1-hour TTL writes at **2.0×** base input versus
**1.25×** for 5 minutes, so it needs **two** reuses to break even where the default
needs one. It pays only when turns are spaced 5–60 minutes apart — long builds,
human review gaps, slow test suites.

TTL selection follows a **6-level precedence order**, and the main conversation is
bucketed separately from subagents and background tasks — full order in
[track 02](../../../docs/02-prompt-caching.md).

## Deferred tool loading

Claude Code defers MCP tool schemas behind `MCPSearch` / `ToolSearch`: only the tool *names* load at
startup, and full schemas are fetched on demand.

- `alwaysLoad` — pin specific tools into the prefix when they are used nearly every
  turn. Pinning is a cost decision: it trades per-turn prefix bytes against a
  round-trip.
- `auto:N` — defer once the server exposes more than N tools.

> `defer_loading` is **not** a settings key; the mechanism is `MCPSearch` →
> `ToolSearch`.

List configured MCP servers and remove the ones you do not use.

## Observability

| Surface | What it gives you |
|---|---|
| `claude_code.token.usage{type=cacheRead\|cacheCreation}` | Per-type token counts — the metric to build a hit-rate dashboard on |
| `OTEL_LOG_RAW_API_BODIES=file:` | **Raw request bodies.** The only way to diff two consecutive prefixes and see which bytes moved |
| `/cost` | Session cost panel, including the prompt-cache breakdown |
| `--output-format json` → `total_cost_usd` | Per-run dollar figure |

Diff turn *N* against turn *N−1*; the first differing byte is your cache break. Raw
bodies contain your source code — write them outside any repo.

> [!WARNING]
> `total_cost_usd` under `--bare` is a **real API-key dollar figure**, not what a Max
> subscriber pays. It is the right number for relative comparisons and the wrong
> number to quote as "what this cost me."

## Prefix stability decays — budget for it

Expect prefix stability to regress on upgrade: roughly **70 changelog entries**
touch prompt caching, mostly invalidation fixes.

| Version | What invalidated the cache |
|---|---|
| 2.1.42 | The **date** in the system prompt |
| 2.1.72 | SDK `query()` — *"reducing input token costs up to 12x"* |
| 2.1.89 | Tool schema bytes changing mid-session |
| 2.1.181 | A per-request attestation token on custom `ANTHROPIC_BASE_URL` / Foundry |
| 2.1.235 | A **language server reconnecting** |
| 2.1.248 | Tool definitions re-rendered after **OAuth refresh** — a miss roughly once an hour |
| 2.1.267 | `/model` switch still re-sending every tool definition |

**Stay current. Re-measure after every upgrade.**

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

**A skill set tuned for VS Code silently truncates in Claude Code** — the listing cap
is 1,536 chars for `description` + `when_to_use`, explicitly *"to reduce context
usage"* ([docs][d-skills]).

Claude Code supports the largest frontmatter set of any harness (14+ fields including
`paths`, `hooks`, `model`, `effort`, `shell`, `agent`). Those are **extensions, not
spec** — other hosts reject or warn on them. Keep portable skills to the open-standard
fields; see [`copilot.md`](copilot.md) for the divergence table.

**Do not treat routing as a cost lever.** Routing plus caching measures **37–69%
cheaper than caching alone** ([`GAPS.md`](../../../GAPS.md) §7b).

[d-skills]: https://code.claude.com/docs/en/skills
[d-caching]: https://code.claude.com/docs/en/prompt-caching
[cc-changelog]: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
