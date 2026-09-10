# 04 — Tool and MCP loading

**Research date:** 2026-09-10. **Scope:** how each harness gets tool definitions in front of the model,
why tool schemas are the most expensive tokens in the request, and what deferred loading actually saves.

---

## 0. TL;DR

1. Tool definitions render **first** — position 0. They are the most expensive real estate in the
   request, because everything after them sits behind them in the prefix.
2. A tool schema costs twice: once as tokens on every uncached turn, and again as **invalidation risk**
   every time the tool set changes.
3. Both harnesses converged on the same fix — **defer the schemas**, send stubs, load the full
   definition only when selected — arriving at it independently.
4. Copilot published numbers: **11–18% fewer tokens per session** on Anthropic models, 8.6–9.8% on
   OpenAI. Anthropic published the mechanism but not the savings.
5. The failure mode to know: when deferral is **unavailable**, an MCP server that reconnects on its own
   silently triggers a full re-read. No user action required to incur it.

---

## 1. Why position 0 is expensive

Render order is `tools` → `system` → `messages`. Two consequences:

**Recurring token cost.** Tool schemas are re-sent on every turn. Cached, they cost ~10% of input rate;
uncached, full. A large MCP tool surface is a fixed tax on every request in the session.

**Invalidation blast radius.** Because tools sit at the front, *any* change to the tool set rewrites
position 0 and invalidates the entire request behind it — system prompt, project context, and the
whole conversation. A one-line change to a tool description costs a full re-read of a 150k-token
conversation.

The second effect dominates. Token cost is linear in schema size; invalidation cost is proportional to
the entire session length and is paid in full each time.

## 2. Claude Code: deferral, and what happens when it is unavailable

### 2.1 Deferred tool loading

Claude Code sends lightweight stubs rather than full schemas, keeping tools "in the same order" so the
cached prefix stays stable, and loading complete definitions only when a tool is selected
([Prompt caching is everything, fetched 2026-09-10](https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything)).

The ordering detail is the load-bearing part. Deferral would be worthless if loading a schema
*reordered* the tool block — that would rewrite position 0, which is exactly what deferral exists to
avoid. Keeping order stable and appending the expansion elsewhere is what makes it cache-neutral.

**Shipping history**, from the changelog
([fetched 2026-09-10](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md)):

| Version | Entry |
|---|---|
| [2.1.7](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md?plain=1#L5098) | Default-on: `When MCP tool descriptions exceed 10% of the context window, they are automatically deferred and discovered via the MCPSearch tool instead of being loaded upfront` |
| 2.1.9 | Threshold syntax `auto:N` |
| 2.1.121 | Per-server opt-out via `alwaysLoad` |
| 2.1.84 | `Global system-prompt caching now works when ToolSearch is enabled, including for users with MCP tools configured` |

Two naming notes for anyone searching primary sources. The feature shipped as **`MCPSearch`** and was
later renamed **`ToolSearch`** — the rename is never announced, it simply appears from v2.1.20 onward.
And **the literal token `defer_loading` does not appear in the changelog at all**; it is API-level
vocabulary from Anthropic's engineering blog, not a Claude Code configuration key. The user-facing
control is `alwaysLoad` and the `auto:N` threshold.

### 2.2 The MCP consequence

Whether an MCP change is free or catastrophic depends entirely on whether that server's tools are
deferred ([Claude Code prompt caching, fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)):

| Tools are… | A server connecting / disconnecting / changing its tool list |
|---|---|
| **Deferred** (default on supported models) | Appends new content only — **cache intact** |
| **Loaded into the prefix** | **Full re-read** of the entire conversation |

Deferral is unavailable or disabled in these cases, and this list is the practical one to check:

- Google Cloud Agent Platform models older than the Claude 4.5 generation
- A custom `ANTHROPIC_BASE_URL` gateway
- Microsoft Foundry deployments hosted on Azure, once Claude Code detects tool search is rejected
- Any server or tool marked `alwaysLoad`
- Definitions kept upfront by threshold-based loading

**The silent case.** When tools do load into the prefix, the most common invalidation is a server
connecting or disconnecting **with no user action at all**: a stdio server's process exits, an HTTP
session expires, or a server reconnects after a transient failure. A connected server can also push a
dynamic tool update that changes its list mid-session. From the user's side this is an unexplained
expensive turn.

Editing MCP config does **not** itself invalidate anything — the change takes effect only on restart,
which is when the connect/disconnect actually happens.

### 2.3 The advisor exception

Toggling the advisor tool is explicitly cache-safe: its definition sits **after** the cache breakpoint,
so enabling or disabling `/advisor` leaves the cached prefix intact. A useful demonstration that
"after the breakpoint" is a design position, not an accident.

### 2.4 Deny rules

Adding a **bare** tool name as a deny rule (`Bash`, `WebFetch`, `"*"`) removes the definition from
context entirely — a prefix change, and therefore a full re-read. **Scoped** deny rules
(`Bash(rm *)`) and all allow/ask rules do not: they are evaluated when Claude attempts a call, leaving
the prefix untouched.

A glob matching only MCP tools (`mcp__*`) removes those tools but leaves the cache intact **when they
are deferred** — they were never in the cached prefix to begin with.

## 3. Copilot: tool search, moved client-side

Copilot's tool search solves the same problem with a different architecture, per
[Improving token efficiency in GitHub Copilot, fetched 2026-09-10](https://code.visualstudio.com/blogs/2026/06/17/improving-token-efficiency-in-github-copilot):

- Upfront, the model sees only **lightweight metadata** — name and description per deferred tool.
  Parameter schemas, which are the bulk of the bytes, stay out of context.
- Deferred tools are added **at the end of the context window**, not the prefix, so the cached prefix
  stays reusable across turns.
- On OpenAI models it uses the native `defer_loading` flag (GPT-5.4+).
- On Anthropic models it started with server-side matching and **moved to client-side, embedding-guided
  search**, retaining a curated core toolset for common actions.

The move to client-side embedding search is the more interesting engineering choice: it trades a
provider round trip for a local vector lookup, which removes both latency and a provider dependency
from the hot path.

### 3.1 Published savings

| Path | Tokens per session | Time to first token | Time to complete |
|---|---|---|---|
| Anthropic models | **−11 to −18%** (prompt and total) | — | 1.9–3.4% faster |
| OpenAI models | **−8.6 to −9.8%** per turn | 6.9–7.3% faster | 5.3–5.4% faster |

These are vendor-reported and we have not independently reproduced them. They are directionally
consistent with the mechanism, and the Anthropic-path figure being roughly double the OpenAI one is
what you would expect given Anthropic tool schemas sit behind explicit breakpoints.

Anthropic documents the same mechanism but publishes **no corresponding savings figure**, so a direct
comparison is not available. This is an asymmetry in disclosure, not necessarily in performance.

## 4. Practical guidance

1. **Audit the MCP surface before blaming the model.** A dozen connected servers is a large fixed
   token tax and a large invalidation surface. The `mcp_server.name` / `mcp_tool.name` attributes on
   `claude_code.token.usage` let you attribute spend per server rather than guessing. (A
   `claude_code.mcp.rpc` metric would help too, but it is unconfirmed — see
   [track 05 §1.1](05-telemetry.md) and [`../GAPS.md`](../GAPS.md) §1.)
2. **Check whether deferral is actually on.** Behind a gateway it may silently not be — which converts
   every MCP reconnect into a full re-read. Track 02 §6.1.
3. **Prefer scoped deny rules to bare ones.** `Bash(rm *)` is cache-neutral; `Bash` is not.
4. **Treat `alwaysLoad` as a cost decision.** It pins a schema into the prefix permanently.

The A/B recipe in this repo isolates exactly this: `just measure-mcp` runs an identical task set with
and without an MCP server attached, interleaved, and reports the paired difference. Results land in
[`../measurements/`](../measurements/).

## 5. What we could not determine

- Copilot's tool-schema byte counts, its core-toolset membership, and its deferral threshold — closed.
- Claude Code's threshold-based loading heuristic — documented as existing, not as a formula.
- Whether Copilot's client-side embedding search ever mis-selects and costs a round trip.

See [`../GAPS.md`](../GAPS.md).

## Sources

- [How Claude Code uses prompt caching, fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)
- [Claude Code: MCP, fetched 2026-09-10](https://code.claude.com/docs/en/mcp)
- [Anthropic: Prompt caching is everything, fetched 2026-09-10](https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything)
- [VS Code: Improving token efficiency in GitHub Copilot, fetched 2026-09-10](https://code.visualstudio.com/blogs/2026/06/17/improving-token-efficiency-in-github-copilot)
- [GitHub: Getting more from each token, fetched 2026-09-10](https://github.blog/ai-and-ml/github-copilot/getting-more-from-each-token-how-copilot-improves-context-handling-and-model-routing/)
- [Anthropic: tool search tool, fetched 2026-09-10](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool)

---

← [03 — Context management](03-context-management.md) · [Index](../README.md) · [05 — Telemetry](05-telemetry.md) →
