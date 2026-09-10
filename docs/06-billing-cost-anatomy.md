# 06 — Billing and cost anatomy

**Research date:** 2026-09-10. **Scope:** how each product converts token consumption into a bill, why
that conversion changed materially in 2026, and where the two are structurally incomparable.

---

## 0. TL;DR

1. **Copilot switched from premium requests to token-based AI credits on 2026-06-01.** Before that,
   cache hits were economically invisible to the buyer — a request cost one PRU whether the prefix was
   cached or not.
2. Post-switch, both products bill on the same four dimensions: input, **cached input**, **cache
   write**, output. Cached input is ~10% of input rate on both.
3. **1 AI credit = $0.01 USD.** Copilot's abstraction is a currency wrapper; Anthropic bills in dollars.
4. Per-request dollar cost on Copilot's *legacy* plans is still premium-request multipliers, not
   tokens — for those users, cache efficiency does not reach the bill at all.
5. A finding from building this repo's harness: **Claude Code's reported `total_cost_usd` is an
   API-key list-price figure, not what a subscription user pays.** Do not read it as your bill.

---

## 1. The 2026 pivot

Until 2026-06-01, GitHub Copilot billed in **premium requests** (PRUs): a fixed monthly allowance, a
per-model multiplier, and $0.04 per PRU in overage. A "request" could be a one-line chat question or a
multi-hour agentic session. GitHub's own framing on
[moving to usage-based billing, fetched 2026-09-10](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/)
is that the abstraction had stopped tracking cost.

**The consequence for this repo's subject matter is the important part.** Under PRUs, prompt caching
was invisible to the buyer. A cache hit and a cache miss cost the same one premium request. Caching
was purely a GitHub-side margin optimisation — which is a coherent reason for a vendor to invest in it
and *not* expose it to users.

Post-switch, cached tokens are a billed line item, and cache efficiency became a thing a Copilot
customer can care about. Much of the tooling gap documented in track 05 is explained by that ordering:
the telemetry was built when the economics did not require it.

## 2. The dimensions, side by side

| | Claude Code (Anthropic API) | Copilot (AI credits) |
|---|---|---|
| Unit | USD per million tokens | 1 credit = **$0.01 USD** |
| Input | 1.0× | 1.0× |
| **Cached input** | ~0.1× | **10% of input rate** |
| **Cache write** | 1.25× (5m TTL), 2.0× (1h TTL) | **+25% on input**, Anthropic and GPT-5.6/6; older OpenAI models **free** |
| Output | model rate | model rate |
| Code completions | n/a | **unbilled**, unlimited on paid plans |

Copilot figures from
[Models and pricing, fetched 2026-09-10](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing);
Anthropic's from [prompt caching pricing, fetched 2026-09-10](https://platform.claude.com/docs/en/build-with-claude/prompt-caching).

Note the near-identity of the cached-read multiplier. **The pricing of caching is not where these
products differ.** They differ in what they let you *do* about it and what they let you *see*.

A concrete instance of the ratio, from a model launch entry rather than a pricing page — Claude Fable
5.1 at **$10/$50 per Mtok with $0.25/Mtok cache reads**, i.e. cache reads at exactly 2.5% of the input
rate on that model
([CHANGELOG v2.1.257, fetched 2026-09-10](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md#21257)).
The "~10% of input" rule of thumb is a generalisation; **check the per-model rate**, because it varies
more than the shorthand suggests.

### 2.1 The one Copilot exposes that Anthropic does not

Copilot's table makes cache write a **model-dependent** property — older OpenAI models carry no cache
write cost at all. On those models caching is strictly free upside: you pay 1.0× to write and 0.1× to
read, so break-even is immediate rather than after one reuse. Anthropic charges a write premium on
every model.

## 3. Break-even arithmetic

Let *P* be the prefix size in tokens and *N* the number of turns reading it.

```text
uncached:        N · P · 1.0
cached, 5m TTL:  P · 1.25  +  (N−1) · P · 0.1
cached, 1h TTL:  P · 2.00  +  (N−1) · P · 0.1
```

| Turns over the prefix | Uncached | 5m TTL | 1h TTL |
|---:|---:|---:|---:|
| 1 | 1.00 | 1.25 | 2.00 |
| 2 | 2.00 | **1.35** | 2.10 |
| 3 | 3.00 | **1.45** | **2.20** |
| 10 | 10.00 | **2.15** | **2.90** |

Three readings:

- **5m TTL pays for itself on the second turn.** Any interactive session clears this trivially.
- **1h TTL needs three.** It is a bet on *idle gaps*, not on volume. Short bursty work that never idles
  past five minutes pays the higher write and never uses the longer life — a straight loss.
- **The asymptote is the real number.** At ten turns the cached session costs ~21% of the uncached one.
  This is why cache hit rate, not context size, is the lever that matters.

## 4. Where the comparison breaks down

**Legacy Copilot plans still bill in premium requests.** Annual Pro/Pro+ subscribers remain on the
legacy model until expiry. For those users there is no token price, so there is no per-request dollar
figure to compare — and cache efficiency cannot reach their bill at all. This is a **structural
incomparability**, not a measurement gap. No tooling closes it.

**Different tokenizers.** Comparing raw token counts across vendors is meaningless arithmetic. Anthropic
changed tokenizers within its own model line (Opus 4.7 tokenizes the same text to roughly 1.0–1.35× the
Opus 4.6 count), so even intra-vendor token comparisons across model generations need re-baselining.

**Consequence for this repo:** the only defensible cross-harness units are **cost per verified-completed
task** on an identical workload, and **cache-read ratio** as a within-harness efficiency metric. We do
not publish cross-vendor token deltas. See [`../METHODOLOGY.md`](../METHODOLOGY.md).

## 5. A finding from building the harness

Claude Code's `--output-format json` reports `total_cost_usd`. Measurement runs in this repo use
`--bare`, which strips hooks, LSP, plugin sync, auto-memory, and `CLAUDE.md` discovery for determinism —
and which **forces `ANTHROPIC_API_KEY`**. That is not an inference; it is what the flag was announced
as doing:

> `Added --bare flag for scripted -p calls — skips hooks, LSP, plugin sync, and skill directory walks;
> requires ANTHROPIC_API_KEY or an apiKeyHelper via --settings (OAuth and keychain auth disabled);
> auto-memory fully disabled`
> — [CHANGELOG v2.1.81, fetched 2026-09-10](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L4038)

That means the reported figure is an **API-key list-price cost**, not what a Pro or Max subscriber
pays. The number is real, but it answers "what would this have cost at API rates," not "what did this
cost me."

> [!WARNING]
> It follows that a subscription user reading `total_cost_usd` in any tooling is reading a notional
> figure. We flag it here because it is the kind of number that gets screenshotted into a cost comparison
> without the caveat attached.

## 6. Attribution

Covered in detail in [track 05 §4](05-telemetry.md); the billing-side summary:

- **Claude Code** emits `user.id`, `session.id`, `model`, and `type=cacheRead|cacheCreation` on the same
  metric data point, plus `claude_code.cost.usage` in USD. One query gives per-user, per-model,
  cache-aware spend, in real time.
- **Copilot** splits it: `ai_credits_used` per user (metrics API NDJSON, ~2-day lag, no token
  breakdown) and per-model token detail (billing AI usage report, no user dimension). **The two cannot
  be joined.**

For an organisation doing internal chargeback this is the single largest practical difference between
the products.

## 7. What actually moves the bill

Ranked, from everything in tracks 01–05:

1. **Cache hit rate.** At ten turns, cached costs ~21% of uncached. Nothing else is close.
2. **Avoiding mid-session invalidation.** One model switch deep in a long session costs a full
   uncached re-read of the entire history — often more than the turn that triggered it.
3. **Idle-gap management.** 5-minute TTL expiry mid-session is the silent killer; Claude Code's answer
   is the 1h TTL, Copilot's is OpenAI's 24h retention, and on Copilot's Anthropic path there is
   currently **no answer** (track 02 §3.3).
4. **Tool surface size.** Position-0 tokens, taxed every turn, with the largest invalidation radius.
5. **Compaction timing.** Fixed overhead; you choose when to pay it. Cold compaction is worst-case.
6. Model and effort selection — real, but dominated by the above in long agentic sessions.

## 8. What we could not determine

- Copilot's actual per-request cost on any plan — no seat available on the test machine, and `gh` lacked
  the `manage_billing:copilot` scope needed for the billing report or metrics API.
- Whether Copilot applies a margin between provider list price and its credit conversion.
- Anthropic subscription effective rates versus API list price.

See [`../GAPS.md`](../GAPS.md).

## Sources

- [GitHub: Copilot is moving to usage-based billing, fetched 2026-09-10](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/)
- [Models and pricing for GitHub Copilot, fetched 2026-09-10](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
- [Requests in GitHub Copilot (legacy), fetched 2026-09-10](https://docs.github.com/copilot/managing-copilot/monitoring-usage-and-entitlements/about-premium-requests)
- [Anthropic prompt caching pricing, fetched 2026-09-10](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [Anthropic pricing, fetched 2026-09-10](https://platform.claude.com/docs/en/about-claude/pricing)
- [Claude Code: costs, fetched 2026-09-10](https://code.claude.com/docs/en/costs)
- [Changelog: per-model token breakdown, fetched 2026-09-10](https://github.blog/changelog/2026-08-11-per-model-token-breakdown-in-the-usage-report/)

---

← [05 — Telemetry](05-telemetry.md) · [Index](../README.md) · [Synthesis](../SYNTHESIS.md) →
