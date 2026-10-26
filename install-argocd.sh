#!/usr/bin/env bash
#
# install-argocd.sh — Install & bootstrap ArgoCD on a local/home Kubernetes cluster.
#
# FOR HOME LAB / PRACTICE USE ONLY — it exposes ArgoCD via NodePort with
# insecure TLS verification for the CLI login. Do not use as-is in production.
#
# Steps performed:
#   1.  Pre-flight checks (kubectl, cluster reachability, curl)
#   2.  Create the argocd namespace
#   3.  Apply the official stable install manifests
#   4.  Wait until every ArgoCD pod is Running/Ready
#   5.  Install the argocd CLI (if missing)
#   6.  Patch argocd-server to a NodePort service (30080 / 30081)
#   7.  Wait for the argocd-server rollout to finish
#   8.  Read the auto-generated initial admin password and show it
#   9.  Log in with the CLI (host/port asked interactively)
#  10.  Change the admin password
#  11.  Delete the initial admin secret
#
# Usage:
#   chmod +x install-argocd.sh
#   ./install-argocd.sh                 # full interactive run
#   ./install-argocd.sh --yes           # no confirmation prompts
#   ./install-argocd.sh --skip-cli      # don't install the argocd CLI
#   ./install-argocd.sh --no-login      # stop after printing the password
#   ./install-argocd.sh --keep-secret   # keep argocd-initial-admin-secret
#   ./install-argocd.sh --timeout 900   # pod wait timeout in seconds
#
set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Configuration (override via environment variables)
# ----------------------------------------------------------------------------
NAMESPACE="${NAMESPACE:-argocd}"
MANIFEST_URL="${MANIFEST_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
CLI_URL="${CLI_URL:-https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64}"
CLI_INSTALL_DIR="${CLI_INSTALL_DIR:-/usr/local/bin}"
HTTP_NODEPORT="${HTTP_NODEPORT:-30080}"
HTTPS_NODEPORT="${HTTPS_NODEPORT:-30081}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600}"      # seconds to wait for pods / rollout

ASSUME_YES=false
SKIP_CLI=false
DO_LOGIN=true
DELETE_SECRET=true

# ----------------------------------------------------------------------------
# Pretty output helpers
# ----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; BLU=$'\033[34m'; RST=$'\033[0m'
else
  BOLD=""; RED=""; GRN=""; YLW=""; BLU=""; RST=""
fi

STEP=0
step()  { STEP=$((STEP + 1)); printf '\n%s==> [%d] %s%s\n' "$BOLD$BLU" "$STEP" "$*" "$RST"; }
info()  { printf '%s[i]%s %s\n'  "$BLU"  "$RST" "$*"; }
ok()    { printf '%s[✓]%s %s\n'  "$GRN"  "$RST" "$*"; }
warn()  { printf '%s[!]%s %s\n'  "$YLW"  "$RST" "$*" >&2; }
err()   { printf '%s[x]%s %s\n'  "$RED"  "$RST" "$*" >&2; }
die()   { err "$*"; exit 1; }

trap 'err "Failed at line $LINENO. Aborting."' ERR

confirm() {
  local prompt="$1"
  $ASSUME_YES && return 0
  local reply
  read -r -p "$(printf '%s[?]%s %s [Y/n] ' "$YLW" "$RST" "$prompt")" reply </dev/tty || reply=""
  [[ -z "$reply" || "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

ask() {  # ask <prompt> <default> -> echoes answer
  local prompt="$1" default="${2:-}" reply
  read -r -p "$(printf '%s[?]%s %s [%s]: ' "$YLW" "$RST" "$prompt" "$default")" reply </dev/tty || reply=""
  printf '%s' "${reply:-$default}"
}

need() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  need sudo && SUDO="sudo"
fi

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------
usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)      ASSUME_YES=true ;;
    --skip-cli)    SKIP_CLI=true ;;
    --no-login)    DO_LOGIN=false ;;
    --keep-secret) DELETE_SECRET=false ;;
    --namespace)   NAMESPACE="${2:?}"; shift ;;
    --timeout)     WAIT_TIMEOUT="${2:?}"; shift ;;
    -h|--help)     usage ;;
    *)             die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

# ----------------------------------------------------------------------------
# 1. Pre-flight checks
# ----------------------------------------------------------------------------
step "Pre-flight checks"
need kubectl || die "kubectl not found in PATH."
need curl    || die "curl not found in PATH."

kubectl cluster-info >/dev/null 2>&1 || die "Cannot reach a Kubernetes cluster. Check your kubeconfig/context."
ok "kubectl is available — current context: $(kubectl config current-context 2>/dev/null || echo 'unknown')"

confirm "Install ArgoCD into namespace '$NAMESPACE' on this cluster?" || die "Cancelled by user."

# ----------------------------------------------------------------------------
# 2. Namespace
# ----------------------------------------------------------------------------
step "Creating namespace '$NAMESPACE'"
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  ok "Namespace '$NAMESPACE' already exists — skipping."
else
  kubectl create namespace "$NAMESPACE"
  ok "Namespace created."
fi

# ----------------------------------------------------------------------------
# 3. Install manifests
# ----------------------------------------------------------------------------
step "Applying ArgoCD install manifests (stable)"
info "$MANIFEST_URL"
kubectl apply -n "$NAMESPACE" -f "$MANIFEST_URL"
ok "Manifests applied."

# ----------------------------------------------------------------------------
# 4. Wait for all pods to be Running/Ready
# ----------------------------------------------------------------------------
step "Waiting for all ArgoCD pods to be Running/Ready (timeout ${WAIT_TIMEOUT}s)"

# Give the controllers a moment to create the pods before we start waiting.
for _ in $(seq 1 30); do
  [[ -n "$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null)" ]] && break
  sleep 2
done

deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
while :; do
  total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  ready=$(kubectl get pods -n "$NAMESPACE" \
            -o 'jsonpath={range .items[*]}{.status.phase}{":"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' \
            2>/dev/null | grep -c '^Running:True$' || true)

  if [[ "$total" -gt 0 && "$ready" -eq "$total" ]]; then
    ok "All $total pods are Running and Ready."
    break
  fi

  if [[ "$(date +%s)" -ge "$deadline" ]]; then
    kubectl get pods -n "$NAMESPACE"
    die "Timed out waiting for pods ($ready/$total ready). Re-run with --timeout <seconds> or inspect with: kubectl describe pods -n $NAMESPACE"
  fi

  printf '\r    %s pods ready: %s/%s ...%s' "$YLW" "$ready" "${total:-0}" "$RST"
  sleep 5
done
printf '\n'
kubectl get pods -n "$NAMESPACE"

# ----------------------------------------------------------------------------
# 5. ArgoCD CLI
# ----------------------------------------------------------------------------
step "Installing the argocd CLI"
if $SKIP_CLI; then
  info "--skip-cli given — skipping CLI installation."
elif need argocd; then
  ok "argocd CLI already installed: $(argocd version --client --short 2>/dev/null || echo present)"
else
  tmp="$(mktemp -d)"
  info "Downloading $CLI_URL"
  curl -sSL -o "$tmp/argocd" "$CLI_URL"
  chmod +x "$tmp/argocd"
  $SUDO mv "$tmp/argocd" "$CLI_INSTALL_DIR/argocd"
  rm -rf "$tmp"
  ok "argocd CLI installed to $CLI_INSTALL_DIR/argocd"
fi

# ----------------------------------------------------------------------------
# 6. Expose argocd-server via NodePort
# ----------------------------------------------------------------------------
step "Patching service 'argocd-server' to NodePort ($HTTP_NODEPORT / $HTTPS_NODEPORT)"
kubectl patch svc argocd-server -n "$NAMESPACE" --type merge -p \
  "{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":8080,\"nodePort\":${HTTP_NODEPORT}},{\"name\":\"https\",\"port\":443,\"targetPort\":8080,\"nodePort\":${HTTPS_NODEPORT}}]}}"
ok "Service patched."
kubectl get svc argocd-server -n "$NAMESPACE"

# ----------------------------------------------------------------------------
# 7. Rollout status
# ----------------------------------------------------------------------------
step "Checking rollout status of argocd-server"
kubectl rollout status deployment/argocd-server -n "$NAMESPACE" --timeout="${WAIT_TIMEOUT}s"
ok "argocd-server rollout complete."

# ----------------------------------------------------------------------------
# 8. Initial admin password
# ----------------------------------------------------------------------------
step "Retrieving the initial admin password"
ADMIN_PASSWORD=""
for _ in $(seq 1 30); do
  ADMIN_PASSWORD="$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
                      -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  [[ -n "$ADMIN_PASSWORD" ]] && break
  sleep 2
done

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
[[ -z "$NODE_IP" ]] && NODE_IP="localhost"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  warn "Secret 'argocd-initial-admin-secret' not found — it may already have been deleted or the password changed."
else
  cat <<EOF

${BOLD}${GRN}===================== ArgoCD LOGIN DETAILS =====================${RST}
  ${BOLD}Username :${RST} admin
  ${BOLD}Password :${RST} ${BOLD}${YLW}${ADMIN_PASSWORD}${RST}

  ${BOLD}This is the password you use to log in to the ArgoCD Web UI.${RST}

  Web UI (NodePort, self-signed cert — accept the browser warning):
      https://${NODE_IP}:${HTTPS_NODEPORT}
      http://${NODE_IP}:${HTTP_NODEPORT}

  Or via port-forward:
      kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443
      then open https://localhost:8080
${BOLD}${GRN}================================================================${RST}

EOF
fi

# ----------------------------------------------------------------------------
# 9. CLI login
# ----------------------------------------------------------------------------
step "Logging in with the argocd CLI"
LOGGED_IN=false
if ! $DO_LOGIN; then
  info "--no-login given — skipping CLI login."
elif ! need argocd; then
  warn "argocd CLI not available — skipping login."
elif [[ -z "$ADMIN_PASSWORD" ]]; then
  warn "No initial password available — skipping automatic login."
else
  LOGIN_HOST="$(ask 'ArgoCD server host/IP to log in to' "$NODE_IP")"
  LOGIN_PORT="$(ask 'ArgoCD server port' "$HTTPS_NODEPORT")"
  info "Running: argocd login ${LOGIN_HOST}:${LOGIN_PORT} --username admin --password <hidden> --insecure"
  if argocd login "${LOGIN_HOST}:${LOGIN_PORT}" --username admin --password "$ADMIN_PASSWORD" --insecure; then
    LOGGED_IN=true
    ok "Logged in as admin."
  else
    warn "Login failed. If you used a port-forward, start it first:"
    warn "  kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:443"
    warn "then run: argocd login localhost:8080 --username admin --password '<password above>' --insecure"
  fi
fi

# ----------------------------------------------------------------------------
# 10. Change the admin password
# ----------------------------------------------------------------------------
step "Changing the admin password (best practice)"
PASSWORD_CHANGED=false
if $LOGGED_IN; then
  if confirm "Change the admin password now?"; then
    info "You will be prompted for the current password (the one shown above) and a new one."
    if argocd account update-password --current-password "$ADMIN_PASSWORD"; then
      PASSWORD_CHANGED=true
      ok "Admin password changed. Use your NEW password for the UI and CLI from now on."
    else
      warn "Password change failed — run 'argocd account update-password' manually."
    fi
  else
    info "Skipped. Run 'argocd account update-password' later."
  fi
else
  info "Not logged in — skipping. Run 'argocd account update-password' after logging in."
fi

# ----------------------------------------------------------------------------
# 11. Delete the initial admin secret
# ----------------------------------------------------------------------------
step "Removing the initial admin secret"
if ! $DELETE_SECRET; then
  info "--keep-secret given — leaving 'argocd-initial-admin-secret' in place."
elif ! kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  ok "Secret already absent."
elif ! $PASSWORD_CHANGED && ! confirm "Admin password was NOT changed. Delete the initial secret anyway?"; then
  warn "Keeping 'argocd-initial-admin-secret'. Delete it after changing the password:"
  warn "  kubectl -n $NAMESPACE delete secret argocd-initial-admin-secret"
else
  kubectl -n "$NAMESPACE" delete secret argocd-initial-admin-secret
  ok "Secret deleted."
fi

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
printf '\n%s%s ArgoCD setup complete %s\n' "$BOLD$GRN" "========================" "$RST"
cat <<EOF
  Namespace : ${NAMESPACE}
  Web UI    : https://${NODE_IP}:${HTTPS_NODEPORT}  (user: admin)
  Password  : $( $PASSWORD_CHANGED && echo "the NEW password you just set" || echo "the one printed above" )

  Handy commands:
    kubectl get pods -n ${NAMESPACE}
    kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443
    argocd app list
    argocd account update-password

  Uninstall:
    kubectl delete -n ${NAMESPACE} -f ${MANIFEST_URL}
    kubectl delete namespace ${NAMESPACE}
EOF
printf '%s%s%s\n' "$BOLD$GRN" "=================================================" "$RST"
