# Settings quick reference

Every cache- and telemetry-relevant setting in both harnesses, with the version that shipped it and an
evidence grade from [`../TIMELINE.md`](../TIMELINE.md) §3.

**Grades:** **A** changelog or release note · **B** merged PR, no release note · **C** maintainer
statement only · **D** vendor blog only.

> [!IMPORTANT]
> A grade is about **how well we can prove it shipped**, not how well it works. A grade-D setting may
> be perfectly functional — we just cannot show you where it was announced.

---

## Claude Code — prompt cache

| Setting / variable | Effect | Default | Shipped | Grade |
|---|---|---|---|:--:|
| `promptCacheTtl` | Main-conversation TTL: `5m` or `1h` | see below | 2.1.243 | **A** |
| `subagentPromptCacheTtl` | TTL for everything else (subagents, workflows, compaction, titles) | `5m` | 2.1.243 | **A** |
| `CLAUDE_CODE_PROMPT_CACHE_TTL` | Env form of the above | — | **never announced** | C |
| `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` | Env form of the above | — | **never announced** | C |
| `ENABLE_PROMPT_CACHING_1H=1` | 1h for **both** buckets; API key, Bedrock, Vertex, Foundry | off | 2.1.108 | **A** |
| `FORCE_PROMPT_CACHING_5M=1` | Force 5m everywhere; overrides all of the above | off | 2.1.108 | **A** |
| `ENABLE_PROMPT_CACHING_1H_BEDROCK=1` | **Deprecated**, still honoured | off | 2.1.108 | **A** |
| `experimental.cacheTtl` (agent frontmatter) | Per-subagent TTL when no bucket setting applies | — | 2.1.248 | **A** |
| `DISABLE_PROMPT_CACHING` (+ `_HAIKU`/`_SONNET`/`_OPUS`/`_FABLE`) | Turn caching off, globally or per model family | off | docs only | C |

**Default TTL depends on how you pay**, which is the part people miss:

| Bucket | Claude subscription, within plan | API key / cloud provider / on usage credits |
|---|---|---|
| Main conversation | **1 hour** | **5 minutes** |
| Everything else | 5 minutes | 5 minutes |

> [!TIP]
> On an API key, `{"promptCacheTtl": "1h", "subagentPromptCacheTtl": "1h"}` is the config. Requires
> **v2.1.243+** — on older builds the settings do not exist and setting them does nothing, silently.
> The 1h TTL doubles cache-write cost, so it is a loss on bursty work that never idles past 5 minutes.

**Precedence**, first match wins: `FORCE_PROMPT_CACHING_5M` → bucket env var → bucket setting →
subagent frontmatter → `ENABLE_PROMPT_CACHING_1H` → bucket default.

## Claude Code — tools and prefix stability

| Setting | Effect | Shipped | Grade |
|---|---|---|:--:|
| `alwaysLoad` (per MCP server/tool) | Pin a schema into the cached prefix — **a cost decision** | 2.1.121 | **A** |
| `auto:N` (tool search threshold) | Defer MCP tools past N% of the context window | 2.1.9 | **A** |
| `MCPSearch` / `ToolSearch` in `disallowedTools` | Disable deferral entirely | 2.1.7 | **A** |
| `--exclude-dynamic-system-prompt-sections` | Strip machine-local prompt sections for cross-user cache sharing | 2.1.98 | **A** |
| `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS` | Stagger same-prefix fan-out agents so later ones read the cache (`0` disables) | 2.1.229 | **A** |
| `--bare` | Scripted `-p`: skips hooks, LSP, plugin sync, auto-memory. **Forces `ANTHROPIC_API_KEY`** | 2.1.81 | **A** |
| `modelPricing` (managed) | Contracted rates for `/cost`, statusline, telemetry instead of list price | 2.1.243 | **A** |

## Claude Code — telemetry

| Variable | Effect | Shipped | Grade |
|---|---|---|:--:|
| `CLAUDE_CODE_ENABLE_TELEMETRY=1` | Master switch | never announced | C |
| `OTEL_METRICS_EXPORTER` / `OTEL_LOGS_EXPORTER` / `OTEL_TRACES_EXPORTER` | `otlp` · `console` · `prometheus` · `none` | — | C |
| `OTEL_EXPORTER_OTLP_ENDPOINT` / `_PROTOCOL` / `_HEADERS` | Where and how to export | — | C |
| `OTEL_LOG_RAW_API_BODIES=file:<dir>` | **Full Messages API request + response JSON to disk** | 2.1.111 | **A** |
| `OTEL_LOG_USER_PROMPTS` / `_ASSISTANT_RESPONSES` / `_TOOL_DETAILS` / `_TOOL_CONTENT` | Content-logging opt-ins | 2.1.85 / 2.1.193 | **A** |
| `OTEL_METRICS_INCLUDE_SESSION_ID` / `_VERSION` / `_ACCOUNT_UUID` / `_ENTRYPOINT` | Cardinality control | 2.1.152 | **A** |
| `CLAUDE_CODE_OTEL_CONTENT_MAX_LENGTH` | Override the 60 KB content-attribute truncation | 2.1.214 | **A** |
| `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` | Beta tracing | — | C |

> [!CAUTION]
> `OTEL_LOG_RAW_API_BODIES` writes full prompts, file contents, and absolute paths to disk. It is the
> only way to *prove* what invalidated a cache prefix, and the largest privacy and disk liability in
> either product. Never point it inside a repository.

## GitHub Copilot — cache

| Setting | Effect | Shipped | Grade |
|---|---|---|:--:|
| `github.copilot.chat.agent.longToolCallCachePreservation` | **Keep-alive probes during long tool calls** — the only cache-TTL workaround Copilot has | VS Code 1.123 | **B** |
| `github.copilot.chat.anthropic.cacheBreakpoints.lastTwoMessages` | Rolling breakpoints on the two most recent messages | VS Code 1.118 | **A** |
| `chat.experimental.symbolTools.cacheStable` | Static descriptions for two symbol tools, keeping tool bytes identical across turns | VS Code 1.118 | **A** |
| `github.copilot.chat.anthropic.toolSearchTool.enabled` | Tool search, Anthropic models | VS Code 1.109 | **A** |
| `github.copilot.chat.responsesApi.toolSearchTool.enabled` | Tool search, OpenAI models | VS Code 1.118 | **A** |
| **TTL selection** | — | **does not exist** | — |

> [!WARNING]
> `longToolCallCachePreservation` is **experimental, default-off, and has no release-note coverage at
> all** — a grep of VS Code release notes v1.107–v1.138 for `preservation`, `keepalive`, or
> `longToolCall` returns nothing. The person who filed the bug it fixes
> ([vscode#321551](https://github.com/microsoft/vscode/issues/321551)) discovered it by accident two
> months after it shipped.
>
> The key also appears as `github.copilot.config.agent.longToolCallCachePreservation.enabled` in
> [PR #316277](https://github.com/microsoft/vscode/pull/316277) itself. We have not reconciled the two
> spellings — **check both** in your settings UI.

## GitHub Copilot — telemetry

| Setting | Effect | Default | Shipped | Grade |
|---|---|---|---|:--:|
| `github.copilot.chat.otel.enabled` | Master switch | `false` | VS Code 1.119 | **A** |
| `github.copilot.chat.otel.otlpEndpoint` | Collector URL | `http://localhost:4318` | VS Code 1.119 | **A** |
| `github.copilot.chat.otel.exporterType` | `otlp-http` | `otlp-http` | VS Code 1.119 | **A** |
| `github.copilot.chat.otel.captureContent` | Emit prompt text | `false` | VS Code 1.119 | **A** |
| `COPILOT_OTEL_ENABLED` / `OTEL_EXPORTER_OTLP_ENDPOINT` | Env overrides | — | VS Code 1.119 | **A** |

> [!NOTE]
> Enterprise-managed OTel export (2026-07-08, VS Code 1.128) lets an organisation mandate the collector
> so individual developers do not set `OTEL_*` themselves.

---

[Index](../README.md) · [Known issues](KNOWN-ISSUES.md) · [Timeline](../TIMELINE.md)
