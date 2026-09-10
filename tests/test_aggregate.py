"""The formula that drifted between run.sh and ab.sh, pinned."""

from __future__ import annotations

import pytest

from measure.lib.aggregate import TokenSemantics, cache_read_share, mean


def test_anthropic_denominator_includes_cache_creation() -> None:
    """run.sh was right, ab.sh was wrong: cr / (cr + cc + inp)."""
    share = cache_read_share(
        cache_read=800,
        cache_creation=100,
        input_tokens=100,
        semantics=TokenSemantics.EXCLUDES_CACHE_READ,
    )
    assert share == pytest.approx(0.8)


def test_ab_sh_formula_would_have_over_reported() -> None:
    """Documents the size of the bug rather than just asserting the fix."""
    correct = cache_read_share(
        cache_read=800,
        cache_creation=100,
        input_tokens=100,
        semantics=TokenSemantics.EXCLUDES_CACHE_READ,
    )
    drifted = 800 / (800 + 100)  # ab.sh:226 — cache_creation omitted
    assert correct is not None
    assert drifted > correct


def test_copilot_denominator_is_input_alone() -> None:
    """Copilot's input_tokens already contains cache reads (copilot-sdk#1160).

    Applying Anthropic's formula here would count them twice.
    """
    share = cache_read_share(
        cache_read=800,
        cache_creation=0,
        input_tokens=1000,
        semantics=TokenSemantics.INCLUDES_CACHE_READ,
    )
    assert share == pytest.approx(0.8)


def test_same_inputs_diverge_by_semantics() -> None:
    """The whole reason token_semantics is a required field."""
    kwargs = {"cache_read": 800.0, "cache_creation": 100.0, "input_tokens": 1000.0}
    excl = cache_read_share(**kwargs, semantics=TokenSemantics.EXCLUDES_CACHE_READ)
    incl = cache_read_share(**kwargs, semantics=TokenSemantics.INCLUDES_CACHE_READ)
    assert excl != incl


def test_incomplete_coverage_is_none_not_zero() -> None:
    """A silent meter is not a cache miss."""
    assert (
        cache_read_share(
            cache_read=0,
            cache_creation=0,
            input_tokens=1000,
            semantics=TokenSemantics.INCLUDES_CACHE_READ,
            coverage=0.5,
        )
        is None
    )


def test_full_coverage_with_genuine_zero_is_zero() -> None:
    share = cache_read_share(
        cache_read=0,
        cache_creation=0,
        input_tokens=1000,
        semantics=TokenSemantics.INCLUDES_CACHE_READ,
        coverage=1.0,
    )
    assert share == 0.0


def test_empty_denominator_is_none() -> None:
    assert (
        cache_read_share(
            cache_read=0,
            cache_creation=0,
            input_tokens=0,
            semantics=TokenSemantics.EXCLUDES_CACHE_READ,
        )
        is None
    )


def test_mean_of_nothing_is_none_not_zero() -> None:
    assert mean([]) is None
    assert mean([1.0, 2.0, 3.0]) == pytest.approx(2.0)
