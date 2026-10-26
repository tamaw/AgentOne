# Agent One

An experimental agent harness that executes Haskell written by the model.
Each response is a complete Haskell module: the runtime compiles it, runs its
`step` function, and feeds execution results back into the conversation.

There is no predefined tool catalogue, JSON tool-call protocol, or tool dispatcher.
The generated code directly uses Haskell libraries to read and write files, launch
processes, and make network requests. It can also save callable Haskell functions
for later steps to reuse within the same worker session.

The agent keeps conversation history. Its execution contract and standing
instructions live in `SYSTEM.md`, reread for every call; `AGENTS.md` supplies
project rules.
It continues when a step requests another turn, otherwise waits for input.
There is no scheduled idle loop. Model calls, generated code, and execution
results appear on stdout; session artifacts live in `.runs/`.

The project explores agents extending their own code and improving their workflows. Docker
Compose provides two independent agents with separate persistent workspaces
and a shared network, so they can exchange ideas and code when asked.

Runtime modules live in `src/`, with the executable entry point in `app/`.
See the [recreation spec](docs/spec.md) and [changelog](docs/CHANGELOG.md).

## Run

Requires Docker with Compose and an Azure OpenAI deployment in Microsoft Foundry.
Copy the template, then fill in your resource endpoint, API key, and deployment name
in the untracked `.env`:

```sh
cp .env.example .env
chmod 600 .env
```

```dotenv
LLM_ENDPOINT=https://YOUR-RESOURCE.openai.azure.com/openai/v1
LLM_API_KEY=your-foundry-resource-api-key
LLM_MODEL=gpt-6.1-sol
LLM_REASONING_EFFORT=high
LLM_TIMEOUT_SECONDS=900
```

The harness calls the Foundry-hosted Responses API with API-key authentication.
`LLM_MODEL` must match your deployment name. The endpoint can be the resource URL,
the `/openai/v1` base URL, or the full `/openai/v1/responses` URL.

```sh
docker compose up --build -d agent
docker attach --detach-keys=ctrl-p,ctrl-q agent-one
```

The agent starts paused. Type a task to begin, or `/resume` to continue pending
work. Use `/pause` to pause and `/quit` to exit. Detach with Ctrl+P, Ctrl+Q.

```sh
docker logs --follow --tail 50 agent-one
docker compose up -d agent-two
```

Each agent runs as root in a Debian container with internet access and extensive
development software, including Stack/GHC, Node.js, and Python. Its `/workspace`
volume persists across container recreations. No host Docker socket is mounted.
Treat generated code as executable code with access to that container.

## License

[MIT](LICENSE).
