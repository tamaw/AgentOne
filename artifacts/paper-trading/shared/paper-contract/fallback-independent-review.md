# Independent focused FALLBACK review — rev3

**APPROVE — bounded engineering candidate, conditional on the sole owner's successful deployed-backend save validation/readback and fresh validation-only native verification.** No remaining source-level blocker found in the focused changes. This supersedes the rev2 CHANGES_REQUIRED assessment for these exact hashes; it is not permission for this reviewer to save or execute anything, and is not intraday capability certification.

## Exact reviewed data

Downloaded all 12 manifest-listed engineering files to `/shared/paper-contract/fallback-rev3/`; SHA256SUMS verification passes for every file. The three explicit review-target hashes also match:

- match.patch.json: `95476744743563d2f4621bffa567ea364db99e1a62e13d3e9a30ea7514477abf`
- batch.patch.json: `b3cb9ce2243eaa703400f5035dc3a0080f36521589455b2f362f2eeb8fdfa491`
- workflow.put.json: `63bdc092e223110a6e216664cbded394100c7f9c892f0ea2accc61cd13194188`

Reviewed actual candidate JSON/code, build3.js, batch-init-tail.js, match-gate.js, review-gate.js, review-skip.js, verify3.js/verify3.out and authoritative_validate.py/authoritative.out. Downloaded scripts were inspected, not executed by this reviewer.

## Prior corrections accepted

- Batch safety flags are now optional in input_schema. Init rejects supplied nonbooleans and normalizes omission to true; execute requires both normalized flags false. Prepare/publication additionally require raw explicit false/false, and summary uses the same omission-safe normalization. Local JSON Schema validation independently admits a complete legacy input with both flags omitted. Direct match omission remains safe and replay-required still blocks before dispatch.
- Batch execution_timeout_seconds has no default. Every explicit value, including 60, remains unsupported and blocks admission with an honest 900-second A2A-timeout explanation. Tracks also have no batch default, so the explicit-false legacy batch path is not universally denied by injected intraday defaults. Manual defaults intentionally retain three tracks and timeout 60 and therefore block unsupported configuration. Nothing falsely enforces a 60-second execution timeout.

## Real review routing accepted

- After authoritative publication, only the original more-matches branch enters the new review gate. Due is review_enabled && ((published_index+1) % review_every_matches == 0), with a validated boolean and integer cadence 1..10. Defaults true/1 route to the original split, BOTH original review A2As, original evidence/source/test-readability gate, and original ready gate. The final-match summary branch is unchanged: this is between-match review, not an added final review.
- Disabled/not-due reviews follow the new skip node, which checks a matching not-due gate and ledger sequence, advances index/ledger, and appends skipped=true with the actual reason, empty evidence, test_truth=not_run, effectiveness=not_verified and strategy_promotion=none. It neither manufactures an evidence pass nor claims strategy promotion, then rejoins the existing ready gate.
- Handoff and publication peer-tip checks require a non-skipped review record for the immediately preceding match. Skips no longer cause reads of nonexistent improvement files. When a review actually runs and passes its existing gate, the original next-match handoff and adoption/rejection checks remain. An invalid due review still blocks advancement; caller-authored state cannot create authorization because internal output keys are excluded by strict admission schemas.

## Preservation and evidence

Independent local structural checks: match 20 nodes/16 edge records; batch 17 nodes/15 edge records; unique IDs, no missing endpoints and all nodes structurally reachable. All 29 manual controls forward exactly once by identical names. Independently compared against downloaded rev2: all 17 legacy-shaped match nodes and every match edge are identical; batch original review split, BOTH A2As, evidence validator and ready gate are identical. Match changes outside its gate descriptions are admission maxima, not accounting changes.

Owner-provided verify3.out reports 69 passing checks against original revisions match643697783a4c/batch65b474cdf302, including original-node/config comparisons, preserved original match edges, the single intentional batch more-route change, unchanged default-path publication, and conditionally retained handoff/tip gates. Inspected verifier source: comparisons are substantive structural/node/code comparisons, with separate timeout-encoding checks, not just node counts. This is accepted owner-provided revision-comparison evidence; raw original exports were not independently re-fetched in this focused review. The candidate still calls the same original v3.2 engine; no alternate engine or accounting/settlement replacement was introduced. Prior actual-v3.2 findings on next-close fill, B-bar advance, carried positions and final mark-to-market remain unchanged.

Owner-provided authoritative.out reports both full routine documents accepted by validate_agent_graph_document and input/output/admission checks passed. The accompanying validator source invokes the backend routine validator and an isolated in-memory workflow save path; it does not perform a production save.

**Do not hide the workflow validation result:** that local workflow save attempt FAILED because its schema rejected the manual node shape. It did not establish typed-port or workflow save acceptance. Under the explicitly authorized evidence substitution, the sole owner must resolve this against the deployed/current backend: successful full save-path validation and readback of the intended workflow, with all 29 derived routine ports and report/status notification edges accepted. If deployed validation also rejects it, STOP and correct the workflow; this review does not waive a real schema error.

Reviewer-performed schema checks: all six complete embedded input/output schemas independently pass Draft 7 and Draft 2020-12 meta-validation; omitted batch flags pass actual admission validation. Match gate_report remains optional, as do legacy terminal outputs. Deployed readback/native checks must establish absent optional outputs are projected correctly. These checks are not represented as reviewer-run authoritative backend validation or native execution.

## Safe native verification conditions for the sole owner

Use fresh unique namespaces and validation_only=true for EVERY native verification, including required-replay and unsupported-track/window cases. Verify normalized flags, blocker reasons/unsupported, zero completed matches, no child/A2A/review execution, and no trading/state/scoreboard/batch-report artifact writes. The source routes these calls straight to summary; summary's entire filesystem-report branch is guarded by !vo, so validation_only=true performs no report I/O. It reports only review settings and empty review evidence, not a simulated review.

Important boundary: with explicit validation_only=false, a replay/config-blocked batch still persists a batch-report under the existing !vo policy, although it dispatches nothing. This is reporting metadata, not trading authorization; do not use such inputs for the zero-write native checks. No claim is made that every blocked non-validation request is globally read-only. Workflow notification documents are a separate existing notification behavior, not trading/report-artifact writes.

Required replay remains unavailable; configured intraday tracks/windows, carry capital, bonuses, customized agents and explicit timeout remain unsupported. This approval does not demand those features or relabel daily data as intraday. Review enable/cadence are now actually supported by routing, not silently ignored knobs.

No canonical saves, native executions, competitor/review dispatches, orders, unit tests or project/engine source edits were performed by this reviewer. Owner-provided synthetic/authoritative outputs are distinguished above from checks actually performed here. Parent retains final writer approval.
