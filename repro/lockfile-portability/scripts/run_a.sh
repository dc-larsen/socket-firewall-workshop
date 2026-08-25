set -e
IDX="https://sfw.mercor.test/pypi/simple/"

mk() {
  rm -rf /work/$1
  mkdir -p /work/$1
  cd /work/$1
  printf '[project]\nname = "repro-%s"\nversion = "0.1.0"\nrequires-python = ">=3.12"\ndependencies = ["asn1crypto==1.5.1", "blinker==1.9.0"]\n' "$1" > pyproject.toml
}

report() {
  echo "--- $1 : uv.lock evidence ---"
  printf 'packages sourced from PROXY registry: '; grep -c 'registry = "https://sfw.mercor.test' uv.lock || true
  printf 'packages sourced from pypi.org      : '; grep -c 'registry = "https://pypi.org' uv.lock || true
  printf 'download urls on files.pythonhosted : '; grep -c 'url = "https://files.pythonhosted.org' uv.lock || true
  printf 'download urls on PROXY host         : '; grep -c 'url = "https://sfw.mercor.test' uv.lock || true
  printf 'pyproject.toml mentions tool.uv.index: '; grep -c 'tool.uv.index' pyproject.toml || true
  echo ""
}

# A1: index declared inside pyproject.toml (Kevin's Aug 20 config)
mk A1
printf '\n[[tool.uv.index]]\nname = "internal-proxy"\nurl = "%s"\ndefault = true\n' "$IDX" >> pyproject.toml
uv lock -q
report A1

# A2: nothing in pyproject.toml; index from UV_INDEX_URL env var (Aaron's Aug 4 case)
mk A2
UV_INDEX_URL="$IDX" uv lock -q
report A2

# A3: nothing in pyproject.toml; index in an external uv.toml (the fix I proposed in Slack)
mk A3
mkdir -p /work/A3cfg
printf '[[index]]\nurl = "%s"\ndefault = true\n' "$IDX" > /work/A3cfg/uv.toml
UV_CONFIG_FILE=/work/A3cfg/uv.toml uv lock -q
report A3
