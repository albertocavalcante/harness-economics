# Methodology

How this teardown was produced, what rules governed it, and where the method is weak.

---

## 1. Structure

Six track documents, each scoped to one subsystem that moves the token bill. The ordering is causal
rather than alphabetical — each track depends on the one before it.

| Track | Subsystem | Why it costs money |
|---|---|---|
| 01 | Request lifecycle | Determines what is in the prefix at all |
| 02 | Prompt caching | Determines what fraction of the prefix is billed at 10% vs 100% |
| 03 | Context management | Determines when the prefix is destroyed and rebuilt |
| 04 | Tool and MCP loading | Determines the size and volatility of position 0 |
| 05 | Telemetry | Determines whether you can see any of the above |
| 06 | Billing and cost anatomy | Converts all of it into a bill |

[`SYNTHESIS.md`](SYNTHESIS.md) carries conclusions that span tracks and contains no URLs by design —
citations live in the tracks.

## 2. Sourcing rules

Applied uniformly:

1. **Every capability claim carries a source URL and a fetch date**, in the form
   `[Vendor docs, fetched YYYY-MM-DD](https://…)`. A claim without a date is treated as unusable.
2. **Every cost or performance number is either cited or measured.** Measured numbers link to a file
   in [`measurements/`](measurements/) produced by the harness in [`measure/`](measure/).
3. **Vendor claims are labelled as vendor claims.** Where a figure comes from a vendor's own blog post
   and we could not reproduce it, the text says so at the point of use, not only in `GAPS.md`.
4. **Nothing unverifiable is asserted.** Items that could not be confirmed move to
   [`GAPS.md`](GAPS.md) with the reason. They are not silently omitted and they are not estimated.
5. **Negative findings are reported.** "This cannot be measured, and here is why" is a result.
6. **Asymmetry is disclosed.** Anthropic documents far more of Claude Code's internals than GitHub
   documents of Copilot's. Where a comparison is one-sided because of that, the text says so rather
   than implying the undocumented side behaves worse.

## 3. Measurement protocol

The part that distinguishes this repo from a documentation summary. Full detail in
[`measure/`](measure/); the design rationale is here.

### 3.1 Deterministic workload

The fixture is **generated, not cloned**. A seeded generator emits a synthetic codebase into
`/private/tmp/harness-econ/fixture/`, pinned by a sha256 over the sorted file tree. This is hermetic
(no network), carries no third-party licensing into a public repo, is byte-identical on any machine,
and costs effectively nothing in disk.

Tasks are **read-only and verified**. Each ships an expected answer and is checked after every
repetition. This is load-bearing rather than fussy: an agent that gives up after two turns produces a
flatteringly *low* cost number, so an unverified harness averages cost across runs that did different
amounts of work — which is the most likely way a repo like this ships confident numbers that mean
nothing. Failed repetitions are retained in the output, marked `valid: false`, excluded from
aggregates, and the **invalid-rep rate is reported as a headline field**.

### 3.2 Controlling the cache

The 5-minute TTL means two repetitions 30 seconds apart are not the same experiment. Two modes, both
reported:

- **cold** — sleep past the TTL between repetitions. Slow, and the only honest cold-start figure.
- **warm** — back to back, with the first repetition discarded as a priming run.

### 3.3 Isolating one variable

`measure/claude/ab.py` runs the same task set under two configurations **interleaved ABAB, not
AAABBB**, and reports the paired difference with a bootstrap interval. Interleaving is what protects
against server-side cache drift and provider load varying over the run window; a blocked design would
confound those with the variable under test.

**The bootstrap is seeded, and the seed is recorded in the measurement.** Any published interval can
therefore be re-derived exactly by rerunning with the same `--seed` over the same differences. This
was not true of the original shell implementation, which used `awk`'s bare `srand()` — drawn from
wall-clock seconds, so intervals differed between runs and were coincidentally *identical* for two
runs inside the same second. The second property is the more dangerous: a quick rerun could read as
independent confirmation. Any interval this repo published before 2026-09-10 is not reproducible, and
none were.

### 3.4 Determinism flags

Runs use `--bare`, which strips hooks, LSP, plugin sync, auto-memory, and `CLAUDE.md` discovery —
removing most uncontrolled inputs.

> [!WARNING]
> **The consequence must be stated wherever the number appears:** `--bare` forces `ANTHROPIC_API_KEY`,
> so the reported `total_cost_usd` is an API-key list-price figure, **not** what a subscription user
> pays. It answers "what would this have cost at API rates." This is itself a finding, in track 06 §5.

### 3.5 The comparable unit

**Cost per verified-completed task** on an identical workload, plus **cache-read ratio** as a
within-harness efficiency metric.

Explicitly **not** raw token counts across vendors: different tokenizers make that arithmetic
meaningless, and legacy Copilot plans have no token price at all. See [`GAPS.md`](GAPS.md) §6.

### 3.6 Fail loud

Every measurement recipe runs a preflight and **refuses to execute** in a degraded environment rather
than emitting a number from it. A script that quietly produces a figure under the wrong conditions is
worse than one that will not run.

## 4. Source hierarchy

In descending order of trust, as used:

1. **Direct verification against a local binary** — the strongest evidence here, and the basis for the
   corrections in [`CHANGELOG.md`](CHANGELOG.md).
2. **Vendor product documentation** — Anthropic's Claude Code docs, GitHub and VS Code docs. Primary
   for capability claims and pricing.
3. **Vendor engineering posts** — used for design rationale and for vendor-reported metrics, always
   labelled as vendor-reported.
4. **Vendor changelogs and public issue trackers** — used for dated facts about what shipped when, and
   for what is acknowledged as broken.
5. **Our own measurements** — authoritative for the specific workload measured, not generalisable.
6. **Community discussion and user-filed issues** — used to locate primary sources and to establish
   that a problem is reported, **never as a source of magnitude**. The vscode#321551 cost multipliers
   are cited under this rule and labelled Low confidence.

## 5. Known method limits

**One side is documented, the other is not.** Anthropic publishes Claude Code's request layering,
invalidation catalogue, and cache scope. GitHub publishes none of the equivalents. This produces an
unavoidable asymmetry: the Claude Code sections are deeper because there is more to cite, not because
the product is better instrumented in every respect — track 05 finds the opposite on tracing.

**No Copilot access.** No seat, no extension, no billing scope on the research machine. Every Copilot
claim is documentation-derived. This is the largest limitation of this edition. See [`GAPS.md`](GAPS.md) §3.

**Synthetic workload.** Hermetic and reproducible, but not representative of a real repository's file
distribution or task fan-out. Cross-run comparison is valid; absolute figures are not a prediction for
your codebase.

**Point-in-time.** Everything is true as of the compile date in the README. Both products ship weekly.
Pricing pages in particular drift faster than research: treat any *uncited* number as suspect and
re-fetch before relying on it.

**Single compiler.** One author produced both the tracks and the synthesis, so the *ranking* and
*emphasis* in [`SYNTHESIS.md`](SYNTHESIS.md) reflect one editorial judgment even where the underlying
track claims are independently sourced.

**Vendor-controlled variables.** The largest cost driver in both products — the system prompt — is
outside our control and changes without notice. Every measurement is an observation of a moving target.

## 6. Reproducing or extending

```sh
just doctor          # environment preflight; reports what is and isn't available
just fixture         # materialize the deterministic workload, print its hash
just measure-cache   # cold and warm cache-hit-rate and token mix
just record FILE     # validate, leak-check, and promote a run into measurements/
just check           # leaks + links + sources + measurement validation
```

- Track documents are self-contained; extending one does not require touching the others.
- New findings go in the relevant `docs/NN-*.md`, then `SYNTHESIS.md` if a headline changes.
- When closing a gap, remove the item from `GAPS.md` **in the same commit** that adds the sourced or
  measured claim.
- Raw API bodies never enter the repository. Staging is `/private/tmp/harness-econ/`.
