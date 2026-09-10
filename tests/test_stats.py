"""The bash bootstrap was irreproducible. These tests are the fix's proof."""

from __future__ import annotations

from measure.lib.stats import DEFAULT_SEED, bootstrap_ci

DIFFS = [0.012, -0.004, 0.031, 0.008, -0.011, 0.022, 0.017, 0.003, -0.002, 0.014]


def test_same_seed_gives_an_identical_interval() -> None:
    """The property awk's bare `srand()` could not provide."""
    first = bootstrap_ci(DIFFS, seed=DEFAULT_SEED)
    second = bootstrap_ci(DIFFS, seed=DEFAULT_SEED)
    assert first == second


def test_different_seed_gives_a_different_interval() -> None:
    """Guards against a seed that is accidentally ignored."""
    first = bootstrap_ci(DIFFS, seed=1)
    second = bootstrap_ci(DIFFS, seed=2)
    assert first is not None and second is not None
    assert (first.ci95_low, first.ci95_high) != (second.ci95_low, second.ci95_high)


def test_seed_is_recorded_so_a_reader_can_re_derive() -> None:
    result = bootstrap_ci(DIFFS, seed=4242)
    assert result is not None
    assert result.seed == 4242
    assert result.resamples == 2000
    assert result.n == len(DIFFS)


def test_interval_brackets_the_mean() -> None:
    result = bootstrap_ci(DIFFS)
    assert result is not None
    assert result.ci95_low <= result.mean <= result.ci95_high


def test_fewer_than_two_values_is_none_not_a_number() -> None:
    """A CI over one observation is not a CI. The caller must say so."""
    assert bootstrap_ci([]) is None
    assert bootstrap_ci([0.5]) is None


def test_percentile_indices_stay_in_range_for_small_resamples() -> None:
    result = bootstrap_ci(DIFFS, resamples=4)
    assert result is not None
    assert result.ci95_low <= result.ci95_high
