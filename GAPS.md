# Gaps and open questions

What this repo could not determine, why, and what it would take to close each item. Negative findings
are first-class results here: "this cannot be measured" is an answer, and in several cases it is the
most useful answer in the document.

**Confidence legend, used throughout:**

- **High** — primary vendor documentation, or verified directly against a local binary.
- **Medium** — credible secondary source, or a vendor claim we have no way to reproduce.
- **Low** — single-sourced, contested, or a user report we could not replicate.

---

## 1. Feature-flag and version uncertainty

| Item | Confidence | Status |
|---|---|---|
| Claude Code miss-cause attribution (`likely cause: …`) | Medium | **Unresolved** |

Anthropic documents this as requiring Claude Code v2.1.260+. The binary available for this research was
**v2.1.220**, on which the emitter appears to be present but gated behind a feature flag that defaults
off and — unlike neighbouring flags — exposes no environment-variable override.

We therefore cannot distinguish between three possibilities: the documented version floor is sufficient
on its own; the feature additionally requires server-side enablement; or the gate was removed between
2.1.220 and 2.1.260. **Track 05 §1.3 states the caveat rather than picking one.**

*To close:* install v2.1.260+ and check whether `/usage` reports a cause after a deliberate
invalidation (e.g. a mid-session `/model` switch).

## 2. Claude Code TTL controls on newer versions

| Item | Confidence | Status |
|---|---|---|
| `promptCacheTtl` / `subagentPromptCacheTtl` absent in v2.1.220 | **High** | Verified |
| Their behaviour on v2.1.242+ | Medium | Documented, not observed |

We confirmed directly that these settings do not exist in the v2.1.220 binary — they are not merely
undocumented there. Their documented behaviour on v2.1.242+ is taken from Anthropic's docs and has not
been observed by us. The six-level precedence order in track 02 §3.1 is likewise documentation-derived.

*To close:* upgrade and confirm via `claude -p "hello" --output-format json`, reading which of
`ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` is populated.

## 3. GitHub Copilot — no access on the research machine

| Item | Confidence | Status |
|---|---|---|
| Copilot CLI | **High** | Not installed |
| Copilot VS Code extension | **High** | Not installed |
| Billing AI usage report | **High** | Inaccessible — token lacked `manage_billing:copilot` |
| Copilot usage metrics API | **High** | Inaccessible — same scope gap |

**Every Copilot claim in this repo is documentation-derived, not observed.** The OTel field names in
track 05 §2.1 come from VS Code's published documentation; we did not see a span. The pricing in track
06 comes from GitHub's published rate table; we did not see an invoice.

This is the single largest limitation of the current edition and it is stated in the README rather
than buried here.

*To close:* a paid Copilot seat, the VS Code extension, a local OTLP collector, and a token carrying
`manage_billing:copilot`.

## 4. Closed by the vendor — cannot be measured from outside

These are not access problems. No amount of tooling closes them.

| Item | Confidence | Why |
|---|---|---|
| Copilot system prompt byte count | **High** (that it's closed) | Not published; spans carry no prompt content |
| Copilot tool-definition byte count | **High** | Same |
| Copilot's full cache-invalidation catalogue | **High** | Not published. Only three behaviours are inferable from GitHub's own posts |
| Copilot compaction threshold and trigger policy | **High** | Not published |
| Copilot core-toolset membership and deferral threshold | **High** | Not published |
| Whether Copilot applies a margin on provider list price | **High** | Not published |

Anthropic publishes an exhaustive invalidation catalogue and Claude Code's system prompt composition.
GitHub publishes neither. **That asymmetry in disclosure is itself a finding** — a user can reason
about Claude Code's cache behaviour from documentation and cannot do the same for Copilot.

## 5. Server-side internals — closed by both vendors

| Item | Confidence |
|---|---|
| Real cache eviction policy | **High** (that it's closed) |
| Exact TTL clock semantics beyond "resets on hit" | High |
| Cross-session and cross-user cache sharing within an org | High |
| Whether cache storage is per-region | High |

Both vendors document the cache *contract* and neither documents the *implementation*. Everything in
track 02 is behavioural, inferred from the contract and from observed token counters.

## 6. Structural incomparabilities — not gaps

Listed separately because they will never be closed and should not be read as todo items.

**Legacy Copilot plans bill in premium requests, not tokens.** Annual Pro/Pro+ subscribers remain on
per-model multipliers until expiry. There is no token price, therefore no per-request dollar figure to
compare against Claude Code. Cache efficiency does not reach those users' bills at all.

**Different tokenizers.** Cross-vendor raw token comparison is meaningless arithmetic. Anthropic
changed tokenizers within its own line (Opus 4.7 tokenizes the same text to ~1.0–1.35× the Opus 4.6
count), so even intra-vendor comparison across generations needs re-baselining. This repo publishes
cost-per-verified-task and cache-read ratio, never cross-vendor token deltas.

**Vendor-controlled system prompts.** The largest single cost driver in both products is a payload
neither of us controls and either vendor can change without notice. Any measured figure is a
point-in-time observation of a moving target.

## 7. Third-party figures we did not reproduce

| Claim | Source | Confidence |
|---|---|---|
| Cache expires on >5 min gaps mid-session; 3–5× on that turn, 8–15× cumulative | [microsoft/vscode#321551](https://github.com/microsoft/vscode/issues/321551) | **Low** — one user report, open issue, no vendor confirmation |
| ~94% cache hit rate on Copilot's Anthropic path | [VS Code blog](https://code.visualstudio.com/blogs/2026/06/17/improving-token-efficiency-in-github-copilot) | Medium — vendor-reported, methodology not published |
| +919% / +338% / +279% hit-rate gain from 24h retention | Same | Medium — vendor-reported |
| 11–18% token reduction from tool search | Same | Medium — vendor-reported |

The vscode#321551 numbers are the weakest thing cited anywhere in this repo and track 02 §3.3 labels
them as such inline. The *mechanism* is not in doubt; the magnitude is one reporter's estimate.

Anthropic publishes **no** cache hit rate figure at all, stating only that it alerts on the metric. So
there is no vendor-to-vendor comparison available on the headline number, in either direction.

## 8. Our own measurement limits

**Measured cost is API list price, not a subscription bill.** The harness runs `--bare` for
determinism, which forces `ANTHROPIC_API_KEY`. `total_cost_usd` therefore answers "what would this cost
at API rates," not "what did this cost me." Track 06 §5.

**Synthetic fixture, not a real repository.** The workload is a generated codebase — hermetic and
byte-identical across machines, but not representative of a real repo's file-size distribution, import
graph, or the way a real task fans out. Cross-run comparisons are valid; absolute figures are not a
prediction of your codebase.

**Single machine, single network.** No cross-region or cross-account variance is captured.

**Claude Code only.** The Copilot arm of the harness is documented-manual (`measure/copilot/SETUP.md`),
not automated, because automating it would promise a reproducibility the environment cannot honour.

## 9. Follow-up queue, ranked

1. Obtain a Copilot seat and run the OTel path — converts §3 from documentation-derived to observed,
   and is the highest-value single change available to this repo.
2. Upgrade Claude Code past v2.1.260 and resolve §1 and §2.
3. Add a real-repository workload mode alongside the synthetic fixture.
4. Attempt to reproduce vscode#321551 with a controlled idle gap.
5. Measure compaction overhead directly via `claude_code.compaction` and its `trigger` attribute.
6. Per-MCP-server cost attribution using `mcp_server.name` across a realistic server set.
