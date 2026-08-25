IDX="https://sfw.mercor.test/pypi/simple/"
rm -rf /work/D1; mkdir -p /work/D1; cd /work/D1
printf '[project]\nname = "repro-d1"\nversion = "0.1.0"\nrequires-python = ">=3.12"\ndependencies = ["asn1crypto==1.5.1", "blinker==1.9.0"]\n' > pyproject.toml
echo "### pypi route now in mode: rewrite (the firewall default)"
if UV_INDEX_URL="$IDX" uv lock -q 2>/tmp/d.log; then
  echo "uv lock: SUCCESS"
  echo -n "  registry sources : "; grep -oE 'registry = "https://[^"]+"' uv.lock | sort -u | tr '\n' ' '; echo ""
  echo -n "  download url hosts: "; grep -oE 'url = "https://[^/"]+' uv.lock | sort -u | tr '\n' ' '; echo ""
  echo ""
  echo "  sample wheel entry:"; grep -oE 'url = "https://[^"]+"' uv.lock | head -1 | sed 's/^/    /'
else
  echo "uv lock FAILED"; head -8 /tmp/d.log
fi
