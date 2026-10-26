# Independent engineering review

Disposition: changes required. This is a static source review, not a trading assessment or evidence of a working live/paper match engine.

Inspected validate-match.js, input-schema.json, batch-init.js, batch-next.js, batch-collect.js and batch-report.js. Final version inspection: 2026-10-25T22:15:04Z. batch-init/next/collect/report appeared incrementally during inspection; all six requested artifacts were ultimately available and reviewed. No routines, competitions, orders, JavaScript bodies, or unit tests were executed. Only this report was written. Counterexample outcomes below are source-derived, not experimentally observed execution results.

Inspected SHA-256:

- validate-match.js: 9bddb6a404a9ca739367a050770d53f7e6cc5d1f4dd14fdbd8b141d2e96a24f6
- input-schema.json: 9af9e8a7ddbc68aebb3676898a316ddf8ba38f4da350009dd5e6b1f001969bf3
- batch-init.js: 09323cea5fbd60a594e82b65e2e4890cfa118942c45ea5d636e210ae8dfdd683
- batch-next.js: ea05acc07ff2fdf3b00b1c025fa2e2fd8f877618650bd22c069a6d0de45583b3
- batch-collect.js: 097817146e423686754490681abf6dd6120ac6434894ad6fa411e59049273673
- batch-report.js: 0c1046d2907ce02d9ead2ba56d43aeb96944001ab59f4b7c13bc04c769381e1d

batch-next/collect/report share the same normalization/progress/child-validation prefix through line 165; their differing tails were also reviewed.

## Findings

### F1 — Blocking: both code-node tool calls use incompatible signatures

validate-match.js:141 calls glob({pattern: absolutePath, max_results:2}); line 155 calls readFile({path: absolutePath,max_lines:10000,max_bytes:2097152}). Neither matches the supplied exact API. This is the original first-draft defect, still present in the inspected hash. A conforming rejecting tool produces data_tool_failure via line 200; successful file validation cannot be established.

For the exact base input B below, the required calls are:

```json
{"path":"/shared/market","pattern":"btc-usd-5m.csv"}
{"file_path":"/shared/market/btc-usd-5m.csv","offset":0,"limit":10000}
```

The first is the glob argument and the second is the readFile argument. readFile returns raw text. Replace the unsupported arguments rather than relying on aliases or response-object guesses.

### F2 — High: glob completeness is fail-open for unknown truncation

validate-match.js:110-112,141-154 accepts array responses and objects with matches/paths/files. truncated() only detects selected affirmative flags; missing, null, or nonboolean truncated is treated as complete. truncation_reason is ignored entirely. That contradicts the requirement to reject unknown completeness. A response with one expected path is not sufficient evidence that the result is complete.

Exact counterexample responses to glob for B (each independently):

```json
{"matches":["/shared/market/btc-usd-5m.csv"]}
{"matches":["/shared/market/btc-usd-5m.csv"],"truncated":null,"truncation_reason":null}
{"matches":["/shared/market/btc-usd-5m.csv"],"truncated":"false","truncation_reason":null}
{"matches":["/shared/market/btc-usd-5m.csv"],"truncated":false,"truncation_reason":"unknown"}
```

All reach the read branch under the current code; none establishes the required exact complete-response contract. Require an object with the exact matches shape, truncated === false, and truncation_reason === null. truncated:true is already rejected. Keep the full raw-text line/byte checks after correcting readFile; do not replace those checks with permissive wrapper handling.

### F3 — Blocking: collector consumes an object child instead of native mapped outputs

batch-collect.js:166-169 requires exactly {progress,child}, then checkChild requires child to be {status,report}. Native routine output_key child is TEXT. The required mapping is output_map {child_report:'report',child_status:'status'}, and the collector must consume child_report and child_status. No such consumption exists. batch-next/report retain child objects in progress.results, which is fine only after the collector constructs and validates them from the mapped outputs.

Exact input demonstrating the envelope rejection before any progress access:

```json
{"progress":null,"child":"native text output","child_report":{},"child_status":"blocked"}
```

strict(input,['progress','child'],'input') throws unsupported_field: input.child_report. This is an envelope counterexample, not a valid progress example: the same rejection occurs unchanged with a valid progress object and a valid mapped report. With only {progress:P,child:'native text output'} and otherwise valid P, checkChild instead rejects the string as invalid_object: child. Consume and type-check both mapped fields, construct {status:child_status,report:child_report}, and do not JSON-parse native child text as though it were the report.

No native routine configuration artifact was in the requested review scope, so the actual deployed output_map wiring is not verified here.

### F4 — High: runtime-seeded request/context collide with strict user-input validation

validate-match.js:31-39 and normalizeCommon in each batch body treat the entire input object as the contract. batch-next/collect/report additionally apply strict() to their entire runtime envelopes. request/context are not allowed at either boundary. Thus the required runtime-seeded fields become unknown user settings or unsupported envelope fields. Unknown actual settings should remain rejected, but known runtime metadata must be separated from the canonical settings/envelope before that check.

Exact per-match counterexample: B with these two additional top-level members:

```json
{"request":{},"context":{}}
```

This produces unknown_property for request and context. The batch-init variant is the batch input A below with the same additions; normalizeCommon throws invalid_batch_settings. Exact batch-next/report envelope demonstrating early failure: {"progress":null,"request":{},"context":{}} produces unsupported_field: input.request before progress validation. As in F3, substituting a valid progress object does not cure the envelope defect. Identify the actual seeded metadata keys explicitly; do not fix this by silently dropping arbitrary unknown contract properties.

### F5 — High: fee/slippage public names do not match the required contract

input-schema.json:31-33 exposes capital, fees, slippage. validate-match.js:24,58-60,223-227 and every batch normalizer use fees/slippage. The required names are fee_bps/slippage_bps. Even the benchmark emits fees_bps (plural) rather than fee_bps. This is not just cosmetic: a caller using the required names is rejected as unknown instead of having the requested costs applied.

Exact counterexample: B plus {"fee_bps":0,"slippage_bps":0}. Both members produce unknown_property and schema additionalProperties rejects them. The current normalized contract retains default fees:10 and slippage:5; it does not apply the requested zero costs. Coordinate schema, defaults, validators, all batch forwarding, and benchmark output on fee_bps/slippage_bps. Either reject old names explicitly or implement a documented-by-contract migration rule that rejects conflicting aliases; do not silently choose between two cost fields.

### F6 — Medium: identity collision and selected-track consistency gaps

Within a batch, duplicate track_id is correctly rejected by normalizeCommon, and checkProgress verifies the full canonical job plan, order, and result count. However, run IDs are generated by unescaped underscore concatenation (batch-init:101-109; shared checkProgress:159-161). Two distinct batches can produce the same run_id:

- Exact batch input A with batch_id replaced by "a_b" and its sole tracks[0].track_id replaced by "c" produces a_b_c_m1.
- Exact batch input A with batch_id replaced by "a" and its sole tracks[0].track_id replaced by "b_c" also produces a_b_c_m1.

These are not path collisions: the slash-delimited planned namespaces differ. They are cross-batch run-ID collisions wherever run_id is used as a global key. Use an injective encoding or explicit scoped identity; do not claim global uniqueness from the present encoding.

The validator's planned namespace (lines 230-235) omits run_id and is derived only from batch_id/track_id/match_index/agent. B and B with run_id changed to "review_other" produce the identical planned namespace /artifacts/trading/review/t5/match-1/agent-one (and the analogous agent-two path). No reservation/existing-namespace check or defined idempotent reuse policy is visible. All namespaces are currently created:false, so no actual overwrite occurred. Resolve the reuse policy before enabling any future writer.

Separately, exact input B with track.symbol changed to "ETH-USD" while leaving tracks unchanged passes the current selected-track membership checks, because no such comparison exists. Batch-generated jobs are protected by checkProgress, but direct validator callers can claim a selected track different from their declared track plan. Require selected-track identity/configuration consistency or explicitly separate the direct-match contract. CSV has no symbol/market manifest; those labels alone are not evidence of instrument provenance.

### F7 — Medium: collector's reference comparator validation is superficial

Shared checkChild:145-148 validates cash completely but checks only three markers on non-null buy_and_hold. It does not validate required numeric fields, fee/capital/entry/mark linkage, finite returns, or even reject extra comparator fields. Given any otherwise accepted child, replacing only child.report.comparators.buy_and_hold with the exact object below still satisfies that comparator branch:

```json
{"status":"available_reference_calculation_only","competition_executed":false,"forced_liquidation":false,"return_fraction":999999,"ending_equity":"invented"}
```

Once F3 is fixed, this weakness applies to the corresponding mapped child_report. batch-report embeds the accepted reference payload in job_validation_reports. The parent does not turn it into executed competition results, but cannot claim the payload's returns are independently validated. Require the validator's exact reference shape and finite numeric/identity invariants, or preserve it as explicitly unverified child-supplied reference data. This is not evidence that such a forged child was actually supplied.

### F8 — Low: exact 2 MiB boundary is rejected more strictly than the stated inclusive limit

validate-match.js:116,168 rejects bytes >= 2097152 and only parses bytes < 2097152. A complete raw response of exactly 2097152 UTF-8 bytes and at most 9999 physical lines is rejected even though the requested maximum is inclusive. This is conservative, not a truncation safety bypass. Exact raw-text counterexample for the byte-limit predicate: the CSV fixture below followed by enough ASCII x characters on a final additional line to make its total UTF-8 length exactly 2097152. Other CSV validation would also reject that deliberately malformed line, but the independent byte-limit predicate incorrectly classifies the inclusive size itself. If an exclusive conservative limit is intentional, expose/reject it explicitly rather than claim <=2 MiB support.

## Safety/correctness properties present in the inspected source

- Execution remains unconditionally unavailable and dispatched:false. validation_only:false requests execution but does not enable it. require_matched_replay:false adds replay_gate_bypass_forbidden rather than bypassing the gate. batch-report preserves these blockers. This is validation/reference reporting only, not a live match implementation.
- Defaults validation_only:true, require_matched_replay:true, evidence_required:true are present in schema and all normalizers. Nonboolean flags and evidence_required:false are rejected, not truthiness-coerced.
- capital_policy:'carry' and bonus_rounds>0 have explicit unsupported errors. Fixed fill/finalization/tie/comparator/timeout/retry/failure settings are validated rather than silently honored by nonexistent execution. Review settings affect plan-only reporting; performed:false and no review/trading claims remain explicit.
- UTC parser combines an exact UTC-seconds regex with a real calendar round-trip. It rejects malformed calendar dates, offsets, fractional seconds, date-only timestamps, and trailing newlines. It does not trust validation_as_of as a wall clock; reports correctly mark as_of_is_trusted_wall_clock:false.
- With complete data actually supplied, cadence checks reject daily relabeling, duplicate/nonmonotonic closes and any noncontiguous rows. Endpoints must align; duration must equal rounds * effective bars_per_round * interval. Every CSV row must be closed=true, valid OHLCV and no later than the manually supplied as_of.
- Coverage requires effective history_bars ending at start (including start), all evaluation closes (start,end], and end+interval. Missing history, start, first fill, or next-fill bars cannot pass merely because a sufficient number of other rows exists.
- Returned text is UTF-8 byte-counted; 10000 or more physical lines are rejected, including the header in the count. At most 9999 lines are accepted. No sampling/window slice is substituted for a complete file. These safeguards do not repair F1/F2 by themselves.
- batch-init forwards all currently recognized common schema settings, plus per-track inherited history_bars/bars_per_round/agents, into each job. batch-next returns the whole verified job; it does not intentionally select a small forwarding subset. Fixing field names and runtime metadata handling must preserve this property.
- batch-report reports completed_matches:0, trading_dispatches:0, empty match results/leaderboards, null drawdown, no replay/evidence/review execution, and references only per-job comparisons rather than pooling raw PnL. checkChild rejects claimed actual match results or dispatched execution. The buy-and-hold number, when calculated, is explicitly labeled a reference calculation only; cash zero is an unexecuted comparator.

## Exact base inputs and data used to specify counterexamples

B is this exact per-match JSON object. All stated B variants change/add only the explicitly named keys; arrays and all other members remain unchanged.

```json
{"batch_id":"review","run_id":"review_t5_m1","match_index":1,"tracks":[{"track_id":"t5","interval":"5m","market":"crypto","symbol":"BTC-USD","data_path":"/shared/market/btc-usd-5m.csv"}],"track":{"track_id":"t5","interval":"5m","market":"crypto","symbol":"BTC-USD","data_path":"/shared/market/btc-usd-5m.csv"},"evaluation_start":"2025-01-01T01:00:00Z","evaluation_end":"2025-01-01T01:05:00Z","validation_as_of":"2025-01-01T01:10:00Z","match_count":1,"round_count":1,"history_bars":10,"bars_per_round":1}
```

A is this exact batch-init JSON object:

```json
{"batch_id":"review","tracks":[{"track_id":"t5","interval":"5m","market":"crypto","symbol":"BTC-USD","data_path":"/shared/market/btc-usd-5m.csv"}],"evaluation_start":"2025-01-01T01:00:00Z","evaluation_end":"2025-01-01T01:05:00Z","validation_as_of":"2025-01-01T01:10:00Z","match_count":1,"round_count":1,"history_bars":10,"bars_per_round":1}
```

A complete-response glob fixture is exactly {"matches":["/shared/market/btc-usd-5m.csv"],"truncated":false,"truncation_reason":null}. The complete raw readFile fixture for B is the following ASCII text, with a final newline. It is a counterexample fixture specification only; no market file was created or tool result injected.

```csv
timestamp,open,high,low,close,volume,closed
2025-01-01T00:15:00Z,100,100,100,100,1,true
2025-01-01T00:20:00Z,100,100,100,100,1,true
2025-01-01T00:25:00Z,100,100,100,100,1,true
2025-01-01T00:30:00Z,100,100,100,100,1,true
2025-01-01T00:35:00Z,100,100,100,100,1,true
2025-01-01T00:40:00Z,100,100,100,100,1,true
2025-01-01T00:45:00Z,100,100,100,100,1,true
2025-01-01T00:50:00Z,100,100,100,100,1,true
2025-01-01T00:55:00Z,100,100,100,100,1,true
2025-01-01T01:00:00Z,100,100,100,100,1,true
2025-01-01T01:05:00Z,100,100,100,100,1,true
2025-01-01T01:10:00Z,100,100,100,100,1,true
```

Additional exact safety-negative cases, all statically checked against branches (not run):

- B with evaluation_start:"2025-02-30T01:00:00Z": invalid_utc_timestamp via calendar round-trip.
- B with validation_as_of:"2025-01-01T01:05:00Z": next_fill_after_validation_as_of because the 01:10 close is required.
- The raw fixture with only its 00:35 row deleted: strict_cadence_violation and insufficient_contiguous_coverage, even though timestamps remain monotonic.
- The raw fixture with only its 01:10 row deleted: missing_next_fill_bar and insufficient_contiguous_coverage.
- The raw fixture with only its 00:15 row changed to closed=false: incomplete_bar.
- Exact daily-relabel raw response: "timestamp,open,high,low,close,volume,closed\n2024-12-30T01:00:00Z,100,100,100,100,1,true\n2024-12-31T01:00:00Z,100,100,100,100,1,true\n2025-01-01T01:00:00Z,100,100,100,100,1,true\n". For B this yields daily_relabel_detected, strict_cadence_violation, and missing interval coverage; daily rows cannot masquerade as 5m history.
- B plus {"validation_only":false,"require_matched_replay":false}: still execution.available:false/dispatched:false and replay_gate_bypass_forbidden.
- B plus {"capital_policy":"carry","bonus_rounds":1}: carry_unsupported and bonus_rounds_unsupported.
- B plus {"unexpected_setting":1}: unknown_property; that behavior should remain after handling runtime metadata.
- B with tracks replaced by two distinct objects both having track_id:"t5", one interval:"5m" and one interval:"15m", all other track fields copied from B: duplicate_track_id. Schema uniqueItems alone does not enforce ID uniqueness, but runtime validation does.

No approval is given for native routine integration, matched replay, or live/paper execution. Correct the blocking boundaries and re-review their exact source versions before relying on validation/report transport.
