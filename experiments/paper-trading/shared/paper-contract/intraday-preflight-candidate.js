const PaperIntraday = (() => {
'use strict';
const intervals={'5m':300000,'15m':900000,'1h':3600000};
const object=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
const copy=x=>JSON.parse(JSON.stringify(x));
const finite=x=>typeof x==='number'&&Number.isFinite(x);
const safe=x=>typeof x==='string'&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$(?![\s\S])/.test(x);
const iso=t=>new Date(t).toISOString().replace('.000Z','Z');
function fail(code){throw new Error(code);}
function utc(s){if(typeof s!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$(?![\s\S])/.test(s))fail('invalid_utc_timestamp');const t=Date.parse(s);if(!Number.isFinite(t)||iso(t)!==s)fail('invalid_utc_timestamp');return t;}
function equal(a,b){if(a===b)return true;if(Array.isArray(a)&&Array.isArray(b))return a.length===b.length&&a.every((v,i)=>equal(v,b[i]));if(!object(a)||!object(b))return false;const x=Object.keys(a).sort(),y=Object.keys(b).sort();return x.length===y.length&&x.every((k,i)=>k===y[i]&&equal(a[k],b[k]));}
function exact(o,keys,p){if(!object(o)||Object.keys(o).length!==keys.length||!keys.every(k=>Object.prototype.hasOwnProperty.call(o,k)))fail('invalid_shape:'+p);}
function runId(b,t,n){return 'r_b'+b.length+'_'+b+'_t'+t.length+'_'+t+'_m'+n;}
function normalizedTrack(c,t){const n=Object.assign({},t);for(const k of ['history_bars','bars_per_round','agents'])if(!Object.prototype.hasOwnProperty.call(n,k))n[k]=c[k];return n;}
function checkContract(c){
 if(!object(c)||!safe(c.batch_id)||!object(c.track)||!safe(c.track.track_id))fail('invalid_identity');
 if(!Number.isInteger(c.match_count)||c.match_count<1||c.match_count>10||!Number.isInteger(c.match_index)||c.match_index<1||c.match_index>c.match_count||!Number.isInteger(c.round_count)||c.round_count<1||c.round_count>5)fail('invalid_match_round_bounds');
 if(c.run_id!==runId(c.batch_id,c.track.track_id,c.match_index))fail('noncanonical_generated_run_id');
 if(!Array.isArray(c.tracks)||c.tracks.length<1||c.tracks.length>3||new Set(c.tracks.map(t=>t.track_id)).size!==c.tracks.length||!c.tracks.some(t=>equal(normalizedTrack(c,t),c.track)))fail('selected_track_mismatch');
 const t=c.track,dt=intervals[t.interval];if(!dt||!Number.isInteger(t.history_bars)||t.history_bars<10||t.history_bars>1000||!Number.isInteger(t.bars_per_round)||t.bars_per_round<1||t.bars_per_round>10000)fail('invalid_effective_track');
 if(!Array.isArray(t.agents)||t.agents.length!==2||new Set(t.agents).size!==2||!t.agents.every(a=>a==='agent-one'||a==='agent-two'))fail('unsupported_agents');
 if(typeof t.market!=='string'||typeof t.symbol!=='string'||typeof t.data_path!=='string'||!/^\/(?:artifacts\/trading\/market|shared\/market)\/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*(?:\/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)*$(?![\s\S])/.test(t.data_path))fail('invalid_instrument_metadata_or_path');
 const start=utc(c.evaluation_start),end=utc(c.evaluation_end),asof=utc(c.validation_as_of);
 if(start>=end||start%dt||end%dt||end-start!==c.round_count*t.bars_per_round*dt||end+dt>asof)fail('invalid_timestamp_window_or_coverage_horizon');
 if(!finite(c.capital)||c.capital<=0||!finite(c.fee_bps)||c.fee_bps<0||!finite(c.slippage_bps)||c.slippage_bps<0||c.slippage_bps>=10000)fail('invalid_costs');
 if(c.capital_policy!=='reset')fail('carry_unsupported');if(c.bonus_rounds!==0)fail('bonus_rounds_unsupported');
 if(c.timezone!=='UTC'||c.fill_policy!=='next_close'||c.finalization_policy!=='mark_to_market'||c.execution_timeout_seconds!==60||c.max_retries!==0||c.failure_policy!=='fail_closed'||c.evidence_required!==true||c.tie_policy!=='no_bonus'||c.bonus_cash_comparator!=='zero_return')fail('unsupported_contract_constant');
 if(typeof c.validation_only!=='boolean'||typeof c.require_matched_replay!=='boolean'||typeof c.review_enabled!=='boolean'||!Number.isInteger(c.review_every_matches)||c.review_every_matches<1||c.review_every_matches>10)fail('invalid_boolean_or_review_cadence');
 if('fees' in c||'slippage' in c||'replay_verified' in c||'independent_replay_available' in c)fail('unsupported_setting_or_untrusted_evidence');
 return {dt,start,end,asof};
}
function validateBars(c,bars){
 const h=checkContract(c);if(!Array.isArray(bars)||bars.length===0||bars.length>=9999)fail('bounded_market_rows_required');
 let prev=null;const map=new Map();for(const b of bars){
  exact(b,['timestamp','open','high','low','close','volume','closed'],'bar');const t=utc(b.timestamp);
  if(b.closed!==true||t>h.asof||t%h.dt||prev!==null&&t-prev!==h.dt)fail('incomplete_future_or_noncontiguous_bar');
  if(!['open','high','low','close','volume'].every(k=>finite(b[k]))||b.open<=0||b.high<=0||b.low<=0||b.close<=0||b.volume<0||b.low>Math.min(b.open,b.close)||b.high<Math.max(b.open,b.close)||b.low>b.high)fail('invalid_ohlcv');
  map.set(t,b);prev=t;
 }
 const first=h.start-(c.track.history_bars-1)*h.dt,last=h.end+h.dt;
 if((last-first)/h.dt+1>bars.length)fail('insufficient_contiguous_coverage');
 for(let t=first;t<=last;t+=h.dt)if(!map.has(t))fail('missing_required_close');
 return {h,map};
}
function namespace(c,agent){const base='/artifacts/trading/'+c.batch_id+'/'+c.track.track_id+'/match-'+c.match_index+'/'+agent;return {agent,namespace:base,account_namespace:base+'/account',artifact_namespace:base+'/artifacts',strategy_namespace:base+'/strategy',created:false,reserved:false,write_authorized:false,reuse_policy:'future_writes_forbidden_until_separate_reservation'};}
function readiness(c){
 checkContract(c);
 return {dispatch_allowed:false,independent_replay_available:false,reservation_available:false,blockers:[c.require_matched_replay?'independent_replay_unavailable':'replay_gate_bypass_forbidden','namespace_reservation_unavailable'],reason:'No trusted independent matched-replay provider or namespace reservation adapter is installed. A caller-supplied flag or synthetic self-check cannot satisfy either gate. Preserve the executable dispatch/settlement path behind these pre-dispatch capability checks.'};
}
function assertExecutionReadiness(c){const r=readiness(c);if(!r.dispatch_allowed)fail('pre_dispatch_blocked:'+r.blockers.join(','));return r;}
function create(c,bars){
 const v=validateBars(c,bars),accounts={};for(const agent of c.track.agents)accounts[agent]={cash:c.capital,units:0,cost_basis:0,realized_pnl:0,fees:0,slippage_cost:0,equity:c.capital,peak_equity:c.capital,max_drawdown:0,fills:[],marks:[{timestamp:c.evaluation_start,equity:c.capital}]};
 return {engine_version:'intraday-candidate-0.1',contract:copy(c),market_bars:copy(bars),phase:'ready',round_index:0,accounts,rounds:[],namespaces:c.track.agents.map(a=>namespace(c,a)),independent_replay_performed:false};
}
function checkState(s){
 if(!object(s)||s.engine_version!=='intraday-candidate-0.1'||!Array.isArray(s.rounds)||!Number.isInteger(s.round_index)||s.round_index<0||s.round_index>s.contract.round_count||s.rounds.length!==s.round_index)fail('invalid_engine_state');
 const v=validateBars(s.contract,s.market_bars);if(!equal(s.namespaces,s.contract.track.agents.map(a=>namespace(s.contract,a))))fail('namespace_identity_mismatch');
 for(const agent of s.contract.track.agents){const a=s.accounts[agent];if(!object(a)||!['cash','units','cost_basis','realized_pnl','fees','slippage_cost','equity','peak_equity','max_drawdown'].every(k=>finite(a[k]))||a.cash<0||a.units<0||a.cost_basis<0||a.fees<0||a.slippage_cost<0||a.equity<0||a.peak_equity<s.contract.capital||a.max_drawdown<0||a.max_drawdown>1||!Array.isArray(a.fills)||!Array.isArray(a.marks))fail('invalid_private_account');}
 return v;
}
function publicView(s,agent){
 const v=checkState(s),c=s.contract;if(!c.track.agents.includes(agent)||s.round_index>=c.round_count)fail('invalid_public_projection');
 const decision=v.h.start+s.round_index*c.track.bars_per_round*v.h.dt,first=decision-(c.track.history_bars-1)*v.h.dt;
 const history=s.market_bars.filter(b=>{const t=utc(b.timestamp);return t>=first&&t<=decision;});
 const a=s.accounts[agent];return {batch_id:c.batch_id,run_id:c.run_id,track_id:c.track.track_id,match_index:c.match_index,round_index:s.round_index,agent,interval:c.track.interval,market:c.track.market,symbol:c.track.symbol,decision_close:iso(decision),last_decision_close:iso(decision+(c.track.bars_per_round-1)*v.h.dt),history:copy(history),account:{cash:a.cash,units:a.units,equity:a.equity,fees:a.fees},own_prior_fills:copy(a.fills),fee_bps:c.fee_bps,slippage_bps:c.slippage_bps,fill_policy:c.fill_policy,finalization_policy:c.finalization_policy,submission_policy:'One precommitted market order per decision close; fills at the immediately following close; no future bars or peer submissions supplied.'};
}
function prepareRound(s){checkState(s);if(s.phase!=='ready'||s.round_index>=s.contract.round_count)fail('round_not_ready');const state=copy(s),public_by_agent={};for(const a of s.contract.track.agents)public_by_agent[a]=publicView(s,a);state.phase='awaiting_submissions';return {state,public_by_agent};}
function normalizeSubmission(c,round,submission){
 exact(submission,['batch_id','run_id','track_id','match_index','round_index','agent','orders'],'submission');
 if(submission.batch_id!==c.batch_id||submission.run_id!==c.run_id||submission.track_id!==c.track.track_id||submission.match_index!==c.match_index||submission.round_index!==round||!c.track.agents.includes(submission.agent))fail('submission_identity_mismatch');
 if(!Array.isArray(submission.orders)||submission.orders.length>c.track.bars_per_round)fail('order_count_bound');
 const dt=intervals[c.track.interval],first=utc(c.evaluation_start)+round*c.track.bars_per_round*dt,end=first+c.track.bars_per_round*dt;let prev=null;
 for(const o of submission.orders){exact(o,['decision_close','side','quantity'],'order');const t=utc(o.decision_close);if(t<first||t>=end||(t-first)%dt||prev!==null&&t<=prev)fail('order_timestamp_outside_round_or_duplicate');if(!['buy','sell'].includes(o.side)||!finite(o.quantity)||o.quantity<=0)fail('invalid_order');prev=t;}
 return copy(submission);
}
function applyFill(account,order,bar,c,agent,round){
 const ref=bar.close,side=order.side,sign=side==='buy'?1:-1,price=ref*(1+sign*c.slippage_bps/10000),q=order.quantity,notional=q*price,fee=notional*c.fee_bps/10000;
 if(![price,notional,fee].every(finite)||price<=0||notional<=0||fee<0)fail('fill_numeric_overflow');
 if(side==='buy'){const debit=notional+fee;if(!finite(debit)||debit>account.cash)fail('insufficient_cash');account.cash-=debit;account.units+=q;account.cost_basis+=debit;}
 else{if(q>account.units)fail('insufficient_position');const proceeds=notional-fee;if(!finite(proceeds)||account.cash+proceeds<0)fail('insufficient_cash_for_sale_fees');const removed=account.cost_basis*(q/account.units);account.cash+=proceeds;account.realized_pnl+=proceeds-removed;account.units-=q;account.cost_basis=account.units===0?0:account.cost_basis-removed;}
 account.fees+=fee;account.slippage_cost+=q*Math.abs(price-ref);
 if(!['cash','units','cost_basis','realized_pnl','fees','slippage_cost'].every(k=>finite(account[k]))||account.cash<0||account.units<0||account.cost_basis<0)fail('account_numeric_overflow');
 account.fills.push({batch_id:c.batch_id,run_id:c.run_id,track_id:c.track.track_id,match_index:c.match_index,agent,round_index:round,decision_close:order.decision_close,fill_close:bar.timestamp,side,quantity:q,reference_price:ref,execution_price:price,notional,fee,cash_after:account.cash,units_after:account.units});
}
function mark(a,bar){const equity=a.cash+a.units*bar.close;if(!finite(equity)||equity<0)fail('mark_numeric_overflow');a.equity=equity;a.peak_equity=Math.max(a.peak_equity,equity);a.max_drawdown=Math.max(a.max_drawdown,(a.peak_equity-equity)/a.peak_equity);a.marks.push({timestamp:bar.timestamp,equity});}
function settleRound(s,submissions){
 const v=checkState(s);if(s.phase!=='awaiting_submissions'||s.round_index>=s.contract.round_count)fail('round_not_awaiting_submissions');
 const c=s.contract;if(!Array.isArray(submissions)||submissions.length!==2||new Set(submissions.map(x=>x.agent)).size!==2)fail('both_agent_submissions_required');
 const normalized=submissions.map(x=>normalizeSubmission(c,s.round_index,x));if(!c.track.agents.every(a=>normalized.some(x=>x.agent===a)))fail('submission_agent_set_mismatch');
 const state=copy(s),decision=v.h.start+s.round_index*c.track.bars_per_round*v.h.dt,end=decision+c.track.bars_per_round*v.h.dt,schedules={};
 for(const sub of normalized)schedules[sub.agent]=new Map(sub.orders.map(o=>[utc(o.decision_close)+v.h.dt,o]));
 for(let t=decision+v.h.dt;t<=end;t+=v.h.dt){const bar=v.map.get(t);if(!bar)fail('missing_fill_or_mark_bar');for(const agent of c.track.agents){const a=state.accounts[agent],o=schedules[agent].get(t);if(o)applyFill(a,o,bar,c,agent,s.round_index);mark(a,bar);}}
 const agents={};for(const agent of c.track.agents){const a=state.accounts[agent],old=s.accounts[agent];agents[agent]={cash:a.cash,units:a.units,equity:a.equity,round_return:a.equity/old.equity-1,cumulative_return:a.equity/c.capital-1,max_drawdown:a.max_drawdown,trades_applied:a.fills.length-old.fills.length,decision_status:a.fills.length===old.fills.length?'valid_hold':'traded'};if(!finite(agents[agent].round_return)&&old.equity!==0)fail('return_numeric_overflow');if(old.equity===0)agents[agent].round_return=a.equity===0?0:null;}
 state.rounds.push({round_index:s.round_index,decision_close:iso(decision),evaluation_close:iso(end),submissions:normalized,agents});state.round_index++;state.phase=state.round_index===c.round_count?'complete':'ready';return state;
}
function benchmark(c,bars){const v=validateBars(c,bars),entry=v.map.get(v.h.start+v.h.dt).close,markPrice=v.map.get(v.h.end).close,executionPrice=entry*(1+c.slippage_bps/10000),feeRate=c.fee_bps/10000,units=(c.capital/(1+feeRate))/executionPrice,entryFee=units*executionPrice*feeRate,equity=units*markPrice,pnl=equity-c.capital,ret=pnl/c.capital;if(![executionPrice,units,entryFee,equity,pnl,ret].every(finite)||executionPrice<=0||units<=0)fail('benchmark_numeric_overflow');return {status:'available_reference_calculation_only',kind:'cost_matched_buy_and_hold',source_verification:'unverified_child_reference_data',batch_id:c.batch_id,run_id:c.run_id,track_id:c.track.track_id,match_index:c.match_index,interval:c.track.interval,market:c.track.market,symbol:c.track.symbol,data_path:c.track.data_path,capital:c.capital,fee_bps:c.fee_bps,slippage_bps:c.slippage_bps,fill_policy:'next_close',entry_close:iso(v.h.start+v.h.dt),entry_reference_price:entry,entry_execution_price:executionPrice,units,entry_fee:entryFee,mark_close:c.evaluation_end,mark_price:markPrice,ending_equity:equity,pnl,return_fraction:ret,finalization_policy:'mark_to_market',forced_liquidation:false,exit_fee:0,drawdown:null,competition_executed:false};}
function finalizeRun(s){
 const v=checkState(s);if(s.phase!=='complete'||s.round_index!==s.contract.round_count)fail('incomplete_match');const c=s.contract,last=v.map.get(v.h.end).close;
 const results=c.track.agents.map(agent=>{const a=s.accounts[agent];return {batch_id:c.batch_id,run_id:c.run_id,track_id:c.track.track_id,match_index:c.match_index,agent,initial_capital:c.capital,cash:a.cash,units:a.units,mark_close:c.evaluation_end,mark_price:last,equity:a.equity,pnl:a.equity-c.capital,return_fraction:a.equity/c.capital-1,realized_pnl:a.realized_pnl,unrealized_pnl:a.units*last-a.cost_basis,fees:a.fees,slippage_cost:a.slippage_cost,max_marked_drawdown:a.max_drawdown,forced_liquidation:false,exit_fee:0,trades_applied:a.fills.length};});
 const leaderboard=results.slice().sort((a,b)=>b.equity-a.equity||a.agent.localeCompare(b.agent)).map((a,i,all)=>Object.assign({},a,{rank:1+all.filter(b=>b.equity>a.equity).length}));
 return {batch_id:c.batch_id,run_id:c.run_id,track_id:c.track.track_id,match_index:c.match_index,calculation_status:'accounting_calculated_not_independently_verified',results,leaderboard,rounds:copy(s.rounds),comparators:{cash:{return_fraction:0,executed:false},buy_and_hold:benchmark(c,s.market_bars)},independent_replay_performed:false,no_cross_track_pooling:true};
}
function reviewRoute(c,settlement,nextSameTrack){
 checkContract(c);if(!object(settlement)||settlement.run_id!==c.run_id||settlement.track_id!==c.track.track_id||settlement.match_index!==c.match_index)fail('review_settlement_identity_mismatch');
 const due=c.review_enabled&&c.match_index%c.review_every_matches===0&&nextSameTrack===true;
 return {review_due:due,execute_review:due&&!c.validation_only&&readiness(c).dispatch_allowed,agents:c.track.agents.slice(),track_id:c.track.track_id,after_match:c.match_index,scope:'same_track_between_matches',evidence_required:true,independent_replay_available:false};
}
return {version:'intraday-candidate-0.1',runId,validateBars,namespace,readiness,assertExecutionReadiness,create,publicView,prepareRound,normalizeSubmission,settleRound,finalizeRun,benchmark,reviewRoute};
})();

const inspected=await (async (input,tools)=>{
// Async QuickJS code-node body. Only input and tools.readFile/tools.glob are used.
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
const allowed = new Set(Object.keys(defaults).concat(['batch_id','run_id','track','match_index','validation_as_of']));
for (const k of Object.keys(source)) if (!allowed.has(k) && !['request','context'].includes(k)) err('unknown_property', k, 'Unknown input property.');
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
if (!safeId(contract.batch_id)) err('invalid_safe_id','batch_id','A safe batch ID is required: 1..64 ASCII alphanumeric, underscore or hyphen, starting alphanumeric.');
if (!safeRunId(contract.run_id)) err('invalid_safe_id','run_id','A safe run ID is required: 1..160 ASCII alphanumeric, underscore or hyphen, starting alphanumeric.');
integer(contract.match_index,1,10,'match_index');
if(safeId(contract.batch_id)&&obj(contract.track)&&safeId(contract.track.track_id)&&Number.isInteger(contract.match_index)&&contract.run_id!=='r_b'+contract.batch_id.length+'_'+contract.batch_id+'_t'+contract.track.track_id.length+'_'+contract.track.track_id+'_m'+contract.match_index)err('noncanonical_generated_run_id','run_id','Use injective length-prefixed batch/track/match run identity.');
for (const [k,lo,hi] of [['match_count',1,10],['round_count',1,5],['history_bars',10,1000],['bars_per_round',1,10000],['review_every_matches',1,10],['bonus_rounds',0,3]]) integer(contract[k],lo,hi,k);
if (Number.isInteger(contract.match_index) && Number.isInteger(contract.match_count) && contract.match_index>contract.match_count) err('match_index_exceeds_match_count','match_index','Match index exceeds the planned batch count.');
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
if (!own(contract,'track')) err('match_track_required','track','Batch callers must iterate tracks/matches and pass one track to this validator.');
checkTrack(contract.track,'track');
const track = obj(contract.track) ? Object.assign({},contract.track) : null;
if (track) for (const k of ['history_bars','bars_per_round','agents']) if (!own(track,k)) track[k] = contract[k];

function equalTrack(a,b){
  if(a===b)return true;
  if(Array.isArray(a)&&Array.isArray(b))return a.length===b.length&&a.every((v,i)=>equalTrack(v,b[i]));
  if(!obj(a)||!obj(b))return false;
  const x=Object.keys(a).sort(),y=Object.keys(b).sort();
  return x.length===y.length&&x.every((k,i)=>k===y[i]&&equalTrack(a[k],b[k]));
}
if(Array.isArray(contract.tracks))contract.tracks=contract.tracks.map(t=>{
  if(!obj(t))return t;
  const n=Object.assign({},t);for(const k of ['history_bars','bars_per_round','agents'])if(!own(n,k))n[k]=contract[k];return n;
});
if(track){
  contract.track=track;
  if(!Array.isArray(contract.tracks)||!contract.tracks.some(t=>equalTrack(t,track)))err('selected_track_mismatch','track','Selected track must exactly equal one fully normalized tracks member, including all overrides and metadata. Symbol and market labels do not establish instrument provenance.');
}
const dt = track ? ({'5m':300000,'15m':900000,'1h':3600000})[track.interval] : undefined;
const start = utc(contract.evaluation_start), end = utc(contract.evaluation_end), asof = utc(contract.validation_as_of);
for (const k of ['evaluation_start','evaluation_end']) {
  if (!own(source,k) || contract[k] === null) err('missing_evaluation_window',k,'Explicit non-null evaluation_start and evaluation_end are required before a match can be validated.');
  else if (utc(contract[k]) === null) err('invalid_utc_timestamp',k,'Use a real UTC calendar timestamp YYYY-MM-DDTHH:mm:ssZ only.');
}
if (asof === null) err('validation_as_of_required','validation_as_of','An explicit valid YYYY-MM-DDTHH:mm:ssZ validation_as_of is required; the sandbox clock is not used.');
if (start !== null && end !== null && start >= end) err('invalid_window_order','evaluation_end','evaluation_start must be strictly before evaluation_end.');
if (end !== null && asof !== null && end > asof) err('evaluation_after_validation_as_of','evaluation_end','Evaluation cannot end after the supplied validation_as_of.');
if (dt) {
  for (const [k,t] of [['evaluation_start',start],['evaluation_end',end]]) if (t !== null && t % dt !== 0) err('window_not_interval_aligned',k,'Window endpoints must be UTC interval boundaries.');
  if (start !== null && end !== null && Number.isInteger(contract.round_count) && Number.isInteger(track.bars_per_round)) {
    const expected = contract.round_count * track.bars_per_round * dt;
    if (end-start !== expected) err('mismatched_duration','evaluation_end','end-start must equal round_count * effective bars_per_round * interval_ms; use per-track overrides for equal cross-track windows.',{actual_ms:end-start,expected_ms:expected});
  }
  if (end !== null && asof !== null && end+dt>asof) err('next_fill_after_validation_as_of','validation_as_of','The required next-fill bar must also have closed by validation_as_of.');
}
const MAX_BYTES = 2097152, MAX_LINES = 10000;
function utf8Bytes(s) {
  let n=0; for (let i=0;i<s.length;i++) { const c=s.charCodeAt(i); if(c<128)n++; else if(c<2048)n+=2; else if(c>=55296 && c<=56319 && i+1<s.length && s.charCodeAt(i+1)>=56320 && s.charCodeAt(i+1)<=57343){n+=4;i++;} else n+=3; } return n;
}
function truncated(r) {
  return obj(r) && (['truncated','is_truncated','isTruncated','has_more','hasMore'].some(k => r[k] === true) || r.complete === false || r.eof === false || ['next_cursor','nextCursor','continuation_token'].some(k => own(r,k) && r[k]!==null && r[k]!==undefined && r[k]!=='') || (obj(r.metadata) && truncated(r.metadata)));
}
function checkMetadata(r,textBytes) {
  if(!obj(r))return;
  for(const k of ['size','file_size','total_bytes','size_bytes','totalBytes','fileSize']) if(typeof r[k]==='number'){
    if(r[k]>=MAX_BYTES)err('file_byte_limit','track.data_path','File metadata reaches or exceeds the conservative 2 MiB limit.');
    if(textBytes!==null && r[k]>textBytes)err('data_read_truncated','track.data_path','Metadata reports more file bytes than the complete read returned.');
  }
  for(const k of ['total_lines','line_count','totalLines']) if(typeof r[k]==='number' && r[k]>=MAX_LINES)err('file_line_limit','track.data_path','File metadata reports 10000 or more lines.');
  if(obj(r.metadata))checkMetadata(r.metadata,textBytes);
}
function csvFields(s) {

  const fields=[]; let i=0;
  while (true) {
    let v='';
    if (s[i] === '"') {
      i++; let closed=false;
      while (i<s.length) { if(s[i] === '"') { if(s[i+1] === '"'){v+='"';i+=2;}else{i++;closed=true;break;} } else v+=s[i++]; }
      if (!closed || (i<s.length && s[i]!==',')) return null;
    } else { while(i<s.length && s[i]!==',') { if(s[i] === '"')return null; v+=s[i++]; } }
    fields.push(v); if(i===s.length)return fields; i++;
  }
}
let data = {status:'not_inspected',path:track ? track.data_path : null,rows:0,required_history_bars:track ? track.history_bars : null,required_evaluation_bars:null,required_next_fill_bars:1,errors:[]};
let benchmark = null;
const dataBegin = errors.length;
const rows = [], byTime = new Map();
if (track && safePath(track.data_path)) {
  try {
    const root=track.data_path.startsWith('/artifacts/trading/market/')?'/artifacts/trading/market/':'/shared/market/';
    const relativeExactPath=track.data_path.slice(root.length);
    const found=await tools.glob({path:root,pattern:relativeExactPath});
    const complete=obj(found) && found.truncated===false && found.truncation_reason===null;
    if(!complete)err('glob_truncated','track.data_path','glob must explicitly return truncated=false and truncation_reason=null; incomplete or unspecified results fail closed.');
    const matches=obj(found) && Array.isArray(found.matches)?found.matches:null;
    let exists=false;
    if(!matches)err('invalid_glob_response','track.data_path','glob must return an object with an absolute-path matches array.');
    else {
      exists=matches.length===1 && typeof matches[0]==='string' && matches[0]===track.data_path;
      if(!exists)err('data_missing_or_ambiguous','track.data_path','Exact-path glob must yield exactly the requested absolute file path.');
      checkMetadata(found,null);
    }
    if(exists && complete){
      const raw=await tools.readFile({file_path:track.data_path,offset:0,limit:10000});
      const text=typeof raw==='string'?raw:null;
      if(text===null)err('invalid_read_response','track.data_path','Code-node readFile must return raw text, not a wrapper object or a status envelope.');
      else {
        const bytes=utf8Bytes(text); data.bytes=bytes;
        checkMetadata(raw,bytes);
        let lines=text.split('\n'); if(lines[lines.length-1]==='')lines.pop();
        data.lines=lines.length;
        if(bytes>=MAX_BYTES)err('file_byte_limit','track.data_path','Reads reaching 2 MiB are conservatively rejected to avoid accepting byte-truncated data.');
        if(lines.length>=MAX_LINES)err('file_line_limit','track.data_path','Files with 10000 or more lines are rejected, not truncated and accepted.');
        if(bytes<MAX_BYTES && lines.length<MAX_LINES && !truncated(raw)) {
          lines=lines.map(s => s.endsWith('\r') ? s.slice(0,-1) : s);
          if(lines[0]!=='timestamp,open,high,low,close,volume,closed')err('invalid_csv_header','track.data_path','Required exact header: timestamp,open,high,low,close,volume,closed.');
          else {
            let prev=null;
            const decimal=/^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/;
            for(let i=1;i<lines.length;i++){
              const f=csvFields(lines[i]), line=i+1;
              if(!f || f.length!==7){err('malformed_csv_row','track.data_path','Every row must have seven fields.',{line});continue;}
              const t=utc(f[0]);
              if(t===null){err('malformed_csv_timestamp','track.data_path','Each timestamp must be an exact UTC close time.',{line});continue;}
              if(f[6]!=='true')err('incomplete_bar','track.data_path','Every bar must have closed=true.',{line});
              if(asof!==null && t>asof)err('future_bar','track.data_path','A close timestamp exceeds validation_as_of.',{line,timestamp:f[0]});
              if(dt && t%dt!==0)err('bar_not_interval_aligned','track.data_path','Bar close is not a UTC interval boundary.',{line});
              if(prev!==null){
                if(t<=prev)err('non_monotonic_or_duplicate_timestamp','track.data_path','Timestamps must be strictly increasing and unique.',{line});
                if(dt && t-prev!==dt)err('strict_cadence_violation','track.data_path','Consecutive closes must follow the selected interval exactly.',{line,delta_ms:t-prev,interval_ms:dt});
                if(dt && t-prev===86400000)err('daily_relabel_detected','track.data_path','Daily-spaced closes cannot be relabeled intraday.',{line});
              }
              prev=t;
              const n=f.slice(1,6).map(v => decimal.test(v) ? Number(v) : NaN);
              if(!n.every(Number.isFinite) || n.slice(0,4).some(v=>v<=0) || n[4]<0)err('invalid_ohlcv','track.data_path','OHLC must be positive finite numbers and volume nonnegative.',{line});
              else if(n[2]>Math.min(n[0],n[3]) || n[1]<Math.max(n[0],n[3]) || n[2]>n[1])err('incoherent_ohlc','track.data_path','Require low <= open/close <= high.',{line});
              const row={t,open:n[0],high:n[1],low:n[2],close:n[3],volume:n[4]};
              rows.push(row); byTime.set(t,row);
            }
          }
        }
      }
    }
  } catch (e) { err('data_tool_failure','track.data_path','Read-only tool call failed: '+(e && typeof e.message==='string'?e.message:String(e))+'; no retry or execution attempted.'); }
} else err('data_not_inspected','track.data_path','A safe exact data path is required for read-only inspection.');
data.rows=rows.length;
const shapeOK=dt && track && Number.isInteger(track.history_bars) && track.history_bars>=10 && track.history_bars<=1000 && Number.isInteger(track.bars_per_round) && track.bars_per_round>=1 && track.bars_per_round<=10000 && Number.isInteger(contract.round_count) && contract.round_count>=1 && contract.round_count<=5;
if(shapeOK && start!==null && end!==null && start<end && start%dt===0 && end%dt===0){
  const first=start-(track.history_bars-1)*dt, last=end+dt, count=(last-first)/dt+1;
  data.required_first_close=iso(first);data.required_last_close=iso(last);data.required_total_bars=count;
  data.required_evaluation_bars=(end-start)/dt;
  data.warmup_includes_decision_start=true;
  if(count>MAX_LINES-2)err('required_segment_exceeds_read_bound','track.data_path','The required history/evaluation/next-fill segment cannot fit the permitted complete CSV.');
  if(!byTime.has(start))err('missing_decision_start_bar','track.data_path','History must include a closed bar at evaluation_start.');
  if(!byTime.has(start+dt))err('missing_first_fill_bar','track.data_path','next_close requires the first close after evaluation_start.');
  if(!byTime.has(end+dt))err('missing_next_fill_bar','track.data_path','The close immediately after evaluation_end is required.');
  let present=0; for(const t of byTime.keys())if(t>=first && t<=last && (t-first)%dt===0)present++;
  if(present!==count)err('insufficient_contiguous_coverage','track.data_path','Require full contiguous warmup ending at start, evaluation closes (start,end], and one next-fill close.',{required:count,present});
} else err('required_segment_unverifiable','track.data_path','A valid aligned window and effective track settings are needed to verify complete coverage.');
const dataCodes = errors.slice(dataBegin).map(e=>e.code);
data.errors=Array.from(new Set(dataCodes));
const timeCodes=['missing_evaluation_window','invalid_utc_timestamp','validation_as_of_required','invalid_window_order','evaluation_after_validation_as_of','window_not_interval_aligned','mismatched_duration','next_fill_after_validation_as_of'];
const dataValid=dataCodes.length===0 && !errors.some(e=>timeCodes.includes(e.code)) && asof!==null;
data.status=dataValid ? 'valid_against_supplied_as_of' : 'invalid_or_unverifiable';
if(dataValid && capitalOK && feeBpsOK && slippageBpsOK && byTime.has(start+dt) && byTime.has(end)){
  const entry=byTime.get(start+dt).close, mark=byTime.get(end).close;
  const executionPrice=entry*(1+contract.slippage_bps/10000), feeRate=contract.fee_bps/10000;
  const units=(contract.capital/(1+feeRate))/executionPrice, notional=units*executionPrice;
  const entryFee=notional*feeRate, equity=units*mark, pnl=equity-contract.capital, ret=pnl/contract.capital;
  if([executionPrice,units,notional,entryFee,equity,pnl,ret].every(Number.isFinite) && executionPrice>0 && units>0){
    benchmark={status:'available_reference_calculation_only',kind:'cost_matched_buy_and_hold',source_verification:'unverified_child_reference_data',batch_id:contract.batch_id,run_id:contract.run_id,track_id:track.track_id,match_index:contract.match_index,interval:track.interval,market:track.market,symbol:track.symbol,data_path:track.data_path,capital:contract.capital,fee_bps:contract.fee_bps,slippage_bps:contract.slippage_bps,fill_policy:'next_close',entry_close:iso(start+dt),entry_reference_price:entry,entry_execution_price:executionPrice,units,entry_fee:entryFee,mark_close:iso(end),mark_price:mark,ending_equity:equity,pnl,return_fraction:ret,finalization_policy:'mark_to_market',forced_liquidation:false,exit_fee:0,drawdown:null,competition_executed:false};
  } else err('benchmark_numeric_overflow','capital','Cost-matched buy-and-hold calculation is not representable as finite numbers.');
}
const namespaces=[];
if(track && safeId(contract.batch_id) && safeId(track.track_id) && Number.isInteger(contract.match_index) && contract.match_index>=1 && contract.match_index<=10 && Array.isArray(track.agents) && track.agents.length===2 && new Set(track.agents).size===2 && track.agents.every(safeId)){
  for(const agent of track.agents){
    const base='/artifacts/trading/'+contract.batch_id+'/'+track.track_id+'/match-'+contract.match_index+'/'+agent;
    namespaces.push({agent,namespace:base,account_namespace:base+'/account',artifact_namespace:base+'/artifacts',strategy_namespace:base+'/strategy',planned_initial_capital:contract.capital,created:false,reserved:false,write_authorized:false,reuse_policy:'future_writes_forbidden_until_separate_reservation'});
  }
}
const executionBlockers=['namespace_reservation_unavailable'];
if(contract.require_matched_replay===false)executionBlockers.push('replay_gate_bypass_forbidden');
else executionBlockers.push('independent_replay_unavailable');
const blockers=Array.from(new Set(errors.map(e=>e.code).concat(executionBlockers)));
const result = {status:errors.length ? 'blocked' : 'validation_passed_execution_blocked',report:{
  contract,effective_track:track,track_id:track ? track.track_id : null,
  validation:{passed:errors.length===0,mode:'read_only',validation_as_of:contract.validation_as_of || null,as_of_is_trusted_wall_clock:false,data},
  errors,blockers,execution:{available:false,requested:contract.validation_only===false,dispatched:false,blockers:executionBlockers,reason:'Current runs fail closed before dispatch because no trusted independent matched-replay provider or namespace reservation adapter is installed. A timestamp-aware deterministic accounting candidate exists but still requires legacy adapter integration and review. Synthetic self-checks and caller flags are not independent evidence; replay bypass is forbidden. The executable competitor and between-match review topology must be preserved behind these capability gates.'},
  review:{enabled:contract.review_enabled,every_matches:contract.review_every_matches,state:'not_run',performed:false},
  namespaces,results:[],leaderboard:[],drawdown:null,cash_comparator:0,
  comparators:{cash:{return_fraction:0,drawdown:null,executed:false},buy_and_hold:benchmark},
  evidence:{required:contract.evidence_required,competition_executed:false,independent_replay_performed:false,real_intraday_proof:false},
  files_written:false,orders_placed:false
}};

return {result,private_rows:errors.length===0?rows.map(b=>({timestamp:iso(b.t),open:b.open,high:b.high,low:b.low,close:b.close,volume:b.volume,closed:true})):null};

})(input,tools);
const summary=inspected.result;
let engine_state=null,execute=false;
if(summary.report.validation.passed){const c=summary.report.contract;const capability=PaperIntraday.readiness(c);if(!c.validation_only&&capability.dispatch_allowed)throw new Error('private_io_adapter_requires_inline_integration_before_dispatch');}
return Object.assign({},summary,{execute,engine_state});
