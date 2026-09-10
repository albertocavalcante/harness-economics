# Synthesis

Conclusions that span more than one track. No URLs here by design — every claim below is cited at the
point it is established, in `docs/01` through `docs/06`.

---

## 1. The ten findings that matter

**1. Cache hit rate is the only cost lever that matters at scale.** At ten turns over the same prefix,
a cached session costs roughly 21% of an uncached one. Model choice, effort level, and context size are
all real levers, and all of them are dominated by this one in any session long enough to be called
agentic.

**2. The two products price caching almost identically.** Cached reads are ~10% of input rate on both.
Cache writes carry a premium on both. **Caching economics is not where these products differ** — they
differ in what you can do about it and what you can see.

**3. Copilot's caching was invisible to buyers until June 2026.** Under premium-request billing, a
cache hit and a cache miss cost the same one request. Caching was a vendor-side margin optimisation
with no customer-facing consequence. That ordering explains most of the tooling gap: the telemetry was
built in an era when the economics did not require exposing it.

**4. "Claude Code has OTel, Copilot doesn't" is false, and the real asymmetry is more interesting.**
Both ship OpenTelemetry. Copilot's *tracing* is arguably better — it follows the GenAI semantic
conventions, models the agent run with a clean span hierarchy, and propagates context into subagents,
while Claude Code's tracing is still beta in a bespoke namespace. Claude Code wins decisively on
*cost* instrumentation: USD-denominated cost metrics, an in-product cache panel, raw request-body
capture, and miss-cause attribution that nothing else offers.

**5. Only one product will tell you *why* the cache missed.** Claude Code names the likely cause. This
is the difference between observing a number and being able to act on it, and it is the single most
useful cache feature in either product.

**6. Only one product gives you control you can find.** Claude Code: TTL per request bucket, per-model
disable, a force-5-minute debugging override — all documented. Copilot ships exactly one cache control,
`longToolCallCachePreservation`, and it is **experimental, default-off, and absent from every release
note**; the user who most needed it found it by accident two months after it shipped. The difference is
less "control vs no control" than **documented vs discoverable-by-luck**.

**7. Copilot's 24-hour retention is the claim we had to retract.** An earlier edition called it the
largest cache lever either product had shipped. It rests on **one sentence in one blog post** — no
release note, no PR, no changelog entry anywhere in VS Code v1.107–v1.138 or the CLI changelog. The
architectural asymmetry is real (Anthropic caps at 1h; OpenAI's parameter allows 24h). The claim that
Copilot operationalised it is not evidenced. Meanwhile Copilot's **Anthropic** path has never shipped
even a 1-hour TTL: its checkpoint type carries no lifetime field, and production data shows only the
1.25× cache-write price, never the 2× that a 1-hour tier would produce.

**8. Copilot has one architectural idea Claude Code lacks entirely: cache-aware model routing.**
Treating "which model" as a scheduling decision constrained to cache boundaries — turn one, and after
compaction — rather than a free-form user toggle. Claude Code merely *warns* before a mid-session
switch. Routing at a boundary where the prefix resets anyway is strictly better, and it is the one
idea in this teardown most worth copying.

**9. For chargeback, Copilot's data cannot be joined.** Per-user spend and per-token detail live in two
different systems with no common key. You can know a user spent 412 credits, or that a model consumed
N cached tokens org-wide, but never that a specific user's spend was cache-inefficient. Claude Code
emits both dimensions on the same data point. For an organisation this is a larger practical difference
than any caching detail.

**10. Claude Code's cache is scoped far more narrowly than users assume.** Per machine, per directory —
two worktrees of the same repository never share. Anyone running parallel agents across worktrees is
paying full cold-start cost on each, and there is no warning that it is happening.

## 2. So which one is cheaper?

The first question every reader has. The honest answer is **not yet answerable**, and this section
exists to say exactly why, and what *is* answerable.

### 2.1 Why the aggregate claim cannot be made

**No measurements have been taken.** This repo ships a harness before its first results. Every cost
statement in it is a citation or arithmetic, never an observation.

**The largest cost driver is invisible on one side.** System prompt plus tool definitions sit at
position 0 and are re-sent every turn. Copilot's are closed, and its spans carry no prompt content. You
cannot compare total harness cost when the biggest single input cannot be measured on one side.

**The only published hit rate belongs to Copilot.** VS Code 1.118 states ">93% of each request is
reused from cache." Anthropic publishes **no** figure — it says it alerts on the metric and stops
there. The single hard efficiency number in existence favours Copilot and has nothing to be compared
against.

**Cross-vendor token counts are meaningless** — different tokenizers. And on legacy Copilot plans there
is no token price at all, so no per-request dollar figure exists on that side to compare.

> [!IMPORTANT]
> "Copilot is more expensive" is not even one claim. **Copilot CLI and the VS Code extension are
> separate implementations** with different caching maturity — the CLI only gained `cache_control`
> breakpoints in v1.0.78 (2026-08-03). Any comparison has to name which one it means.

### 2.2 The one directional claim that survives

> **For work with idle gaps beyond ~5 minutes, on Copilot's Anthropic path, Copilot carries a cost
> exposure whose only remedy is undocumented, off by default, and narrowly scoped — while Claude
> Code's remedy for the same scenario is a documented setting.**

> [!NOTE]
> **Narrowed 2026-09-10.** This previously read "no user remedy," which contradicted
> [track 02 §3.3](docs/02-prompt-caching.md) in this same repo: `longToolCallCachePreservation`
> shipped in VS Code 1.123. It is a real remedy — but it is scoped to `execution_subagent` calls,
> sends **3 probes maximum, every 4 minutes**, has no release note, and is off by default. The
> asymmetry survives; the absolute claim did not.

| Evidence | Grade |
|---|:--:|
| 300 s idle → **32%** of prefix rewritten; 330 s → **100%** | production data, `copilot-cli#3808` |
| Copilot's `CacheControlCheckpoint` carries **no lifetime field**; only the 1.25× cache-write price ever appears, never 2× ⇒ the 1-hour tier has never been exercised | same |
| Claude Code ships `promptCacheTtl: "1h"`, documented, default-on within subscription usage | **A** — v2.1.243 |
| Copilot's own keep-alive benchmark: **$29.26 with the fix vs $39.61 without** | **B** — PR #316277 |

That last row is the closest thing to a quantified answer anyone has published: **roughly a quarter of
session cost**, from fixing one cache issue. The fix is experimental, default-off, and has no
release-note coverage — so most users are on the $39.61 side of it without knowing the setting exists.

### 2.3 What cuts the other way

Claude Code carries cost exposures Copilot does not, and omitting them would make this section
advocacy rather than analysis:

- **Cache is scoped per machine *and per directory*.** Two worktrees of the same repository never share
  one. Fan agents across worktrees and you pay cold-start on every one, with no warning.
- **Subagents default to five minutes even on a subscription**, unless the second TTL bucket is set.
- **Resuming a long session after an upgrade is the most expensive request in the product** — new
  system prompt, entire history behind it, zero hits.
- **No cache-aware model routing.** Copilot re-routes only where the prefix resets anyway; Claude Code
  warns and lets you absorb the miss.
- **~70 changelog entries fixing cache-invalidation regressions**, still landing in v2.1.267.

### 2.4 What would settle it

Cost per verified-completed task on an identical workload, both harnesses pinned to the same model,
run cold and warm — which is what [`measure/`](measure/) is built for. Two confounds survive even
then: the vendor system prompts (closed on one side) and turn-count non-determinism.

Until that exists, the defensible position is **narrow claims with evidence, not a verdict**.

## 3. Where each product is genuinely ahead

Neither product wins outright, and a comparison that concludes otherwise is not looking hard enough.

**Claude Code is ahead on:** cache observability and diagnosis; user control over cache behaviour;
documented invalidation semantics; per-MCP-server cost attribution; USD-denominated cost; chargeback
attribution; treating hit rate as a production SLO with alerting.

**Copilot is ahead on:** OTel standards alignment; trace structure and subagent propagation; maximum
cache retention on its OpenAI path; cache-aware model routing; and solving a materially harder
engineering problem — a caching abstraction over two incompatible provider paradigms.

**Neither is ahead on:** cache pricing, which is near-identical; or server-side transparency, where
both publish the contract and neither publishes the implementation.

## 4. The asymmetry that shapes both designs

Claude Code targets one provider family and can therefore design *for* the cache contract: plan mode as
a tool rather than a tool-set swap, deferred loading that preserves block ordering, compaction that
reuses the parent prefix. Every one of those is a product decision made to protect a prefix.

Copilot targets six providers which, when its architecture was built, spanned two incompatible caching
paradigms — explicit breakpoints and automatic prefix inference. **That gap has since closed:** OpenAI
shipped explicit caching with GPT-5.6 on 2026-07-09, with the same four-breakpoint budget and the same
1.25× / 0.1× economics as Anthropic. The abstraction problem was real when Copilot solved it and is
now substantially smaller — a fact that makes the design look prescient rather than over-engineered,
but which this document overstated in earlier editions.

It could not design for a contract it did not control, so it invested instead
in things that hold regardless of provider: deferring schemas out of the prefix entirely, compacting at
points where the prefix resets anyway, and routing only at those boundaries.

The resulting products are not better-and-worse versions of each other. They are different answers to
different constraints, and reading either as a feature-parity race misses what is actually going on.

## 5. Corrections to things commonly said

| Commonly said | Actually |
|---|---|
| "Copilot has no telemetry" | It ships OTel with GenAI semconv compliance, and its trace model is arguably better designed than Claude Code's |
| "Prompt caching saves ~90%" | Cache *reads* cost ~10%. Cache *writes* cost 25–100% **more** than uncached input. Net saving depends entirely on reuse count |
| "Longer TTL is strictly better" | The 1-hour TTL doubles the write cost. On bursty work that never idles past five minutes it is a straight loss |
| "Newer models cache better" | The minimum cacheable prefix is not monotonic. A 3k-token prefix caches on Opus 5 and silently does not on Haiku 4.5 |
| "Compaction saves money" | Afterwards, yes. The event itself is a cost, and doing it cold is the worst case |
| "Editing CLAUDE.md fixes behaviour mid-session" | It is inert until reload — which is also why it is cache-safe |
| "Adding an MCP server is cheap" | Free when tool search defers it; a full re-read of the entire conversation when it does not |
| "Claude Code's reported cost is my bill" | It is API list price. Under `--bare` it is explicitly not a subscription figure |

## 6. What would change these conclusions

Stated up front so a reader can judge how durable this is.

**A Copilot cache-diagnosis surface.** Finding 5 is the widest single gap. If GitHub shipped miss-cause
attribution, most of the observability argument narrows to standards alignment, where Copilot already
leads.

**Anthropic shipping a retention tier beyond one hour.** Finding 7 disappears.

**Cache-aware routing in Claude Code.** Finding 8 disappears, and it is the most likely of these to
happen because the mechanism is already understood.

**Copilot joining its billing and usage datasets.** Finding 9 disappears — this is a data-plumbing
problem, not an architectural one.

**A resolution to the 5-minute gap issue.** If GitHub ships a keepalive or exposes retention on the
Anthropic path, one of the sharpest practical differences goes away.

Three of those five are small changes. This document has a short half-life and says so.

## 7. If you only change one thing

> [!TIP]
> Measure your own cache hit rate before optimising anything else. Both products will tell you the two
> numbers that matter — tokens read from cache, tokens written to cache — and the ratio between them
> answers more than any comparison table, including this one.

A session that shows high cache *creation* turn after turn is not an expensive model problem. It is a
prefix-stability problem, and it is almost always caused by something small and fixable: a model
switched mid-task, an MCP server reconnecting, a gateway stripping cache markers, or a worktree that
never shared a cache with its sibling in the first place.
