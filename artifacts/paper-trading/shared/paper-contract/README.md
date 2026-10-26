# Synthetic evaluation report

All fixtures were generated in memory. No market data was downloaded or read from real market files. These observations are not real intraday evidence or competition results.

Execution environment: Node.js AsyncFunction wrapping the asynchronous code-node body. JSON Schema parsed successfully. Native QuickJS execution was not certified.

| Synthetic observation | Observed outcome |
| --- | --- |
| Complete 5m history, evaluation and next-fill coverage; 96 bars | Validation passed; execution blocked; reference buy-and-hold available |
| Common five-hour window, five rounds; 5m/15m/1h overrides of 12/4/1 bars per round | All three validated; 121/81/66 bars respectively; execution blocked |
| Non-validation request, replay bypass, carry and bonus | Blocked: replay_gate_bypass_forbidden, carry_unsupported, bonus_rounds_unsupported |
| Mismatched duration and invalid header | Both blockers accumulated; no benchmark |
| Truncated read | Rejected; no benchmark |
| Exactly 10,000 CSV lines | Rejected rather than accepting a truncated dataset |
| Null evaluation endpoints | missing_evaluation_window; required segment unverifiable |
| Newline in safe ID or data path | Rejected by runtime and schema patterns; unsafe path not read |

All observations: no dispatch, orders, filesystem writes by the validator, reviews, replay, forced liquidation or competition execution. Results and leaderboard remained empty; drawdown remained null; the cash return comparator remained zero.

Every otherwise-valid fixture retained legacy_intraday_adapter_unavailable and independent_replay_unavailable. The bypass fixture retained legacy_intraday_adapter_unavailable and replay_gate_bypass_forbidden. The legacy daily engine strips dates and randomly selects windows; timestamped intraday execution remains unavailable.

Buy-and-hold values were reference arithmetic only: next-close entry with configured basis-point fee_bps/slippage_bps and end-close mark-to-market, without forced liquidation. validation_as_of was supplied fixture data, not trusted wall-clock evidence.

Scope limitation: the schema checks structural constraints; unique track IDs and calendar-valid UTC dates are additionally checked by the body. Tool calls were synthetic readFile/glob adapters, not a live deployment integration.

## Canonical-field correction observations

Both final schemas have fully inlined definitions, zero local references, and operator descriptions for every property. Titles are paper-trading-batch and paper-trading-match; only the latter exposes run_id, track and match_index.

A subsequent synthetic in-memory Node evaluation completed three track validation jobs with fee_bps=200 and slippage_bps=100. Each reference benchmark matched ending equity 1067.7538342069502 for initial capital 1000, entry close 100 and mark close 110. Canonical defaults remained 10 and 5 basis points. Legacy aliases were rejected rather than silently accepted.

Collector status compatibility was observed: valid validation-only requests yielded validation_only_blocked_replay; non-validation requests yielded blocked_execution for both replay settings; alias and null-window errors yielded validation_failed. Completed matches and trading dispatches remained zero.

Actual execution is permanently disabled in the saved implementation. The legacy daily engine strips dates and randomly chooses windows; no timestamped intraday adapter or independent matched replay is available. Replay bypass remains forbidden. These observations are synthetic only, not downloaded data, actual execution, native QuickJS certification or real intraday proof.

Runtime-bridge correction: synthetic in-memory strict-signature Node evaluation succeeded for both allowed roots, including nested exact relative paths. glob received only path and pattern; readFile received only file_path, offset=0 and limit=10000, returning raw text.
Missing/true truncation flags or a truncation reason blocked reads. Thrown glob/readFile fixture messages remained in data_tool_failure reports. Wrapped reads, 10000-line responses and 2 MiB responses were rejected.
Seeded request/context and allowlisted batch intermediates passed without entering authored contracts; unknown batch fields remained rejected. Canonical schema names, flat schemas, basis-point fields and collector status values remained intact. These were synthetic bridge observations, not native QuickJS certification or real-data execution.

Projected nested-routine correction observations: synthetic Node evaluation consumed separate child_report and child_status fields while ignoring non-JSON child text. Collected results retained {status,report}. Missing projections, string reports, run/track/match identity mismatches, wrong status and mismatched transport jobs were rejected.
The per-match run_id bound is now 128 characters; batch/track IDs retain their 64-character bounds. Synthetic generated IDs of lengths 70 and 128 validated; a derived 129-character ID was rejected before dispatch. This supersedes earlier 64-character derived-ID observations.
Embedded defaults produced 30 planned jobs without host schema reads. Statuses remained validation_only_blocked_replay, validation_failed and blocked_execution as appropriate. Completed matches and trading dispatches remained zero; no real data, trading or replay was used.
