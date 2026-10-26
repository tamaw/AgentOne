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
return {status:errors.length ? 'blocked' : 'validation_passed_execution_blocked',report:{
  contract,effective_track:track,track_id:track ? track.track_id : null,
  validation:{passed:errors.length===0,mode:'read_only',validation_as_of:contract.validation_as_of || null,as_of_is_trusted_wall_clock:false,data},
  errors,blockers,execution:{available:false,requested:contract.validation_only===false,dispatched:false,blockers:executionBlockers,reason:'Current runs fail closed before dispatch because no trusted independent matched-replay provider or namespace reservation adapter is installed. A timestamp-aware deterministic accounting candidate exists but still requires legacy adapter integration and review. Synthetic self-checks and caller flags are not independent evidence; replay bypass is forbidden. The executable competitor and between-match review topology must be preserved behind these capability gates.'},
  review:{enabled:contract.review_enabled,every_matches:contract.review_every_matches,state:'not_run',performed:false},
  namespaces,results:[],leaderboard:[],drawdown:null,cash_comparator:0,
  comparators:{cash:{return_fraction:0,drawdown:null,executed:false},buy_and_hold:benchmark},
  evidence:{required:contract.evidence_required,competition_executed:false,independent_replay_performed:false,real_intraday_proof:false},
  files_written:false,orders_placed:false
}};
