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

return PaperIntraday.reviewRoute(input.match_contract,input.authoritative_settlement,input.has_next_same_track);
