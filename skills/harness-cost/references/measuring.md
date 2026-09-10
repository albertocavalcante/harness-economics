# Measuring — which fields lie, and when

The most expensive mistake in cost work is optimising against a broken instrument.
Check this page **before** trusting a number, not after.

## The field-name trap

| | Anthropic | Copilot |
|---|---|---|
| `input_tokens` | **excludes** cached tokens | **includes** cached tokens |
| Correct total | `input + cache_read + cache_creation` | `input_tokens` alone |

A GitHub maintainer, [`copilot-sdk#1160`][sdk1160], 2026-04-30:

> *"**Input tokens is the total covering all kinds of input, including cached.**
> Similarly output tokens is the total covering all kinds of output, including
> reasoning."*

> [!CAUTION]
> `input_tokens + cache_read_tokens` is **correct arithmetic for Anthropic and
> double-counting for Copilot.** The field names are identical; the semantics are
> inverted. A formula ported between vendors inflates or deflates the total **without
> erroring**.

## Zero is not evidence of zero

Several Copilot paths report a hardcoded or unread zero. A broken meter reads as
perfect frugality — which is the failure mode most likely to produce a confidently
wrong conclusion.

| # | What reads zero | Window |
|---|---|---|
| [#309207][i309207] | `ExtensionContributedChatEndpoint` **hardcoded** `{prompt_tokens: 0, cached_tokens: 0}` for every non-Copilot provider | before VS Code **1.120.0** |
| [#308370][i308370] | OpenAI/CustomOAI BYOK never reads `prompt_tokens_details.cached_tokens`. Maintainer's own eval: **282 instances, all 0% cached** | **still open** |
| [`copilot-sdk#613`][sdk613] | Anthropic BYOK response mapper never maps `cache_read_input_tokens`. Opened with a **$400-in-one-hour** burn | closed as backlog trim |

**If you measure cache-hit rate on an OpenAI-compatible BYOK path today, you will
conclude caching is broken when it may be working perfectly.**

## The meter was wrong in both directions at once

- [#331438][i331438] — subagent credits **double-counted** in turn telemetry until
  **1.135.0**: *"summing `billedNanoAiu` across events double-counted nested usage."*
- [#323424][i323424] — the session hover was **missing** subagent credits until
  **1.131.0**.

Same underlying spend, over-reported in one surface and under-reported in another,
fixed four versions apart. **Never cross-compare a pre-1.131 hover with post-1.135
telemetry.**

## Structural under-reporting that is still live

- **Cancelled turns.** Maintainer, verbatim: *"there are still unflushed credits from
  the proxy that we aren't including here."* If your harness cancels on timeout, your
  cost floor is fiction.
- **Cache writes are absent from Copilot's debug log.** `main.jsonl` carries
  `cachedTokens` (read) but not `cacheCreationTokens` ([#329657][i329657]). Writes
  bill at 1.25×–2.0×, so **any cost model built on those logs structurally
  underestimates** — and does so worst on the cache-thrashing sessions you most want
  to measure.
- **OTel metrics omit cached input tokens**; only traces carry them ([#317837][i317837]).
  A Prometheus/Grafana pipeline literally cannot compute hit rate. **Parse traces,
  not metrics.**

## A live contradiction, unresolved

Two maintainers disagree on whether Copilot bills cache writes:

> **lramos15**, [#319403][i319403]: *"Hovering each model in the model picker will give
> you the cost … broken down by input, output, and cache read tokens. **We eat the
> cost of cache writes.**"*

> **bhavyaus**, maintainer-authored P0 COGS issue [#322775][i322775]: *"**5-minute TTL
> (default): cache write = 1.25× base input. 1-hour TTL (extended): cache write =
> 2.0× base input.**"*

This repo does not assert either. **If you are modelling Copilot cost, this is the
single most load-bearing unknown.**

## Rules that fall out

1. **Never compare cost across VS Code versions.** The meter changed at 1.120, 1.121,
   1.125, 1.128, 1.129, 1.131, 1.135, 1.137.
2. **Never compare across auth modes.** BYOK and subscription are different code paths
   with different cache behaviour inside one binary.
3. **Check your telemetry's date.** Before 2026-05-20 (CLI v1.0.51) cache reporting is
   unreliable; before 2026-06-23 (v1.0.64) the OTel attribute *names* were
   non-conforming.
4. **Verify a fix shipped.** Issues have been closed by bot, by "offline discussion",
   and by declaring the billing model obsolete. A closed issue is not a fix.
5. **Prefer a byte diff to a counter.** Every cache bug is "bytes moved that shouldn't
   have." Claude Code's `OTEL_LOG_RAW_API_BODIES` and Copilot's Cache Explorer both
   show you the bytes; counters only show you the consequence.

## Comparable units

Raw token counts are not comparable across vendors — different tokenizers, and
Anthropic re-tokenized within its own model line (Opus 4.7 produces roughly 1.0–1.35×
the Opus 4.6 count for the same text). The only defensible units:

- **Cost per verified-completed task** on an identical workload, cross-harness
- **Cache-read ratio**, as a within-harness efficiency metric

See [`METHODOLOGY.md`](../../../METHODOLOGY.md).

[sdk1160]: https://github.com/github/copilot-sdk/issues/1160
[sdk613]: https://github.com/github/copilot-sdk/issues/613
[i309207]: https://github.com/microsoft/vscode/issues/309207
[i308370]: https://github.com/microsoft/vscode/issues/308370
[i331438]: https://github.com/microsoft/vscode/pull/331438
[i323424]: https://github.com/microsoft/vscode/issues/323424
[i329657]: https://github.com/microsoft/vscode/issues/329657
[i317837]: https://github.com/microsoft/vscode/issues/317837
[i319403]: https://github.com/microsoft/vscode/issues/319403
[i322775]: https://github.com/microsoft/vscode/issues/322775
