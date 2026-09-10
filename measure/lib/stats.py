"""Bootstrap confidence intervals — seeded, so a reader can re-derive them.

The bash version (`ab.sh:167-193`) seeded with a bare awk `srand()`, which draws
from wall-clock seconds. Measured on macOS: three runs 1.2s apart produced
0.689 / 0.054 / 0.771, while two runs inside the same second were byte-identical.
So the published interval was irreproducible across runs and accidentally
identical within a second — the second property being the more dangerous, since a
quick rerun could look like independent confirmation.

Here the seed is an explicit argument and is recorded in the emitted measurement.
The percentile convention is also fixed: awk used `int(0.025 * B)` against a
1-indexed array, which is off by one against a proper percentile.
"""

from __future__ import annotations

import random
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Final, final

DEFAULT_RESAMPLES: Final[int] = 2000
DEFAULT_SEED: Final[int] = 20260910


@final
@dataclass(frozen=True, slots=True)
class BootstrapCI:
    mean: float
    ci95_low: float
    ci95_high: float
    n: int
    resamples: int
    seed: int


def bootstrap_ci(
    values: Sequence[float],
    *,
    seed: int = DEFAULT_SEED,
    resamples: int = DEFAULT_RESAMPLES,
) -> BootstrapCI | None:
    """Percentile bootstrap over paired differences.

    Returns None for fewer than two values — a CI over one observation is not a
    CI, and the caller must say so rather than print a number.
    """
    n = len(values)
    if n < 2:
        return None

    rng = random.Random(seed)
    observed_mean = sum(values) / n

    means: list[float] = []
    for _ in range(resamples):
        total = 0.0
        for _ in range(n):
            total += values[rng.randrange(n)]
        means.append(total / n)
    means.sort()

    # Nearest-rank percentile on a 0-indexed sorted list. `max(0, ...)` and
    # `min(len-1, ...)` keep both ends in range for small `resamples`.
    low_index = max(0, round(0.025 * (resamples - 1)))
    high_index = min(resamples - 1, round(0.975 * (resamples - 1)))

    return BootstrapCI(
        mean=observed_mean,
        ci95_low=means[low_index],
        ci95_high=means[high_index],
        n=n,
        resamples=resamples,
        seed=seed,
    )
