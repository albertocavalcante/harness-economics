# 07 — Research context

**Research date:** 2026-09-10. **Scope:** the systems literature underneath prompt caching, the
cost-reduction techniques it competes and combines with, and what other harness vendors published
independently.

Tracks 01–06 describe what two vendors do. This one asks whether they had to.

> [!NOTE]
> **Academic sources sit on a different axis from the A–E scale in [`../TIMELINE.md`](../TIMELINE.md).**
> That scale grades *shipping* evidence — a paper is not a shipped artifact. A peer-reviewed result is
> a claim about what is **possible**; a changelog entry is a claim about what a vendor **did**. Both
> are cited here, kept separate, and never blended into one grade.

---

## 0. TL;DR

1. **Exact-prefix-match is a product decision, not a law.** Four independent lines of work reuse KV
   state at non-prefix positions. It costs accuracy or training — but it is not physics.
2. **The literature corroborates this repo's central claim, and one paper states the mechanism
   exactly**: token reduction correlates with cost reduction at **r = 0.15**, because cache reads
   already dominate input cost.
3. **Routing does *not* destroy cache locality.** This corrects an earlier claim of ours.
4. **Query-aware prompt compression *does* conflict with caching**, mechanically, and loses.
5. **Harness design moves cost as much as caching does** — because harness design is largely *how* you
   achieve a hit rate. One controlled study swapped only the orchestration layer for **−41% cost/task**.
6. The most useful published numbers in the field are **cache hit rates by harness**, and almost
   nobody publishes them.

---

## 1. Is the exact-prefix constraint fundamental?

The repo asserts throughout that caching is a prefix match on exact bytes. It never asked whether that
is a law of the technology. It is not.

**What is genuinely fundamental:** a token's KV vector is a function of every token before it. Causal
attention makes KV state context-dependent, so after an edit, later tokens genuinely have different
correct values. [Hydragen](https://arxiv.org/abs/2402.05099) shows the flip side — shared-prefix
attention decomposes and re-merges *exactly*, with no approximation. That is why prefix reuse is the
one form of reuse a vendor can offer with **zero quality caveat**.

**What is implementation:** the "any byte change invalidates everything after it" behaviour is a
chain-hash. vLLM's
[prefix caching design doc](https://docs.vllm.ai/en/latest/design/prefix_caching.html) states it
plainly — each block is keyed on *(parent block hash, this block's exact tokens, extra keys)* — so one
flipped token rewrites that block's hash and every descendant. [SGLang's
RadixAttention](https://arxiv.org/abs/2312.07104) does the same thing structurally, as longest-common-prefix
lookup in a radix tree.

**A whole literature exists to break it:**

| Work | Approach | Cost of relaxing exactness |
|---|---|---|
| [Prompt Cache](https://arxiv.org/abs/2311.04934) (MLSys 2024) | Reuse at non-prefix positions via a declared schema, position IDs preserved | Requires a per-application schema |
| [CacheBlend](https://arxiv.org/abs/2405.16444) | Reuse "regardless prefix or not", selectively recompute ~15% of tokens | Compute, on a tunable dial |
| [EPIC](https://arxiv.org/abs/2410.15332) (ICML 2025) | Recompute ~20 boundary tokens per chunk; up to 8× TTFT | Small fixed recompute |
| [Block-Attention](https://arxiv.org/abs/2409.15355) (ICLR 2025) | Blocks encode independently; needs block-mask fine-tuning | **Accuracy 67.9% → 48.0%** without fine-tuning, recovering to 68.4% after training |

EPIC names the constraint in the framing this repo needed: *"existing context caching requires exact
prefix matches across requests, limiting reuse cases."*

**The honest conclusion:** exact-prefix-match is the only reuse policy that is simultaneously *exact*,
*model-agnostic*, and *free of per-customer schema*. That makes it the correct default for a
multi-tenant API — not a law. The interesting question is not whether it could be relaxed, but **why no
vendor sells the relaxed version.**

Two findings suggest an answer beyond engineering cost. [Auditing Prompt
Caching](https://arxiv.org/abs/2502.07776) (ICML 2025) detected **global cross-user cache sharing at
seven API providers, including OpenAI**, via statistical timing tests — so sharing scope is a policy
dial. And [SpliceLeak](https://arxiv.org/abs/2606.21842) shows non-prefix fusion **widens** the timing
side channel rather than narrowing it. Relaxing exactness has a security price, not just an accuracy one.

## 2. Does the literature agree that caching dominates?

Broadly yes, in a scoped form — and the scoping makes the claim stronger.

**The mechanism paper.** [Token Reduction Is Not Cost
Reduction](https://arxiv.org/abs/2607.12161) measured, on SWE-bench Go, a Pearson **r = 0.15** between
token reduction and cost reduction. Its most aggressive compressor cut tool-output tokens by **38.4%
and increased billed cost by 6.8%**. The stated cause is exactly this repo's thesis: cache creation and
cache reads already dominate input cost, so only a thin slice is addressable — and perturbing it adds
turns, each re-transmitting the prefix.

**Corroboration from production.** [Inference Economics of Enterprise Coding
Agents](https://arxiv.org/abs/2607.13080) reports a **99.3% prompt-cache hit rate → $0.57 per 1M
tokens effective**. [Don't Break the Cache](https://arxiv.org/abs/2601.06007) measures **41–80% cost
reduction** across three providers over 500+ long-horizon sessions — and finds naive full-context
caching can *increase* latency.

**And from a vendor, independently.** Manus's [Context Engineering for AI
Agents](https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus)
(2025-07-18) opens with *"the KV-cache hit rate is the single most important metric for a
production-stage AI agent"*, reports an input:output ratio of roughly **100:1**, and notes that a
second-precision timestamp at the top of a system prompt *"kills your cache hit rate."*

### 2.1 Where the literature says something else matters as much

**Harness design.** [The Harness Effect](https://arxiv.org/abs/2607.06906) held models and tasks fixed,
swapped only the orchestration layer, and measured **−41% cost per task at quality parity** —
concluding *"the orchestration layer moved cost per task more than the full spread of the model menu
did."* This is the most direct precedent for what this repo is doing. Note the two are not rivals:
that paper's own mechanism families include **cache-shape discipline**. Harness design is largely *how*
a hit rate is achieved.

**A methodological correction we accept.** [Claw-SWE-Bench](https://arxiv.org/abs/2606.12344) states
it bluntly: *"cache hit rate is not a coding-capability metric… it is primarily a run-level and
billing-level diagnostic."* This repo's comparable unit is already cost-per-verified-task
([`../METHODOLOGY.md`](../METHODOLOGY.md) §3.5) — hit rate is the **explanatory variable**, not the finding.

## 3. What combines with caching, and what fights it

The question tracks 01–06 never asked.

### 3.1 Routing — complementary. We were wrong.

> [!IMPORTANT]
> **Correction.** We previously asserted that model routing destroys cache locality. Measured evidence
> says otherwise for an API consumer. LiteLLM's
> [production benchmark](https://docs.litellm.ai/blog/auto-router-prompt-caching-benchmark) found
> routing **+** caching was **37.4–68.7% cheaper than caching alone** on every dataset. Mechanism:
> caches are per-model, but a router's tier set is small and the TTL comfortably exceeds inter-turn
> latency, so **99.3% of the time a session returns to a model whose cache is still warm.** The
> measured failure mode is the opposite of the intuition — running the router *without* caching was
> ~4× more expensive than caching one fixed model.

It inverts only when flip frequency exceeds the TTL, or the tier count grows enough that per-tier
prefixes go cold. And **cache-blind** routing is genuinely catastrophic: Factory measured gateway-level
cache-blind routing at **2.12× baseline cost at turns 61–150 and 2.37× at 151–200**, against
**0.19–0.28×** for cache-aware in-harness routing — an order of magnitude from cache awareness alone.

### 3.2 Prompt compression — conflicting, and it loses

[Cache-Aware Prompt Compression](https://arxiv.org/abs/2607.15516) is the sharpest result here.
Query-aware compressors — the LLMLingua family — *"produce a different compressed prefix per query,
mechanically invalidating the prefix-strict cache on every call."* Measured on τ-bench retail:
query-aware compression came in at **+40.1% cost overhead versus vanilla**.

Two corollaries: [LLMLingua-2](https://arxiv.org/abs/2403.12968) is the exception because it is
explicitly *task-agnostic*, so its output is byte-stable and stays cacheable. And the compression
literature's cost models are systematically optimistic — CAPC measured real cache effectiveness at
**ρ ≈ 0.83**, against the ρ = 1.0 that prior work assumes in the baseline it beats.

### 3.3 Compaction — a necessity, not a lever

Compaction rewrites history, so it invalidates by construction. [TRACE](https://arxiv.org/abs/2608.06503)
adds that it degrades *execution*: compression *"weaken[s] the influence of recent interactions,
increasing blocked actions, repeated exploration, and instability"* — and FIFO, cheapest in tokens,
needs substantially more steps. **Treat compaction as a cost you defer, not one you avoid**, and place
the boundary so the stable prefix survives. OpenHands states the design rule directly: condense at
thresholds rather than continuously, to *"amortize rebuilding costs across multiple turns."*

### 3.4 Tool-schema compilation — the compression that helps

[TSCG](https://arxiv.org/abs/2605.04107) reports **52–57% token savings** with accuracy retained. It
helps rather than hurts precisely because compilation is *deterministic*: the compiled schema is
byte-stable, so it shrinks position 0 without destabilising it. If you adopt one compression technique
alongside caching, adopt this one.

## 4. What other harness vendors published

Tracks 01–06 cover two vendors. Six techniques were arrived at **independently** by teams that were not
coordinating — which is stronger evidence they are correct than any single vendor's advocacy.

| Convergent technique | Independently shipped by |
|---|---|
| Static prefix first, volatile content at the tail | Manus, OpenAI, Google, Cline, Deriv, Fireworks — near-identical wording. The closest thing to a law |
| **Mask tools, don't remove them** | Manus derived it from KV mechanics; OpenAI shipped it as `tool_choice: "none"` / `allowed_tools` |
| Deferred tool loading | Amp, Cursor, OpenAI, Factory — all within eight months; savings 15–47% |
| Compaction at a threshold, not continuously | OpenHands, Gemini CLI (50%), Amp (90%), Codex |
| Subagents as context isolation | Amp, Cognition, Cursor, Factory, Cline |
| **Cache-aware model routing** | Cursor, Factory, Cognition |

Two published numbers worth having:
[Cursor](https://cursor.com/blog/dynamic-context-discovery) measured **46.9% total agent token
reduction** from deferred MCP tool loading (A/B, statistically significant). Factory's
[Deferred Context Engine](https://factory.ai/news/deferred-context-engine) found ~330 MCP tools cost
~47K schema tokens, while **only 5.4% of sessions ever executed an MCP tool** — the clearest possible
argument for track 04's position-0 thesis.

### 4.1 The idea that goes further than Copilot's

Cognition's [Devin Fusion](https://cognition.com/blog/devin-fusion) (2026-06-29) runs two agents with
*"their own persistent, cached contexts"* and **schedules model switches to coincide with context
compaction, "which would trigger a cache miss anyway."**

This repo called Copilot's cache-boundary routing the idea most worth copying. Cognition took it a step
further: not merely *routing at* a boundary, but **manufacturing the boundary and hiding the switch
inside it.** Cache invalidation as a scheduling primitive.

### 4.2 Published cache hit rates — the rarest data in the field

Almost nobody publishes these. Every figure below is a vendor's own number, unreproduced by us.

| Source | Hit rate | Context |
|---|---:|---|
| [Requesty](https://requesty.ai/coding-agent-economy) gateway telemetry | **Claude Code 92%**, Kilo Code 46% | Platform-wide 86%. At 92% vs 46%, effective input cost differs **5.4×** |
| [Cline](https://cline.bot/blog/how-to-save-millions-by-self-hosting-llms) | 83.5% | Production; calls it *"the load-bearing one"* |
| [Deriv](https://derivai.substack.com/p/prompt-caching-production-ai-agent-costs) | 20% → **85.8%** | *"the expensive part was not what the prompt contained, it was where we put it"* |
| [ProjectDiscovery](https://projectdiscovery.io/blog/how-we-cut-llm-cost-with-prompt-caching) | 7% → 74% → **84%** | One task: **91.8% vs 3.2%** pre-fix, ~60× cost delta |
| [Mooncake](https://arxiv.org/abs/2407.00079) | **≤50% ceiling** | *"up to only 50% of the KVCache can be reused in our current workloads"* even with infinite storage — the credible pessimistic bound |

## 5. The counter-arguments

Stated because a survey that only finds supporting evidence is not a survey.

**The pricing may not reflect cost.** Martin Alderson's
[first-principles estimate](https://martinalderson.com/posts/are-openai-and-anthropic-really-losing-money-on-inference/)
puts input at ~$0.001–0.005/M against output at ~$3/M — a **~1000× asymmetry**, because prefill batches
while decode is one forward pass per token. If right, the 0.1× cached-read discount is a **margin
decision, not a cost pass-through**. This does not dispute that cache reads dominate the *bill*; it
disputes that the bill reflects cost. [Can I Buy Your KV Cache?](https://arxiv.org/abs/2606.13361)
reaches a compatible conclusion from the other direction — reuse is 9–50× cheaper in compute than
prefill, placing the 10% tariff inside a wide margin envelope.

**A large share of tokens is not cacheable.** [Concordia](https://arxiv.org/abs/2601.14470) (MSR 2026)
measured **53.9% input / 24.4% output / 21.6% reasoning** — roughly 46% uncacheable — with cost
concentrated in Code Review, where context changes every round.

**Caching can be negative-value.** [SqueezeBits](https://blog.squeezebits.com/vllm-vs-tensorrtllm-12-automatic-prefix-caching-38189)
measured automatic prefix caching at **−36.7% throughput and +25.0% TPOT** when there are no shared
prefixes. The lookup is not free.

**Sometimes you should discard a warm cache deliberately.** Cognition found review agents perform
better with *"completely clean context"* — trading a warm prefix for quality.

But the most rigorous measurement refutes the strong form of the objection.
[How Do AI Agents Spend Your Money?](https://arxiv.org/abs/2604.22750) (8 frontier models, 500
SWE-bench Verified instances, 4 runs each) states: *"Cache reads remain the dominant cost contributor
in every phase"* — because although output is priced ~80× higher per token, accumulated context volume
outweighs it in aggregate. Note this appears in the body, not the abstract.

## 6. What we could not verify

- `openai.com/index/*` returns **HTTP 403** to fetchers, killing three otherwise-citable OpenAI posts.
- The benchmark behind FrugalGPT's headline "up to 98% cost reduction" is **not named in its abstract**.
  By this repo's own standard that number is not yet usable.
- PROMPTPEEK's accuracy figures are not on the NDSS landing page we loaded.

See [`../GAPS.md`](../GAPS.md).

## Sources

Every arXiv ID above was verified by loading its abstract page on 2026-09-10. Key entry points:
[vLLM prefix caching design](https://docs.vllm.ai/en/latest/design/prefix_caching.html) ·
[SGLang / RadixAttention](https://arxiv.org/abs/2312.07104) ·
[Token Reduction Is Not Cost Reduction](https://arxiv.org/abs/2607.12161) ·
[The Harness Effect](https://arxiv.org/abs/2607.06906) ·
[Cache-Aware Prompt Compression](https://arxiv.org/abs/2607.15516) ·
[Auditing Prompt Caching](https://arxiv.org/abs/2502.07776) ·
[Manus: Context Engineering for AI Agents](https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus)

---

← [06 — Billing and cost anatomy](06-billing-cost-anatomy.md) · [Index](../README.md) · [Synthesis](../SYNTHESIS.md) →
