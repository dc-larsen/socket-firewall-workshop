cd /work/D1
echo "### CI (off-tailnet) installing from a lock generated in REWRITE mode"
rm -rf .venv
if uv sync --frozen -q 2>/tmp/e.log; then
  echo "uv sync --frozen: SUCCESS"
else
  echo "uv sync --frozen: FAILED"
  grep -iE "failed to fetch|caused by" /tmp/e.log | head -4 | sed 's/^/  | /'
fi
