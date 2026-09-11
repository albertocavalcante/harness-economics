# Gaps and open questions

What this repo could not determine, why, and what it would take to close each item. Negative findings
are first-class results here: "this cannot be measured" is an answer, and in several cases it is the
most useful answer in the document.

**Confidence legend, used throughout:**

- **High** — primary vendor documentation, or verified directly against a local binary.
- **Medium** — credible secondary source, or a vendor claim we have no way to reproduce.
- **Low** — single-sourced, contested, or a user report we could not replicate.

---

## 1. Metric names with no public evidence

| Item | Confidence | Status |
|---|---|---|
| `claude_code.compaction`, `.mcp.rpc`, `.subagent.spawn`, `.tool.execution` | **Low** | **Unconfirmed — do not build on these** |

These four names appear in string inspection of the v2.1.220 binary. They appear **nowhere** in
Anthropic's telemetry documentation, and nowhere in the changelog through v2.1.267 — which *does*
announce comparable metrics (`claude_code.llm_request` and `.active_time.total` at v2.1.139,
`claude_code.tool` spans at v2.1.145, `.assistant_response` at v2.1.193).

A string in a binary establishes that the name exists in the artifact. It does not establish that the
metric is emitted, that it is enabled by default, or what its attributes are. The `trigger: auto|manual`
and `message_count` attributes cited in track 03 §2.6 rest on the same weak basis.

*To close:* run a session against a local OTLP collector and see whether they appear.

### 1b. Miss-cause attribution — mostly resolved

The version floor is now **confirmed by the changelog**, not just the docs — v2.1.260:
`Added a likely cause for prompt-cache misses (e.g. tool definitions or system prompt changed, idle
past the TTL) to /cost and the status line's prompt_cache field`.

What remains open: on the v2.1.220 binary the emitter appears present but gated behind a flag that
defaults off with no environment-variable override. We could not test v2.1.260+, so we cannot say
whether the version bump alone is sufficient or whether server-side enablement is also required.

## 2. TTL controls — evidence now split

| Item | Confidence | Status |
|---|---|---|
| `promptCacheTtl` / `subagentPromptCacheTtl` shipped in **v2.1.243** | **High** | Changelog-confirmed |
| Absent from v2.1.220 | **High** | Verified against the binary |
| `CLAUDE_CODE_{,SUBAGENT_}PROMPT_CACHE_TTL` env vars | **Low** | Documented, **never announced** |
| The six-level precedence order (track 02 §3.1) | Medium | Documentation-derived only |

**Anthropic's documentation is off by one on this.** It says the settings require v2.1.242. The
changelog places them in **v2.1.243**, and **there is no v2.1.242 section at all** — the file skips
from 2.1.241 to 2.1.243. We verified this directly rather than taking it second-hand. Either the docs
are wrong or 2.1.242 was pulled before release; we cannot tell which.

The two environment variables are the weaker claim: **zero occurrences in the changelog**. They may
work exactly as documented, but they shipped silently and we have not exercised them.

## 2b. Docs and changelog disagree on output styles

Track 02 §4.1 lists output-style switching as cache-relevant, sourced to the docs page, which describes
mid-session switching applying from v2.1.251. The changelog points the **other way**:

- v2.1.73 — `Deprecated /output-style command — use /config instead. Output style is now fixed at
  session start for better prompt caching`
- v2.1.238 — `Fixed custom, project, and plugin output styles drifting back to the default voice
  mid-session`

There is no v2.1.251 output-style entry; we read the whole section. We have not reconciled this and do
not assert either version. Treat the output-style row in that table as the least reliable line in it.

## 2c. Fable 5.1's cache-read rate does not match the rule of thumb

v2.1.257 announces Claude Fable 5.1 at `$10/$50 per Mtok with $0.25/Mtok cache reads` — that is **2.5%
of the input rate, not the ~10% this repo quotes as the general multiplier**. We verified the line
verbatim. We cannot explain the deviation: it may be a per-model pricing decision, an introductory
rate, or a changelog error. Track 06 §2 cites it and flags that per-model rates must be checked rather
than assumed.

## 3. GitHub Copilot — no access on the research machine

| Item | Confidence | Status |
|---|---|---|
| Copilot CLI | **High** | Not installed |
| Copilot VS Code extension | **High** | Not installed |
| Billing AI usage report | **High** | Inaccessible — token lacked `manage_billing:copilot` |
| Copilot usage metrics API | **High** | Inaccessible — same scope gap |

> [!WARNING]
> **Every Copilot claim in this repo is documentation-derived, not observed.** The OTel field names in
> track 05 §2.1 come from VS Code's published documentation; we did not see a span. The pricing in
> track 06 comes from GitHub's published rate table; we did not see an invoice.

This is the single largest limitation of the current edition and it is stated in the README rather
than buried here.

*To close:* a paid Copilot seat, the VS Code extension, a local OTLP collector, and a token carrying
`manage_billing:copilot`.

## 4. Closed by the vendor — cannot be measured from outside

These are not access problems. No amount of tooling closes them.

| Item | Confidence | Why |
|---|---|---|
| ~~Copilot system prompt byte count~~ | **Retracted 2026-09-11** | **Measurable, not closed — see below** |
| ~~Copilot tool-definition byte count~~ | **Retracted 2026-09-11** | **Measurable, not closed — see below** |
| Copilot's full cache-invalidation catalogue | **High** | Not published. Only three behaviours are inferable from GitHub's own posts |
| Copilot compaction threshold and trigger policy | **High** | Not published |
| Copilot core-toolset membership and deferral threshold | **High** | Not published |
| Whether Copilot applies a margin on provider list price | **High** | Not published |

> [!WARNING]
> **Two rows retracted on 2026-09-11.** We asserted Copilot's system prompt and tool-definition byte
> counts were unmeasurable because *"spans carry no prompt content"*. That is false when content
> capture is enabled. `github.copilot.chat.otel.captureContent` (VS Code) and
> `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` (CLI) populate
> **`gen_ai.system_instructions`** and **`gen_ai.tool.definitions`** — which *are* the system prompt
> and the tool block. Both default to `false`, so the data is opt-in rather than absent.
>
> These are therefore **§3 items (need a Copilot seat)**, not §4 items (closed by the vendor). The
> distinction matters: §4 says no tooling closes it, and tooling does.
>
> Three open defects mean the flag is not a reliable privacy control either — content has been
> observed exporting with `captureContent=false`
> ([vscode#307407](https://github.com/microsoft/vscode/issues/307407),
> [#326254](https://github.com/microsoft/vscode/issues/326254)), and tool arguments and results are
> reported to export **unconditionally**
> ([#325720](https://github.com/microsoft/vscode/issues/325720)). Anyone enabling Copilot telemetry
> should assume prompt content may leave the machine regardless of the setting.

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

Superseded in detail by [`TIMELINE.md`](TIMELINE.md) §3, which grades every claim **A–E**. Summary:

| Claim | Grade | Note |
|---|---|---|
| 3–5× / 8–15× cost from mid-session cache expiry | **E** | One user report on an open issue, no vendor confirmation. The *mechanism* is now independently quantified (idle-gap table, track 02 §3.3); the *magnitude* is not |
| >93% cache reuse on Copilot's Anthropic path | **A** | VS Code 1.118 release note. Prefer it to the blog's ~94% |
| +919% / +338% / +279% from 24h retention | **D** | Blog only — and so is the claim that Copilot sets `prompt_cache_retention` at all |
| 11–18% (blog) vs up to 20% (release note) from tool search | A / D | Both vendor-reported; they measure different things. Cite the release note |
| `longToolCallCachePreservation` benchmark ($29.26 vs $39.61) | **B** | Merged PR body. No release note exists for the feature at all |
| `cache_control` default-on in Copilot CLI v1.0.78 | **C** | Maintainer comment only; zero hits in the CLI changelog |

Anthropic publishes **no** cache hit rate figure, stating only that it alerts on the metric — so **no
vendor-to-vendor hit-rate comparison exists in either direction**, and any that appears elsewhere is
comparing a Copilot number against nothing.

### 7b. Claims this repo retracted

Recorded rather than silently edited, because a teardown that never visibly corrects itself is not
being checked:

1. **"Copilot's 24-hour retention is the single largest cache lever either product has shipped."**
   Downgraded to grade D. No release note, PR, or changelog entry anywhere in VS Code v1.107–v1.138 or
   the CLI changelog.
2. **"Copilot exposes no setting that would let a user work around mid-session expiry."** False.
   `longToolCallCachePreservation` shipped in VS Code 1.123 — undocumented and default-off, but real.
3. **"Copilot CLI has no prompt caching."** False since v1.0.78 (2026-08-03).
4. **"Whether users can invoke Copilot's compaction manually is undocumented."** False — VS Code 1.110
   documents `/compact`.
5. **Four Claude Code metrics described as "verified present."** Downgraded to unconfirmed (§1).

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
