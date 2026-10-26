function generatedRunId(batch,track,index){return 'r_b'+batch.length+'_'+batch+'_t'+track.length+'_'+track+'_m'+index;}
function normalizeCommon(input){
const errors = [], errorKeys = new Map();
function err(code, field, message, detail) {
  const key = code + ':' + field;
  if (errorKeys.has(key)) { errorKeys.get(key).occurrences++; return; }
  const e = {code, field, message, occurrences: 1};
  if (detail !== undefined) e.detail = detail;
  errorKeys.set(key, e); errors.push(e);
}
const own = (o,k) => Object.prototype.hasOwnProperty.call(o,k);
const obj = o => o !== null && typeof o === 'object' && !Array.isArray(o);
const safeId = x => typeof x === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$(?![\s\S])/.test(x);
const safeRunId = x => typeof x === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,159}$(?![\s\S])/.test(x);
const safePath = x => typeof x === 'string' && x.length <= 1024 && /^\/(artifacts\/trading\/market|shared\/market)\/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*(?:\/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)*$(?![\s\S])/.test(x);
function utc(x) {
  if (typeof x !== 'string' || !/^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$(?![\s\S])/.test(x)) return null;
  const n = Date.parse(x);
  return Number.isFinite(n) && new Date(n).toISOString() === x.slice(0,-1) + '.000Z' ? n : null;
}
const iso = n => new Date(n).toISOString().replace('.000Z','Z');
const defaults = {
  agents: ['agent-one','agent-two'],
  tracks: ['5m','15m','1h'].map(interval => ({track_id:interval,interval,market:'crypto',symbol:'BTC-USD',data_path:'/artifacts/trading/market/btc-usd-'+interval+'.csv'})),
  evaluation_start:null, evaluation_end:null, timezone:'UTC', match_count:10, round_count:5,
  history_bars:60, bars_per_round:7, capital:1000, fee_bps:10, slippage_bps:5,
  capital_policy:'reset', fill_policy:'next_close', finalization_policy:'mark_to_market',
  review_enabled:true, review_every_matches:1, evidence_required:true, bonus_rounds:0,
  tie_policy:'no_bonus', bonus_cash_comparator:'zero_return', execution_timeout_seconds:60,
  max_retries:0, failure_policy:'fail_closed', validation_only:true, require_matched_replay:true,
  brief:'paper recursive self improvement'
};
const source = typeof input !== 'undefined' && obj(input) ? input : {};
if (typeof input === 'undefined' || !obj(input)) err('invalid_input','input','Input must be an object.');
const allowed = new Set(Object.keys(defaults).concat(['batch_id','validation_as_of']));
for (const k of Object.keys(source)) if (!allowed.has(k) && !['request','context','progress','job','child','child_report','child_status','summary','status','report','more'].includes(k)) err('unknown_property', k, 'Unknown authored input property.');
const contract = {};
for (const k of allowed) {
  if (own(source,k)) contract[k] = source[k];
  else if (own(defaults,k)) contract[k] = defaults[k];
}
function integer(v,lo,hi,p) {
  const ok = Number.isInteger(v) && v >= lo && v <= hi;
  if (!ok) err('invalid_integer',p,'Expected an integer in the inclusive bounds.',{minimum:lo,maximum:hi});
  return ok;
}
function number(v,lo,hi,exclusiveLo,exclusiveHi,p) {
  const ok = typeof v === 'number' && Number.isFinite(v) && (exclusiveLo ? v>lo : v>=lo) && (exclusiveHi ? v<hi : v<=hi);
  if (!ok) err('invalid_number',p,'Expected a finite number within the contract bounds.');
  return ok;
}
function agents(v,p) {
  if (!Array.isArray(v) || v.length !== 2 || new Set(v).size !== 2 || !v.every(safeId)) err('invalid_agents',p,'Exactly two unique safe agent names are required.');
  if (Array.isArray(v) && v.some(a => a !== 'agent-one' && a !== 'agent-two')) err('unsupported_agents',p,'Only agent-one and agent-two are supported; no alternate agent can execute.');
}
for (const k of ['batch_id']) if (!safeId(contract[k])) err('invalid_safe_id',k,'A safe ID is required: 1..64 ASCII alphanumeric, underscore or hyphen, starting alphanumeric.');
for (const [k,lo,hi] of [['match_count',1,10],['round_count',1,5],['history_bars',10,1000],['bars_per_round',1,10000],['review_every_matches',1,10],['bonus_rounds',0,3]]) integer(contract[k],lo,hi,k);
const capitalOK = number(contract.capital,0,Infinity,true,false,'capital');
const feeBpsOK = number(contract.fee_bps,0,Infinity,false,false,'fee_bps');
const slippageBpsOK = number(contract.slippage_bps,0,10000,false,true,'slippage_bps');
for (const k of ['review_enabled','validation_only','require_matched_replay']) if (typeof contract[k] !== 'boolean') err('invalid_boolean',k,'Expected boolean.');
for (const [k,v] of Object.entries({timezone:'UTC',fill_policy:'next_close',finalization_policy:'mark_to_market',evidence_required:true,tie_policy:'no_bonus',bonus_cash_comparator:'zero_return',execution_timeout_seconds:60,max_retries:0,failure_policy:'fail_closed'})) if (contract[k] !== v) err('invalid_constant',k,'Fixed contract setting.',{required:v});
if (!['reset','carry'].includes(contract.capital_policy)) err('invalid_capital_policy','capital_policy','Expected reset or carry.');
if (contract.capital_policy === 'carry') err('carry_unsupported','capital_policy','Carry is unsupported by the current adapter; no execution.');
if (typeof contract.bonus_rounds === 'number' && contract.bonus_rounds > 0) err('bonus_rounds_unsupported','bonus_rounds','Bonus rounds are unsupported; no execution.');
if (typeof contract.brief !== 'string') err('invalid_string','brief','Expected a string.');
agents(contract.agents,'agents');
const trackKeys = new Set(['track_id','interval','market','symbol','data_path','history_bars','bars_per_round','agents']);
function checkTrack(t,p) {
  if (!obj(t)) { err('invalid_track',p,'Expected a track object.'); return; }
  for (const k of Object.keys(t)) if (!trackKeys.has(k)) err('unknown_property',p+'.'+k,'Unknown track property.');
  if (!safeId(t.track_id)) err('invalid_safe_id',p+'.track_id','A safe track ID is required.');
  if (!['5m','15m','1h'].includes(t.interval)) err('invalid_interval',p+'.interval','Supported intervals are 5m, 15m, 1h only.');
  for (const [k,max] of [['market',64],['symbol',128]]) if (typeof t[k] !== 'string' || t[k].length<1 || t[k].length>max) err('invalid_string',p+'.'+k,'Expected a nonempty bounded string.');
  if (!safePath(t.data_path)) err('unsafe_data_path',p+'.data_path','Use an exact safe path under /artifacts/trading/market/ or /shared/market/; no dot segments, backslashes or glob syntax.');
  if (own(t,'history_bars')) integer(t.history_bars,10,1000,p+'.history_bars');
  if (own(t,'bars_per_round')) integer(t.bars_per_round,1,10000,p+'.bars_per_round');
  if (own(t,'agents')) agents(t.agents,p+'.agents');
}
if (!Array.isArray(contract.tracks) || contract.tracks.length<1 || contract.tracks.length>3) err('invalid_tracks','tracks','Expected 1..3 tracks.');
if (Array.isArray(contract.tracks)) {
  const ids = new Set();
  contract.tracks.forEach((t,i) => { checkTrack(t,'tracks['+i+']'); if (obj(t)) { if (ids.has(t.track_id)) err('duplicate_track_id','tracks','Track IDs must be unique.'); ids.add(t.track_id); } });
}
const start=utc(contract.evaluation_start), end=utc(contract.evaluation_end), asof=utc(contract.validation_as_of);
for(const k of ['evaluation_start','evaluation_end'])if(contract[k]!==null && utc(contract[k])===null)err('invalid_utc_timestamp',k,'Expected null or a real UTC calendar timestamp YYYY-MM-DDTHH:mm:ssZ.');
if(asof===null)err('validation_as_of_required','validation_as_of','Explicit valid UTC validation_as_of is required; no wall clock is consulted.');
if(start!==null && end!==null && start>=end)err('invalid_window_order','evaluation_end','Start must be strictly before end.');
if(end!==null && asof!==null && end>asof)err('evaluation_after_validation_as_of','evaluation_end','Evaluation end exceeds validation_as_of.');
if(Array.isArray(contract.tracks))for(let i=0;i<contract.tracks.length;i++){
  const t=contract.tracks[i];if(!obj(t))continue;
  const dt=own({'5m':1,'15m':1,'1h':1},t.interval)?({'5m':300000,'15m':900000,'1h':3600000})[t.interval]:null;
  const bpr=own(t,'bars_per_round')?t.bars_per_round:contract.bars_per_round;
  if(dt){
    for(const [k,n] of [['evaluation_start',start],['evaluation_end',end]])if(n!==null && n%dt!==0)err('window_not_interval_aligned','tracks['+i+'].'+k,'Evaluation endpoints must align to the track UTC interval.');
    if(start!==null && end!==null && Number.isInteger(bpr) && Number.isInteger(contract.round_count) && end-start!==contract.round_count*bpr*dt)err('mismatched_duration','tracks['+i+'].bars_per_round','Window duration must equal round_count * effective bars_per_round * interval_ms.');
    if(end!==null && asof!==null && end+dt>asof)err('next_fill_after_validation_as_of','tracks['+i+']','The next-fill close must not exceed validation_as_of.');
  }
}
if(Array.isArray(contract.tracks) && Number.isInteger(contract.match_count) && contract.tracks.length*contract.match_count>30)err('batch_job_limit','tracks','At most 30 validation jobs are permitted.');
if(errors.length)throw new Error('invalid_batch_settings: '+JSON.stringify(errors));
contract.tracks=contract.tracks.map(t=>{const n=Object.assign({},t);for(const k of ['history_bars','bars_per_round','agents'])if(!own(n,k))n[k]=contract[k];return n;});
for(const t of contract.tracks)for(let n=1;n<=contract.match_count;n++){
  const id=generatedRunId(contract.batch_id,t.track_id,n);
  if(!safeRunId(id))throw new Error('derived_run_id_invalid: '+id+'; combined run ID must fit the per-match 160-character safe-ID bound.');
}
return JSON.parse(JSON.stringify(contract));
}
const own=(o,k)=>Object.prototype.hasOwnProperty.call(o,k);
const obj=o=>o!==null && typeof o==='object' && !Array.isArray(o);
function strict(o,keys,path){
  if(!obj(o))throw new Error('invalid_object: '+path);
  for(const k of Object.keys(o))if(!keys.includes(k))throw new Error('unsupported_field: '+path+'.'+k);
  for(const k of keys)if(!own(o,k))throw new Error('missing_field: '+path+'.'+k);
}
function equal(a,b){
  if(a===b)return true;
  if(Array.isArray(a) && Array.isArray(b))return a.length===b.length && a.every((v,i)=>equal(v,b[i]));
  if(!obj(a) || !obj(b))return false;
  const x=Object.keys(a).sort(),y=Object.keys(b).sort();
  return x.length===y.length && x.every((k,i)=>k===y[i] && equal(a[k],b[k]));
}
function commonOf(job){
  if(!obj(job))throw new Error('invalid_job');
  const common=Object.assign({},job);delete common.run_id;delete common.track;delete common.match_index;return common;
}
function checkChild(child,job){
  strict(child,['status','report'],'child');
  const r=child.report;
  strict(r,['contract','effective_track','track_id','validation','errors','blockers','execution','review','namespaces','results','leaderboard','drawdown','cash_comparator','comparators','evidence','files_written','orders_placed'],'child.report');
  if(!obj(r.contract) || r.contract.run_id!==job.run_id || !obj(r.contract.track) || r.contract.track.track_id!==job.track.track_id || r.contract.match_index!==job.match_index || !equal(r.contract,job) || r.track_id!==job.track.track_id || !equal(r.effective_track,job.track))throw new Error('child_identity_mismatch: '+job.run_id);
  strict(r.validation,['passed','mode','validation_as_of','as_of_is_trusted_wall_clock','data'],'child.report.validation');
  strict(r.execution,['available','requested','dispatched','blockers','reason'],'child.report.execution');
  strict(r.review,['enabled','every_matches','state','performed'],'child.report.review');
  strict(r.evidence,['required','competition_executed','independent_replay_performed','real_intraday_proof'],'child.report.evidence');
  const expectedBlockers=['namespace_reservation_unavailable',job.require_matched_replay?'independent_replay_unavailable':'replay_gate_bypass_forbidden'];
  if(!Array.isArray(r.errors) || !r.errors.every(e=>obj(e) && typeof e.code==='string') || !Array.isArray(r.blockers) || !r.blockers.every(x=>typeof x==='string'))throw new Error('invalid_child_errors');
  if(!equal(r.execution.blockers,expectedBlockers) || !expectedBlockers.every(x=>r.blockers.includes(x)) || !r.errors.every(e=>r.blockers.includes(e.code)))throw new Error('child_execution_gate_mismatch');
  const passed=r.errors.length===0;
  if(r.validation.passed!==passed || child.status!==(passed?'validation_passed_execution_blocked':'blocked'))throw new Error('child_status_mismatch');
  if(r.validation.mode!=='read_only' || r.validation.validation_as_of!==job.validation_as_of || r.validation.as_of_is_trusted_wall_clock!==false || !obj(r.validation.data))throw new Error('child_validation_mode_mismatch');
  if(passed && r.validation.data.status!=='valid_against_supplied_as_of')throw new Error('child_data_status_mismatch');
  if(r.execution.available!==false || r.execution.dispatched!==false || r.execution.requested!==(job.validation_only===false) || typeof r.execution.reason!=='string')throw new Error('child_dispatch_claim_forbidden');
  if(r.files_written!==false || r.orders_placed!==false || r.drawdown!==null || r.cash_comparator!==0 || !Array.isArray(r.results) || r.results.length || !Array.isArray(r.leaderboard) || r.leaderboard.length)throw new Error('child_actual_results_forbidden');
  if(r.review.enabled!==job.review_enabled || r.review.every_matches!==job.review_every_matches || r.review.state!=='not_run' || r.review.performed!==false)throw new Error('child_review_claim_forbidden');
  if(r.evidence.required!==true || r.evidence.competition_executed!==false || r.evidence.independent_replay_performed!==false || r.evidence.real_intraday_proof!==false)throw new Error('child_evidence_claim_forbidden');
  strict(r.comparators,['cash','buy_and_hold'],'child.report.comparators');
  strict(r.comparators.cash,['return_fraction','drawdown','executed'],'child.report.comparators.cash');
  if(r.comparators.cash.return_fraction!==0 || r.comparators.cash.drawdown!==null || r.comparators.cash.executed!==false)throw new Error('child_cash_comparator_mismatch');

  const b=r.comparators.buy_and_hold;
  if(b===null){
    if(passed)throw new Error('child_benchmark_missing');
  }else{
    strict(b,['status','kind','source_verification','batch_id','run_id','track_id','match_index','interval','market','symbol','data_path','capital','fee_bps','slippage_bps','fill_policy','entry_close','entry_reference_price','entry_execution_price','units','entry_fee','mark_close','mark_price','ending_equity','pnl','return_fraction','finalization_policy','forced_liquidation','exit_fee','drawdown','competition_executed'],'child.report.comparators.buy_and_hold');
    const nums=['capital','fee_bps','slippage_bps','entry_reference_price','entry_execution_price','units','entry_fee','mark_price','ending_equity','pnl','return_fraction','exit_fee'];
    if(!nums.every(k=>typeof b[k]==='number'&&Number.isFinite(b[k])))throw new Error('child_benchmark_nonfinite_number');
    if(b.entry_reference_price<=0||b.entry_execution_price<=0||b.units<=0||b.mark_price<=0||b.ending_equity<=0||b.entry_fee<0)throw new Error('child_benchmark_invalid_number');
    const links={status:'available_reference_calculation_only',kind:'cost_matched_buy_and_hold',source_verification:'unverified_child_reference_data',batch_id:job.batch_id,run_id:job.run_id,track_id:job.track.track_id,match_index:job.match_index,interval:job.track.interval,market:job.track.market,symbol:job.track.symbol,data_path:job.track.data_path,capital:job.capital,fee_bps:job.fee_bps,slippage_bps:job.slippage_bps,fill_policy:'next_close',entry_close:new Date(Date.parse(job.evaluation_start)+({'5m':300000,'15m':900000,'1h':3600000})[job.track.interval]).toISOString().replace('.000Z','Z'),mark_close:job.evaluation_end,finalization_policy:'mark_to_market',forced_liquidation:false,exit_fee:0,drawdown:null,competition_executed:false};
    if(!Object.keys(links).every(k=>b[k]===links[k]))throw new Error('child_benchmark_contract_linkage_mismatch');
    if(r.validation.data.status!=='valid_against_supplied_as_of'||r.validation.data.path!==job.track.data_path||r.validation.data.required_history_bars!==job.track.history_bars||r.validation.data.required_evaluation_bars!==job.round_count*job.track.bars_per_round||r.validation.data.required_next_fill_bars!==1)throw new Error('child_benchmark_data_linkage_mismatch');
    const executionPrice=b.entry_reference_price*(1+job.slippage_bps/10000),feeRate=job.fee_bps/10000;
    const units=(job.capital/(1+feeRate))/executionPrice,notional=units*executionPrice;
    const entryFee=notional*feeRate,equity=units*b.mark_price,pnl=equity-job.capital,ret=pnl/job.capital;
    if(![executionPrice,units,notional,entryFee,equity,pnl,ret].every(Number.isFinite)||b.entry_execution_price!==executionPrice||b.units!==units||b.entry_fee!==entryFee||b.ending_equity!==equity||b.pnl!==pnl||b.return_fraction!==ret)throw new Error('child_benchmark_arithmetic_mismatch');
  }

  const expectedNamespaces=job.track.agents.map(agent=>{const base='/artifacts/trading/'+job.batch_id+'/'+job.track.track_id+'/match-'+job.match_index+'/'+agent;return {agent,namespace:base,account_namespace:base+'/account',artifact_namespace:base+'/artifacts',strategy_namespace:base+'/strategy',planned_initial_capital:job.capital,created:false,reserved:false,write_authorized:false,reuse_policy:'future_writes_forbidden_until_separate_reservation'};});
  if(!equal(r.namespaces,expectedNamespaces))throw new Error('child_namespace_mismatch');
}
function checkProgress(p,needJob){
  strict(p,['index','jobs','results','errors'],'progress');
  if(!Array.isArray(p.jobs) || p.jobs.length<1 || p.jobs.length>30 || !Array.isArray(p.results) || !Array.isArray(p.errors))throw new Error('invalid_progress_arrays');
  if(!Number.isInteger(p.index) || p.index<0 || p.index>p.jobs.length || p.results.length!==p.index || (needJob && p.index===p.jobs.length))throw new Error('progress_index_out_of_bounds_or_out_of_order');
  const common=normalizeCommon(commonOf(p.jobs[0]));
  if(p.jobs.length!==common.tracks.length*common.match_count)throw new Error('job_plan_count_mismatch');
  for(let i=0;i<p.jobs.length;i++){
    const track=common.tracks[i%common.tracks.length],match_index=Math.floor(i/common.tracks.length)+1;
    const expected=Object.assign({},common,{run_id:generatedRunId(common.batch_id,track.track_id,match_index),track,match_index});
    if(!equal(p.jobs[i],expected))throw new Error('job_plan_identity_mismatch: '+i);
    if(i<p.index)checkChild(p.results[i],p.jobs[i]);
  }
  return common;
}
const authoredKeys=["batch_id","agents","tracks","evaluation_start","evaluation_end","validation_as_of","timezone","match_count","round_count","history_bars","bars_per_round","capital","fee_bps","slippage_bps","capital_policy","fill_policy","finalization_policy","review_enabled","review_every_matches","evidence_required","bonus_rounds","tie_policy","bonus_cash_comparator","execution_timeout_seconds","max_retries","failure_policy","validation_only","require_matched_replay","brief"];
function checkNodeInput(o,required){
  if(!obj(o))throw new Error('invalid_object: input');
  for(const k of required)if(!own(o,k))throw new Error('missing_field: input.'+k);
}
function checkOuterCommon(o,common){
  const merged=Object.assign({},common);
  for(const k of authoredKeys)if(own(o,k))merged[k]=o[k];
  if(!equal(normalizeCommon(merged),common))throw new Error('outer_common_settings_mismatch');
}
checkNodeInput(input,['progress']);
const p=input.progress,common=checkProgress(p,false);checkOuterCommon(input,common);
const errors=p.errors.map(e=>({source:'progress',code:obj(e) && typeof e.code==='string'?e.code:'progress_error',error:e}));
if(p.index!==p.jobs.length)errors.push({source:'batch',code:'batch_incomplete',validated_jobs:p.index,planned_jobs:p.jobs.length});
const job_validation_reports=p.jobs.map((job,i)=>{
  const child=i<p.index?p.results[i]:null;
  if(child)for(const e of child.report.errors)errors.push({source:'validator',run_id:job.run_id,track_id:job.track.track_id,match_index:job.match_index,error:e,code:e.code});
  return {run_id:job.run_id,track_id:job.track.track_id,match_index:job.match_index,normalized_input:job,status:child?child.status:'not_validated',report:child?child.report:null};
});
const tracks=common.tracks.map(track=>{
  const jobs=job_validation_reports.filter(j=>j.track_id===track.track_id),validated=jobs.filter(j=>j.report!==null),failed=validated.filter(j=>j.report.validation.passed!==true);
  const validation_status=failed.length?'validation_failed':validated.length!==jobs.length?'incomplete':'validation_passed';
  return {track_id:track.track_id,effective_track:track,validation_status,planned_matches:common.match_count,validated_jobs:validated.length,failed_validation_jobs:failed.length,completed_matches:0,trading_dispatches:0,match_results:[],leaderboard:[],leaderboards:[],drawdown:null,job_validation_statuses:jobs.map(j=>({run_id:j.run_id,match_index:j.match_index,status:j.status,validation_passed:j.report?j.report.validation.passed:false}))};
});
const passed=errors.length===0 && p.index===p.jobs.length && tracks.every(t=>t.validation_status==='validation_passed');
const executionBlockers=['namespace_reservation_unavailable',common.require_matched_replay?'independent_replay_unavailable':'replay_gate_bypass_forbidden'];
const blockers=Array.from(new Set(errors.map(e=>e.code).concat(executionBlockers,p.results.flatMap(child=>child.report.blockers))));
const planned_after_matches=[];
if(common.review_enabled)for(let n=common.review_every_matches;n<common.match_count;n+=common.review_every_matches)planned_after_matches.push(n);
const status=!passed?'validation_failed':common.validation_only?'validation_only_blocked_replay':'blocked_execution';
return {status,report:{
  batch_id:common.batch_id,normalized_contract:common,tracks,job_validation_reports,errors,blockers,
  validation:{passed,planned_jobs:p.jobs.length,completed_validation_jobs:p.index,validation_as_of:common.validation_as_of,as_of_is_trusted_wall_clock:false},
  execution:{available:false,requested:common.validation_only===false,dispatched:false,blockers:executionBlockers,reason:'Current runs fail closed before dispatch because no trusted independent matched-replay provider or namespace reservation adapter is installed. A timestamp-aware deterministic accounting candidate exists but still requires legacy adapter integration and review. Synthetic self-checks and caller flags are not independent evidence; replay bypass is forbidden. The executable competitor and between-match review topology must be preserved behind these capability gates.'},
  review:{enabled:common.review_enabled,every_matches:common.review_every_matches,planned_after_matches,per_track:common.tracks.map(t=>({track_id:t.track_id,planned_after_matches:planned_after_matches.slice()})),state:'not_run',performed:false},
  completed_matches:0,trading_dispatches:0,match_results:[],leaderboard:[],leaderboards:[],drawdown:null,cash_comparator:0,
  comparison_policy:'per_job_reference_calculations_only_no_raw_pnl_pooling',reference_verification:'contract_and_arithmetic_only; source_prices_are_unverified_child_reference_data',
  competition_executed:false,orders_placed:false,trading_performed:false,review_tests_performed:false,reviews_performed:0,bonus_rounds_performed:0,replay_performed:false,matched_replays_performed:0,real_intraday_proof:false,files_written:false
}};
