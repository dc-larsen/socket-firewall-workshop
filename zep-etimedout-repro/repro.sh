#!/bin/bash
# Deterministic repro for FIRE-150: sfw wrapper mode AggregateError ETIMEDOUT
#
# Runs inside a linux/amd64 container. Reproduces two distinct sfw bugs by
# blackholing the upstream Go module proxy and varying only the number of
# resolved addresses for that host.
#
# Usage (from repo root, with SOCKET_API_KEY in .env.secrets):
#   docker run --rm --platform linux/amd64 \
#     -e SOCKET_API_TOKEN="$KEY" \
#     -v "$PWD/zep-etimedout-repro:/repro" \
#     ubuntu:22.04 bash /repro/repro.sh

set -u
SFW_VERSION="${SFW_VERSION:-v1.15.0}"

apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq curl ca-certificates golang-go >/dev/null 2>&1

curl -sL -o /usr/local/bin/sfw \
  "https://github.com/SocketDev/firewall-release/releases/download/${SFW_VERSION}/sfw-linux-x86_64"
chmod +x /usr/local/bin/sfw
echo "### $(sfw --version)"

mkdir -p /work && cd /work
go mod init reprotest >/dev/null 2>&1
printf 'package main\nimport (\n"fmt"\n"github.com/google/uuid"\n)\nfunc main(){fmt.Println(uuid.New().String())}\n' > main.go
go mod edit -require=github.com/google/uuid@v1.6.0
export GOFLAGS=-mod=mod
cp /etc/hosts /etc/hosts.orig

# Resolve the real upstream IP NOW, before any /etc/hosts poisoning below.
# Resolving it later returns our own blackhole entry and silently turns the
# dual-stack failover tests into single-dead-address tests.
REAL=$(getent ahostsv4 proxy.golang.org | awk '{print $1}' | sort -u | head -1)
echo "### real proxy.golang.org = ${REAL:-<unresolved>}"

# Blackhole addresses: non-routable RFC1918 space, so connects TIME OUT
# rather than being refused. ECONNREFUSED takes a different code path.
blackhole() {
  cp /etc/hosts.orig /etc/hosts
  for ip in "$@"; do echo "$ip proxy.golang.org" >> /etc/hosts; done
}

attempt() {
  local label="$1"; shift
  echo
  echo "=================================================="
  echo "### $label"
  echo "=================================================="
  go clean -modcache >/dev/null 2>&1
  rm -f /work/out
  "$@" > /work/log 2>&1
  local rc=$?
  echo "--> exit code : $rc"
  echo "--> artifact  : $( [ -f /work/out ] && echo YES || echo 'NO (build failed)' )"
  echo "--> output    :"
  sed 's/^/     /' /work/log | head -8
}

# ---------------------------------------------------------------------------
# BUG 1: error class depends on how many addresses the host resolves to.
# One address  -> plain Error, message NAMES the host:port (diagnosable)
# Two addresses-> AggregateError, EMPTY message, host:port discarded
# ---------------------------------------------------------------------------
blackhole 10.255.255.1
attempt "ONE blackholed address -> plain Error, host is visible" \
  sfw go build -o /work/out ./...

blackhole 10.255.255.1 10.255.255.2
attempt "TWO blackholed addresses -> AggregateError, host is LOST" \
  sfw go build -o /work/out ./...

# ---------------------------------------------------------------------------
# BUG 2: sfw swallows the wrapped command's non-zero exit code.
# Control: bare `go build` under the identical network fault.
# ---------------------------------------------------------------------------
blackhole 10.255.255.1 10.255.255.2
attempt "CONTROL: bare go build, same fault (expect exit 1)" \
  go build -o /work/out ./...

# ---------------------------------------------------------------------------
# NEGATIVE RESULTS: Node-level Happy Eyeballs knobs do NOT help.
# Shape here is realistic dual-stack: one dead address, one working address.
# $REAL was resolved at the top of the script, before any /etc/hosts edits.
# ---------------------------------------------------------------------------
dualstack() {
  cp /etc/hosts.orig /etc/hosts
  echo "10.255.255.1 proxy.golang.org" >> /etc/hosts
  echo "$REAL proxy.golang.org"        >> /etc/hosts
}

dualstack
attempt "default attempt timeout (250ms) -> fails over fine" \
  sfw go build -o /work/out ./...

dualstack
attempt "attempt timeout 5000ms -> SLOWER failover, not a fix" \
  env NODE_OPTIONS=--network-family-autoselection-attempt-timeout=5000 \
  sfw go build -o /work/out ./...

dualstack
attempt "--no-network-family-autoselection -> HANGS, actively harmful" \
  env NODE_OPTIONS=--no-network-family-autoselection \
  sfw go build -o /work/out ./...
