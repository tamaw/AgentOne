#!/bin/sh
set -eu
if [ ! -f /workspace/agent-one.cabal ]; then
  cp /opt/agent/agent-one.cabal /opt/agent/stack.yaml /opt/agent/stack.yaml.lock /workspace/
  cp -R /opt/agent/app /workspace/
  cp /opt/agent/RequestGate.hs /opt/agent/StepLoader.hs /opt/agent/ContextWindow.hs /opt/agent/ExecutionEvidence.hs /opt/agent/NativePreflight.hs /opt/agent/ModelConnection.hs /workspace/
fi
if [ ! -f /workspace/AGENTS.md ]; then
  cp /opt/agent/AGENTS.md /workspace/
fi
if [ ! -f /workspace/SYSTEM.md ]; then
  cp /opt/agent/SYSTEM.md /workspace/
fi
stack --allow-different-user build --jobs 2
exec stack --allow-different-user exec agent-one
