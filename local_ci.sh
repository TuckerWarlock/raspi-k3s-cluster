#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# local_ci.sh — mirrors .github/workflows/helm-validate.yml locally
# Runs both jobs: kubeconform (Helm schema validation) + Pluto (API deprecation)
#
# Helm releases are discovered automatically from helmfile.yaml — add a new
# chart there and this script (and CI) will pick it up with no other changes.
# =============================================================================

KUBECONFORM_VERSION="v0.6.7"
PLUTO_VERSION="5.23.5"
HELMFILE_VERSION="v1.4.2"
K8S_TARGET_VERSION="v1.31.0"

# Resolve repo root regardless of where the script is called from
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${REPO_ROOT}/tmp"
HELMFILE_BIN=""
KUBECONFORM_BIN=""
PLUTO_BIN=""

# Ensure tmp/ is gitignored (safety net if .gitignore is ever missing)
if ! grep -qx 'tmp/' "${REPO_ROOT}/.gitignore" 2>/dev/null; then
  echo 'tmp/' >> "${REPO_ROOT}/.gitignore"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

step() { echo ""; echo "==> $*"; }
pass() { echo "    ✓ $*"; }
fail() { echo "    ✗ $*"; exit 1; }

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    armv7l)  arch="armv7" ;;
    *)       fail "Unsupported architecture: $arch" ;;
  esac
  echo "${os}_${arch}"
}

check_deps() {
  for cmd in curl tar helm; do
    command -v "$cmd" &>/dev/null || fail "'$cmd' not found — install it first"
  done
}

install_helmfile() {
  if [[ -n "$HELMFILE_BIN" && -x "$HELMFILE_BIN" ]]; then
    return
  fi

  step "Installing helmfile $HELMFILE_VERSION"

  if command -v brew &>/dev/null; then
    if brew list --versions helmfile &>/dev/null || brew install helmfile; then
      HELMFILE_BIN="$(command -v helmfile || true)"
      if [[ -n "$HELMFILE_BIN" && -x "$HELMFILE_BIN" ]]; then
        pass "helmfile $("$HELMFILE_BIN" version 2>&1 | head -1) (brew)"
        return
      fi
    fi
  fi

  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  [[ "$arch" == "x86_64" ]] && arch="amd64"
  [[ "$arch" == "arm64" || "$arch" == "aarch64" ]] && arch="arm64"
  curl -fsSL -o "$WORK_DIR/helmfile.tar.gz" \
    "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_${os}_${arch}.tar.gz"
  tar -xzf "$WORK_DIR/helmfile.tar.gz" -C "$WORK_DIR" helmfile
  HELMFILE_BIN="$WORK_DIR/helmfile"
  pass "helmfile $("$HELMFILE_BIN" version 2>&1 | head -1) (curl fallback)"
}

install_kubeconform() {
  if [[ -n "$KUBECONFORM_BIN" && -x "$KUBECONFORM_BIN" ]]; then
    return
  fi

  step "Installing kubeconform $KUBECONFORM_VERSION"

  if command -v brew &>/dev/null; then
    if brew list --versions kubeconform &>/dev/null || brew install kubeconform; then
      KUBECONFORM_BIN="$(command -v kubeconform || true)"
      if [[ -n "$KUBECONFORM_BIN" && -x "$KUBECONFORM_BIN" ]]; then
        pass "kubeconform $("$KUBECONFORM_BIN" -v 2>&1) (brew)"
        return
      fi
    fi
  fi

  local kubeconform_platform
  kubeconform_platform="${PLATFORM//_/-}"
  curl -fsSL -o "$WORK_DIR/kubeconform.tar.gz" \
    "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-${kubeconform_platform}.tar.gz"
  tar -xzf "$WORK_DIR/kubeconform.tar.gz" -C "$WORK_DIR" kubeconform
  KUBECONFORM_BIN="$WORK_DIR/kubeconform"
  pass "kubeconform $("$KUBECONFORM_BIN" -v 2>&1) (curl fallback)"
}

install_pluto() {
  if [[ -n "$PLUTO_BIN" && -x "$PLUTO_BIN" ]]; then
    return
  fi

  step "Installing Pluto $PLUTO_VERSION"

  if command -v brew &>/dev/null; then
    if brew list --versions pluto &>/dev/null || brew install pluto; then
      PLUTO_BIN="$(command -v pluto || true)"
      if [[ -n "$PLUTO_BIN" && -x "$PLUTO_BIN" ]]; then
        pass "Pluto $("$PLUTO_BIN" version 2>&1 | head -1) (brew)"
        return
      fi
    fi
  fi

  curl -fsSL -o "$WORK_DIR/pluto.tar.gz" \
    "https://github.com/FairwindsOps/pluto/releases/download/v${PLUTO_VERSION}/pluto_${PLUTO_VERSION}_${PLATFORM}.tar.gz"
  tar -xzf "$WORK_DIR/pluto.tar.gz" -C "$WORK_DIR" pluto
  PLUTO_BIN="$WORK_DIR/pluto"
  pass "Pluto $("$PLUTO_BIN" version 2>&1 | head -1) (curl fallback)"
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

step "Checking dependencies"
check_deps
pass "helm, curl, tar all present"

PLATFORM="$(detect_platform)"
step "Detected platform: $PLATFORM"

mkdir -p "$WORK_DIR"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Helmfile — renders all releases defined in helmfile.yaml
# ---------------------------------------------------------------------------

install_helmfile

step "Rendering all Helm releases via helmfile"
XDG_CACHE_HOME="$WORK_DIR/.cache" "$HELMFILE_BIN" template \
  > "$WORK_DIR/all-rendered.yaml"
test -s "$WORK_DIR/all-rendered.yaml" || fail "helmfile rendered empty output"
pass "All releases rendered to $WORK_DIR/all-rendered.yaml"

step "Linting all releases via helmfile"
XDG_CACHE_HOME="$WORK_DIR/.cache" "$HELMFILE_BIN" lint
pass "Lint passed"

# ---------------------------------------------------------------------------
# Job 1: kubeconform — schema validation
# ---------------------------------------------------------------------------

install_kubeconform

step "kubeconform: validating raw cluster manifests"
find cluster -type f \( -name "*.yaml" -o -name "*.yml" \) \
  ! -name "values.yaml" \
  ! -name "*-values.yaml" \
  -print > "$WORK_DIR/raw-manifest-files.txt"
test -s "$WORK_DIR/raw-manifest-files.txt" || fail "No raw manifests found"

xargs "$KUBECONFORM_BIN" \
  -strict \
  -summary \
  -ignore-missing-schemas \
  < "$WORK_DIR/raw-manifest-files.txt"
pass "Raw manifests passed"

step "kubeconform: validating rendered Helm manifests"
"$KUBECONFORM_BIN" \
  -strict \
  -summary \
  -ignore-missing-schemas \
  "$WORK_DIR/all-rendered.yaml"
pass "Rendered manifests passed"

# ---------------------------------------------------------------------------
# Job 2: Pluto — API deprecation check
# ---------------------------------------------------------------------------

install_pluto

step "Pluto: checking raw cluster manifests (target k8s $K8S_TARGET_VERSION)"
"$PLUTO_BIN" detect-files \
  --output wide \
  --target-versions "k8s=${K8S_TARGET_VERSION}" \
  -d cluster
pass "Raw manifests — no deprecated APIs"

step "Pluto: checking rendered Helm manifests"
"$PLUTO_BIN" detect-files \
  --output wide \
  --target-versions "k8s=${K8S_TARGET_VERSION}" \
  "$WORK_DIR/all-rendered.yaml"
pass "Rendered manifests — no deprecated APIs"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
echo "==> All checks passed — PR should be green"
