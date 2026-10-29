#!/usr/bin/env bash

# Sincroniza los metadatos de empaquetado de un repo -arch con su fuente
# (spec despliegue-duo-arch-por-commit, ticket 4: PR + automerge en CI
# verde). El write-set es exactamente {PKGBUILD, .SRCINFO, checksum del
# tarball cuando no es SKIP}: el wrapper vendido es propiedad del -arch y
# este script jamas lo lee ni lo escribe; el launcher real viaja en el
# tarball y llega a los usuarios con el siguiente build del paquete.
#
# Uso:
#   sync-arch.sh sync   # drift -> update metadata -> branch -> PR -> merge en CI verde
#   sync-arch.sh ship   # el arbol de trabajo ya trae los cambios (cron de shared_dir-arch)
#
# Entorno:
#   TARGET_REPO         owner/name del repo -arch (requerido)
#   ARCH_DIR            checkout del -arch con credenciales de push (default: .)
#   TIMEOUT_SECONDS     techo de espera del CI del PR (default 900)
#   POLL_SECONDS        intervalo de sondeo del CI (default 15)
#   NO_CI_GRACE_SECONDS segundos sin runs antes de declarar "sin CI" (default 240)

set -Eeuo pipefail

readonly TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
readonly POLL_SECONDS="${POLL_SECONDS:-15}"
readonly NO_CI_GRACE_SECONDS="${NO_CI_GRACE_SECONDS:-240}"

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" > /dev/null 2>&1 || die "$1 is required."
}

# --- lectura del PKGBUILD --------------------------------------------------

read_pkgbuild_value() { # read_pkgbuild_value <name> <file>
  awk -F= -v name="$1" '$1 == name { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' "$2"
}

# Devuelve el pkgver base tanto de pkgver=0.3.0 como de pkgver="${PKGVER:-0.2.0}".
read_pkgver_base() { # read_pkgver_base <file>
  local raw
  raw="$(read_pkgbuild_value pkgver "$1")"
  raw="${raw%\"}"
  raw="${raw#\"}"
  raw="${raw#*PKGVER:-}"
  raw="${raw%\}}"
  printf '%s\n' "$raw"
}

# Primer checksum del bloque sha256sums (la entrada del tarball).
read_tarball_checksum() { # read_tarball_checksum <file>
  awk -F "'" '
    /^sha256sums=\(/ { in_checksums = 1; next }
    in_checksums && /^\)/ { exit }
    in_checksums && NF >= 2 { print $2; exit }
  ' "$1"
}

# --- tags de la fuente -----------------------------------------------------

latest_source_version() { # latest_source_version <source_repo>
  local repo="$1" page chunk all tag
  all=""
  for page in 1 2 3; do
    chunk="$(gh api "repos/${repo}/tags?per_page=100&page=${page}" --jq '.[].name' 2>/dev/null || true)"
    all+="${chunk}"$'\n'
    if [[ "$(printf '%s\n' "$chunk" | grep -c . || true)" -lt 100 ]]; then
      break
    fi
  done
  tag="$(printf '%s\n' "$all" | grep -E '^v?[0-9]+([.][0-9]+)*$' | sort -V | tail -n 1 || true)"
  [[ -n $tag ]] || die "no stable version tag found in ${repo}."
  printf '%s\n' "${tag#v}"
}

# 0 si la candidate es mayor que current; 1 si igual o menor (nunca downgrade).
version_ahead() { # version_ahead <candidate> <current>
  [[ "$1" == "$2" ]] && return 1
  local lowest
  lowest="$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)"
  [[ "$lowest" == "$2" ]]
}

# --- escritura del write-set ------------------------------------------------

apply_metadata() { # apply_metadata <dir> <version>
  local dir="$1" version="$2" pkgbuild srcinfo current_rel checksum
  pkgbuild="${dir}/PKGBUILD"
  srcinfo="${dir}/.SRCINFO"
  [[ -f $pkgbuild ]] || die "missing PKGBUILD in ${dir}."
  [[ -f $srcinfo ]] || die "missing .SRCINFO in ${dir}."

  current_rel="$(read_pkgbuild_value pkgrel "$pkgbuild")"
  [[ $current_rel =~ ^[0-9]+$ ]] || die 'PKGBUILD pkgrel is not a number.'
  checksum="$(read_tarball_checksum "$pkgbuild")"

  # pkgver y pkgrel (un cambio de version reinicia pkgrel a 1).
  if grep -q 'PKGVER:-' "$pkgbuild"; then
    sed -Ei "s|^pkgver=.*|pkgver=\"\${PKGVER:-${version}}\"|" "$pkgbuild"
  else
    sed -Ei "s|^pkgver=.*|pkgver=${version}|" "$pkgbuild"
  fi
  sed -Ei "s/^pkgrel=.*/pkgrel=1/" "$pkgbuild"
  sed -Ei "s/^[[:space:]]*pkgver = .*/\tpkgver = ${version}/" "$srcinfo"
  sed -Ei "s/^[[:space:]]*pkgrel = .*/\tpkgrel = 1/" "$srcinfo"

  # Checksum del tarball solo donde el PKGBUILD no usa SKIP.
  if [[ $checksum != 'SKIP' ]]; then
    local pkg_url archive sha
    pkg_url="$(read_pkgbuild_value url "$pkgbuild")"
    pkg_url="${pkg_url%\'}"
    pkg_url="${pkg_url#\'}"
    [[ -n $pkg_url ]] || die 'PKGBUILD has no url to download the tag archive from.'
    archive="$(mktemp "${TMPDIR:-/tmp}/sync-arch-archive.XXXXXX")"
    curl --fail --location --silent --show-error --retry 3 --retry-delay 2 \
      "${pkg_url}/archive/refs/tags/v${version}.tar.gz" --output "$archive"
    sha="$(sha256sum "$archive" | awk '{print $1}')"
    rm -f "$archive"
    [[ $sha =~ ^[[:xdigit:]]{64}$ ]] || die 'failed to compute the tag archive checksum.'
    sed -Ei "/^sha256sums=\(/,/^\)/{0,/^[[:space:]]*'[^']*'[[:space:]]*$/{s//  '${sha}'/}}" "$pkgbuild"
    sed -Ei "0,/^[[:space:]]*sha256sums = /s//\tsha256sums = ${sha}/" "$srcinfo"
  fi

  [[ "$(read_pkgver_base "$pkgbuild")" == "$version" ]] \
    || die 'failed to update pkgver in PKGBUILD.'
  [[ "$(read_pkgbuild_value pkgrel "$pkgbuild")" == '1' ]] \
    || die 'failed to reset pkgrel in PKGBUILD.'
  [[ "$(awk -F= '/^[[:space:]]*pkgver = /{gsub(/ /, "", $2); print $2; exit}' "$srcinfo")" == "$version" ]] \
    || die 'failed to update pkgver in .SRCINFO.'
}

# --- ship: rama, PR, CI verde, merge -----------------------------------------

pr_body() { # pr_body <dir> <source_repo>
  local pkgbuild="$1/PKGBUILD" srcinfo="$1/.SRCINFO"
  cat <<BODY
## Summary

Sincroniza los metadatos de empaquetado con la fuente (${2}): pkgver
$(read_pkgver_base "$pkgbuild") y, donde el PKGBUILD no usa SKIP, el checksum
del tarball. El wrapper vendido no se toca: es propiedad del -arch y su
entrada en sha256sums queda intacta; el launcher real viaja en el tarball y
llega a los usuarios con el siguiente build del paquete.

## Evidence

- PKGBUILD: pkgver -> $(read_pkgver_base "$pkgbuild"), pkgrel -> $(read_pkgbuild_value pkgrel "$pkgbuild").
- sha256sums[0] (tarball): $(read_tarball_checksum "$pkgbuild").
- .SRCINFO actualizado en las mismas entradas (pkgver, pkgrel y checksum).

## Merge Danger

- El merge es automatico y solo ocurre con el CI del PR en verde; con CI
  rojo (o sin CI) el PR queda abierto sin merge.
BODY
}

wait_and_merge() { # wait_and_merge <repo> <pr_number>
  local head_sha
  head_sha="$(gh pr view "$2" -R "$1" --json headRefOid --jq .headRefOid)"
  wait_and_merge_sha "$1" "$head_sha"
}

# Solo mergea con todos los runs del head sha en verde; con CI rojo o sin CI
# no mergea nunca (el PR queda abierto).
wait_and_merge_sha() { # wait_and_merge_sha <repo> <head_sha>
  local repo="$1" sha="$2" waited=0 flags total pending failed
  while :; do
    flags="$(gh api "repos/${repo}/actions/runs?head_sha=${sha}" \
      --jq '"total " + (.workflow_runs | length | tostring), "pending " + ([.workflow_runs[] | select(.status != "completed")] | length | tostring), "failed " + ([.workflow_runs[] | select(.status == "completed" and .conclusion != "success")] | length | tostring)' 2>/dev/null || printf 'total 0\npending 0\nfailed 0\n')"
    total="$(printf '%s\n' "$flags" | awk '$1 == "total" {print $2}')"
    pending="$(printf '%s\n' "$flags" | awk '$1 == "pending" {print $2}')"
    failed="$(printf '%s\n' "$flags" | awk '$1 == "failed" {print $2}')"
    [[ $total =~ ^[0-9]+$ && $pending =~ ^[0-9]+$ && $failed =~ ^[0-9]+$ ]] \
      || die 'respuesta ilegible de la API de runs.'
    if (( failed > 0 )); then
      die 'CI rojo en el head del PR: no se mergea.'
    fi
    if (( total > 0 && pending == 0 )); then
      printf 'CI verde en %s: merge.\n' "${sha:0:7}"
      gh pr merge "$(open_pr_for_sha "$repo" "$sha")" -R "$repo" --squash
      return 0
    fi
    if (( total == 0 && waited >= NO_CI_GRACE_SECONDS )); then
      die "sin runs de CI para ${sha:0:7}: no se mergea sin CI verde."
    fi
    if (( waited >= TIMEOUT_SECONDS )); then
      printf 'espera agotada: el PR queda abierto para merge manual.\n'
      return 0
    fi
    sleep "$POLL_SECONDS"
    (( waited += (POLL_SECONDS > 0 ? POLL_SECONDS : 1) ))
  done
}

open_pr_for_sha() { # open_pr_for_sha <repo> <head_sha>
  local num
  num="$(gh pr list -R "$1" --state open --json number,headRefOid \
    --jq ".[] | select(.headRefOid == \"$2\") | .number" | head -n 1)"
  [[ -n $num ]] || die "no open PR found for head ${2:0:7}."
  printf '%s\n' "$num"
}

ship() { # ship <dir> <target_repo>
  local dir="$1" repo="$2"
  local default_branch branch title existing pr_url
  cd "$dir"
  default_branch="$(gh api "repos/${repo}" --jq .default_branch)"
  title="$(expected_title "$dir")"

  # Un PR abierto con el mismo titulo ya cubre este estado: no duplicar.
  existing="$(gh pr list -R "$repo" --state open --json number,title \
    --jq ".[] | select(.title == \"${title//\"/}\") | .number" 2>/dev/null || true)"
  if [[ -n $existing ]]; then
    printf 'PR #%s ya cubre %s; no duplico.\n' "$existing" "$title"
    wait_and_merge "$repo" "$existing"
    return 0
  fi

  if git diff --quiet -- PKGBUILD .SRCINFO && git diff --cached --quiet -- PKGBUILD .SRCINFO; then
    printf 'nada que sincronizar: el -arch ya esta al dia.\n'
    return 0
  fi

  branch="sync/metadata-v$(read_pkgver_base "$dir/PKGBUILD")"
  if git ls-remote --heads origin "$branch" | grep -q .; then
    branch="${branch}-$(date +%s)"
  fi
  git checkout -b "$branch"
  git add PKGBUILD .SRCINFO
  git commit -m "chore: sync package metadata to v$(read_pkgver_base "$dir/PKGBUILD")"
  git push origin "HEAD:refs/heads/${branch}"

  pr_url="$(gh pr create -R "$repo" --base "$default_branch" --head "$branch" \
    --title "$title" --body "$(pr_body "$dir" "${SOURCE_REPO:-${repo%-arch}}")")"
  printf 'PR abierto: %s\n' "$pr_url"
  wait_and_merge "$repo" "$(gh pr view --json number --jq .number 2>/dev/null || true)"
}

expected_title() { # expected_title <dir>
  local pkg
  pkg="$(read_pkgbuild_value pkgname "$1/PKGBUILD")"
  printf 'sync: %s metadata to v%s\n' "$pkg" "$(read_pkgver_base "$1/PKGBUILD")"
}

# --- entrada -----------------------------------------------------------------

main() {
  local mode="${1:-}"
  require_command git
  require_command gh
  [[ -n ${TARGET_REPO:-} ]] || die 'TARGET_REPO is required.'
  [[ $mode == sync || $mode == ship ]] || die 'usage: sync-arch.sh sync|ship'
  local dir="${ARCH_DIR:-.}"
  local source_repo="${SOURCE_REPO:-${TARGET_REPO%-arch}}"

  if [[ $mode == sync ]]; then
    local version current
    version="$(latest_source_version "$source_repo")"
    current="$(read_pkgver_base "${dir}/PKGBUILD")"
    if ! version_ahead "$version" "$current"; then
      printf 'sin drift: el -arch ya apunta a v%s.\n' "$current"
      return 0
    fi
    apply_metadata "$dir" "$version"
  fi

  ship "$dir" "$TARGET_REPO"
}

main "$@"
