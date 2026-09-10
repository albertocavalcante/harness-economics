# Harness Economics

What agentic coding actually costs, and which architecture decisions drive it — a subsystem-by-subsystem
teardown of **Claude Code** and **GitHub Copilot**, with sourced claims and a reproducible measurement
harness.

This is not a feature comparison. It follows a single question down through six layers of both
products: when you send one message, what gets billed, and why? The answer turns out to be mostly about
prompt caching — which is why both vendors reorganised their entire request architecture around it.

**Compiled:** 2026-09-10 · ~15,000 words across 6 tracks · 81 inline citations · measurement harness
included

---

## Contents

- [Scope](#scope)
- [At a glance](#at-a-glance)
- [The tracks](#the-tracks)
- [Where they actually differ](#where-they-actually-differ)
- [Measure it yourself](#measure-it-yourself)
- [Conventions](#conventions)

## Scope

An evidence-based teardown, not a link list. It answers three questions:

1. **What is in the request?** How each harness assembles the payload it sends on every turn, and which
   structural decisions in that assembly determine cost.
2. **What does it cost, really?** Cache read/write pricing, break-even arithmetic, and the 2026 shift
   that made cache efficiency visible to Copilot buyers for the first time.
3. **Can you see any of it?** What each product's telemetry exposes, what it hides, and what neither
   will tell you.

Every capability claim carries a source URL and a fetch date. Every cost number is either cited or
produced by the harness in [`measure/`](measure/) and recorded in [`measurements/`](measurements/).
Anything that could not be verified is in [`GAPS.md`](GAPS.md) rather than estimated or omitted.

**One limitation stated up front:** no Copilot seat was available on the research machine, so **every
Copilot claim here is documentation-derived rather than observed.** The Claude Code claims include
direct verification against a local binary. See [`GAPS.md`](GAPS.md) §3.

**Out of scope:** code-completion quality, benchmark scores, IDE ergonomics, and any other harness
(Codex, Cursor, Gemini CLI). Those are different questions and this repo does not pretend to answer them.

## At a glance

- **Cache hit rate is the only cost lever that matters at scale.** At ten turns over the same prefix, a
  cached session costs ~21% of an uncached one. Everything else is a rounding error next to it.
- **Both vendors price caching almost identically** — reads at ~10% of input rate, writes at a premium.
  The products differ in *control* and *visibility*, not in price.
- **"Copilot has no telemetry" is false.** Both ship OpenTelemetry. Copilot's tracing is arguably the
  better design — GenAI semconv compliant, clean span hierarchy, subagent propagation.
- **Only Claude Code will tell you why the cache missed.** `likely cause: tool definitions changed` has
  no equivalent anywhere in Copilot, and it is the difference between a number and an action.
- **Only Claude Code gives you cache controls.** TTL per request bucket, per-model disable, a debugging
  override. Copilot exposes none.
- **Copilot has one lever Claude Code cannot match:** OpenAI's 24-hour cache retention, against
  Anthropic's one-hour maximum.
- **Copilot has one idea worth stealing:** cache-aware model routing — switching models only at
  boundaries where the prefix resets anyway.
- **Claude Code's cache is per-machine and per-directory.** Two worktrees of the same repo never share
  one. Most users do not know this.
- **For chargeback, Copilot's per-user and per-token data cannot be joined.** For an organisation this
  is a bigger practical difference than any caching detail.

## The tracks

| # | Document | Covers |
|---|---|---|
| 01 | [Request lifecycle](docs/01-request-lifecycle.md) | How each harness assembles a request; why position 0 is expensive |
| 02 | [Prompt caching](docs/02-prompt-caching.md) | Prefix matching, breakpoints, TTL, the full invalidation catalogue, cache scope |
| 03 | [Context management](docs/03-context-management.md) | Compaction cost, memory loading, `/rewind` vs `/compact`, image eviction |
| 04 | [Tool and MCP loading](docs/04-tool-and-mcp-loading.md) | Deferred loading, tool search, the silent MCP reconnect problem |
| 05 | [Telemetry](docs/05-telemetry.md) | OTel on both sides, miss-cause attribution, the chargeback join problem |
| 06 | [Billing and cost anatomy](docs/06-billing-cost-anatomy.md) | Premium requests → AI credits, break-even math, structural incomparabilities |

Cross-cutting conclusions are in [`SYNTHESIS.md`](SYNTHESIS.md). Method and its limits are in
[`METHODOLOGY.md`](METHODOLOGY.md). What could not be determined is in [`GAPS.md`](GAPS.md).

## Where they actually differ

Neither product wins outright.

| | Claude Code | Copilot |
|---|---|---|
| Cache read / write pricing | ~0.1× / 1.25×–2.0× | ~0.1× / +25% (free on older OpenAI models) |
| Max cache retention | 1 hour | **24 hours** (OpenAI path) |
| User-facing TTL control | ✅ per request bucket | ❌ none |
| Miss-cause attribution | ✅ | ❌ |
| Cost metric in USD | ✅ | ❌ credits, computed downstream |
| OTel GenAI semconv | ❌ bespoke namespace | ✅ |
| Trace hierarchy + subagent propagation | ⚠️ beta | ✅ |
| Cache-aware model routing | ❌ | ✅ |
| Per-user + per-token attribution joinable | ✅ same data point | ❌ two systems, no common key |
| Invalidation semantics documented | ✅ exhaustively | ❌ |
| Providers abstracted | 1 family | 6 |

The full argument for each row is in the tracks. The short version: **Claude Code built the better cost
instrumentation; Copilot built the better tracing model and solved a harder abstraction problem.**

## Measure it yourself

Every cost claim that is not a citation is reproducible:

```sh
just doctor          # environment preflight — reports what is and isn't available
just fixture         # generate the deterministic workload, print its hash
just measure-cache   # cold and warm cache-hit-rate and token mix
just measure-mcp     # what attaching an MCP server actually costs, A/B interleaved
just record FILE     # validate, leak-check, and promote a run into measurements/
```

The workload is a **generated** synthetic codebase, pinned by hash — hermetic, no network, byte-identical
on any machine. Tasks are read-only and **verified against an expected answer**, because an agent that
gives up early produces a flatteringly low cost number and an unverified harness would average that in
silently.

Two things to know before reading any number the harness produces: runs use `--bare`, so reported cost
is **API list price, not a subscription bill**; and the fixture is synthetic, so cross-run comparisons
are valid while absolute figures are not a prediction for your codebase. Both are expanded in
[`METHODOLOGY.md`](METHODOLOGY.md) §3.

The Copilot arm is **documented-manual** ([`measure/copilot/SETUP.md`](measure/copilot/SETUP.md)) rather
than an automated recipe — it needs a paid seat and GUI configuration, and automating it would promise a
reproducibility this environment cannot honour.

## Conventions

**Sources are mandatory.** Every capability claim carries a URL and a fetch date.

**Measured or cited, never asserted.** A number is either backed by a citation or by a file in
`measurements/`.

**Vendor claims are labelled as vendor claims.** Where a figure comes from a vendor's own blog and could
not be reproduced, the text says so at the point of use.

**Negative findings are results.** "This cannot be measured, and here is why" belongs in `GAPS.md`, not
in a silence.

**Prices and products drift faster than research.** Both ship weekly. Treat any uncited number as
suspect and re-fetch before relying on it.

**No personal paths or credentials.** Enforced mechanically.

```sh
just          # run all checks
just check    # leaks + links + sources + measurement validation
just stats    # word and citation counts per document
```

Local hooks are managed with [Lefthook](https://lefthook.dev); commit subjects follow
[Conventional Commits](https://www.conventionalcommits.org). See [`CONTRIBUTING.md`](CONTRIBUTING.md).

Licensed [CC0 1.0](LICENSE) — public domain. Corrections and reproductions are welcome, especially from
anyone with a Copilot seat who can convert [`GAPS.md`](GAPS.md) §3 from documented to observed.
