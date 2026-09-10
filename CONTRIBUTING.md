# Contributing

This is a sourced teardown of two agentic coding harnesses, not a feature-comparison table. A claim
earns its place by being **sourced** or **measured**, not by sounding plausible.

## The rules

1. **Every capability claim carries a source URL with a fetch date.** Format:
   `[Vendor docs, fetched YYYY-MM-DD](https://...)`. A claim without a date is unusable.
2. **Every cost or performance number is either cited or backed by a measurement.** If it is a
   number you ran, not a number you read, it must correspond to a file under `measurements/`
   produced by `just record` — cite the file, not a vibe.
3. **Never add a URL you have not opened.** If a page 404s, redirects to another host, or is
   gated, do not guess — mark the row `[unverified YYYY-MM-DD]` and add it to
   [`GAPS.md`](GAPS.md) with the reason it failed.
4. **Unverifiable items go to `GAPS.md`.** Do not estimate a number you cannot source or measure,
   and do not silently omit the claim either — an absence with no explanation looks like an
   oversight, not a boundary.
5. **Negative findings are first-class results.** A capability that cannot be measured, a metric
   the vendor does not expose, or a measurement that could not be reproduced is worth recording
   with the same care as a positive number. Say what you tried and why it did not work.
6. **No vendor-competitive framing in metadata.** The repo describes what it measures. Positioning
   arguments belong in prose, with evidence.
7. **Never commit raw API bodies or personal paths**, ever. `just leaks` and
   `just verify-measurements` enforce this — a failure there blocks the commit, it does not get
   silenced.

## Where things go

| Change | File |
|---|---|
| New or updated capability claim | the relevant `docs/NN-*.md` |
| New measurement | `measurements/`, produced via `just record` |
| Something that cannot be measured | `GAPS.md` |
| A cross-cutting conclusion | `SYNTHESIS.md` |
| A change to measurement method | `METHODOLOGY.md` |
| A research log entry | `CHANGELOG.md` |

Do not restructure a track document to add one entry. Additive edits keep the diff reviewable.

## Before committing

```sh
just check    # leaks + links + sources + verify-measurements — this runs on pre-commit too
just stats    # word and citation counts per document
```

`just sources` enforces a minimum citation density per track document, counting both source URLs
and references into `measurements/`. It is there to catch unsourced documents before the first
commit; do not lower the threshold to make it pass — add the citations or the measurement.

Install hooks after cloning:

```sh
lefthook install
```

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope):
description`, scope optional, subject ≤ 72 characters. Types: `feat`, `fix`, `docs`, `style`,
`refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Most changes here are `docs`.

Work on `main`. This repo is trunk-based.
