"""Aggregate formulas. ONE copy — this module exists because there were two.

`run.sh:143` computed cache_read_share as cr/(cr+cc+inp) while `ab.sh:226`
computed cr/(cr+inp), omitting cache creation. schema.json says the first is
correct for Anthropic's token semantics, so every A/B run over-reported cache
share. Two files, one formula, silent divergence.
"""

from __future__ import annotations

from collections.abc import Sequence
from enum import StrEnum

from measure.lib.projection import Rep


class TokenSemantics(StrEnum):
    """Whether `input_tokens` already contains cache-read tokens.

    Anthropic excludes them. GitHub Copilot includes them (copilot-sdk#1160).
    Same field name, inverted meaning — so the denominator differs, and applying
    one vendor's formula to the other silently double-counts.
    """

    EXCLUDES_CACHE_READ = "input_excludes_cache_read"
    INCLUDES_CACHE_READ = "input_includes_cache_read"


def cache_read_share(
    *,
    cache_read: float,
    cache_creation: float,
    input_tokens: float,
    semantics: TokenSemantics,
    coverage: float | None = None,
) -> float | None:
    """Share of billed input served from cache, or None when unknowable.

    Deliberately not called a hit rate: uncached input, output and cache creation
    are not independently available on every surface.

    Returns None rather than 0.0 when coverage is incomplete. A meter that said
    nothing is not a cache that missed, and encoding both as 0.0 is the failure
    mode that makes a broken meter read as perfect frugality.
    """
    if coverage is not None and coverage < 1.0:
        return None

    if semantics is TokenSemantics.INCLUDES_CACHE_READ:
        denominator = input_tokens
    else:
        denominator = cache_read + cache_creation + input_tokens

    if denominator <= 0:
        return None
    return cache_read / denominator


def share_from_reps(
    reps: Sequence[Rep],
    semantics: TokenSemantics,
    coverage: float | None = None,
) -> float | None:
    """cache_read_share over a set of already-projected reps.

    `coverage` is REQUIRED in practice even though it defaults to None. It cannot
    be derived from `reps`: the projection coerces a missing cache_read to 0.0, so
    by this point "the meter said nothing" and "the meter said zero" are already
    indistinguishable. It has to be measured from the raw payloads and threaded in.

    This parameter did not exist until 2026-09-11, which meant the guard in
    cache_read_share() was dead on the Claude path — a run with half its cache
    attributes missing still published a confident number. The suite missed it
    because it exercised cache_read_share() directly and never this call site.
    """
    return cache_read_share(
        cache_read=sum(r.usage.cache_read_input_tokens for r in reps),
        cache_creation=sum(r.usage.cache_creation_input_tokens for r in reps),
        input_tokens=sum(r.usage.input_tokens for r in reps),
        semantics=semantics,
        coverage=coverage,
    )


def mean(values: Sequence[float]) -> float | None:
    """Arithmetic mean, or None for an empty set.

    None, not 0.0: "no valid reps" and "the mean was zero" are different claims.
    """
    if not values:
        return None
    return sum(values) / len(values)
