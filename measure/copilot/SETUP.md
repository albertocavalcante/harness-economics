# Measuring GitHub Copilot

**This path is documented-manual, not an automated `just` recipe.** It requires a paid Copilot seat and
GUI configuration in VS Code, so wrapping it in a recipe would promise a reproducibility this repo
cannot honour. The Claude Code path is automated; this one is a procedure you run.

**Status as of 2026-09-10:** not executed. No Copilot seat was available on the research machine, so
every Copilot claim in `docs/` is documentation-derived rather than observed. Converting this from
documented to observed is the top item in [`../../GAPS.md`](../../GAPS.md) §9.

---

## What you can measure

| Signal | Source | Comparable to Claude Code? |
|---|---|---|
| `gen_ai.usage.cache_read.input_tokens` | span attribute on `chat` / `invoke_agent` | ✅ same meaning as `cacheRead` |
| `gen_ai.usage.cache_creation.input_tokens` | span attribute | ✅ same meaning as `cacheCreation` |
| `gen_ai.usage.input_tokens` / `output_tokens` | span attribute | ⚠️ different tokenizer — ratios only |
| `gen_ai.client.token.usage` | histogram metric | ✅ for within-harness trends |
| `copilot_chat.tool.call.count` | counter | ✅ roughly `claude_code.tool.execution` |
| `copilot_chat.agent.invocation.duration` | histogram | ✅ |

## What you cannot measure, at any effort

- **Per-request dollar cost.** On legacy plans Copilot bills premium requests with per-model
  multipliers, not tokens. There is no token price to compute against. This is structural, not a
  tooling gap.
- **System prompt and tool-definition byte counts.** Closed, and the spans carry no prompt content.
- **Cache miss cause.** No equivalent to Claude Code's `likely cause:` exists.
- **Per-user token attribution.** `ai_credits_used` (metrics API) has no token breakdown; the billing
  report has tokens but no user dimension. The two cannot be joined.

## Procedure

### 1. Start a collector

```sh
just collector-up      # podman, staged under /private/tmp/harness-econ/collector
```

The collector writes received spans as JSON lines to
`/private/tmp/harness-econ/collector/spans.jsonl`. It is **disk-gated** — it refuses to start below a
free-space threshold, because a full disk is a known trigger for a wedged podman VM.

If you would rather not run a container, any OTLP/HTTP receiver on `localhost:4318` works. The
collector config is [`../collector/otelcol.yaml`](../collector/otelcol.yaml).

### 2. Configure VS Code

In `settings.json`:

```json
{
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "otlp-http",
  "github.copilot.chat.otel.otlpEndpoint": "http://localhost:4318",
  "github.copilot.chat.otel.captureContent": false
}
```

Leave `captureContent` **off**. It emits prompt text, which is a privacy liability and is not needed
for token accounting. Environment overrides `COPILOT_OTEL_ENABLED` and `OTEL_EXPORTER_OTLP_ENDPOINT`
also work.

### 3. Run the same workload

```sh
just fixture           # generates the identical deterministic workload
```

Open the generated fixture directory in VS Code, then run the tasks from
[`../fixture/tasks/`](../fixture/tasks/) through Copilot agent mode, **one task per fresh chat session**.

Two things to hold constant if you want the comparison to mean anything:

- **Same task text**, copied verbatim from the task file.
- **Same cache mode.** For `warm`, run repetitions back to back and discard the first. For `cold`,
  leave ≥ 6 minutes between repetitions so the provider TTL expires.

Verify each answer against the `EXPECTED:` line in the task file, exactly as the Claude Code runner
does. A run that produced the wrong answer is not a cheaper run — it is a different run, and averaging
it in is how a harness produces confident numbers that mean nothing.

### 4. Parse

```sh
uv run --locked python -m measure.copilot.parse_spans \
  /private/tmp/harness-econ/collector/spans.jsonl \
  --surface copilot-vscode
```

`--surface` is mandatory and is not guessable from the spans. The VS Code extension, the CLI and the
SDK have reported different numbers for the same spend, so a record that does not name one is not
comparable to anything. Valid values: `copilot-vscode`, `copilot-cli`, `copilot-sdk`.

Prints per-span token totals and an aggregate cache-read share, then writes a schema-validated
measurement JSON to `/private/tmp/harness-econ/runs/`. Promote it with `just record <file>` after
reviewing it.

Two outputs deserve attention before you trust the run:

- **`parent spans (excl.)`** — `invoke_agent` rollups already contain their children, so they are
  counted and never summed. Adding both double-counts every nested call.
- **`cache read share: n/a`** — the meter was silent on at least one span, so no share is reported at
  all. That is not a cache miss and must not be read as a cheap run; several Copilot paths never
  populate these attributes ([known issues](../../reference/KNOWN-ISSUES.md)).

### 5. Stop

```sh
just collector-down
```

## Confounds you cannot remove

State these alongside any number this procedure produces:

1. **Different underlying model.** Unless you pin Copilot to a Claude model, you are comparing
   different models as well as different harnesses.
2. **Different system prompt and tool set** — the largest single cost driver, vendor-controlled on both
   sides, and closed on Copilot's.
3. **Editor-injected context.** VS Code adds open-editor and selection context that has no Claude Code
   CLI equivalent.
4. **Human-in-the-loop timing.** Manual operation means variable idle gaps, which interact directly
   with cache TTL. This is the biggest threat to a `warm`-mode comparison and the reason the Claude
   Code runner automates its timing.
5. **Turn-count non-determinism.** Both harnesses vary run to run; only the verifier and a decent
   repetition count control for it.

Because of (5) and the tokenizer difference, **report cost-per-verified-task and cache-read ratio, never
raw cross-vendor token deltas.** See [`../../METHODOLOGY.md`](../../METHODOLOGY.md) §3.5.
