echo "### CI container (no route to sfw.mercor.test). Force a RE-RESOLUTION."
echo ""

trial() {
  proj="$1"; label="$2"
  cp -r /work/$proj /work/${proj}-ci 2>/dev/null
  cd /work/${proj}-ci
  # simulate a developer adding a dependency -> lock is now stale, uv must re-resolve
  sed -i 's/dependencies = \[.*\]/dependencies = ["asn1crypto==1.5.1", "blinker==1.9.0", "six==1.17.0"]/' pyproject.toml
  echo "=== $label"
  echo -n "    pyproject pins an index? "; grep -q 'tool.uv.index' pyproject.toml && echo "YES (proxy url committed in repo)" || echo "no"
  if uv lock -q 2>/tmp/c.log; then
    echo "    uv lock: SUCCESS"
    echo -n "    lock now sourced from: "
    grep -oE 'registry = "https://[^"]+"' uv.lock | sort -u | head -2 | tr '\n' ' '; echo ""
  else
    echo "    uv lock: FAILED"
    grep -iE "failed to fetch|dns error|lookup|caused by" /tmp/c.log | head -3 | sed 's/^/    | /'
  fi
  echo ""
}

rm -rf /work/A1-ci /work/A3-ci
trial A1 "C1: index committed in pyproject.toml (Kevin's config)"
trial A3 "C2: index kept OUTSIDE the repo (uv.toml / env var)"
