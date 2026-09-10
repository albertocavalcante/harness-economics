# Harness Economics

**What agentic coding actually costs, and which architecture decisions drive it.** A
subsystem-by-subsystem teardown of **Claude Code** and **GitHub Copilot**, with every claim
evidence-graded and a measurement harness you can run yourself.

**Compiled:** 2026-09-10 · ~25,300 words across 7 tracks · 193 inline citations · CC0

> [!WARNING]
> **No Copilot seat was available on the research machine, so every Copilot claim here is
> documentation-derived rather than observed.** Claude Code claims include direct verification against a
> local binary. This is the largest limitation of the current edition — stated here rather than buried.
> Details and the path to closing it: [`GAPS.md` §3](GAPS.md).

---

## The one idea everything else follows from

A model remembers nothing between turns, so a harness re-sends the entire conversation on every
request. Your bill is set by **what fraction of that payload can be served from cache** — and caching
is a prefix match on exact bytes, so a change anywhere invalidates everything after it.

```mermaid
flowchart TD
    A["1 · TOOLS — tool definitions<br/>changes on: MCP connect, plugin, deny rule"]
    B["2 · SYSTEM — core instructions<br/>changes on: harness upgrade, output style"]
    C["3 · PROJECT CONTEXT — CLAUDE.md, memory<br/>changes on: session start, /clear, /compact"]
    D["4 · CONVERSATION — messages, tool results<br/>changes on: every turn, append-only"]
    A --> B --> C --> D
    A -. "a byte changed here<br/>invalidates all of this" .-> D

    style A fill:#fde2e2,stroke:#c33
    style B fill:#fdeee2,stroke:#c83
    style C fill:#fdf9e2,stroke:#aa3
    style D fill:#e6f5e6,stroke:#3a3
```

Volatility increases downward; blast radius decreases. **The cheapest place for changing content is the
bottom, the most expensive is the top.** Both vendors reorganised their request architecture around
that single fact — which is why this is a caching teardown rather than a feature comparison.

And here is what that costs you, turn by turn:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/turn-cost-anatomy-dark.svg">
  <img alt="Four agent turns as horizontal bars. Turn 1 is a cold start billed as a cache write. Turns 2 and 3 grow by appending, with the unchanged prefix served from cache at roughly a tenth of the input rate. On turn 4 the model is switched, so the entire conversation is reprocessed as uncached input at full price." src="assets/turn-cost-anatomy.svg" width="760">
</picture>

The turn that triggers a miss is not the expensive one. **Every turn after it pays to rebuild the
prefix**, and that cost scales with how long the session already is — which is why a model switch feels
free and then quietly is not.

## Start here

| If you want… | Go to |
|---|---|
| The short answer on **which is cheaper** | [`SYNTHESIS.md` §2](SYNTHESIS.md) |
| To look up **a setting** | [`reference/SETTINGS.md`](reference/SETTINGS.md) |
| To check **a known bug or its workaround** | [`reference/KNOWN-ISSUES.md`](reference/KNOWN-ISSUES.md) |
| **When a feature shipped**, with a link | [`TIMELINE.md`](TIMELINE.md) |
| The **full argument**, subsystem by subsystem | [the seven tracks](#the-seven-tracks) |
| To **run the measurements** | [Measure it yourself](#measure-it-yourself) |
| What we **could not determine** | [`GAPS.md`](GAPS.md) |

> [!NOTE]
> **"So which one is cheaper?"** — [`SYNTHESIS.md` §2](SYNTHESIS.md) answers it head-on. Short version:
> **not yet answerable.** No measurements have been taken, and the biggest cost driver — the vendor
> system prompt — is closed on Copilot's side. Exactly one directional claim survives the evidence, and
> it is narrow. That section also lists what cuts the *other* way, because a comparison that only finds
> fault with one side is advocacy.

## Five findings

The full set of ten is in [`SYNTHESIS.md` §1](SYNTHESIS.md).

| Finding | Why it matters | Source |
|---|---|---|
| **Cache hit rate is the only cost lever that matters at scale** | At ten turns over one prefix, a cached session costs **~21%** of an uncached one | [arithmetic][t06] over [Anthropic pricing][api-cache] |
| **Both vendors price caching almost identically** | Reads ~10% of input, writes at a premium, on both. They differ in **control and visibility**, not price | [Anthropic][api-cache] · [GitHub][gh-pricing] |
| **"Copilot has no telemetry" is false** | Both ship OpenTelemetry. Copilot's *tracing* is arguably the better design — GenAI semconv, clean spans, subagent propagation | [VS Code 1.119][vsc-1119] · [Claude Code][cc-monitor] |
| **Only Claude Code tells you *why* the cache missed** | `likely cause: tool definitions changed`. The difference between a number and an action | [CHANGELOG v2.1.260][cc-260] |
| **Claude Code's cache is per-machine *and per-directory*** | Two worktrees of the same repo never share one. Most users do not know this | [Claude Code docs][cc-cache] |

## Where they actually differ

Neither product wins outright: **Claude Code leads 5 of 8 capabilities, Copilot 3** — and they lead on
different *kinds* of thing, which matters more than the tally.

### Observability — a split decision

| Capability | Claude Code | Copilot |
|---|---|---|
| Tells you **why** the cache missed | ✅ [v2.1.260][cc-260] | ❌ no equivalent found |
| Cost metric denominated in **USD** | ✅ `claude_code.cost.usage` [↗][cc-monitor] | ❌ credits, computed downstream [↗][gh-pricing] |
| Per-user **and** per-token attribution joinable | ✅ same data point [↗][cc-monitor] | ❌ two systems, no common key — [metrics API][gh-metrics] vs [billing report][gh-tokens] |
| OTel **GenAI semantic conventions** | ❌ bespoke `claude_code.*` [↗][cc-monitor] | ✅ [VS Code 1.119][vsc-1119] |
| Trace hierarchy + subagent propagation | ⚠️ beta [↗][cc-monitor] | ✅ [VS Code 1.119][vsc-1119] |

**Claude Code owns cost instrumentation; Copilot owns standards-compliant tracing.** Standardising
dashboards across many tools? Copilot's shape fits better. Working out why a bill is high? Only Claude
Code will tell you.

### Cache control — Claude Code, with one exception

| Capability | Claude Code | Copilot |
|---|---|---|
| User-facing TTL control | ✅ per request bucket — [`promptCacheTtl`][cc-cache], [v2.1.243][cc-243] | ❌ none; one undocumented keep-alive setting [PR #316277][vsc-keepalive] |
| Invalidation semantics documented | ✅ exhaustive catalogue [↗][cc-cache] | ❌ nothing published |
| **Cache-aware model routing** | ❌ warns only [↗][cc-cache] | ✅ [changelog 2026-05-20][gh-routing] |

That last row is the idea in this teardown most worth copying: Copilot re-routes models **only at
boundaries where the prefix resets anyway** — turn one, and after compaction. Claude Code merely warns
you and lets you absorb the miss.

### The numbers — not a scoreboard

Values, not wins. Forcing these into ✅/❌ is what made the original single table unreadable.

| Dimension | Claude Code | Copilot |
|---|---|---|
| Cache **read** price | ~0.1× input [↗][api-cache] | 10% of input [↗][gh-pricing] |
| Cache **write** price | 1.25× at 5m TTL, 2.0× at 1h [↗][api-cache] | +25% on input; **free** on older OpenAI models [↗][gh-pricing] |
| **Max cache retention** | **1 hour** — [API docs][api-cache], selectable via [`promptCacheTtl`][cc-cache] since [v2.1.243][cc-243] | **5 minutes** on the Anthropic path — its checkpoint type carries no lifetime field, and production data shows only the 1.25× write price, never the 2× a 1h tier would produce [↗][cli-3808]. The 24h OpenAI claim rests on [one blog sentence][vsc-blog] with no release note behind it — graded **D** in [`TIMELINE.md`](TIMELINE.md) |
| Providers abstracted | 1 family [↗][cc-cache] | **6** — OpenAI, Anthropic, Google, Microsoft, xAI, Moonshot [↗][gh-pricing] |

That last row excuses much of the rest: **Copilot solved a harder problem** — at the time, two
incompatible caching paradigms behind one interface — and paid for it in the controls it can expose.

> [!IMPORTANT]
> That framing is now partly historical. OpenAI shipped **explicit** caching with GPT-5.6 on
> 2026-07-09 — caller-placed breakpoints, max 4, writes 1.25×, reads 0.1× — the same shape and the same
> numbers as Anthropic. The paradigms converged. Corrected in [track 02 §2](docs/02-prompt-caching.md).

The full argument for every row is in [the seven tracks](#the-seven-tracks).

## The seven tracks

| # | Document | Covers |
|---|---|---|
| 01 | [Request lifecycle](docs/01-request-lifecycle.md) | How each harness assembles a request; why position 0 is expensive |
| 02 | [Prompt caching](docs/02-prompt-caching.md) | Prefix matching, breakpoints, TTL, the invalidation catalogue, cache scope |
| 03 | [Context management](docs/03-context-management.md) | Compaction cost, memory loading, `/rewind` vs `/compact`, image eviction |
| 04 | [Tool and MCP loading](docs/04-tool-and-mcp-loading.md) | Deferred loading, tool search, the silent MCP reconnect problem |
| 05 | [Telemetry](docs/05-telemetry.md) | OTel on both sides, miss-cause attribution, the chargeback join problem |
| 06 | [Billing and cost anatomy](docs/06-billing-cost-anatomy.md) | Premium requests → AI credits, break-even math, structural incomparabilities |
| 07 | [Research context](docs/07-research-context.md) | Is exact-prefix a law? What the literature says dominates, what fights caching, what other vendors published |

## How claims are graded

Every capability is anchored to a dated shipping artifact, not a docs page asserting "requires vX".

| Grade | Means | Example |
|:--:|---|---|
| **A** | Vendor changelog entry or release note | `promptCacheTtl` in Claude Code v2.1.243 |
| **B** | Merged PR, **never got a release note** | `longToolCallCachePreservation`, VS Code 1.123 |
| **C** | Maintainer comment, no linked commit | `copilot-sdk#1073`'s fix — closed, unauditable |
| **D** | Vendor blog only, no shipping artifact | `prompt_cache_retention: "24h"` |
| **E** | User report, unreproduced | vscode#321551's cost multipliers |

> [!IMPORTANT]
> Applying that scale honestly **downgraded two of this repo's own claims**, including a headline
> finding. The retractions are documented in [`GAPS.md` §7b](GAPS.md) rather than quietly edited out — a
> teardown that never visibly corrects itself is not being checked.

## Measure it yourself

Every cost claim that is not a citation is reproducible:

```sh
just doctor          # environment preflight — reports what is and isn't available
just fixture         # generate the deterministic workload, print its hash
just measure-cache   # cold and warm cache-hit-rate and token mix
just measure-mcp     # what attaching an MCP server actually costs, A/B interleaved
just record FILE     # validate, leak-check, and promote a run into measurements/
```

The workload is a **generated** synthetic codebase pinned by hash — hermetic, no network,
byte-identical on any machine. Tasks are read-only and **verified against an expected answer**, because
an agent that gives up early produces a flatteringly low cost number and an unverified harness would
average that in silently.

> [!CAUTION]
> Two things to know before trusting any number the harness prints. Runs use `--bare`, which forces an
> API key — so reported cost is **API list price, not a subscription bill**. And the fixture is
> synthetic, so cross-run comparisons are valid while absolute figures are **not** a prediction for your
> codebase. Both expanded in [`METHODOLOGY.md` §3](METHODOLOGY.md).

The Copilot arm is [**documented-manual**](measure/copilot/SETUP.md), not an automated recipe — it needs
a paid seat and GUI configuration, and automating it would promise a reproducibility this environment
cannot honour.

## Conventions

| Rule | |
|---|---|
| **Sources are mandatory** | Every capability claim carries a URL and a fetch date |
| **Measured or cited, never asserted** | A number is backed by a citation or a file in `measurements/` |
| **Vendor claims are labelled as such** | Where a figure comes from a vendor blog and was not reproduced, the text says so at the point of use |
| **Negative findings are results** | "This cannot be measured, and here is why" belongs in `GAPS.md`, not in a silence |
| **Prices drift faster than research** | Both products ship weekly. Treat any uncited number as suspect and re-fetch |
| **No personal paths or credentials** | Enforced mechanically by `just leaks` |

```sh
just          # run all checks
just check    # leaks + links + sources + measurements + lint + fmt-check
just lint     # shellcheck every shell script
just fmt      # shfmt every shell script in place
just stats    # word and citation counts per document
```

> [!NOTE]
> These gates run locally via Lefthook, **not** in CI. A pull request from a fork will not run them —
> run `just check` before opening one, and expect a maintainer to run it on your branch.

Local hooks via [Lefthook](https://lefthook.dev); commits follow
[Conventional Commits](https://www.conventionalcommits.org). See [`CONTRIBUTING.md`](CONTRIBUTING.md).

Licensed [CC0 1.0](LICENSE) — public domain. **Corrections and reproductions are welcome**, especially
from anyone with a Copilot seat who can convert [`GAPS.md` §3](GAPS.md) from documented to observed.

<!-- Every factual cell in the tables above resolves through one of these.
     `just refs` fails the build if a reference is used but not defined, or defined but unused. -->

[api-cache]: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
[cc-cache]: https://code.claude.com/docs/en/prompt-caching
[cc-monitor]: https://code.claude.com/docs/en/monitoring-usage
[cc-243]: https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L656
[cc-260]: https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L193
[gh-pricing]: https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing
[gh-metrics]: https://docs.github.com/en/copilot/reference/copilot-usage-metrics/copilot-usage-metrics
[gh-tokens]: https://github.blog/changelog/2026-08-11-per-model-token-breakdown-in-the-usage-report/
[gh-routing]: https://github.blog/changelog/2026-05-20-auto-model-selection-now-routes-based-on-your-task-in-vs-code/
[vsc-1119]: https://code.visualstudio.com/updates/v1_119
[vsc-blog]: https://code.visualstudio.com/blogs/2026/06/17/improving-token-efficiency-in-github-copilot
[vsc-keepalive]: https://github.com/microsoft/vscode/pull/316277
[cli-3808]: https://github.com/github/copilot-cli/issues/3808
[t06]: docs/06-billing-cost-anatomy.md
