// rev3 candidate builder. Inputs: dir with live/rev JSON (from build3.sh). Output dir. No network.
// Usage: node build3.js <work> <out>
const fs = require('fs'), path = require('path');
const [W, O] = process.argv.slice(2);
const rd = (f) => JSON.parse(fs.readFileSync(path.join(W, f), 'utf8'));
const liveM = rd('m.json'), liveB = rd('b.json'), liveW = rd('w.json'), revM = rd('rev-643697.json'), revB = rd('rev-65b474.json'), vp = rd('vp.json');
const clone = (x) => JSON.parse(JSON.stringify(x));
const core = (g) => ({ entry: g.entry, nodes: g.nodes, edges: g.edges, policy_id: g.policy_id, input_schema: g.input_schema, output_schema: g.output_schema });
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
// Live graphs must equal the restored revisions (fidelity baseline).
const canon = (v) => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map((y) => [y, x[y]])) : x));
for (const [l, r, n] of [[liveM, revM, 'match/643697783a4c'], [liveB, revB, 'batch/65b474cdf302']])
  if (canon(core(l)) !== canon(core(r))) throw Error('live core != revision ' + n);
function once(s, a, b) { const parts = s.split(a); if (parts.length !== 2) throw Error('anchor count ' + (parts.length - 1) + ': ' + a.slice(0, 60)); return parts.join(b); }
function all(s, a, b, expect) { const n = s.split(a).length - 1; if (n !== expect) throw Error(`anchor ${a} count ${n} != ${expect}`); return s.split(a).join(b); }
const js = (f) => fs.readFileSync(path.join(__dirname, f), 'utf8').replace(/\n/g, '');
const node = (g, id) => { const n = g.nodes.find((x) => x.id === id); if (!n) throw Error('missing ' + id); return n; };

// ---------------- MATCH (unchanged from rev2)
const M = clone(core(liveM));
M.entry = 'node_37ce03817f1e';
M.nodes.push(
  { id: 'node_37ce03817f1e', kind: 'code', output_key: 'match_gate', description: 'Additive direct-call gate. Omitted validation_only/require_matched_replay mean true; only explicit false/false continues to the original executable path.', config: { language: 'javascript', code: js('../match-gate.js'), timeout: 60, retry: { max_retries: 0 }, cache: false } },
  { id: 'node_8d45e44b3779', kind: 'condition', output_key: 'gate_flag', description: 'Route to original entry only when the gate allows execution.', config: { expression: 'match_gate.execute', timeout: 60, retry: { max_retries: 0 } } },
  { id: 'node_f7e9e17dcb9a', kind: 'eval', output_key: 'gate_report', description: 'Terminal report for blocked or validation-only direct calls; nothing dispatched.', config: { expression: 'match_gate', timeout: 60, retry: { max_retries: 0 } } });
M.edges.push({ from: 'node_37ce03817f1e', to: 'node_8d45e44b3779', level: 'normal' },
  { from: 'node_8d45e44b3779', level: 'route', router: 'state_equals', state_key: 'gate_flag', branches: { true: 'node_b50bd6aa3ba4', false: 'node_f7e9e17dcb9a' } });
Object.assign(M.input_schema.properties, {
  validation_only: { type: 'boolean', default: true, description: 'Direct-call gate. Omitted = true: no dispatch. Legacy batch caller passes false explicitly.' },
  require_matched_replay: { type: 'boolean', default: true, description: 'Omitted = true: fails closed before dispatch (replay unavailable). false = explicitly requested UNVERIFIED paper run.' } });
M.output_schema.properties.gate_report = { type: 'object' };
// Pure admission tightening, consistent with batch bounds (no node changes).
M.input_schema.properties.round_count.maximum = 5;
M.input_schema.properties.history_bars.maximum = 1000;
M.input_schema.properties.bars_per_round.maximum = 10000;

// ---------------- BATCH
const B = clone(core(liveB));
const REVIEWED = "const __eh=input.progress.evidence_history,__last=__eh[__eh.length-1],__reviewed=input.progress.index>0&&!!__last&&__last.after_match===input.progress.index&&__last.skipped!==true;";
// init: flags optional (omitted=true), reject provided non-booleans; contract checks; review controls validated (supported).
const init = node(B, 'node_0a53eccb6e3a');
init.config.code = once(init.config.code, "for(const k of ['validation_only','require_matched_replay'])if(typeof input[k]!=='boolean')throw Error('Missing boolean '+k);", "for(const k of ['validation_only','require_matched_replay'])if(input[k]!==undefined&&typeof input[k]!=='boolean')throw Error('Invalid boolean '+k);");
init.config.code = once(init.config.code, 'return {index:0,ledger:[],evidence_history:[],blocked:false,execute:!input.validation_only&&!input.require_matched_replay};', js('batch-init-tail.js'));
// prepare: flags !==false; handoff only after an actual completed review of the immediately preceding match.
const prep = node(B, 'node_c47e33d099a6');
prep.config.code = once(prep.config.code, 'if(input.validation_only||input.require_matched_replay||', REVIEWED + 'if(input.validation_only!==false||input.require_matched_replay!==false||');
prep.config.code = once(prep.config.code, "const prior=input.progress.index>0?", "const prior=__reviewed?");
// publication: flags !==false; peer-tip decision gate only after an actual completed review.
const pub = node(B, 'node_d08c651a9063');
pub.config.code = once(pub.config.code, "if(input.validation_only||input.require_matched_replay)throw Error('Publication forbidden');", REVIEWED + "if(input.validation_only!==false||input.require_matched_replay!==false)throw Error('Publication forbidden');");
pub.config.code = once(pub.config.code, 'if(input.progress.index>0){for(const n of names)', 'if(__reviewed){for(const n of names)');
// summary: normalized flags, unsupported precedence, unverified label, review plan (settings only, no simulated review claim).
const sum = node(B, 'node_faed70b2dfd2');
let sc = sum.config.code;
sc = all(sc, 'input.validation_only', 'vo', 3);
sc = all(sc, 'input.require_matched_replay', 'rr', 3);
sc = "const vo=input.validation_only!==false,rr=input.require_matched_replay!==false;" + sc;
sc = once(sc, 'const status=vo?', "const status=(input.progress.unsupported||[]).length?'blocked_unsupported_config':vo?");
sc = once(sc, ":'completed';", ":'completed_unverified_replay';");
sc = once(sc, 'const report={batch_id:input.batch_id,', "const report={batch_id:input.batch_id,replay_mode:rr?'required_unavailable':'not_required_unverified',unsupported:input.progress.unsupported||[],review_plan:{review_enabled:input.review_enabled===undefined?true:input.review_enabled,review_every_matches:input.review_every_matches===undefined?1:input.review_every_matches,note:'settings only; reviews are executed only on non-validation runs and recorded in improvement_evidence'},");
sum.config.code = sc;
// routine call: explicit flags to the match gate (only reached when both are explicitly false).
Object.assign(node(B, 'node_81ac4b14b121').config.input_map, { validation_only: 'validation_only', require_matched_replay: 'require_matched_replay' });
// review routing: after publication AND more; due -> original split/A2A/validator; not due -> truthful skip, then original ready gate.
B.nodes.push(
  { id: 'node_fa8d98e0835a', kind: 'code', output_key: 'review_gate', description: 'Deterministic review cadence after authoritative publication. Defaults (enabled, every 1) always route to the original review split.', config: { language: 'javascript', code: js('review-gate.js'), timeout: 60, retry: { max_retries: 0 }, cache: false } },
  { id: 'node_a1dc3dd60120', kind: 'condition', output_key: 'review_due_flag', description: 'Due -> original review split; otherwise truthful skip.', config: { expression: 'review_gate.due', timeout: 60, retry: { max_retries: 0 } } },
  { id: 'node_21fb15fcc454', kind: 'code', output_key: 'progress', description: 'Skipped review: advances index/ledger/evidence_history only; records skip reason; no evidence pass, no strategy promotion.', config: { language: 'javascript', code: js('review-skip.js'), timeout: 60, retry: { max_retries: 0 }, cache: false } });
const moreEdge = B.edges.find((e) => e.from === 'node_564a5b71b8aa');
if (moreEdge.branches.true !== 'node_dfbb0590a181') throw Error('unexpected more edge');
moreEdge.branches.true = 'node_fa8d98e0835a';
B.edges.push({ from: 'node_fa8d98e0835a', to: 'node_a1dc3dd60120', level: 'normal' },
  { from: 'node_a1dc3dd60120', level: 'route', router: 'state_equals', state_key: 'review_due_flag', branches: { true: 'node_dfbb0590a181', false: 'node_21fb15fcc454' } },
  { from: 'node_21fb15fcc454', to: 'node_f7ae7efb2ab1', level: 'normal' });
// schema: flags optional default true; contract props; timeout without default; history/bars tightened.
const strip = (x) => JSON.parse(JSON.stringify(x, (k, v) => (v && typeof v === 'object' && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).filter(([kk]) => kk !== 'description')) : v)));
const S = B.input_schema;
S.required = S.required.filter((k) => k !== 'validation_only' && k !== 'require_matched_replay');
S.properties.validation_only = { type: 'boolean', default: true };
S.properties.require_matched_replay = { type: 'boolean', default: true };
S.properties.history_bars.maximum = 1000; S.properties.bars_per_round.maximum = 10000;
for (const k of ['agents', 'tracks', 'evaluation_start', 'evaluation_end', 'validation_as_of', 'timezone', 'capital_policy', 'fill_policy', 'finalization_policy', 'review_enabled', 'review_every_matches', 'evidence_required', 'bonus_rounds', 'tie_policy', 'bonus_cash_comparator', 'execution_timeout_seconds', 'max_retries', 'failure_policy']) S.properties[k] = strip(vp[k]);
delete S.properties.tracks.default;
delete S.properties.execution_timeout_seconds.default;
S.properties.validation_as_of = { anyOf: [S.properties.validation_as_of, { type: 'null' }], default: null };

// ---------------- WORKFLOW
const WF = clone(liveW);
const manualProps = clone(S.properties);
manualProps.tracks.default = clone(vp.tracks.default);
manualProps.execution_timeout_seconds.default = 60;
manualProps.brief = clone(S.properties.brief);
WF.description = 'Manual-only bounded paper competition on the original executable batch -> match -> review path. Every manual control is forwarded by the same name to paper-trading-improvement-batch. Defaults validation_only=true and require_matched_replay=true: zero dispatch. review_enabled/review_every_matches are enforced (skipped reviews are recorded, never claimed). Default tracks (5m/15m/1h BTC-USD), explicit evaluation windows, carry capital, bonus rounds, agent customization, explicit execution_timeout_seconds and other non-default knobs are BLOCKED before dispatch as unsupported pending the timestamped intraday adapter; never run on daily data. Legacy daily execution requires tracks omitted and explicit validation_only=false; require_matched_replay=false runs are labelled UNVERIFIED. No cron/event triggers; no real trading.';
WF.updated_at = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
delete WF.graph.nodes.node_3a3f6fc82872;
WF.graph.nodes.node_45cef6f22948.output_schema = { type: 'object', required: ['batch_id'], additionalProperties: false, properties: manualProps };
for (const id of ['node_82566e054c56', 'node_24ef4a8ba1eb', 'node_3b112a66eec5']) { delete WF.graph.nodes[id].input_schema; delete WF.graph.nodes[id].output_schema; }
WF.graph.edges = WF.graph.edges.filter((e) => e.from.node !== 'node_3a3f6fc82872' && e.to.node !== 'node_3a3f6fc82872' && e.from.node !== 'node_45cef6f22948')
  .concat(Object.keys(manualProps).sort().map((k) => ({ from: { node: 'node_45cef6f22948', port: k }, to: { node: 'node_82566e054c56', port: k } })));

// ---------------- write (restore original float timeout encodings)
const enc = (o) => JSON.stringify(o).replace(/"timeout":(60|900|20000)([,}])/g, '"timeout":$1.0$2');
fs.mkdirSync(O, { recursive: true });
fs.writeFileSync(path.join(O, 'match.patch.json'), enc(M));
fs.writeFileSync(path.join(O, 'batch.patch.json'), enc(B));
fs.writeFileSync(path.join(O, 'workflow.put.json'), JSON.stringify({ path: 'workflow_51af71f98b2b', workflow: WF }));
console.log('built', O);
