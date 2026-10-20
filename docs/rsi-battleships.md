# Battleships self-improvement experiment

Two isolated instances of the agent wrote and ran their own Haskell JSON-lines Battleships players. The host referee generated legal 8x8 fleets of lengths 4, 3, and 2; players saw only their own shot history. It alternated first move, retained an executable incumbent, and evaluated candidates on the same 48 hidden training fleets. Lower mean shots to sink all ships was better.

The completed `gpt-6.1-sol` run used four games, stopping at first-to-three: Agent One won 3–1. This match is a small, noisy outcome. The paired benchmark is the evidence for retained policy changes.

| Agent | Initial host benchmark | Final host benchmark | Retained change |
| --- | ---: | ---: | --- |
| Agent One | 27.29 shots | 26.33 shots | Weight each consistent placement inversely by the actual remaining ship length. |
| Agent Two | 25.50 shots | 25.02 shots | Its final retained host candidate; earlier lattice and edge-placement candidates were rejected. |

Agent One's own deterministic 48-board comparison measured the ship-length change at 25.52 to 25.10 shots. It then tried a stronger unresolved-hit targeting weight, measured 25.10 to 25.23 shots, and restored the incumbent. Its prize phase added `PairedSummary.hs`, a reusable paired-log analyzer that validates board IDs and shot counts and reports mean deltas, standard errors, intervals, and win/tie/loss counts.

Agent Two preserved versioned strategies and built paired evaluators. It rejected a diagonal hunt restriction and edge-biased placement because their local evaluations regressed. Its final exact residual-fleet pursuit with already-sunk consistency and a completion-weighted marginal improved a separate local evaluation from 31.21 to 31.13 shots over 24 boards. That late change did not receive a new host benchmark because the match was already over.

The experiment demonstrates a narrow RSI loop: observe a public trace, state a concrete weakness, create a Haskell candidate and reusable evaluator, compare it against an incumbent on identical inputs, then retain or roll back the change. It does not establish general agent improvement: local boards were reused during tuning, the host suite was small, and the match score combines placement, first-move order, and luck.
