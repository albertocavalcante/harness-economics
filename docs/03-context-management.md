# 03 — Context management

**Research date:** 2026-09-10. **Scope:** compaction, memory loading, and truncation — what each
harness does when the conversation outgrows the window, and what each strategy costs.

---

## 0. TL;DR

1. Compaction **destroys the conversation cache by design** — the new history is shorter and shares no
   prefix with the old one. That is the point; the question is what it costs to get there.
2. Claude Code's summarisation call **reuses the parent prefix**, so a *warm* `/compact` costs far less
   than the context size implies. A *cold* one reprocesses everything.
3. **Resuming a long session after a Claude Code upgrade is the single most expensive request in the
   product** — new system prompt, entire history behind it, zero cache hits.
4. `/rewind` is the underused lever: it truncates back to an **already-warm** prefix, where `/compact`
   builds a new one. When abandoning a line of work, rewinding is strictly cheaper.
5. Copilot treats compaction as a **routing boundary** — the prefix resets anyway, so it is a free
   moment to re-evaluate which model to use. Claude Code does not exploit this.

---

## 1. Why compaction is a cost event, not a saving

The intuition is that compaction saves money: a shorter history means cheaper turns. That is true
*afterwards*. The event itself is expensive, because:

- The summary must be **generated**, which is output tokens over a large input.
- The post-compaction history **shares no prefix** with the pre-compaction one, so the conversation
  layer starts from zero and must be written to cache again.

Claude Code's docs are explicit that this is by design: compaction "replaces your message history with
a summary… the next request has a new, shorter history that doesn't share a prefix with the old one"
([Claude Code prompt caching, fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)).

## 2. Claude Code: summarising against its own cached prefix

### 2.1 The prefix-reuse trick

To produce the summary, Claude Code sends a **separate request with the same system prompt, tools, and
history as the conversation**, plus a summarisation instruction appended as a final user message.

Because that request shares the conversation's prefix, a warm `/compact` **reads the whole history from
cache** and spends its cost on generation rather than reprocessing. Anthropic describes the same
approach in [Prompt caching is everything, fetched 2026-09-10](https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything):
new tokens consist only of the compaction prompt itself.

The corollary is the expensive case. After a break longer than the TTL there is no cache to read, so
the summarisation request reprocesses the full history as uncached input. **`/compact` costs the most
when you resume an old session** — precisely the moment a user is most likely to reach for it.

### 2.2 What survives, and what reloads

| Layer | On `/compact` |
|---|---|
| System prompt | Reused — cache hit |
| Project context | **Reloaded from disk**; cache-hits only if `CLAUDE.md` and memory are unchanged since session start |
| Conversation | Replaced by the summary; cache rebuilt for the much shorter history |

The turn *after* compaction is therefore not the slow one — it rebuilds a cache for a small payload.

### 2.3 Memory loading is start-of-session only

Project-root and user-level `CLAUDE.md` are read **once at session start** and held in memory. Editing
one mid-session does not invalidate the cache — but it also **does not apply**. Claude keeps working
with the version loaded at startup; the new content lands on the next `/clear`, `/compact`, or restart.

Two exceptions worth knowing: nested `CLAUDE.md` files in subdirectories, and rules with `paths:`
frontmatter, load **later** — when Claude first reads a matching file. Editing one *before* it loads
does take effect; after it loads, the content is part of conversation history and a mid-session edit
does not retroactively change it.

This is a frequent source of confusion: a user edits `CLAUDE.md` to correct behaviour mid-session,
observes no change, and concludes the file is being ignored.

### 2.4 The cheaper alternatives

| Command | Effect on the prefix | When to reach for it |
|---|---|---|
| `/compact` | Conversation layer replaced; new prefix built | Genuinely out of window, or discarding context you no longer need |
| `/rewind` | Truncates to an **already-cached** earlier prefix | Abandoning a line of work — strictly cheaper than compacting |
| `/recap` | Appends a summary as command output; prefix untouched | You want the summary for yourself, not for the model |
| `/clear` | Full reset | Starting unrelated work |

`/rewind` works because every turn since the rewind point read *through* that prefix, keeping the entry
warm even if the original turn was longer ago than the TTL.

### 2.5 Image eviction

The API caps images and PDFs per request, and Claude Code additionally caps their total size. When the
next request would exceed either limit, Claude Code **removes a batch of the oldest images** from what
it sends. Because that mutates the messages that held them, the conversation reprocesses from the
earliest affected message onward. Batching means one slower turn per batch rather than one per new
screenshot. Removed images are gone from Claude's view — they must be re-shared if needed again.

### 2.6 Observability

A **`claude_code.compaction`** metric carrying `trigger` (`auto` or `manual`) and `message_count` would
be the cleanest signal for "how much of my spend is compaction overhead," and would separate
user-initiated from automatic compaction — the distinction that matters for tuning.

> [!WARNING]
> **Treat this as unconfirmed.** The name appears in string inspection of the v2.1.220 binary but
> **nowhere in Anthropic's documentation or in the changelog through v2.1.267**. That establishes the
> string exists in the artifact, not that the metric is emitted or that those are its attributes. Confirm
> against your own collector before relying on it. See [`../GAPS.md`](../GAPS.md) §1.

What *is* evidenced: compaction's cache behaviour has been actively worked on. v2.1.70 —
`Improved compaction to preserve images in the summarizer request, allowing prompt cache reuse for
faster and cheaper compaction`
([changelog](https://github.com/anthropics/claude-code/blob/9cdc2a4d946c586a8472e504fb20b3e79106518c/CHANGELOG.md#2170)).

## 3. Copilot: compaction as a re-routing boundary

GitHub documents that Copilot "compacts long-running sessions when needed," and that compaction "resets
the prompt prefix"
([Getting more from each token, fetched 2026-09-10](https://github.blog/ai-and-ml/github-copilot/getting-more-from-each-token-how-copilot-improves-context-handling-and-model-routing/)).

The design difference is what it does with that fact. Because the prefix resets anyway, compaction is
one of exactly two points where Copilot's Auto router will change models — the other being turn one.
Re-routing costs nothing at a boundary where the cache is already being discarded.

That is a genuinely better use of the event than Claude Code makes of it. Claude Code rebuilds the same
prefix with the same model and does not treat compaction as a decision point.

> [!IMPORTANT]
> **Correcting an earlier claim.** This document previously listed "whether users can invoke it
> manually" and "whether it emits telemetry" as undocumented. Both are documented; we had not looked at
> the release notes:

| Date | Release | Evidence |
|---|---|---|
| 2026-03-04 | VS Code 1.110 | `Context compaction summarizes the conversation history to free up space… VS Code automatically compacts the conversation when the context window reaches its limit, but you can also trigger compaction manually.` Manual trigger is `/compact` ([notes](https://code.visualstudio.com/updates/v1_110)) |
| 2026-04-29 | VS Code 1.118 | `Cache-friendly background compaction… These background summaries now reuse the same cached context as the main agent` ([notes](https://code.visualstudio.com/updates/v1_118)) |
| 2026-06-23 | CLI v1.0.64 | Emits a `gen_ai.conversation.compacted` OTel signal ([CLI changelog](https://github.com/github/copilot-cli/blob/main/changelog.md)) |

The 1.118 entry is the more interesting one: **Copilot independently arrived at the same prefix-reuse
trick as Claude Code** — running the summarisation call against the main agent's cached context rather
than as a fresh request. Two harnesses, different providers, same optimisation.

**Genuinely still undocumented:** the compaction trigger threshold, and what survives summarisation.

## 4. Cost consequences

1. **Compact at a natural break, not mid-task.** The overhead is fixed; you choose when to pay it.
   Waiting for auto-compaction means paying it at an arbitrary moment, usually mid-task.
2. **Never compact cold if you can avoid it.** Resuming an old session and immediately compacting is
   the worst-case ordering — full uncached reprocess, then a rebuild. On a Pro or Max plan Claude Code
   will instead offer to resume from a summary, which avoids carrying the full history at all.
3. **Prefer `/rewind` for abandonment.** Different operation, much cheaper, frequently the one actually
   wanted.
4. **Do not edit `CLAUDE.md` expecting mid-session effect.** It is cache-safe precisely because it is
   inert until reload.

Measured compaction overhead under controlled conditions, where we have it, is in
[`../measurements/`](../measurements/).

## 5. What we could not determine

- Copilot's compaction threshold, trigger policy, and summarisation prompt — all closed.
- Whether Copilot's compaction is observable at all in its telemetry.
- Claude Code's auto-compaction threshold as a function of model context window.

See [`../GAPS.md`](../GAPS.md).

## Sources

- [How Claude Code uses prompt caching, fetched 2026-09-10](https://code.claude.com/docs/en/prompt-caching)
- [Claude Code: context window, fetched 2026-09-10](https://code.claude.com/docs/en/context-window)
- [Anthropic: Prompt caching is everything, fetched 2026-09-10](https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything)
- [Claude Code: monitoring usage, fetched 2026-09-10](https://code.claude.com/docs/en/monitoring-usage)
- [GitHub: Getting more from each token, fetched 2026-09-10](https://github.blog/ai-and-ml/github-copilot/getting-more-from-each-token-how-copilot-improves-context-handling-and-model-routing/)

---

← [02 — Prompt caching](02-prompt-caching.md) · [Index](../README.md) · [04 — Tool and MCP loading](04-tool-and-mcp-loading.md) →
