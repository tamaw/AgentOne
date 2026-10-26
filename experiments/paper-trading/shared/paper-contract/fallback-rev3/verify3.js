// rev3 local verification: fidelity vs revisions 643697783a4c/65b474cdf302 + synthetic logic of actual candidate code. No network.
const fs = require('fs'), path = require('path'), assert = require('assert');
const D = process.argv[2];
const rd = (f) => JSON.parse(fs.readFileSync(path.join(D, f), 'utf8'));
const raw = (f) => fs.readFileSync(path.join(D, f), 'utf8');
const M = rd('match.patch.json'), B = rd('batch.patch.json'), WP = rd('workflow.put.json'), W = WP.workflow;
const RM = rd('rev-643697.json'), RB = rd('rev-65b474.json'), OW = rd('.orig-workflow.json');
const canon = (v) => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map((y) => [y, x[y]])) : x));
const eq = (a, b) => canon(a) === canon(b);
const out = []; const ok = (c, m) => { assert.ok(c, m); out.push('PASS ' + m); };
const byId = (g) => Object.fromEntries(g.nodes.map((n) => [n.id, n]));
const BODY = ['nodes', 'edges', 'entry', 'status', 'summary', 'policy_id', 'input_schema', 'output_schema', '$defs'];
const CFG = { code: ['language', 'code', 'filesystem', 'retry', 'timeout', 'cache'], condition: ['language', 'expression', 'expression_file', 'retry', 'timeout'], eval: ['language', 'expression', 'expression_file', 'defaults', 'retry', 'timeout', 'cache'] };

// ---------- fidelity: MATCH vs 643697783a4c
const mI = byId(M), rmI = byId(RM);
ok(Object.keys(M).every((k) => BODY.includes(k)), 'match body keys valid');
ok(RM.nodes.every((n) => eq(mI[n.id], n)), 'match: all 17 nodes of 643697783a4c byte-equivalent (A2A dispatch, settlement, evidence, finalize)');
ok(RM.edges.every((e) => M.edges.some((x) => eq(x, e))) && M.edges.length === RM.edges.length + 2, 'match: all 14 revision edges present, +2 gate edges');
ok(M.nodes.length === 20 && M.entry === 'node_37ce03817f1e', 'match: 20 nodes, entry = gate');
ok(eq(M.input_schema.required, RM.input_schema.required) && M.input_schema.additionalProperties === false, 'match: required unchanged, additionalProperties=false');
const mp = M.input_schema.properties, rmp = RM.input_schema.properties;
ok(mp.round_count.maximum === 5 && mp.history_bars.maximum === 1000 && mp.bars_per_round.maximum === 10000 && Object.keys(rmp).every((k) => ['round_count', 'history_bars', 'bars_per_round'].includes(k) ? eq({ ...mp[k], maximum: undefined }, { ...rmp[k], maximum: undefined }) : eq(mp[k], rmp[k])), 'match: admission maxima round_count<=5, history_bars<=1000, bars_per_round<=10000; other props unchanged');
ok(mp.validation_only.default === true && mp.require_matched_replay.default === true, 'match: gate flags optional, default true');
ok((raw('match.patch.json').match(/"timeout":900\.0/g) || []).length === 4, 'match: A2A timeout encodings 900.0 preserved');

// ---------- fidelity: BATCH vs 65b474cdf302
const bI = byId(B), rbI = byId(RB);
ok(Object.keys(B).every((k) => BODY.includes(k)) && B.entry === RB.entry, 'batch body keys valid, entry unchanged');
const changed = RB.nodes.filter((n) => !eq(bI[n.id], n)).map((n) => n.id).sort();
ok(eq(changed, ['node_0a53eccb6e3a', 'node_81ac4b14b121', 'node_c47e33d099a6', 'node_d08c651a9063', 'node_faed70b2dfd2']), 'batch: only init, prepare, publication, routine-call map, summary changed (' + changed.join(',') + ')');
ok(['node_48beb85bc6dd', 'node_564a5b71b8aa', 'node_dfbb0590a181', 'node_bcbc22fed00b', 'node_542f283f77a9', 'node_c7071b045565', 'node_f7ae7efb2ab1', 'node_8a788c60697a', 'node_58039404d6d0'].every((id) => eq(bI[id], rbI[id])), 'batch: review split, both review A2A nodes, evidence validator, ready gate, conditions, evals byte-equivalent');
for (const id of changed) { const a = bI[id], b = rbI[id]; ok(eq({ ...a, config: { ...a.config, code: 0, input_map: 0 } }, { ...b, config: { ...b.config, code: 0, input_map: 0 } }), `batch ${id}: only code/input_map differ (kind, output_key, timeout, filesystem identical)`); }
const rc = bI.node_81ac4b14b121.config, orc = rbI.node_81ac4b14b121.config;
ok(rc.routine_name === 'paper-trading-competition-v3' && Object.entries(orc.input_map).every(([k, v]) => rc.input_map[k] === v) && Object.keys(rc.input_map).length === Object.keys(orc.input_map).length + 2, 'batch routine call: callable name + original map kept, +validation_only/+require_matched_replay');
const origEdges = RB.edges.filter((e) => e.from !== 'node_564a5b71b8aa');
ok(origEdges.every((e) => B.edges.some((x) => eq(x, e))), 'batch: all revision edges except the more-route present unchanged');
const more = B.edges.find((e) => e.from === 'node_564a5b71b8aa'), rmore = RB.edges.find((e) => e.from === 'node_564a5b71b8aa');
ok(more.branches.true === 'node_fa8d98e0835a' && more.branches.false === rmore.branches.false && eq({ ...more, branches: 0 }, { ...rmore, branches: 0 }), 'batch: more-route true -> review gate (was split); false -> summary unchanged');
ok(B.edges.length === RB.edges.length + 3 && B.nodes.length === 17, 'batch: 14+3 nodes, +3 edges');
const rr = B.edges.find((e) => e.from === 'node_a1dc3dd60120');
ok(rr.branches.true === 'node_dfbb0590a181' && rr.branches.false === 'node_21fb15fcc454' && B.edges.some((e) => e.from === 'node_21fb15fcc454' && e.to === 'node_f7ae7efb2ab1') && B.edges.some((e) => e.from === 'node_fa8d98e0835a' && e.to === 'node_a1dc3dd60120'), 'batch: due -> original split; skip -> original ready gate');
for (const n of B.nodes.concat(M.nodes)) if (CFG[n.kind] && !rbI[n.id] && !rmI[n.id]) ok(Object.keys(n.config).every((k) => CFG[n.kind].includes(k)), `new node ${n.id} (${n.kind}) config keys valid`);
ok(['node_fa8d98e0835a', 'node_a1dc3dd60120', 'node_21fb15fcc454'].every((id) => bI[id]) && ['node_37ce03817f1e', 'node_8d45e44b3779', 'node_f7e9e17dcb9a'].every((id) => mI[id]), 'only parent-generated IDs used');
const bp = B.input_schema.properties;
ok(!B.input_schema.required.includes('validation_only') && !B.input_schema.required.includes('require_matched_replay') && bp.validation_only.default === true && bp.require_matched_replay.default === true, 'batch: flags optional, default true (documentation; seed inserts no defaults)');
ok(eq(B.input_schema.required, RB.input_schema.required.filter((k) => k !== 'validation_only' && k !== 'require_matched_replay')), 'batch: required = original minus the two flags');
ok(!('default' in bp.execution_timeout_seconds) && !('default' in bp.tracks), 'batch: execution_timeout_seconds and tracks have NO schema default');
ok(Object.keys(bp).length === 29 && B.input_schema.additionalProperties === false && bp.tracks.items.additionalProperties === false, 'batch: 29 props, additionalProperties=false (top + tracks.items)');
ok((raw('batch.patch.json').match(/"timeout":(60|900|20000)\.0/g) || []).length === (canon(RB).match(/"timeout":/g) || []).length + 3, 'batch: original timeout encodings preserved (+3 new node timeouts)');
const outKeys = [...new Set(B.nodes.concat(M.nodes).map((n) => n.output_key || n.id))];
ok(!outKeys.some((k) => k in bp || k in mp || k in W.graph.nodes.node_45cef6f22948.output_schema.properties), 'injection guard: no node output_key is an authored input (' + outKeys.length + ' keys)');

// ---------- synthetic logic of actual candidate code
const AF = Object.getPrototypeOf(async function () {}).constructor;
const fn = (g, id) => new AF('input', 'tools', byId(g)[id].config.code);
const init = fn(B, 'node_0a53eccb6e3a'), prep = fn(B, 'node_c47e33d099a6'), pub = fn(B, 'node_d08c651a9063'), summ = fn(B, 'node_faed70b2dfd2'), gateR = fn(B, 'node_fa8d98e0835a'), skip = fn(B, 'node_21fb15fcc454'), valid = fn(B, 'node_c7071b045565'), mgate = fn(M, 'node_37ce03817f1e');
const oprep = new AF('input', 'tools', rbI.node_c47e33d099a6.config.code), opub = new AF('input', 'tools', rbI.node_d08c651a9063.config.code);
const base = { batch_id: 'b1', match_count: 3, round_count: 1, capital: 1000, fee_bps: 10, slippage_bps: 5, history_bars: 60, bars_per_round: 7, brief: 'x', request: 'r', context: {} };
const LEG = { ...base, validation_only: false, require_matched_replay: false };
const mem = () => { const st = {}, reads = []; return { st, reads, tools: { readFile: async (a) => { reads.push(a.file_path); if (a.file_path in st) return st[a.file_path]; throw Error('not found'); }, writeFile: async (a) => { st[a.file_path] = a.content; } } }; };
(async () => {
  // init + summary statuses
  const status = async (inp) => { const p = await init(inp); const m = mem(); const s = await summ({ ...inp, progress: p }, m.tools); return [p.execute, s.status, Object.keys(m.st).length, s.report]; };
  const cases = [
    [{ ...base }, false, 'validation_only_with_replay_blocker', 'flags omitted -> normalized true'],
    [LEG, true, 'completed_unverified_replay', 'legacy explicit false/false'],
    [{ ...LEG, review_enabled: false }, true, 'completed_unverified_replay', 'review_enabled=false supported'],
    [{ ...LEG, review_every_matches: 3 }, true, 'completed_unverified_replay', 'review_every_matches=3 supported'],
    [{ ...LEG, execution_timeout_seconds: 60 }, false, 'blocked_unsupported_config', 'explicit timeout 60 blocked'],
    [{ ...LEG, tracks: [{ track_id: '5m', interval: '5m', market: 'crypto', symbol: 'BTC-USD', data_path: '/artifacts/trading/market/btc-usd-5m.csv' }] }, false, 'blocked_unsupported_config', 'track blocked'],
    [{ ...LEG, evaluation_start: '2026-01-01T00:00:00Z' }, false, 'blocked_unsupported_config', 'window blocked'],
    [{ ...LEG, capital_policy: 'carry' }, false, 'blocked_unsupported_config', 'carry blocked'],
    [{ ...LEG, bonus_rounds: 1 }, false, 'blocked_unsupported_config', 'bonus blocked'],
    [{ ...LEG, agents: ['agent-one', 'x'] }, false, 'blocked_unsupported_config', 'custom agents blocked'],
    [{ ...LEG, require_matched_replay: true }, false, 'blocked_replay', 'replay required'],
    [{ ...base, require_matched_replay: false }, false, 'validation_only', 'validation omitted -> true'],
  ];
  for (const [inp, ex, st, label] of cases) { const [e, s, writes, rep] = await status(inp); assert.strictEqual(e, ex, label); assert.strictEqual(s, st, label); if (inp.validation_only !== false) assert.strictEqual(writes, 0, label + ' wrote'); out.push(`PASS ${label}: execute=${e} status=${s}`); }
  const [, , , rep] = await status({ ...base, review_every_matches: 2 });
  ok(rep.review_plan.review_every_matches === 2 && rep.improvement_evidence.length === 0 && rep.validation_only === true, 'validation-only report exposes review plan only, no review evidence claimed');
  for (const bad of [{ validation_only: 'no' }, { require_matched_replay: 1 }, { review_enabled: 'yes' }, { review_every_matches: 0 }, { review_every_matches: 11 }]) await assert.rejects(init({ ...LEG, ...bad }));
  await assert.rejects(init({ ...LEG, tracks: [{ track_id: 'a' }, { track_id: 'a' }] }), /Duplicate/);
  out.push('PASS init rejects provided non-boolean flags, invalid review settings, duplicate track_id');
  // prepare: flags + handoff equivalence/conditioning
  const P = (idx, eh, over = {}) => prep({ ...LEG, ...over, progress: { index: idx, ledger: [], blocked: false, evidence_history: eh } });
  await assert.rejects(prep({ ...base, progress: { index: 0, ledger: [], blocked: false, evidence_history: [] } }), /Dispatch forbidden/); out.push('PASS prepare throws when flags omitted (normalized true)');
  const reviewed = (k) => ({ after_match: k, evidence: [{ agent: 'agent-one' }] }), skipped = (k) => ({ after_match: k, skipped: true, evidence: [] });
  for (const [idx, eh] of [[0, []], [1, [reviewed(1)]], [2, [reviewed(1), reviewed(2)]]]) {
    const a = await P(idx, eh), o = await oprep({ ...LEG, progress: { index: idx, ledger: [], blocked: false, evidence_history: eh } });
    assert.deepStrictEqual(a, o);
  }
  out.push('PASS prepare output identical to original for default all-reviewed histories (index 0,1,2)');
  ok(!(await P(1, [skipped(1)])).brief.includes('Between-match handoff') && (await P(2, [skipped(1), reviewed(2)])).brief.includes('/match-2'), 'prepare: no handoff after skipped review; handoff targets the actually reviewed match path');
  // publication: peer-tip gate only after actual review; flags normalized
  const mkState = (m, run) => { m.st['/artifacts/trading/' + run + '/state.json'] = JSON.stringify({ run_id: run, rounds: [{ round: 0, benchmark_equity: 1000, agents: Object.fromEntries(['agent-one', 'agent-two'].map((n) => [n, { failures: [], trades_applied: 0, equity: 1000, cumulative_return: 0, round_return: 0, max_drawdown: 0 }])) }], settings: { capital: 1000, round_count: 1, fee_bps: 10, slippage_bps: 5, history_bars: 60, bars_per_round: 7 } }); };
  { const m = mem(); mkState(m, 'b1_m2'); await assert.rejects(pub({ ...base, match: { run_id: 'b1_m2' }, progress: { index: 1, ledger: [{}], evidence_history: [reviewed(1)] } }, m.tools), /Publication forbidden/); out.push('PASS publication throws when flags omitted, before any read'); assert.strictEqual(m.reads.length, 0); }
  { const m = mem(); mkState(m, 'b1_m2'); await assert.rejects(pub({ ...LEG, match: { run_id: 'b1_m2' }, progress: { index: 1, ledger: [{}], evidence_history: [reviewed(1)] } }, m.tools), /not found|peer-tip/); const m2 = mem(); mkState(m2, 'b1_m2'); await assert.rejects(opub({ ...LEG, match: { run_id: 'b1_m2' }, progress: { index: 1, ledger: [{}], evidence_history: [reviewed(1)] } }, m2.tools), /not found|peer-tip/); ok(m.reads.some((p) => p.endsWith('/match-1/agent-two/improvement.json')), 'publication after real review still REQUIRES peer improvement + peer_tip_decisions (same failure as original)'); }
  { const m = mem(); mkState(m, 'b1_m2'); const r = await pub({ ...LEG, match: { run_id: 'b1_m2' }, progress: { index: 1, ledger: [{}], evidence_history: [skipped(1)] } }, m.tools); ok(r.more === true && r.ledger.length === 2 && !m.reads.some((p) => p.includes('improvement.json')), 'publication after skipped review: no nonexistent improvement reads; authoritative state/settings checks + write-once scoreboard still run'); }
  { const m = mem(), m2 = mem(); mkState(m, 'b1_m1'); mkState(m2, 'b1_m1'); const a = await pub({ ...LEG, match: { run_id: 'b1_m1' }, progress: { index: 0, ledger: [], evidence_history: [] } }, m.tools), o = await opub({ ...LEG, match: { run_id: 'b1_m1' }, progress: { index: 0, ledger: [], evidence_history: [] } }, m2.tools); assert.deepStrictEqual(a, o); assert.deepStrictEqual(m.st, m2.st); out.push('PASS publication match 1 output and writes identical to original'); }
  // review gate + skip + ready semantics
  const G = (mr, over = {}) => gateR({ ...LEG, ...over, match_result: mr });
  const mr = (i) => ({ index: i, ledger: Array(i + 1).fill({}), more: true, public_dir: '/shared/competition/b1/match-' + (i + 1) });
  ok((await Promise.all([0, 1, 2, 5, 8].map((i) => G(mr(i))))).every((r) => r.due === true && r.reason === 'review_due'), 'review gate defaults (enabled, every 1): always due -> original split');
  ok((await G(mr(0), { review_enabled: false })).reason === 'skipped_due_to_disabled' && (await G(mr(0), { review_every_matches: 2 })).reason === 'skipped_not_due' && (await G(mr(1), { review_every_matches: 2 })).due === true, 'review gate: disabled -> skipped_due_to_disabled; every 2 -> match1 skipped_not_due, match2 due');
  await assert.rejects(G({ ...mr(0), more: false })); out.push('PASS review gate refuses without authoritative publication+more');
  const gs = await G(mr(0), { review_enabled: false }); const sk = await skip({ ...LEG, match_result: mr(0), review_gate: gs, progress: { index: 0, ledger: [], evidence_history: [] } });
  ok(sk.index === 1 && sk.ledger.length === 1 && sk.blocked === false && sk.evidence_history[0].skipped === true && sk.evidence_history[0].review === 'skipped_due_to_disabled' && sk.evidence_history[0].test_truth === 'not_run' && sk.evidence_history[0].strategy_promotion === 'none' && !('validation' in sk.evidence_history[0]), 'skip: advances index/ledger/evidence_history, records truthful skip, no evidence pass/promotion');
  await assert.rejects(skip({ ...LEG, match_result: mr(0), review_gate: await G(mr(0)), progress: { index: 0, ledger: [], evidence_history: [] } })); out.push('PASS skip refuses a due review (cannot bypass validator)');
  { const m = mem(); const v = await valid({ ...LEG, match_result: mr(0), progress: { index: 0, ledger: [], evidence_history: [] } }, m.tools); ok(v.blocked === true && v.index === 1, 'due path: original evidence validator still blocks advancement on missing review evidence'); }
  // match gate
  const mg = (o) => mgate({ request: {}, context: {}, run_id: 'r', ...o });
  ok((await mg({})).execute === false && (await mg({})).status === 'validation_only_with_replay_blocker' && (await mg({ validation_only: true, require_matched_replay: true })).execute === false && (await mg({ validation_only: false, require_matched_replay: false })).execute === true, 'match gate: omitted/true -> no dispatch; only explicit false/false continues');
  await assert.rejects(mg({ validation_only: 'x' })); out.push('PASS match gate rejects non-boolean');
  // workflow
  const mpw = W.graph.nodes.node_45cef6f22948.output_schema.properties;
  ok(WP.path === W.id && W.created_at === OW.created_at && eq(W.ui, OW.ui) && W.title === OW.title && W.enabled && !W.paused && W.version === OW.version && W.notify_on_pause === OW.notify_on_pause, 'workflow: id/created_at/ui/title/enabled/paused/version/notify preserved');
  ok(!W.graph.nodes.node_3a3f6fc82872 && !W.graph.edges.some((e) => e.from.node === 'node_3a3f6fc82872' || e.to.node === 'node_3a3f6fc82872'), 'workflow: daily formatter + edges removed');
  ok(eq(Object.keys(mpw).sort(), Object.keys(bp).sort()) && Object.keys(mpw).every((k) => W.graph.edges.filter((e) => e.from.node === 'node_45cef6f22948' && e.from.port === k && e.to.node === 'node_82566e054c56' && e.to.port === k).length === 1) && W.graph.edges.filter((e) => e.from.node === 'node_45cef6f22948').length === 29, 'workflow: 29 manual fields each wired once to same-named batch port');
  ok(eq(W.graph.edges.filter((e) => e.from.node !== 'node_45cef6f22948').map(canon).sort(), OW.graph.edges.filter((e) => e.from.node !== 'node_45cef6f22948' && e.from.node !== 'node_3a3f6fc82872').map(canon).sort()), 'workflow: status/report/message/title edges unchanged');
  ok(mpw.execution_timeout_seconds.default === 60 && mpw.tracks.default.length === 3 && mpw.validation_only.default === true && mpw.require_matched_replay.default === true && mpw.additionalProperties === undefined && W.graph.nodes.node_45cef6f22948.output_schema.additionalProperties === false, 'workflow manual: timeout default 60, 3 default tracks, flags true; additionalProperties=false');
  const wfDef = Object.fromEntries(Object.entries(mpw).filter(([, v]) => 'default' in v).map(([k, v]) => [k, v.default]));
  { const [e, s] = await status({ ...base, ...wfDef, batch_id: 'x' }); ok(e === false && s === 'blocked_unsupported_config', 'workflow defaults -> blocked_unsupported_config, no child call'); }
  console.log(out.join('\n')); console.log(`\n${out.length} checks passed`);
})().catch((e) => { console.log(out.join('\n')); console.error('FAIL', e.stack); process.exit(1); });
