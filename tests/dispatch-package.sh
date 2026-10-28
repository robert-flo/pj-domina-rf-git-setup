#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-package-test.XXXXXX")"
TEST_BIN="$TEST_ROOT/bin"
export STUB_DIR="$TEST_ROOT/stub"

trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

WORKFLOW="$ROOT_DIR/.github/workflows/dispatch-package.yml"
CI_WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"
SOURCE_REPO="robert-flo/pj-domina-rf-git-setup"

# El disparo vigila el CI existente por su nombre (leído de ci.yml, no
# copiado) y el job filtra conclusion success.
if ! grep -q '^on:' "$WORKFLOW" || ! grep -q 'workflow_run:' "$WORKFLOW"; then
  fail 'the workflow must trigger on workflow_run'
fi
ci_name="$(sed -nE 's/^name: +(.+)$/\1/p' "$CI_WORKFLOW")"
grep -qF -- "- ${ci_name}" "$WORKFLOW" || \
  fail "the workflow_run trigger must watch the CI workflow '${ci_name}'"
grep -qF "github.event.workflow_run.conclusion == 'success'" "$WORKFLOW" || \
  fail 'the job must require a successful CI conclusion'
grep -qF 'secrets.ARCH_DISPATCH_TOKEN' "$WORKFLOW" || \
  fail 'the dispatch token must come from the ARCH_DISPATCH_TOKEN secret'

# El cuerpo del paso es la única lógica ejecutable: se extrae del bloque
# `run: |` (última clave del archivo) y se prueba en modo dry-run con un gh
# de mentira que registra las llamadas.
script="$TEST_ROOT/dispatch-package.sh"
awk '
  found {
    if ($0 ~ /^ {10}/) { sub(/^ {10}/, ""); print; next }
    if ($0 ~ /^[[:space:]]*$/) { next }
    exit
  }
  /^        run: \|$/ { found=1 }
' "$WORKFLOW" > "$script"
[[ -s "$script" ]] || fail 'could not extract the run script from the workflow'
bash -n "$script" || fail 'the extracted run script is not valid bash'

mkdir -p "$TEST_BIN" "$STUB_DIR"
cat > "$TEST_BIN/gh" <<'STUB'
#!/bin/bash
[[ -n ${STUB_DIR:-} ]] || { echo 'STUB_DIR no exportado' >&2; exit 1; }
printf '%s\n' "$*" >>"$STUB_DIR/gh-calls"
for arg in "$@"; do
  case "$arg" in
    --jq) want_branch=1 ;;
  esac
done
if [[ ${want_branch:-0} == 1 ]]; then
  printf '%s\n' "$DEFAULT_BRANCH"
fi
exit 0
STUB
chmod +x "$TEST_BIN/gh"
export DEFAULT_BRANCH="master"

run_dispatch() { # run_dispatch <conclusion> <head_branch> <head_sha>
  : > "$STUB_DIR/gh-calls"
  # Aislado: el PATH del script contiene SOLO el gh de mentira, ninguna
  # llamada puede llegar al gh real ni a la red.
  PATH="$TEST_BIN" \
  DEFAULT_BRANCH="$DEFAULT_BRANCH" \
  GITHUB_REPOSITORY="$SOURCE_REPO" \
  WF_CONCLUSION="$1" WF_HEAD_BRANCH="$2" WF_HEAD_SHA="$3" \
    /bin/bash "$script" >"$TEST_ROOT/out" 2>&1
}

dispatch_calls() {
  grep -F 'dispatches' "$STUB_DIR/gh-calls" || true
}

# CI verde en la rama default (master): un solo dispatch con payload completo.
run_dispatch success master 1111111111111111111111111111111111111111
[[ "$(dispatch_calls | wc -l)" -eq 1 ]] || fail 'green CI on the default branch must dispatch exactly once'
dispatch_line="$(dispatch_calls)"
grep -qF "repos/${SOURCE_REPO}-arch/dispatches" <<<"$dispatch_line" || \
  fail "the dispatch must target the -arch duo: $dispatch_line"
grep -qF 'event_type=source-updated' <<<"$dispatch_line" || \
  fail "the dispatch must use event_type source-updated: $dispatch_line"
grep -qF "client_payload[repo]=${SOURCE_REPO}" <<<"$dispatch_line" || \
  fail "the payload must carry the source repo: $dispatch_line"
grep -qF 'client_payload[sha]=1111111111111111111111111111111111111111' <<<"$dispatch_line" || \
  fail "the payload must carry the head sha: $dispatch_line"
grep -qF "repos/${SOURCE_REPO} --jq .default_branch" "$STUB_DIR/gh-calls" || \
  fail 'the default branch must be resolved from the source repo via API'

# CI rojo: nada. Y rama no default: nada (aunque el CI esté verde).
run_dispatch failure master 2222222222222222222222222222222222222222
[[ -z "$(dispatch_calls)" ]] || fail 'a failed CI run must not dispatch'
run_dispatch success fo/otra-rama 3333333333333333333333333333333333333333
[[ -z "$(dispatch_calls)" ]] || fail 'a non-default branch must not dispatch'

# Sin hardcodeo: si la default fuera otra (main), la rama main despacha.
DEFAULT_BRANCH=main run_dispatch success main 4444444444444444444444444444444444444444
[[ "$(dispatch_calls | wc -l)" -eq 1 ]] || fail 'the watched branch must follow the API default, not a hardcoded name'

echo "ok dispatch-package"
