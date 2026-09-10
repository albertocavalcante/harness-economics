# Known issues

Cache- and telemetry-affecting defects in both harnesses, with current state, blast radius, and
workaround. State verified **2026-09-10** via the GitHub API.

> [!NOTE]
> A closed issue is not automatically a solved problem. Two entries below were closed **by a
> maintainer's comment with no linked PR or commit**, because the fix lives in a closed-source
> component. Those are marked *closed, unauditable*.

---

## Open

### 🔴 Prompt cache expires mid-session on gaps > 5 minutes — Copilot

[microsoft/vscode#321551](https://github.com/microsoft/vscode/issues/321551) · filed 2026-06-16 · last
activity 2026-08-04 · milestone `Backlog Candidates` · no assignee, no linked PR

The cache silently expires when two consecutive model calls are more than ~5 minutes apart — a long
terminal command, a large file read, or waiting on the user. The next call pays full input price with
no indication it happened.

**Blast radius.** Quantified independently on
[copilot-cli#3808](https://github.com/github/copilot-cli/issues/3808) from production session data:

| Idle gap | Prefix rewritten |
|---:|---:|
| 240 s | 3.5% |
| 270 s | 11.6% |
| **300 s** | **32.0%** |
| **330 s** | **100%** |

The reporter's own cost figures — 3–5× on the affected turn, 8–15% cumulative — are **one user's
estimate, unreproduced** (grade E). The mechanism is not in doubt; the magnitude is.

**Workaround.** `github.copilot.chat.agent.longToolCallCachePreservation` — see
[`SETTINGS.md`](SETTINGS.md). It is experimental, default-off, and undocumented.

**Maintainer position**, 2026-06-22: *"some of this is expected. a longer cache ttl might help but is
also expensive based on the model."*

### 🟠 No configurable cache TTL on Copilot's Anthropic path

[copilot-cli#3808](https://github.com/github/copilot-cli/issues/3808) · filed 2026-06-15 · open

The issue was split. Its `cache_control` half became
[#4256](https://github.com/github/copilot-cli/issues/4256) and closed completed 2026-08-09. **The
1-hour TTL request remains open.**

Evidence that the 1h tier has never been exercised, from the issue itself:

> `declare type CacheControlCheckpoint = { type: "ephemeral"; };` … **with no lifetime on it**. Our
> session data agrees the 1-hour tier has never been exercised: every Claude model shows exactly one
> cache-write price, always 1.25× base, and the 2× rate never appears.

**Workaround.** None. Claude Code's equivalent knob is `promptCacheTtl` — see [`SETTINGS.md`](SETTINGS.md).

---

## Closed

### ✅ `cache_control` breakpoints absent from Copilot CLI

[copilot-cli#4256](https://github.com/github/copilot-cli/issues/4256) · closed completed 2026-08-09

Claude requests now mark the static prefix (system prompt, tool definitions) with ephemeral
`cache_control` breakpoints by default, visible in the `Tokens` line of the session summary from
**v1.0.78** (2026-08-03).

> [!WARNING]
> **Closed, unauditable.** A grep of the entire 3,083-line CLI changelog for
> `cache_control|breakpoint|ttl` returns **zero hits**. This behaviour exists in the public record only
> as the issue's closing comment.

### ✅ `cacheReadTokens` / `cacheWriteTokens` always `0.0`

[copilot-sdk#1073](https://github.com/github/copilot-sdk/issues/1073) · filed **and closed** 2026-04-14

The SDK defined and documented both fields, but the CLI never extracted `cache_read_input_tokens` /
`cache_creation_input_tokens` from Anthropic responses, nor `prompt_tokens_details.cached_tokens` from
OpenAI's. Every consumer saw a confident zero.

> [!CAUTION]
> **Closed, unauditable — and it has a data-quality consequence.** The closing artifact is one comment:
> *"This has been fixed and will be available in the next release."* No PR, no commit, no named
> version; the root cause was in the closed-source CLI server.
>
> The nearest dated public confirmation that cache tokens actually flow is CLI **v1.0.51**
> (2026-05-20). Before that, **Copilot cache telemetry is unreliable**, and before **v1.0.64**
> (2026-06-23) the OTel attribute names themselves were non-conforming. Any historical Copilot cost
> analysis spanning that window was measuring a broken instrument.

---

## Claude Code — a different shape of problem

Claude Code has no comparable open cache defect. What it has instead is **volume**: roughly **70
changelog entries touch prompt caching**, and most are fixes for invalidation regressions rather than
features. A representative sample:

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

> [!IMPORTANT]
> The lesson is not "Claude Code is buggy." It is that **prefix stability decays** — in a product whose
> vendor treats cache hit rate as a production SLO and alerts on it. Measure your own hit rate rather
> than reasoning about it from documentation. That is what [`../measure/`](../measure/) is for.

---

## Version currency

| Harness | Latest observed | Note |
|---|---|---|
| Claude Code | **v2.1.267** | A disproportionate share of recent releases are prompt-cache fixes. If sessions feel expensive, upgrading likely beats any config change |
| VS Code | **v1.137** (2026-09-09) | Weekly releases since March 2026; v1.110 was the last monthly |
| Copilot CLI | **v1.0.81** (2026-08-27) | Separate implementation from the VS Code extension — conclusions do not transfer either way |

---

[Index](../README.md) · [Settings](SETTINGS.md) · [Timeline](../TIMELINE.md) · [Gaps](../GAPS.md)
