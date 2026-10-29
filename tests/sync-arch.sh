#!/usr/bin/env bash

# Suite del mecanismo de sync (spec despliegue-duo-arch-por-commit, ticket 4).
# Corre offline con stubs de gh y curl: fixtures de repos -arch con remote
# bare que graba los refs empujados. Invariantes:
#   - write-set exacto {PKGBUILD, .SRCINFO, checksum del tarball cuando no es SKIP}
#   - el wrapper vendido nunca se toca
#   - push solo a la rama del sync, nunca a la default
#   - merge solo con CI verde; rojo o sin CI, sin merge
# Mutaciones que deben morir en la suite:
#   - automerge con CI rojo
#   - PR que no actualiza el checksum del tarball
#   - push directo a la rama default

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="${ROOT_DIR}/.github/scripts/sync-arch.sh"
[[ -f $SYNC_SCRIPT ]] || { printf 'no encuentro %s\n' "$SYNC_SCRIPT" >&2; exit 1; }

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sync-arch-suite.XXXXXX")"
export TEST_ROOT
trap 'rm -rf "$TEST_ROOT"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail_test() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1" >&2; }

# --- stubs -------------------------------------------------------------------

STUB_BIN="${TEST_ROOT}/bin"
mkdir -p "$STUB_BIN"
GH_LOG="${TEST_ROOT}/gh.log"
: > "$GH_LOG"

setup_gh_stub() {
  cat > "${STUB_BIN}/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "${GH_LOG}"
cmd="$1"; shift || true
case "$cmd" in
  api)
    case "$*" in
      *"/tags"*) printf '%s\n' "$GH_TAGS" ;;
      *"--jq .default_branch"*) echo "master" ;;
      *"actions/runs"*) printf '%s\n' "$GH_RUNS_FLAGS" ;;
      *) echo "{}" ;;
    esac
    ;;
  pr)
    sub="$1"; shift || true
    case "$sub" in
      list)
        if [[ "$*" == *"title"* ]]; then printf '%s\n' "$GH_PR_LIST_NUMBERS"
        else printf '%s\n' "$GH_LIST_SHA_NUMBERS"; fi
        ;;
      create) echo "${GH_PR_CREATE_URL:-https://github.com/robert-flo/demo-arch/pull/9}" ;;
      view) echo "${GH_PR_VIEW_SHA:-deadbeefcafe}" ;;
      merge) echo "merged" ;;
    esac
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/gh"
}

setup_curl_stub() {
  cat > "${STUB_BIN}/curl" <<'STUB'
#!/usr/bin/env bash
out=""
prev=""
for arg in "$@"; do
  if [[ $prev == "--output" ]]; then out="$arg"; fi
  prev="$arg"
done
[[ -n $out ]] || exit 1
cp "${TEST_ROOT}/archive-body" "$out"
STUB
  chmod +x "${STUB_BIN}/curl"
}

# --- fixture de repo -arch ----------------------------------------------------

make_arch_fixture() { # make_arch_fixture <name> <skip_or_checksum>
  local name="$1" mode="$2"
  local dir="${TEST_ROOT}/${name}"
  mkdir -p "$dir"
  local pkgname="demo-${name}"
  local tarball_entry='SKIP'
  if [[ $mode != skip ]]; then tarball_entry='0000000000000000000000000000000000000000000000000000000000000000'; fi
  cat > "${dir}/PKGBUILD" <<PKGBUILD
pkgname=${pkgname}
pkgver="\${PKGVER:-0.2.0}"
pkgrel=3
url='https://github.com/robert-flo/demo-source'
sha256sums=(
  '${tarball_entry}'
  'e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150'
)
PKGBUILD
  cat > "${dir}/.SRCINFO" <<SRCINFO
pkgbase = ${pkgname}
\tpkgver = 0.2.0
\tpkgrel = 3
\tsha256sums = ${tarball_entry}
\tsha256sums = e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150
SRCINFO
  printf '#!/usr/bin/env bash\nexec /opt/%s/%s "$@"\n' "$pkgname" "$pkgname" > "${dir}/${pkgname}"
  git -C "$dir" init -q -b master
  git -C "$dir" config user.name "Roberto Flores"
  git -C "$dir" config user.email "25asab015@ujmd.edu.sv"
  git -C "$dir" add -A
  git -C "$dir" commit -qm "init"
  git init -q --bare "${dir}.remote"
  cat > "${dir}.remote/hooks/post-receive" <<HOOK
#!/usr/bin/env bash
while read -r _old _new ref; do printf '%s\n' "\$ref" >> "${dir}.remote/pushed-refs.log"; done
HOOK
  chmod +x "${dir}.remote/hooks/post-receive"
  git -C "$dir" remote add origin "${dir}.remote"
  printf '%s' "$dir"
}

# --- corrida del script --------------------------------------------------------

run_sync() { # run_sync <arch_dir> (usa las variables GH_* exportadas)
  : > "$GH_LOG"
  env PATH="${STUB_BIN}:$PATH" GH_LOG="$GH_LOG" \
    TARGET_REPO="robert-flo/demo-arch" SOURCE_REPO="robert-flo/demo-source" \
    ARCH_DIR="$1" TIMEOUT_SECONDS="${TIMEOUT_SECONDS_OVERRIDE:-5}" \
    POLL_SECONDS="${POLL_SECONDS_OVERRIDE:-0}" \
    NO_CI_GRACE_SECONDS="${NO_CI_GRACE_OVERRIDE:-0}" \
    bash "$SYNC_SCRIPT" sync
}

runs_flags() { # runs_flags <total> <pending> <failed> (formato del --jq del script)
  printf 'total %s\npending %s\nfailed %s\n' "$1" "$2" "$3"
}

merge_called() {
  grep -q ' pr merge ' "$GH_LOG"
}

pushed_refs() {
  cat "$1.remote/pushed-refs.log" 2>/dev/null || true
}

# --- casos ----------------------------------------------------------------------

case_skip_fixture_updates_metadata_without_touching_wrapper() {
  local dir
  dir="$(make_arch_fixture skip-repo skip)"
  setup_curl_stub
  export GH_TAGS="v0.3.0" GH_PR_LIST_NUMBERS="" GH_LIST_SHA_NUMBERS="9" GH_PR_VIEW_SHA="deadbeefcafe"
  GH_RUNS_FLAGS="$(runs_flags 1 0 0)"
  export GH_RUNS_FLAGS
  run_sync "$dir" > /dev/null || { fail_test "el sync fallo en el fixture SKIP"; return 0; }
  # shellcheck disable=SC2016 # patron literal que el test busca
  if grep -q 'pkgver="\${PKGVER:-0.3.0}"' "${dir}/PKGBUILD"; then
    ok "pkgver base a 0.3.0 conservando PKGVER:-"
  else
    fail_test "pkgver base no actualizado"
  fi
  if grep -q '^pkgrel=1$' "${dir}/PKGBUILD"; then
    ok "pkgrel reiniciado a 1"
  else
    fail_test "pkgrel no reiniciado"
  fi
  if grep -q "sha256sums = SKIP" "${dir}/.SRCINFO"; then
    ok "SKIP intacto en .SRCINFO"
  else
    fail_test "SKIP tocado"
  fi
  if grep -q 'e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150' "${dir}/PKGBUILD"; then
    ok "checksum del wrapper intacto en PKGBUILD"
  else
    fail_test "checksum del wrapper tocado"
  fi
  if grep -q "sha256sums = e1940018" "${dir}/.SRCINFO"; then
    ok "checksum del wrapper intacto en .SRCINFO"
  else
    fail_test "checksum del wrapper tocado en .SRCINFO"
  fi
  if [[ "$(cat "${dir}/demo-skip-repo")" == $'#!/usr/bin/env bash\nexec /opt/demo-skip-repo/demo-skip-repo "$@"' ]]; then
    ok "el archivo vendido no se toca"
  else
    fail_test "el archivo vendido fue modificado"
  fi
  if [[ "$(pushed_refs "$dir")" == *"refs/heads/sync/metadata-v0.3.0"* ]]; then
    ok "push a la rama del sync"
  else
    fail_test "no se empujo la rama del sync"
  fi
  if ! grep -qE 'refs/heads/master$' < <(pushed_refs "$dir"); then
    ok "nunca se empujo la default"
  else
    fail_test "se empujo la default"
  fi
  if merge_called; then
    ok "merge con CI verde"
  else
    fail_test "no hubo merge con CI verde"
  fi
}

case_checksum_fixture_updates_tarball_checksum() {
  local dir new_sha
  dir="$(make_arch_fixture checksum-repo checksum)"
  printf 'contenido del archive v0.3.0' > "${TEST_ROOT}/archive-body"
  new_sha="$(sha256sum "${TEST_ROOT}/archive-body" | awk '{print $1}')"
  setup_curl_stub
  export GH_TAGS="v0.3.0" GH_PR_LIST_NUMBERS="" GH_LIST_SHA_NUMBERS="9" GH_PR_VIEW_SHA="deadbeefcafe"
  GH_RUNS_FLAGS="$(runs_flags 1 0 0)"
  export GH_RUNS_FLAGS
  run_sync "$dir" > /dev/null || { fail_test "el sync fallo en el fixture con checksum"; return 0; }
  if grep -q "'${new_sha}'" "${dir}/PKGBUILD"; then
    ok "checksum del tarball actualizado"
  else
    fail_test "checksum del tarball no actualizado"
  fi
  if grep -q 'e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150' "${dir}/PKGBUILD"; then
    ok "checksum del wrapper intacto"
  else
    fail_test "checksum del wrapper tocado"
  fi
  if grep -q "sha256sums = ${new_sha}" "${dir}/.SRCINFO"; then
    ok "checksum actualizado en .SRCINFO"
  else
    fail_test "checksum no actualizado en .SRCINFO"
  fi
  if grep -q "sha256sums = e1940018" "${dir}/.SRCINFO"; then
    ok "checksum del wrapper intacto en .SRCINFO"
  else
    fail_test "checksum del wrapper tocado en .SRCINFO"
  fi
}

case_no_drift_opens_nothing() {
  local dir
  dir="$(make_arch_fixture no-drift skip)"
  setup_curl_stub
  export GH_TAGS="v0.2.0" GH_PR_LIST_NUMBERS="" GH_LIST_SHA_NUMBERS="9" GH_PR_VIEW_SHA="deadbeefcafe"
  GH_RUNS_FLAGS="$(runs_flags 1 0 0)"
  export GH_RUNS_FLAGS
  run_sync "$dir" > /dev/null || { fail_test "el sync fallo sin drift"; return 0; }
  if [[ -z "$(pushed_refs "$dir")" ]]; then
    ok "sin drift: nada empujado"
  else
    fail_test "sin drift pero se empujo"
  fi
  if ! merge_called; then
    ok "sin drift: sin merge"
  else
    fail_test "sin drift pero se mergeo"
  fi
}

case_red_ci_never_merges() {
  local dir
  dir="$(make_arch_fixture red-ci skip)"
  setup_curl_stub
  export GH_TAGS="v0.3.0" GH_PR_LIST_NUMBERS="" GH_LIST_SHA_NUMBERS="9" GH_PR_VIEW_SHA="deadbeefcafe"
  GH_RUNS_FLAGS="$(runs_flags 1 0 1)"
  export GH_RUNS_FLAGS
  if run_sync "$dir" > /dev/null 2>&1; then
    fail_test "con CI rojo el script debio fallar"
    return 0
  fi
  if ! merge_called; then
    ok "con CI rojo no se mergeo"
  else
    fail_test "se mergeo con CI rojo"
  fi
}

case_no_ci_never_merges() {
  local dir
  dir="$(make_arch_fixture no-ci skip)"
  setup_curl_stub
  export GH_TAGS="v0.3.0" GH_PR_LIST_NUMBERS="" GH_LIST_SHA_NUMBERS="9" GH_PR_VIEW_SHA="deadbeefcafe"
  GH_RUNS_FLAGS="$(runs_flags 0 0 0)"
  export GH_RUNS_FLAGS
  if run_sync "$dir" > /dev/null 2>&1; then
    fail_test "sin CI el script debio fallar"
    return 0
  fi
  if ! merge_called; then
    ok "sin CI no se mergeo"
  else
    fail_test "se mergeo sin CI"
  fi
}

case_pending_ci_times_out_without_merge() {
  local dir
  dir="$(make_arch_fixture pending skip)"
  setup_curl_stub
  export GH_TAGS="v0.3.0" GH_PR_LIST_NUMBERS="" GH_LIST_SHA_NUMBERS="9" GH_PR_VIEW_SHA="deadbeefcafe"
  GH_RUNS_FLAGS="$(runs_flags 1 1 0)"
  export GH_RUNS_FLAGS
  run_sync "$dir" > /dev/null 2>&1 \
    || { fail_test "con CI pendiente el run debio salir 0 (el PR queda abierto)"; return 0; }
  if ! merge_called; then
    ok "CI pendiente: sin merge, PR queda abierto"
  else
    fail_test "se mergeo con CI pendiente"
  fi
}

case_duplicate_title_is_reused() {
  local dir
  dir="$(make_arch_fixture dup skip)"
  setup_curl_stub
  export GH_TAGS="v0.3.0" GH_PR_VIEW_SHA="aaa" GH_PR_LIST_NUMBERS="7" GH_LIST_SHA_NUMBERS="7"
  GH_RUNS_FLAGS="$(runs_flags 1 0 0)"
  export GH_RUNS_FLAGS
  run_sync "$dir" > /dev/null || { fail_test "el sync fallo en la reutilizacion de PR"; return 0; }
  if grep -q ' pr create ' "$GH_LOG"; then
    fail_test "duplico el PR con uno abierto del mismo titulo"
  else
    ok "PR duplicado reutilizado"
  fi
  if merge_called; then
    ok "merge sobre el PR ya abierto"
  else
    fail_test "no se mergeo el PR reutilizado"
  fi
}

# --- mutaciones ------------------------------------------------------------------
# Cada mutacion reproduce el comportamiento prohibido; si la corrida mutada NO
# lo produce, la mutacion no se activo y el guard no esta cubierto.

mutate() { # mutate <src> <dst> <old_literal> <new_literal>
  awk -v old="$3" -v new="$4" '
    { while ((i = index($0, old)) > 0) $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); print }
  ' "$1" > "$2"
}

run_mutation() { # run_mutation <nombre> <old_literal> <new_literal> <fixture> <mode> <flags_failed> <assertion>
  local name="$1" old="$2" new="$3" fixture="$4" mode="$5" flags_failed="$6" assertion="$7"
  local dir mutated
  dir="$(make_arch_fixture "$fixture" "$mode")"
  mutated="${TEST_ROOT}/mutated-${name}.sh"
  mutate "$SYNC_SCRIPT" "$mutated" "$old" "$new"
  setup_curl_stub
  if [[ $mode == checksum ]]; then
    printf 'contenido del archive v0.3.0' > "${TEST_ROOT}/archive-body"
  fi
  export GH_TAGS="v0.3.0" GH_PR_LIST_NUMBERS="" GH_LIST_SHA_NUMBERS="9" GH_PR_VIEW_SHA="deadbeefcafe"
  : > "$GH_LOG"
  GH_RUNS_FLAGS="$(runs_flags 1 0 "$flags_failed")"
  export GH_RUNS_FLAGS
  env PATH="${STUB_BIN}:$PATH" GH_LOG="$GH_LOG" \
    TARGET_REPO="robert-flo/demo-arch" SOURCE_REPO="robert-flo/demo-source" \
    ARCH_DIR="$dir" TIMEOUT_SECONDS=5 POLL_SECONDS=0 NO_CI_GRACE_SECONDS=0 \
    bash "$mutated" sync \
    > /dev/null 2>&1 || { fail_test "mutacion ${name}: el script fallo en vez de ejecutarse"; return 0; }
  if eval "$assertion"; then
    ok "mutacion ${name}: el guard la detecta"
  else
    fail_test "mutacion ${name}: el guard no la cubre"
  fi
}

mutation_red_automerge() {
  # Con el gate de CI rojo desactivado, el script mergea igual.
  run_mutation red-automerge 'if (( failed > 0 )); then' 'if false; then' \
    mut-red skip 1 'merge_called'
}

mutation_checksum_not_updated() {
  # Saltandose el reemplazo del checksum, el PKGBUILD conserva el viejo.
  run_mutation checksum-skipped "'\${sha}'" "'\${checksum}'" \
    mut-check checksum 0 "grep -q '0000000000000000000000000000000000000000000000000000000000000000' '${TEST_ROOT}/mut-check/PKGBUILD'"
}

mutation_push_to_default() {
  # Empujando HEAD a master en vez de a la rama del sync.
  # shellcheck disable=SC2016 # literal del push que la mutacion reemplaza
  run_mutation push-default 'HEAD:refs/heads/${branch}' 'HEAD:refs/heads/master' \
    mut-push skip 0 "grep -qE 'refs/heads/master\$' < <(pushed_refs '${TEST_ROOT}/mut-push')"
}

main() {
  setup_gh_stub
  case_skip_fixture_updates_metadata_without_touching_wrapper
  case_checksum_fixture_updates_tarball_checksum
  case_no_drift_opens_nothing
  case_red_ci_never_merges
  case_no_ci_never_merges
  case_pending_ci_times_out_without_merge
  case_duplicate_title_is_reused
  mutation_red_automerge
  mutation_checksum_not_updated
  mutation_push_to_default
  printf '%d ok, %d fail\n' "$PASS" "$FAIL"
  (( FAIL == 0 ))
}

main "$@"
