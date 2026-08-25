cd /work/A1
echo "### CI container: sfw.mercor.test is unresolvable. uv.lock says registry = proxy."
echo ""

t() {
  label="$1"; shift
  rm -rf /work/A1/.venv
  echo "=== $label"
  echo "    cmd: $*"
  out=$( "$@" 2>&1 )
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "    RESULT: SUCCESS"
  else
    echo "    RESULT: FAILED (exit $rc)"
    echo "$out" | grep -iE "error|caused by|dns|resolve|lockfile|outdated|mismatch" | head -5 | sed 's/^/    | /'
  fi
  echo ""
}

t "B1 uv sync --frozen (install exactly what lock says, no revalidation)" uv sync --frozen -q
t "B2 uv sync --locked (assert lock is up to date, then install)" uv sync --locked -q
t "B3 uv sync (default: revalidate + re-resolve if needed)" uv sync -q
t "B4 uv lock --check (what a CI drift gate would run)" uv lock --check
t "B5 uv export to requirements.txt" uv export --format requirements.txt -o /tmp/req.txt -q

echo "=== B6: uv sync --frozen with CI pointed at public PyPI (index override)"
rm -rf /work/A1/.venv
if UV_INDEX_URL=https://pypi.org/simple uv sync --frozen -q 2>/tmp/b6.log; then
  echo "    RESULT: SUCCESS"
else
  echo "    RESULT: FAILED"; grep -iE "error|caused by" /tmp/b6.log | head -4 | sed 's/^/    | /'
fi
echo ""
echo "=== B7: does --frozen install actually reach files.pythonhosted.org only?"
rm -rf /work/A1/.venv
uv sync --frozen -q && python -c "import asn1crypto, blinker; print('    imported asn1crypto', asn1crypto.__version__, '/ blinker', blinker.__version__)" 2>/dev/null || true
