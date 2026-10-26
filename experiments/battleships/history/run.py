import os,sys,json,time,pathlib,subprocess,random,hashlib,select,concurrent.futures,shutil,statistics,re
BASE=pathlib.Path(__file__).resolve().parent
RUN='battleships-'+str(int(time.time()))
WORK='/workspace/.runs/'+RUN
NAMES=['agent-one','agent-two']
GAMES=15
IMPROVE_EVERY=3
HASKELL_ERROR_LIMIT=3
OUT=BASE/RUN;OUT.mkdir()
STATUS=BASE/'latest.txt'
EVENTS=OUT/'events.jsonl'
RULES='''ASCII BATTLESHIPS. Board 8x8, cell index row*8+column (0..63); fleets lengths [4,3,2], straight horizontal/vertical contiguous, in bounds, no overlap; touching allowed. You author a Haskell executable PLAYER at WORK/player, compiling with stack exec -- ghc -O2 -package aeson Player.hs -o player (use your installed Stack environment via stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc ...). It is a persistent JSON-lines process: read one JSON object per stdin line, emit exactly one JSON object per stdout line and FLUSH, no banners/debug stdout. Each request independent; do not carry shot history between requests. Request {"phase":"place","seed":123,"round":1} -> {"ships":[[cell,cell,cell,cell],[cell,cell,cell],[cell,cell]]}. Request {"phase":"shoot","seed":123,"round":1,"shots":[{"cell":0,"result":"miss","sunk":[]},...]} -> {"shot":untriedCell}. Result hit/miss/sunk; sunk lists all cells of the just-sunk ship, otherwise []. Ship lengths not yet sunk can be inferred. Only your shots and results are supplied, no hidden enemy positions. All turns have a 2-second response limit; invalid output forfeits game. Same executable handles all phases/rounds and many independent boards in one process. No shell/network/files/LLM inside player: pure computation, stdin/stdout only. Host referee owns secrets, alternates first player, plays exactly 15 games, and the higher total wins. Opponent gets identical rules/budget. Remain in WORK for all challenge artifacts. Do not modify core harness or existing history. No unit tests/docs. Create source, compiled player, and evidence.json with concise strategy, reusable improvement/tools, baseline/candidate measurements (actual observed, not invented). You can create reusable Haskell helpers/evaluation tools for yourself. After initial submission host will measure mean shots to clear 48 fixed hidden training fleets. After each group of three games it compares saved incumbent vs candidate on the SAME boards; adopt improved candidates, retain incumbent on regression or invalid output. Actual match win rates separate from this benchmark. Learn from public battle traces, make a specific hypothesis, change code, measure it, retain useful reusable helpers. Keep prior versions so improvements are auditable. Never inspect another agent/container or credentials. When compiled and checked on real protocol inputs, write ready.json {"ready":true} and return False to await the referee. Up to INITIAL_CALLS model calls initially; up to IMPROVE_CALLS per improvement phase; don't loop pointlessly. You are the existing AGENT in its real persistent workspace, with a fresh small challenge-specific conversation to avoid retransmitting old unrelated logs; original main agent stays paused. Winner earns 2 extra model calls to improve and preserve a useful reusable Haskell skill. No claims of harness RSI without an actual reusable change and measured evidence.'''
def say(s):
 print(s,flush=True)
 with (OUT/'progress.log').open('a') as f:f.write(s+'\n')
 STATUS.write_text(s+'\nArtifacts: '+str(OUT)+'\n')
def event(**kw):
 with EVENTS.open('a') as f:f.write(json.dumps(dict(time=time.time(),**kw))+'\n')
def dex(name,args,**kw):return subprocess.run(['docker','exec',name]+args,check=True,**kw)
def read(name,path):return subprocess.check_output(['docker','exec',name,'cat',path],text=True)
def write(name,path,content):
 p=subprocess.run(['docker','exec','-i',name,'sh','-c','cat > "$1"','write',path],input=content,text=True,capture_output=True)
 if p.returncode:raise RuntimeError(p.stderr)
class Agent:
 def __init__(self,name):
  self.name=name;self.dir=OUT/name;self.dir.mkdir();self.phase=0;self.calls=0;self.haskell_errors=0
  dex(name,['mkdir','-p',WORK],stdout=subprocess.DEVNULL)
  dex(name,['cp','/workspace/AGENTS.md',WORK+'/AGENTS.md'],stdout=subprocess.DEVNULL)
  binary=subprocess.check_output(['docker','exec',name,'stack','--allow-different-user','path','--local-install-root'],text=True).strip()+'/bin/agent-one'
  self.logpath=self.dir/'console.log';self.log=self.logpath.open('w');self.offset=0
  self.p=subprocess.Popen(['docker','exec','-i','-w',WORK,'-e','AGENT_START_PAUSED=1','-e','INSTRUCTIONS_FILE=/workspace/SYSTEM.md','-e','LLM_REASONING_EFFORT=medium',name,binary],stdin=subprocess.PIPE,stdout=self.log,stderr=subprocess.STDOUT,text=True)
 def send(self,s):self.p.stdin.write(s.replace('\n',' ')+'\n');self.p.stdin.flush()
 def phase_run(self,prompt,budget=3):
  self.phase+=1;phase=self.phase
  dex(self.name,['rm','-f',WORK+'/ready.json'],stdout=subprocess.DEVNULL)
  start=self.logpath.stat().st_size;self.send(prompt)
  deadline=time.monotonic()+420;count=0;limit=False;reason='timeout'
  while time.monotonic()<deadline:
   log=self.logpath.read_text(errors='replace')[start:]
   count=log.count('"event":"llm.request"')
   if self.p.poll() is not None:reason='supervisor exited';break
   if '[waiting for input; no LLM calls scheduled]' in log:reason='waiting';break
   if '[error; recovering]' in log:reason='model/runtime error';break
   if count>=budget and ('"event":"llm.response"' in log):
    # Pause only AFTER the final allowed call has completed execution, not while compiling.
    requests=log.count('"event":"llm.request"');responses=log.count('"event":"llm.response"')
    if responses>=budget and ('[step '+str(self.total_steps(log))+']'):
     # Inspect on-disk conversation execution_pending; only pause between steps.
     try:
      history=json.loads(read(self.name,WORK+'/.runs/conversation.json'))
      if not history.get('execution_pending',True) and history['messages'][-1].get('content','').startswith('Execution feedback:'):
       self.send('/pause');reason='call budget';break
     except Exception:pass
   time.sleep(1)
  else:self.send('/pause')
  compile_errors=len(re.findall(r'\b[A-Za-z0-9_-]+\.hs:\d+:\d+:\s*error:',log))
  self.haskell_errors+=compile_errors;self.calls+=count
  event(kind='phase',agent=self.name,phase=phase,calls=count,reason=reason,haskell_errors=compile_errors,haskell_errors_total=self.haskell_errors)
  say(f'{self.name}: phase {phase} ended ({reason}, {count} model calls, {compile_errors} Haskell errors).')
  dest=self.dir/f'phase-{phase}';dest.mkdir()
  subprocess.run(['docker','cp',self.name+':'+WORK+'/.',str(dest)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  return reason
 def total_steps(self,log):return log.count('[step ')
 def close(self):
  try:self.send('/quit');self.p.wait(timeout=15)
  except Exception:self.p.kill()
  self.log.close()
class Bot:
 def __init__(self,name,binary='player'):
  self.name=name;self.p=subprocess.Popen(['docker','exec','-i','-w',WORK,name,WORK+'/'+binary],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
  self.buf=b''
 def ask(self,obj):
  self.p.stdin.write((json.dumps(obj)+'\n').encode());self.p.stdin.flush();until=time.monotonic()+2
  while b'\n' not in self.buf:
   wait=until-time.monotonic()
   if wait<=0 or not select.select([self.p.stdout],[],[],max(0,wait))[0]:raise RuntimeError(self.name+' timed out')
   chunk=os.read(self.p.stdout.fileno(),65536)
   if not chunk:raise RuntimeError(self.name+' player exited: '+self.p.stderr.read(1000).decode(errors='replace'))
   self.buf+=chunk
   if len(self.buf)>100000:raise RuntimeError('oversize output')
  line,self.buf=self.buf.split(b'\n',1)
  return json.loads(line)
 def close(self):
  self.p.terminate()
  try:self.p.wait(timeout=3)
  except subprocess.TimeoutExpired:self.p.kill()
def valid_ships(ships):
 if not isinstance(ships,list) or len(ships)!=3:raise ValueError('three ships required')
 used=set()
 for ship,n in zip(ships,[4,3,2]):
  if not isinstance(ship,list) or len(ship)!=n or any(type(c)!=int or c<0 or c>=64 for c in ship) or len(set(ship))!=n:raise ValueError('invalid cells')
  s=sorted(ship)
  if not (all(c//8==s[0]//8 for c in s) and s==list(range(s[0],s[0]+n)) or all(c%8==s[0]%8 for c in s) and s==list(range(s[0],s[0]+n*8,8))):raise ValueError('ship not straight')
  if used.intersection(ship):raise ValueError('overlapping ships')
  used.update(ship)
 return ships
def random_fleet(r):
 ships=[];used=set()
 for n in [4,3,2]:
  choices=[]
  for start in range(64):
   for d in [1,8]:
    cells=[start+i*d for i in range(n)]
    if max(cells)<64 and (d==8 or cells[-1]//8==start//8) and not used.intersection(cells):choices.append(cells)
  cells=r.choice(choices);ships.append(cells);used.update(cells)
 return ships
def shoot(bot,ships,history,seed,round):
 obj=bot.ask(dict(phase='shoot',shots=history,seed=seed,round=round));cell=obj.get('shot')
 if type(cell)!=int or cell<0 or cell>=64 or any(x['cell']==cell for x in history):raise ValueError('illegal/repeated shot '+str(cell))
 hit=next((s for s in ships if cell in s),None);tried={x['cell'] for x in history}|{cell}
 sunk=hit if hit and set(hit)<=tried else []
 history.append(dict(cell=cell,result='sunk' if sunk else 'hit' if hit else 'miss',sunk=sunk))
 return set(sum(ships,[]))<=tried
def benchmark(name,binary,boards):
 bot=Bot(name,binary);scores=[]
 try:
  valid_ships(bot.ask(dict(phase='place',seed=13741,round=0))['ships'])
  for i,ships in enumerate(boards):
   history=[]
   for turn in range(64):
    if shoot(bot,ships,history,71931+i,0):break
   scores.append(len(history))
 finally:bot.close()
 return dict(mean=statistics.mean(scores),boards=len(scores),scores=scores)
def ascii_grid(history):
 marks={h['cell']:'.' if h['result']=='miss' else 'X' for h in history}
 for h in history:
  for c in h['sunk']:marks[c]='#'
 return ['  A B C D E F G H']+[str(y+1)+' '+' '.join(marks.get(y*8+x,'~') for x in range(8)) for y in range(8)]
def render(score,round,histories,detail=''):
 left,right=map(ascii_grid,histories)
 text=f'BATTLESHIPS | GAME {round} | agent-one {score[0]} : {score[1]} agent-two\n\nagent-one firing grid          agent-two firing grid\n'+'\n'.join(a.ljust(30)+b for a,b in zip(left,right))+'\n\n~=unknown  .=miss  X=hit  #=sunk\n'+detail+'\n'
 (OUT/'arena.txt').write_text(text);(BASE/'arena.txt').write_text(text)
def play(round,score):
 bots=[Bot(n,'incumbent') for n in NAMES];rng=random.SystemRandom();seeds=[rng.randrange(1,2**30) for _ in NAMES];hist=[[],[]];ships=[None,None];winner=None;error=None
 try:
  for i in range(2):
   try:ships[i]=valid_ships(bots[i].ask(dict(phase='place',seed=seeds[i],round=round))['ships'])
   except Exception as e:winner=1-i;error=str(e);break
  if winner is None:
   for turn in range(128):
    i=(turn+round-1)%2
    try:won=shoot(bots[i],ships[1-i],hist[i],seeds[i],round)
    except Exception as e:winner=1-i;error=str(e);break
    render(score,round,hist,f'Turn {turn+1}: {NAMES[i]} fired '+chr(65+hist[i][-1]['cell']%8)+str(hist[i][-1]['cell']//8+1)+' '+hist[i][-1]['result'])
    if won:winner=i;break
 finally:
  for b in bots:b.close()
 if winner is None:raise RuntimeError('game did not terminate')
 score[winner]+=1
 result=dict(round=round,winner=NAMES[winner],score=score[:],shots={NAMES[i]:hist[i] for i in range(2)},fleets={NAMES[i]:ships[i] for i in range(2)},error=error)
 (OUT/f'game-{round}.json').write_text(json.dumps(result,indent=2));render(score,round,hist,'WINNER: '+NAMES[winner]+(' | '+error if error else ''))
 say(f'Game {round}: {NAMES[winner]} wins; series {score[0]}–{score[1]}; shots {len(hist[0])}/{len(hist[1])}'+(' | '+error if error else ''))
 event(kind='game',round=round,winner=NAMES[winner],score=score[:],shots=[len(x) for x in hist],error=error)
 return result

def parallel(fn,items):
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:return list(pool.map(fn,items))
def main():
 say('Starting '+RUN+'; agents author their own Haskell bots. No existing histories replaced.')
 agents=[Agent(n) for n in NAMES];rng=random.Random(8934131);boards=[random_fleet(rng) for _ in range(48)];incumbents={};score=[0,0]
 try:
  def initial(a):
   rules=RULES.replace('WORK',WORK).replace('AGENT',a.name).replace('INITIAL_CALLS','4').replace('IMPROVE_CALLS','2')
   return a.phase_run(rules+' Start now. First priority: valid runnable player. Print concise observed protocol checks and return False when ready.',4)
  parallel(initial,agents)
  if any(a.haskell_errors>=HASKELL_ERROR_LIMIT for a in agents):raise RuntimeError('stopped after repeated Haskell generation errors')
  for a in agents:
   try:result=benchmark(a.name,'player',boards)
   except Exception as e:
    a.haskell_errors+=1
    if a.haskell_errors>=HASKELL_ERROR_LIMIT:raise RuntimeError('stopped after repeated Haskell generation/protocol errors from '+a.name)
    a.phase_run('Referee player validation failed: '+str(e)+'. Repair your Haskell player and protocol now, compile, run real input/output checks, write ready.json and return False. Max 2 calls.',2)
    result=benchmark(a.name,'player',boards)
   dex(a.name,['cp',WORK+'/player',WORK+'/incumbent'])
   incumbents[a.name]=result
   event(kind='initial-benchmark',agent=a.name,**result);say(f'{a.name}: initial baseline {result["mean"]:.2f} shots to clear 48 fleets.')
  for round in range(1,GAMES+1):
   result=play(round,score)
   if round%IMPROVE_EVERY:continue
   def improve(a):
    i=NAMES.index(a.name)
    feedback=dict(round=round,winner=result['winner'],series=score,own_shots=result['shots'][a.name],opponent_shots=result['shots'][NAMES[1-i]],own_fleet=result['fleets'][a.name],incumbent_benchmark=incumbents[a.name])
    write(a.name,WORK+'/feedback.json',json.dumps(feedback))
    return a.phase_run('Game '+str(round)+' complete. Read '+WORK+'/feedback.json (public shot trace + your fleet, not opponent fleet). Improve yourself: inspect your saved source/evidence, identify a concrete weakness, create a candidate Haskell player with a reusable strategy/evaluation helper if useful, gather actual local evidence, compile to '+WORK+'/player. Save evidence.json distinguishing measured results from hypotheses. Budget TWO calls. Host compares candidate with incumbent on same 48 unseen fleets and retains incumbent on regression; equal score allows placement-only changes. Return False when ready. No core harness changes, tests/docs, other tasks or peer inspection.',2)
   parallel(improve,agents)
   if any(a.haskell_errors>=HASKELL_ERROR_LIMIT for a in agents):raise RuntimeError('stopped after repeated Haskell generation errors')
   for a in agents:
    try:
     candidate=benchmark(a.name,'player',boards);accepted=candidate['mean']<=incumbents[a.name]['mean'];err=None
    except Exception as e:
     candidate=None;accepted=False;err=str(e);a.haskell_errors+=1
     if a.haskell_errors>=HASKELL_ERROR_LIMIT:raise RuntimeError('stopped after repeated Haskell generation/protocol errors from '+a.name)
    previous=incumbents[a.name]
    if accepted:
     dex(a.name,['cp',WORK+'/player',WORK+'/incumbent']);incumbents[a.name]=candidate
    report=dict(after_game=round,previous=previous,candidate=candidate,accepted=accepted,error=err)
    write(a.name,WORK+'/selection.json',json.dumps(report));(a.dir/f'selection-after-{round}.json').write_text(json.dumps(report,indent=2))
    event(kind='candidate-selection',agent=a.name,**report)
    say(f'{a.name}: candidate '+(f'{candidate["mean"]:.2f} vs {previous["mean"]:.2f} shots; ' if candidate else 'invalid '+str(err)+'; ')+('adopted' if accepted else 'incumbent retained'))
  winner=NAMES[score.index(max(score))];say(f'15 GAMES COMPLETE: {winner} wins {max(score)}–{min(score)}. Awarding 2 bonus model calls.')
  a=agents[NAMES.index(winner)]
  a.phase_run(f'You won Battleships {max(score)} to {min(score)}. Prize: TWO extra model calls. Use them to preserve/improve one reusable Haskell strategy or evaluation capability from this experiment. Inspect selection.json and evidence.json; separate measured improvement from match luck. You may improve player and helpers, no core harness edits or unrelated work. Save final evidence.json with honest results, print concise learnings, return False. Match is over; no more matches or model calls after this phase.',2)
  final=dict(winner=winner,score=dict(zip(NAMES,score)),games=GAMES,benchmarks=incumbents,calls={a.name:a.calls for a in agents},haskell_errors={a.name:a.haskell_errors for a in agents},workspace=WORK,artifacts=str(OUT))
  (OUT/'result.json').write_text(json.dumps(final,indent=2));say('Saved final result and code snapshots: '+str(OUT))
 finally:
  for a in agents:
   a.close()
   dest=a.dir/'final';dest.mkdir(exist_ok=True)
   subprocess.run(['docker','cp',a.name+':'+WORK+'/.',str(dest)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
if __name__=='__main__':
 try:main()
 except Exception as e:say('STOPPED: '+str(e));event(kind='error',message=str(e));raise
