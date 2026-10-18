#!/bin/sh
set -eu
cp /opt/agent/LICENSE /workspace/LICENSE
if [ ! -f /workspace/agent-one.cabal ]; then
  cp /opt/agent/agent-one.cabal /opt/agent/stack.yaml /opt/agent/stack.yaml.lock /workspace/
  cp -R /opt/agent/app /opt/agent/src /workspace/
fi
if [ ! -f /workspace/AGENTS.md ]; then
  cp /opt/agent/AGENTS.md /workspace/
fi
if [ ! -f /workspace/SYSTEM.md ]; then
  cp /opt/agent/SYSTEM.md /workspace/
fi
stack --allow-different-user build --jobs 2
exec stack --allow-different-user exec agent-one
