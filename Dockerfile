FROM debian:trixie-slim
ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 STACK_ROOT=/home/tama/.stack
RUN apt-get update && apt-get install -y --no-install-recommends \
    haskell-stack gcc make libc6-dev libgmp-dev libffi-dev libtinfo6 zlib1g-dev \
    build-essential pkg-config bash bash-completion ca-certificates curl wget git \
    python3 python3-pip python3-venv jq ripgrep fd-find tree file less nano vim-tiny \
    procps psmisc lsof strace gdb iproute2 iputils-ping dnsutils netcat-openbsd \
    openssh-client rsync zip unzip tar xz-utils bzip2 patch sqlite3 && \
    mkdir -p /workspace /home/tama/.stack
RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm python3-dev python3-build pipx \
    rustc cargo rustfmt golang-go default-jdk-headless maven \
    ruby ruby-dev bundler perl lua5.4 luarocks \
    clang clangd clang-format clang-tidy lldb llvm valgrind gdbserver \
    cmake ninja-build autoconf automake libtool ccache \
    shellcheck shfmt parallel moreutils entr tmux screen \
    socat tcpdump nmap iperf3 net-tools openssl \
    postgresql-client redis-tools libssl-dev libsqlite3-dev libxml2-dev \
    libxslt1-dev libcurl4-openssl-dev libreadline-dev libncurses-dev \
    gettext zstd 7zip
COPY agent-one.cabal stack.yaml stack.yaml.lock AGENTS.md SYSTEM.md /opt/agent/
COPY RequestGate.hs StepLoader.hs ContextWindow.hs ExecutionEvidence.hs NativePreflight.hs /opt/agent/
COPY app /opt/agent/app
COPY container-entrypoint.sh /usr/local/bin/agent-one-start
RUN chmod +x /usr/local/bin/agent-one-start
WORKDIR /workspace
ENTRYPOINT ["agent-one-start"]
