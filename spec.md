# Agent One — recreation specification

This describes the working application as of 2026-10-15. Recreate the current
minimal application first; the final section lists proposed improvements that
have not been implemented. This specification was explicitly requested as an
exception to the project's usual no-documentation preference.

## Purpose and constraints

Build an interactive, persistent, code-first agent. Its model writes Haskell
programs and the runtime executes them. Generated programs can access files,
processes and the internet, install reusable functions, and call functions
installed by earlier programs. No TypeScript implementation or JSON tool-call
dispatcher is required. Node.js is available as a tool inside the container.

Use Stack. Keep the harness small. Do not add unit tests. Optimize for correctness
and efficiency; human readability is not a requirement. Do not generate additional
documentation unless requested.

The agent has no model-level finish action. It remains alive waiting for input
when work runs out. Starting another model call is a decision made after the
previous response and execution finish, never a periodic scheduled task.

## Research references

1. [How Much of a Harness Does a Strong Agent Need for Autonomous ML Engineering?](https://arxiv.org/abs/2609.40303)
   — Kirill Brilliantov, Alejandro Hernández-Cano and Emmanuel Abbé. Under the
   tested model and equal time budgets, elaborate MLE harnesses did not outperform
   a minimal coding-agent session. Motivation: begin with direct execution and a
   strong model; add machinery in response to measured failures.
2. [An Empirical Study of Harness Design for Coding Agents](https://arxiv.org/abs/2609.20804)
   — Run-Ze Fan et al. Studies planning, action space and context management.
   Context management primarily prevents overflow; removing bulky content before
   model-based summarization was particularly efficient. Benefits of planning
   and predefined tools depend on model capability and task. Motivation: manage
   long histories before expanding the orchestration system.
3. [Recursive self-improvement of AI research agents (AIDE²)](https://arxiv.org/abs/2609.26457)
   — Dhruv Srikanth et al. Proposes edits to agent code, evaluates candidate agents
   and retains improvements using hidden evaluations. Motivation: distinguish
   writing a new capability from demonstrating better task performance; compare
   versions under equal budgets and preserve the best version.
4. [Metaⁿ: Recursive Self-Improvement through Emergent Depth](https://arxiv.org/abs/2608.24735)
   — Zae Myung Kim, Young-Jun Lee, Seungyeon Jwa and Dongyeop Kang. Keeps the
   improvement operation fixed while using solver code and execution traces to
   produce strategy layers and callable helpers. Motivation: let the agent build
   useful helpers and learn from execution traces while retaining a stable
   execution contract.

These papers motivate design choices. The current application does not reproduce
their full systems or establish their benchmark claims for Haskell or this model.

## Source layout and build

Required files:

```text
app/Main.hs                 supervisor and worker in one executable
agent-one.cabal             executable/package definition
stack.yaml                 Stack resolver
stack.yaml.lock             generated dependency lock
Dockerfile                 Debian development environment
compose.yaml               service, input terminal and volumes
container-entrypoint.sh     seed workspace, build, launch
SYSTEM.md            live standing task instructions
AGENTS.md                  project preferences
.dockerignore              build-context allowlist
.gitignore                 exclude credentials and runtime/build artifacts
.env                       local credentials; never commit or bake into image
```

Package: `agent-one`, version `0.1.0.0`, Cabal 2.4, build type Simple, executable
`agent-one`, `main-is: Main.hs`, `hs-source-dirs: app`, Haskell2010.
Default extensions: `OverloadedStrings`, `ScopedTypeVariables`.
GHC options: `-O2 -dynamic -threaded -rtsopts`.
Dependencies: `base >=4.18 && <5`, `aeson`, `async`, `bytestring`, `containers`,
`directory`, `hint`, `process`, `stm`, `text`, `time`, `unix`.
Stack resolver: `lts-22.44` (GHC 9.6.7); packages: `[.]`.

## Model connection

Read configuration from environment variables, optionally loading missing values
from a local `.env` file with `NAME=value` entries. Existing environment values
win. Required configuration:

```dotenv
LLM_ENDPOINT=https://YOUR-RESOURCE.openai.azure.com/openai/v1
LLM_API_KEY=<supply privately>
LLM_MODEL=gpt-6.1-sol
```

Optional `INSTRUCTIONS_FILE` defaults to `SYSTEM.md`; Compose sets it to
`/workspace/SYSTEM.md`. The deployment/model name must exist on the supplied
endpoint. No real credential belongs in this specification.

Use the Azure OpenAI Responses API through `curl`, not an SDK. Remove trailing
slashes from the endpoint; strip a `/api/projects/...` suffix if supplied. Append
`/responses` when the base ends in `/v1`, otherwise append `/openai/v1/responses`.
Send `api-key` and `Content-Type: application/json` headers. Pass curl configuration
and credentials through stdin (`--config -`), not process arguments. Use
`--silent --show-error --fail-with-body --max-time 120`.

Request JSON contains `model`, `instructions`, `input` and `store: false`.
`input` is the saved conversation as role/content objects. Instructions combine
the runtime contract, freshly read `AGENTS.md`, and freshly read standing
instructions on every call. Parse completed Responses output messages and
concatenate their `output_text` content. Reject empty source or incomplete status.
There is no token streaming; stdout shows request metadata immediately and source
when the full response arrives.

## Generated-code contract

Every model response must be an entire Haskell module without Markdown fences:

```haskell
module Step where
import Data.IORef
import qualified Data.Map.Strict as M

step :: IORef (M.Map String String)
     -> IORef (M.Map String (IO ()))
     -> IO Bool
step memory actions = do
  putStrLn "Waiting for work."
  pure False
```

Other imports are allowed. `memory` holds string values shared across steps.
`actions` holds named `IO ()` closures shared across steps. An installed action
can capture the memory IORef, read its inputs from named keys and write results
back to named keys. Subsequent generated modules retrieve and invoke the stored
closure without redefining it. Modules can also use ordinary Haskell file and
process APIs directly; these are not special harness tools.

`True` requests another model call after execution feedback is saved. `False`
blocks until new user input or `/resume`. Do not sleep, invent tasks or generate
idle steps. The Boolean is evaluated by the generated program at execution time;
the model sees the resulting output on the next call if continuation is requested.

## Supervisor and worker

Run the executable normally as supervisor; `--worker` selects the worker mode.
The supervisor owns model credentials, history, terminal input, logging and
scheduling. Spawn a persistent worker subprocess with a stdin pipe and its own
process group. Remove environment variables whose names contain `KEY`, `TOKEN`,
`SECRET`, `PASSWORD` or `LLM_` before spawning it.

The worker creates the two IORefs once. For each source-file path received on
stdin, load the module with `hint`, select module `Step`, interpret `Step.step`
at the required type, and run it with those IORefs. Dynamic loading is what lets
new generated code install functions for later steps without restarting the worker.

Redirect worker stdout/stderr to `<source>.output` during compilation/execution.
Write `<source>.result.tmp`, then rename to `<source>.result` on completion. Result
is `CONTINUE`, `WAIT`, or exception text. Apply a 60-second action timeout and a
90-second supervisor wait limit. Relay up to 16,000 bytes of output to stdout and
the model; poll execution files every 50 ms. This polling only watches local
execution output and does not schedule model calls.

One model request and one generated step may be active at a time. Terminal input
remains responsive through a concurrent input loop. Save user input immediately,
increment an STM generation counter and clear pause. Snapshot the generation
before a request; when its step returns False, wait for a different generation.
This preserves wakeups for messages arriving during an active call or execution.

Compile errors and normal step exceptions become execution feedback and request
another call so the agent can repair its code. There is currently no repair-count
or task-cost cap. Transport/API failures and supervisor failures pause the agent
and require user input or `/resume`; do not retry on a timer.

Terminal controls:

- Ordinary nonempty line: save as a user message and wake the agent.
- `/pause`: cancel the active operation, kill the worker process group, start a
  fresh worker and remain paused. Live memory/actions reset; files survive.
- `/resume`: unpause/wake and request another model turn.
- `/quit`: exit the supervisor and stop its worker.

Without a standing instructions file, start paused awaiting input. With one,
start automatically. Read the existence choice at startup and reread its contents
on each call. An idle process remains alive without repeated LLM calls.

## Durable conversation and observations

Use `.runs/conversation.json` containing `messages` and `execution_pending`.
Serialize modifications with an MVar and checkpoint through temporary-file rename.
Save assistant source with pending=True before executing; save feedback with
pending=False afterward. Do not silently discard malformed saved history.

On restart, restore history and append a message explaining that worker memory and
actions were reset while files persisted. If execution was pending, explain that
effects may have partially happened and should be inspected before repeating.
Do not automatically replay old source. With standing instructions present,
restart initiates a model turn even if the previous process was idle.

Create `.runs/haskell-<microsecond timestamp>/` per supervisor session:

- `llm-N.request.json`: complete request payload without authentication headers.
- `llm-N.request.json.response.json`: complete successful response JSON.
- `StepN.hs`, `StepN.hs.output`, `StepN.hs.result`: generated source and execution.
- `events.jsonl`: user messages, step source/output/continuation and failures.

Emit JSON events `llm.request`, `llm.response` and `llm.error` to stdout. Include
request path, message count, timing, model, response ID/status and usage where
available. Print generated source between `[llm code]` markers, relay execution
output, and explicitly print when waiting. Redact the known API key from model
logging and supervisor error text. Do not print authentication headers.

Full conversation is currently sent on every call; no context compaction exists.
Runtime closures and IORef data are not persisted or automatically restored.
Saved source/history provide evidence but are not a capability-loading system.
Credential filtering and instructions are best-effort precautions, not a security
boundary against arbitrary code sharing a root-owned container.

## Container and operating environment

Base image: `debian:trixie-slim`, default root user, UTF-8 locale
`LANG=C.UTF-8 LC_ALL=C.UTF-8`. Set `STACK_ROOT=/home/tama/.stack` consistently so
cached toolchain paths match. Work in `/workspace`.

Provide Stack and native Haskell dependencies (`gcc`, `make`, `libc6-dev`,
`libgmp-dev`, `libffi-dev`, `libtinfo6`, `zlib1g-dev`). Also install a generous
development environment: Node/npm; Python/pip/venv/pipx; Rust/Cargo; Go; Java/Maven;
Ruby/Bundler; Perl; Lua/LuaRocks; GCC and Clang/LLVM tools; CMake/Ninja/Autotools;
debuggers, valgrind, strace and lsof; Git, editors, shellcheck, shfmt, tmux and
screen; curl, wget, DNS tools, ping, netcat, socat, tcpdump, nmap and iperf;
jq, ripgrep, fd-find, archive tools, rsync, SQLite, PostgreSQL and Redis clients;
common SSL, XML, curl, SQLite and terminal development libraries. Install trusted
CA certificates. Exact apt versions follow the Debian image/repository state;
the existing Dockerfile is the package manifest, not a frozen OS snapshot.

Copy source templates to `/opt/agent`. On first startup only, seed missing
`/workspace/agent-one.cabal` and associated source/config files from that directory.
Seed instructions if missing. Run `stack --allow-different-user build --jobs 2`,
then `exec stack --allow-different-user exec agent-one`. Existing workspace source
takes priority over image templates; rebuilding the image does not overwrite a
previously initialized workspace volume. Deploy subsequent source edits into that
volume explicitly and restart to rebuild.

Compose service `agent`: image `local/agent-one:haskell`, container `agent-one`,
`init: true`, `stdin_open: true`, `tty: true`, `restart: unless-stopped`, credentials
from `.env`. Use Docker's default bridge with outbound internet. Mount:

```text
agent-one-work  -> /workspace
agent-one-stack -> /home/tama/.stack
./SYSTEM.md -> /workspace/SYSTEM.md (read-only)
./AGENTS.md       -> /workspace/AGENTS.md (read-only)
```

No host Docker socket or host project directory is mounted. Do not include `.env`
in the build context/image. Allowlist only Dockerfile, app sources, Cabal/Stack
files, entrypoint and instruction templates in `.dockerignore`. Ignore `.env`,
`.runs/` and `.stack-work/` in Git.

An empty Stack volume can download/build the toolchain with network access.
Optionally seed it from a compatible existing Stack installation at the same
absolute path; this was used locally to avoid downloading GHC again.

## Standing instructions

`AGENTS.md` carries the project preferences stated above. `SYSTEM.md` tells
the agent about its root Debian environment, tools, network and persistent volume;
requires it to obey AGENTS.md, use Haskell for generated steps, and avoid reading
`.env` or disclosing credentials. On startup it inspects the workspace, verifies
writing and access to `https://example.com`, saves `.runs/environment.json`, and
reports the observations. It then follows the latest task, prioritizes user
input, and returns False when no work remains. Source changes require a task.

## Running and live acceptance checks

```sh
docker compose up -d --build
docker compose logs -f --tail 100 agent
docker attach --sig-proxy=false agent-one
```

Detach from attach using Ctrl+P then Ctrl+Q. Ctrl+C in the log viewer stops only
the viewer. For local execution with configured environment: `stack build`, then
`stack exec agent-one`.

Use actual agent interactions for acceptance checks; do not create unit tests:

1. Receive generated Haskell, compile it dynamically, and print a known result.
2. Store a value and action in one module, call that action from a later module,
   and replace it with a new implementation while retaining worker memory.
3. Return True to trigger a subsequent call, then False to wait. Confirm request
   count stays unchanged while idle; a new input wakes the process.
4. Save a conversation marker, restart, and recall it from restored history.
5. Confirm root, Node/npm, writable workspace, outbound HTTPS and both instruction
   files are available. Confirm logs do not contain the supplied API key.

Observed capability-extension demonstration: the agent confirmed no `calculator`
action existed, wrote and installed one, then a separate generated module invoked
the stored closure. Inputs used memory keys `calc.operator`, `calc.left` and
`calc.right`; output used `calc.result`. Results were `17+25=42`, `6*7=42`,
`144/12=12`. After idling, a fresh request reused it for `100-58=42` and received
`ERROR: division by zero` for `9/0`. Invocation modules did not redefine the
calculator. This demonstrates runtime capability extension, not a measured
improvement in general agent performance.

## Proposed next improvements — not implemented

1. Persist reusable capability modules and an explicit registry, then reload them
   after restart. Do not mistake archived source for automatic restoration.
2. Evaluate baseline and modified agent versions on the same task collection with
   equal budgets. Record task success, token use and elapsed time; reserve tasks
   unseen during improvement for checking transfer. Respect the no-unit-tests
   preference: these are agent-level experiments.
3. Archive known working versions and accept replacements only when measurements
   improve. Keep an easy rollback path.
4. Bound request context while retaining full logs: remove bulky old execution
   outputs first, summarize older work when necessary, preserve current task and
   recent failures. Preserve the durable full conversation separately.
5. Explore a stable improvement operation that reads code and execution traces and
   writes reusable helpers or strategy modules. Add depth only when measurements
   justify it; do not schedule idle self-improvement calls.
