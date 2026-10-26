// UNAPPROVED candidate only: preserve canonical original engine until parent approves cutover.
const engine=(function () {
  var names=['agent-one','agent-two'],NL=String.fromCharCode(10);
  async function exists(tools,path) {
    var roots=['/artifacts/trading/','/shared/competition/'];
    var scope=roots.filter(function(r){return path.indexOf(r)===0;})[0];
    if(!scope || path.indexOf('..')>=0 || /[\\*?\[\]{}]/.test(path)) throw new Error('Unsafe existence path: '+path);
    var result=await tools.glob({path:scope,pattern:path.slice(scope.length)});
    if(!result || !Array.isArray(result.matches)) throw new Error('Unexpected glob response for '+path);
    if(result.truncated!==false || result.truncation_reason!==null) throw new Error('Incomplete glob result: '+path);
    return result.matches.indexOf(path)>=0;
  }
  async function optional(tools,path) {
    if(!await exists(tools,path)) return null;
    return await readBounded(tools,path);
  }
  async function verify(tools,path,text) {
    var actual=await readBounded(tools,path);
    if(actual!==text) throw new Error('Write readback differs: '+path);
  }
  async function put(tools,path,text) {
    var old=await optional(tools,path);
    if(old!==null) {
      if(old!==text) throw new Error('Existing immutable file differs: '+path);
      return;
    }
    bounded(text); await tools.writeFile({file_path:path,content:text});
    await verify(tools,path,text);
  }
  async function replace(tools,path,text) {
    bounded(text);
    if(await exists(tools,path)) await tools.deleteFile({file_path:path});
    bounded(text); await tools.writeFile({file_path:path,content:text});
    await verify(tools,path,text);
  }
  function valid(p,round) {
    if(!p._contract || p.run_id!==generated(p.batch_id,p.track.track_id,p.match_index))throw new Error('Canonical identity required');
    if(!Number.isInteger(p.round_count)||p.round_count<1||p.round_count>5||!Number.isInteger(p.history_bars)||p.history_bars<10||p.history_bars>1000||!Number.isInteger(p.bars_per_round)||p.bars_per_round<1||p.bars_per_round>10000)throw new Error('Invalid effective round/history settings');
    if(round&&(!Number.isInteger(p.round_index)||p.round_index<0||p.round_index>=p.round_count))throw new Error('Invalid round_index');
    return p.capital;
  }
  function root(p){return '/artifacts/trading/'+p.batch_id+'/'+p.track.track_id+'/match-'+p.match_index+'/judge';}
  function base(p){return '/artifacts/trading/'+p.batch_id+'/'+p.track.track_id+'/match-'+p.match_index;}
  function agentDir(p,n){if(names.indexOf(n)<0)throw new Error('Unsupported agent');return base(p)+'/'+n;}
  function orderDir(p,n){return agentDir(p,n)+'/artifacts/round-'+p.round_index;}
  function pub(p){return '/shared/competition/'+p.batch_id+'/'+p.track.track_id+'/match-'+p.match_index+'/round-'+p.round_index;}
  function params(p){return {contract:p._contract,capital:valid(p,false),fee_bps:p.fee_bps,slippage_bps:p.slippage_bps,history_bars:p.history_bars,bars_per_round:p.bars_per_round,round_count:p.round_count};}
  function match(s,p){if(s.version!=='3.2-intraday-candidate.1'||s.run_id!==p.run_id||JSON.stringify(s.settings)!==JSON.stringify(params(p)))throw new Error('Private timestamped state/contract mismatch');}
  function generated(b,t,n){return 'r_b'+b.length+'_'+b+'_t'+t.length+'_'+t+'_m'+n;}
  function utc(s){var t=Date.parse(s);if(typeof s!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$(?![\s\S])/.test(s)||!Number.isFinite(t)||new Date(t).toISOString().replace('.000Z','Z')!==s)throw new Error('Invalid UTC timestamp');return t;}
  function deterministicStart(rows,p){var dt={'5m':300000,'15m':900000,'1h':3600000}[p.track.interval],first=utc(p.evaluation_start)-(p.history_bars-1)*dt;for(var i=0;i<rows.length;i++)if(rows[i].t===first)return i;throw new Error('Missing exact warmup start');}
  function executionGuard(p){
    if(p.validation_only)throw new Error('validation_only_forbids_dispatch_and_writes');
    if(!p.require_matched_replay)throw new Error('replay_gate_bypass_forbidden');
    throw new Error('independent_replay_unavailable; candidate_cutover_unverified; namespace_reservation_and_scope_unavailable');
  }
  function bytes(s){var n=0;for(var ch of s){var c=ch.codePointAt(0);n+=c<=127?1:c<=2047?2:c<=65535?3:4;}return n;}
  function bounded(text){if(typeof text!=='string')throw new Error('readFile must return raw text');var lines=text.split(NL);if(lines[lines.length-1]==='')lines.pop();if(bytes(text)>=2097152||lines.length>=10000)throw new Error('Exclusive file bounds: <2MiB and <10000 lines');return text;}
  async function readBounded(t,path){return bounded(await t.readFile({file_path:path,offset:0,limit:10000}));}
  function fresh(c){return {cash:c,units:0,equity:c,peak:c,max_drawdown:0};}
  function at(rows,s,i){if(!rows[i])throw new Error('Market index outside required timestamped segment');return rows[i].close;}
  function decision(p,s){return s.start+p.history_bars-1+p.round_index*p.bars_per_round;}
  function bars(rows,s,p){var lines=['timestamp,open,high,low,close,volume,closed'];for(var i=s.start;i<=decision(p,s);i++){var b=rows[i];lines.push([b.timestamp,b.open,b.high,b.low,b.close,b.volume,true].join(','));}return lines.join(NL)+NL;}
  async function stateText(t,p){
    var pointer=await optional(t,root(p)+'/state.json'),cached=null,chosen=null,text=null,missing=false,latest=0;
    if(pointer!==null&&jsonSyntax(pointer)){cached=JSON.parse(pointer);match(cached,p);if(!Array.isArray(cached.rounds))throw new Error('Invalid private pointer rounds');chosen=cached;text=pointer;}
    for(var r=0;r<p.round_count;r++){
      var raw=await optional(t,root(p)+'/ledger/round-'+r+'.json');
      if(raw===null){missing=true;continue;}if(missing)throw new Error('Noncontiguous immutable accounting journal');
      if(!jsonSyntax(raw))throw new Error('Invalid immutable journal JSON');var journal=JSON.parse(raw);match(journal,p);
      if(!Array.isArray(journal.rounds)||journal.rounds.length!==r+1||journal.rounds.some(function(v,i){return v.round!==i;}))throw new Error('Invalid immutable journal sequence');
      if(chosen&&(chosen.market_text!==journal.market_text||JSON.stringify(chosen.rounds.slice(0,Math.min(chosen.rounds.length,journal.rounds.length)))!==JSON.stringify(journal.rounds.slice(0,Math.min(chosen.rounds.length,journal.rounds.length)))))throw new Error('Conflicting private accounting history');
      latest=r+1;if(!chosen||chosen.rounds.length<=journal.rounds.length){if(chosen&&chosen.rounds.length===journal.rounds.length&&JSON.stringify(chosen)!==JSON.stringify(journal))throw new Error('Pointer/journal disagreement');chosen=journal;text=raw;}
    }
    if(cached&&cached.rounds.length>latest)throw new Error('Unjournaled committed state');
    if(pointer!==null&&!cached&&!chosen)throw new Error('Invalid private state without a recoverable journal');
    return text;
  }
  async function getState(ctx){var t=await stateText(ctx.tools,ctx.input);if(t===null)throw new Error('Missing private state');var s=JSON.parse(t);match(s,ctx.input);return s;}
  async function publishAccounts(t,p,s){var r=s.rounds[p.round_index];if(!r)throw new Error('Missing authoritative round for account publication');for(var i=0;i<names.length;i++){var n=names[i];await put(t,agentDir(p,n)+'/account/round-'+p.round_index+'.json',JSON.stringify({run_id:p.run_id,track_id:p.track.track_id,match_index:p.match_index,agent:n,account:r.agents[n]}));}}
  function roundBrief(p) {
    return p.brief+NL+NL+[
      'Round '+p.round_index+' of '+p.round_count+'. Simulated capital '+valid(p,false)+'. Most simulated equity wins; ties have no winner.',
      'You may communicate, cooperate, compete, and modify your own code freely. No version is selected or promoted by this routine.',
      'Public bars contain exact UTC close timestamps and OHLCV, with closed=true. Only observed history through the decision close is published. Absolute instrument prices are used; dates are never stripped or daily rows relabelled.',
      'Orders fill at the next close after the decision bar. Buys pay close*(1+slippage_bps/10000); sells receive close*(1-slippage_bps/10000). Fee is fee_bps/10000 of notional in cash.',
      'fee_bps='+p.fee_bps+', slippage_bps='+p.slippage_bps+'. Long only, no leverage. Buy costs including fees must fit cash; sells must fit held units.',
      'All orders in a round are precommitted and fill in file order at its single first next-close timestamp; there are no intraround future observations. Write orders.csv with exact header side,quantity; each row buy or sell and strictly positive numeric units. Header-only is valid no-trade.',
      'Write manifest.json with string fields code_ref, approach, changes. Missing or invalid manifest rejects the whole submission, including no-trade.',
      'Missing, malformed, or infeasible submission is rejected entirely before any trades are applied. Orders are validated in file order.',
      'Equity is marked '+p.bars_per_round+' bars after the decision bar. Cash and units carry forward.',
      'The buy-and-hold benchmark buys once at the round-0 fill with the same buy slippage and fee, and holds those units.',
      'Agent reports and P&L are untrusted. Only this routine settlement counts.'
    ].join(NL)+NL;
  }
  async function prepareRound(ctx) {
    var loaded=await loadMarket(ctx),p=loaded.input,t=ctx.tools,c=valid(p,true),rows=loaded.rows;executionGuard(p);ctx=Object.assign({},ctx,{input:p});
    var raw=await stateText(t,p),s;
    if(raw===null){
      if(p.round_index!==0) throw new Error('Cannot start after round 0');
      var start=deterministicStart(rows,p);
      s={version:'3.2-intraday-candidate.1',run_id:p.run_id,settings:params(p),start:start,market_text:loaded.text,agents:{},benchmark:null,rounds:[],failures:[],notable_changes:[]};
      names.forEach(function(n){s.agents[n]=fresh(c);});
      await put(t,root(p)+'/state.json',JSON.stringify(s));
    }else{s=JSON.parse(raw);match(s,p);}
    if(s.market_text!==loaded.text)throw new Error('Market data changed after match initialization');
    if(p.round_index!==s.rounds.length) throw new Error('Prepare requires next unsettled round');
    var dir=pub(p),previous=p.round_index===0?'none':pub(Object.assign({},p,{round_index:p.round_index-1}))+'/evidence.md',brief=roundBrief(p);
    await put(t,dir+'/bars.csv',bars(rows,s,p));await put(t,dir+'/brief.md',brief);
    return {public_dir:dir,bars_path:dir+'/bars.csv',brief_path:dir+'/brief.md',brief_text:brief,previous_evidence:previous,agent_one_orders:orderDir(p,'agent-one')+'/orders.csv',agent_one_manifest:orderDir(p,'agent-one')+'/manifest.json',agent_two_orders:orderDir(p,'agent-two')+'/orders.csv',agent_two_manifest:orderDir(p,'agent-two')+'/manifest.json',agent_one_strategy:agentDir(p,'agent-one')+'/strategy',agent_two_strategy:agentDir(p,'agent-two')+'/strategy',agent_one_cash:s.agents['agent-one'].cash,agent_one_units:s.agents['agent-one'].units,agent_two_cash:s.agents['agent-two'].cash,agent_two_units:s.agents['agent-two'].units};
  }
  // Validate JSON syntax before parsing. No exception is consumed as business data.
  function jsonSyntax(text) {
    var i=0,len=text.length;
    function ws(){while(i<len&&/[\x20\x09\x0a\x0d]/.test(text[i]))i++;}
    function string(){
      if(text[i++]!=='"')return false;
      while(i<len){var ch=text[i++];if(ch==='"')return true;if(ch.charCodeAt(0)<32)return false;
        if(ch==='\\'){if(i>=len)return false;var esc=text[i++];if(esc==='u'){if(!/^[0-9a-fA-F]{4}$/.test(text.slice(i,i+4)))return false;i+=4;}else if('"\\/bfnrt'.indexOf(esc)<0)return false;}}
      return false;
    }
    function value(depth){
      if(depth>64)return false;ws();var ch=text[i];
      if(ch==='"')return string();
      if(ch==='{'||ch==='['){var object=ch==='{',end=object?'}':']';i++;ws();if(text[i]===end){i++;return true;}
        while(i<len){if(object){if(!string())return false;ws();if(text[i++]!==':')return false;}if(!value(depth+1))return false;ws();if(text[i]===end){i++;return true;}if(text[i++]!==',')return false;ws();}return false;}
      for(var k=0;k<3;k++){var word=['true','false','null'][k];if(text.slice(i,i+word.length)===word){i+=word.length;return true;}}
      var number=/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(text.slice(i));if(!number)return false;i+=number[0].length;return true;
    }
    if(!value(0))return false;ws();return i===len;
  }
  function bad(reason){return {error:reason};}
  function parseOrders(text) {
    var lines=text.trim().split(NL),orders=[];
    if(lines.shift().trim()!=='side,quantity')return bad('malformed orders: header must be side,quantity');
    for(var i=0;i<lines.length;i++){
      var a=lines[i].trim().split(',');if(a.length!==2)return bad('malformed orders: row '+(i+1));
      var side=a[0].trim(),v=a[1].trim();
      if(side!=='buy'&&side!=='sell')return bad('malformed orders: side must be buy or sell');
      if(!/^[+]?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+)(?:[eE][+-]?[0-9]+)?$/.test(v))return bad('malformed orders: quantity must be numeric');
      var q=Number(v);if(!Number.isFinite(q)||q<=0)return bad('malformed orders: quantity must be > 0');orders.push({side:side,quantity:q});
    }
    return {orders:orders};
  }
  async function submission(t,dir) {
    var orders=await optional(t,dir+'/orders.csv'),manifest=await optional(t,dir+'/manifest.json'),summary=null,errors=[],parsed=[];
    if(manifest===null)errors.push('missing manifest.json');
    else if(!jsonSyntax(manifest))errors.push('invalid manifest.json: invalid JSON syntax');
    else{
      var m=JSON.parse(manifest);
      if(!m||Array.isArray(m)||typeof m.code_ref!=='string'||typeof m.approach!=='string'||typeof m.changes!=='string')errors.push('invalid manifest.json: required string fields code_ref, approach, changes');
      else summary={code_ref:m.code_ref,approach:m.approach,changes:m.changes};
    }
    if(orders===null)errors.push('missing submission: orders.csv');
    else{var result=parseOrders(orders);if(result.error)errors.push(result.error);else parsed=result.orders;}
    return {orders:parsed,manifest:summary,failures:errors};
  }
  function simulate(prior,orders,close,p) {
    var cash=prior.cash,units=prior.units,trades=[];
    for(var i=0;i<orders.length;i++){
      var o=orders[i],price=close*(1+(o.side==='buy'?1:-1)*p.slippage_bps/10000),notional=o.quantity*price,fee=notional*p.fee_bps/10000;
      if(!Number.isFinite(notional)||!Number.isFinite(fee))return bad('infeasible order: non-finite cost');
      if(o.side==='buy'){
        if(notional+fee>cash)return bad('infeasible buy: total cost exceeds cash');cash=cash-notional-fee;units+=o.quantity;
      }else{
        if(o.quantity>units)return bad('infeasible sell: quantity exceeds units');cash=cash+notional-fee;units-=o.quantity;
        if(cash<0)return bad('infeasible sell: fee exceeds available cash');
      }
      if(!Number.isFinite(cash)||!Number.isFinite(units))return bad('infeasible order: non-finite balance');
      trades.push({side:o.side,quantity:o.quantity,price:price,notional:notional,fee:fee});
    }
    return {cash:cash,units:units,trades:trades};
  }
  function evidence(result) {
    var lines=['Round '+result.round,'Fill '+result.fill_timestamp+' at absolute close '+result.fill_close+'; mark '+result.mark_timestamp+' at '+result.mark_close+'.','Agent-produced P&L is untrusted. Only this settlement counts.'];
    lines.push('| Agent | Cash | Units | Equity | Round return | Cumulative return | Max drawdown | Trades | Failures |','|---|---:|---:|---:|---:|---:|---:|---:|---|');
    names.forEach(function(n){var a=result.agents[n];lines.push('|'+n+'|'+a.cash+'|'+a.units+'|'+a.equity+'|'+a.round_return+'|'+a.cumulative_return+'|'+a.max_drawdown+'|'+a.trades_applied+'|'+a.failures.join('; ')+'|');});
    lines.push('Buy-and-hold benchmark: equity '+result.benchmark_equity+', units '+result.benchmark.units+'. Bought once at the round-0 fill using the same buy slippage and fees.','Standing: '+(result.winner===null?'tie':result.winner+' leads')+'.');return lines.join(NL)+NL;
  }
  function view(r,dir,text,replayed){return {round_index:r.round,results_path:dir+'/results.json',evidence_path:dir+'/evidence.md',evidence_text:text,standing:r.winner===null?'tie':r.winner+' leads',agent_one_cash:r.agents['agent-one'].cash,agent_one_units:r.agents['agent-one'].units,agent_one_equity:r.agents['agent-one'].equity,agent_two_cash:r.agents['agent-two'].cash,agent_two_units:r.agents['agent-two'].units,agent_two_equity:r.agents['agent-two'].equity,replayed:replayed};}
  async function settleRound(ctx) {
    var loaded=await loadMarket(ctx),p=loaded.input,t=ctx.tools,c=valid(p,true);executionGuard(p);ctx=Object.assign({},ctx,{input:p});var dir=pub(p),s=await getState(ctx),publicText=await optional(t,dir+'/results.json');
    if(s.market_text!==loaded.text)throw new Error('Market data changed after match initialization');
    if(publicText!==null){
      var recorded=s.rounds[p.round_index];if(!recorded)throw new Error('Public results exist without private recorded settlement; refusing to apply orders');
      if(publicText!==JSON.stringify(recorded))throw new Error('Public results differ from private settlement');
      var recordedEvidence=evidence(recorded);
      // A replay never rewrites an existing result or ledger; only recover absent evidence.
      await put(t,dir+'/evidence.md',recordedEvidence);
      await publishAccounts(t,p,s);
      return view(recorded,dir,recordedEvidence,true);
    }
    if(s.rounds[p.round_index]){
      var saved=s.rounds[p.round_index],savedText=evidence(saved);
      await publishAccounts(t,p,s);await put(t,dir+'/results.json',JSON.stringify(saved));await put(t,dir+'/evidence.md',savedText);return view(saved,dir,savedText,true);
    }
    if(s.rounds.length!==p.round_index)throw new Error('Settlement must be sequential');
    var rows=loaded.rows,d=decision(p,s),fill=at(rows,s,d+1),mark=at(rows,s,d+p.bars_per_round);
    if(s.benchmark===null){
      if(p.round_index!==0)throw new Error('Missing benchmark entry');
      var price=fill*(1+p.slippage_bps/10000),units=c/(price*(1+p.fee_bps/10000));
      s.benchmark={cash:0,units:units,entry_price:price,entry_close:fill,entry_fee:c*p.fee_bps/10000/(1+p.fee_bps/10000),fill_t:d+1-s.start};
    }
    var result={round:p.round_index,decision_t:d-s.start,fill_t:d+1-s.start,mark_t:d+p.bars_per_round-s.start,fill_close:fill,mark_close:mark,agents:{},benchmark:s.benchmark,benchmark_equity:s.benchmark.cash+s.benchmark.units*mark,winner:null};
    result.batch_id=p.batch_id;result.run_id=p.run_id;result.track_id=p.track.track_id;result.match_index=p.match_index;result.decision_timestamp=rows[d].timestamp;result.fill_timestamp=rows[d+1].timestamp;result.mark_timestamp=rows[d+p.bars_per_round].timestamp;result.drawdown_sampling='round_marks_only';result.finalization_policy='mark_to_market';result.forced_liquidation=false;
    for(var i=0;i<names.length;i++){
      var n=names[i],prior=s.agents[n],sub=await submission(t,orderDir(p,n)),next={cash:prior.cash,units:prior.units,trades:[]};
      if(sub.manifest)s.notable_changes.push({round:p.round_index,agent:n,code_ref:sub.manifest.code_ref,approach:sub.manifest.approach,changes:sub.manifest.changes});
      if(sub.failures.length===0){var trial=simulate(prior,sub.orders,fill,p);if(trial.error)sub.failures.push(trial.error);else next=trial;}
      var equity=next.cash+next.units*mark,peak=Math.max(prior.peak,equity),dd=Math.max(prior.max_drawdown,(peak-equity)/peak);
      if(!Number.isFinite(equity))throw new Error('Non-finite equity');
      result.agents[n]={cash:next.cash,units:next.units,equity:equity,round_return:prior.equity===0?null:(equity-prior.equity)/prior.equity,cumulative_return:(equity-c)/c,max_drawdown:dd,trades_applied:next.trades.length,trades:next.trades,failures:sub.failures,manifest_summary:sub.manifest};
      s.agents[n]={cash:next.cash,units:next.units,equity:equity,peak:peak,max_drawdown:dd};sub.failures.forEach(function(reason){s.failures.push({round:p.round_index,agent:n,reason:reason});});
    }
    var e1=result.agents['agent-one'].equity,e2=result.agents['agent-two'].equity;result.winner=e1===e2?null:(e1>e2?'agent-one':'agent-two');s.rounds.push(result);
    // Ledger is durable before public results: a resumed settlement republishes, never reapplies.
    await put(t,root(p)+'/ledger/round-'+p.round_index+'.json',JSON.stringify(s));
    await replace(t,root(p)+'/state.json',JSON.stringify(s));
    await publishAccounts(t,p,s);
    var text=evidence(result);await put(t,dir+'/results.json',JSON.stringify(result));await put(t,dir+'/evidence.md',text);return view(result,dir,text,false);
  }
  async function finalizeRun(ctx){
    var loaded=await loadMarket(ctx),p=loaded.input;executionGuard(p);ctx=Object.assign({},ctx,{input:p});valid(p,false);var s=await getState(ctx),last=s.rounds[s.rounds.length-1];
    if(s.market_text!==loaded.text)throw new Error('Market data changed after match initialization');
    if(s.rounds.length!==p.round_count)throw new Error('Cannot finalize incomplete run');
    var report={contract:p._contract,batch_id:p.batch_id,run_id:p.run_id,track_id:p.track.track_id,match_index:p.match_index,interval:p.track.interval,market:p.track.market,symbol:p.track.symbol,capital:p.capital,fee_bps:p.fee_bps,slippage_bps:p.slippage_bps,fill_policy:'next_close',finalization_policy:'mark_to_market',forced_liquidation:false,drawdown_sampling:'round_marks_only',rounds:s.rounds,final_balances:last.agents,winner:last.winner,failures:s.failures,notable_changes:s.notable_changes,independent_replay_proof:null};
    return {status:'completed',report:report,final_balances:last.agents,winner:last.winner,rounds:s.rounds,failures:s.failures,notable_changes:s.notable_changes};
  }
  async function inspect(ctx){
const source=ctx.input;if(!source||typeof source!=='object'||Array.isArray(source))throw Error('Input object required');const projected={};const runtimeKeys=["round_index","prepared","dispatch_split","reply_one","reply_two","settled","evidence_split","evidence_one","evidence_two","continue_flag","result","final_balances","winner","rounds","failures","notable_changes","preflight","summary","status","report"];for(const k of Object.keys(source))if(!runtimeKeys.includes(k))projected[k]=source[k];let text=null;const readonlyTools={glob:q=>ctx.tools.glob(q),readFile:async q=>{text=await ctx.tools.readFile(q);return text;}};const found=await(async(input,tools)=>{
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
const result={status:errors.length ? 'blocked' : 'validation_passed_execution_blocked',report:{
  contract,effective_track:track,track_id:track ? track.track_id : null,
  validation:{passed:errors.length===0,mode:'read_only',validation_as_of:contract.validation_as_of || null,as_of_is_trusted_wall_clock:false,data},
  errors,blockers,execution:{available:false,requested:contract.validation_only===false,dispatched:false,blockers:executionBlockers,reason:'Current runs fail closed before dispatch because no trusted independent matched-replay provider or namespace reservation adapter is installed. A timestamp-aware deterministic accounting candidate exists but still requires legacy adapter integration and review. Synthetic self-checks and caller flags are not independent evidence; replay bypass is forbidden. The executable competitor and between-match review topology must be preserved behind these capability gates.'},
  review:{enabled:contract.review_enabled,every_matches:contract.review_every_matches,state:'not_run',performed:false},
  namespaces,results:[],leaderboard:[],drawdown:null,cash_comparator:0,
  comparators:{cash:{return_fraction:0,drawdown:null,executed:false},buy_and_hold:benchmark},
  evidence:{required:contract.evidence_required,competition_executed:false,independent_replay_performed:false,real_intraday_proof:false},
  files_written:false,orders_placed:false
}};

return {public_result:result,rows:errors.length===0?rows.map(b=>({timestamp:iso(b.t),t:b.t,open:b.open,high:b.high,low:b.low,close:b.close,volume:b.volume,closed:true})):null};

})(projected,readonlyTools);return Object.assign(found,{text});}
  async function loadMarket(ctx){const found=await inspect(ctx);if(!found.public_result.report.validation.passed)throw new Error('invalid_timestamped_contract_or_data:'+JSON.stringify(found.public_result.report.errors));const c=found.public_result.report.contract;if(ctx.csvPath!==undefined&&ctx.csvPath!==c.track.data_path)throw new Error('csvPath differs from selected normalized track');return {input:Object.assign({},c,{_contract:c,round_index:ctx.input.round_index,history_bars:c.track.history_bars,bars_per_round:c.track.bars_per_round}),rows:found.rows,text:found.text};}
  async function validateOnly(ctx){return (await inspect(ctx)).public_result;}
  return {version:'3.2-intraday-candidate.1',validateOnly:validateOnly,exists:exists,replace:replace,jsonSyntax:jsonSyntax,prepareRound:prepareRound,settleRound:settleRound,finalizeRun:finalizeRun};
})();
return await engine.prepareRound({input,tools,csvPath:input.track && input.track.data_path});
