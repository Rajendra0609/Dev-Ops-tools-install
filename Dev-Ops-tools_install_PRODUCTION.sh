#!/usr/bin/env bash
################################################################################
# PRODUCTION-GRADE DevOps Tools Installer v3.0 (Latest Versions)
# Updated: 2026-06-29
# Ubuntu/Debian focused installer with latest stable versions and fixed syntax
################################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
BACKUP_DIR="$SCRIPT_DIR/backups"
STATE_DB="$SCRIPT_DIR/.installation_state.db"
LOCK_FILE="/tmp/devops-installer.lock"
CACHE_DIR="/tmp/devops-installer-cache"

mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$CACHE_DIR"
LOG_FILE="$LOG_DIR/devops-installer-$(date +%Y%m%d_%H%M%S).log"
DEBUG_LOG="$LOG_DIR/debug-$(date +%Y%m%d_%H%M%S).log"

MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"
MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-3}"

# Latest stable versions checked on 2026-06-29. Package-manager based tools install
# from official repositories to receive newest patch automatically.
KUBECTL_VERSION="${KUBECTL_VERSION:-$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || echo v1.34.0)}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.15.7}"
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-3.12.0}"
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.11.1}"
MAVEN_VERSION="${MAVEN_VERSION:-3.9.16}"
GRADLE_VERSION="${GRADLE_VERSION:-9.6.1}"
DEPENDENCY_CHECK_VERSION="${DEPENDENCY_CHECK_VERSION:-12.2.2}"
PACKER_VERSION="${PACKER_VERSION:-1.15.4}"
VAGRANT_VERSION="${VAGRANT_VERSION:-2.4.9}"
ISTIO_VERSION="${ISTIO_VERSION:-1.30.2}"
VAULT_VERSION="${VAULT_VERSION:-2.0.3}"
CONSUL_VERSION="${CONSUL_VERSION:-2.0.1}"
POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-18}"
SQLITE_VERSION="${SQLITE_VERSION:-3.53.3}"
PGADMIN_VERSION="${PGADMIN_VERSION:-9.16}"
DBEAVER_VERSION="${DBEAVER_VERSION:-26.1.1}"
FLYWAY_VERSION="${FLYWAY_VERSION:-12.9.0}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log() {
  local level="$1"; shift
  local msg="$*"
  local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE" >/dev/null
  case "$level" in
    INFO) echo -e "${BLUE}[INFO]${NC} $msg" ;;
    SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $msg" ;;
    WARN) echo -e "${YELLOW}[WARN]${NC} $msg" ;;
    ERROR) echo -e "${RED}[ERROR]${NC} $msg" ;;
    DEBUG) [[ "${DEBUG:-0}" == "1" ]] && echo "[DEBUG] $msg" | tee -a "$DEBUG_LOG" ;;
  esac
}

on_error() {
  local exit_code=$1 line_no=$2
  log ERROR "Script failed at line $line_no with exit code $exit_code"
  cleanup
  exit "$exit_code"
}
trap 'on_error $? $LINENO' ERR
trap cleanup EXIT

cleanup() {
  rm -f "$LOCK_FILE" 2>/dev/null || true
  find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true
}

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local old_pid; old_pid="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      log ERROR "Another installer is running with PID $old_pid"
      exit 1
    fi
  fi
  echo "$$" > "$LOCK_FILE"
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log ERROR "Run this script with sudo/root. Example: sudo $0 --profile=full"
    exit 1
  fi
}

retry() {
  local attempt=1
  until "$@"; do
    if (( attempt >= MAX_RETRIES )); then
      return 1
    fi
    log WARN "Command failed. Retrying in ${RETRY_DELAY}s ($attempt/$MAX_RETRIES): $*"
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

run_cmd() {
  log DEBUG "Running: $*"
  timeout "$TIMEOUT_SECONDS" bash -lc "$*"
}

init_state_db() {
  sqlite3 "$STATE_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS installations (
  tool_name TEXT PRIMARY KEY,
  version TEXT,
  install_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  status TEXT CHECK(status IN ('pending','success','failed')),
  details TEXT
);
SQL
}

record_status() {
  local tool="$1" version="$2" status="$3" details="${4:-}"
  sqlite3 "$STATE_DB" "INSERT OR REPLACE INTO installations(tool_name,version,status,details) VALUES('$(printf "%q" "$tool")','$(printf "%q" "$version")','$status','$(printf "%q" "$details")');" || true
}

preflight_checks() {
  log INFO "Running pre-flight checks..."
  require_root
  if [[ ! -f /etc/os-release ]]; then log ERROR "Cannot detect OS"; exit 1; fi
  . /etc/os-release
  case "$ID" in ubuntu|debian) ;; *) log ERROR "Only Ubuntu/Debian are supported by this script. Detected: $ID"; exit 1;; esac
  local free_kb; free_kb="$(df / | awk 'NR==2{print $4}')"
  (( free_kb > 5242880 )) || { log ERROR "Need at least 5GB free disk space"; exit 1; }
  command -v curl >/dev/null 2>&1 || apt-get update
  log SUCCESS "Pre-flight checks passed on $PRETTY_NAME"
}

install_base_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  retry apt-get update
  retry apt-get install -y ca-certificates curl wget gnupg lsb-release apt-transport-https software-properties-common unzip zip tar gzip jq sqlite3 coreutils findutils
}

add_apt_keyring() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  curl -fsSL "$url" | gpg --dearmor -o "$dest"
  chmod 0644 "$dest"
}

setup_hashicorp_repo() {
  [[ -f /etc/apt/sources.list.d/hashicorp.list ]] && return 0
  add_apt_keyring https://apt.releases.hashicorp.com/gpg /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
  apt-get update
}

setup_docker_repo() {
  [[ -f /etc/apt/sources.list.d/docker.list ]] && return 0
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
}

setup_kubernetes_repo() {
  [[ -f /etc/apt/sources.list.d/kubernetes.list ]] && return 0
  add_apt_keyring https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
  apt-get update
}

setup_jenkins_repo() {
  [[ -f /etc/apt/sources.list.d/jenkins.list ]] && return 0
  add_apt_keyring wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
  echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" https://pkg.jenkins.io/debian-stable binary/ | sudo tee  /etc/apt/sources.list.d/jenkins.list > /dev/null
  apt-get update
}

setup_grafana_repo() {
  [[ -f /etc/apt/sources.list.d/grafana.list ]] && return 0
  add_apt_keyring https://apt.grafana.com/gpg.key /etc/apt/keyrings/grafana.gpg
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
  apt-get update
}

setup_pgadmin_repo() {
  [[ -f /etc/apt/sources.list.d/pgadmin4.list ]] && return 0
  curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub | gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg
  echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list
  apt-get update
}

setup_dbeaver_repo() {
  [[ -f /etc/apt/sources.list.d/dbeaver.list ]] && return 0
  add_apt_keyring https://dbeaver.io/debs/dbeaver.gpg.key /usr/share/keyrings/dbeaver.gpg
  echo "deb [signed-by=/usr/share/keyrings/dbeaver.gpg] https://dbeaver.io/debs/dbeaver-ce /" > /etc/apt/sources.list.d/dbeaver.list
  apt-get update
}

setup_postgresql_repo() {
  [[ -f /etc/apt/sources.list.d/pgdg.list ]] && return 0
  add_apt_keyring https://www.postgresql.org/media/keys/ACCC4CF8.asc /usr/share/keyrings/postgresql.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  apt-get update
}

install_archive_bin() {
  local url="$1" pattern="$2" binary="$3"
  local work; work="$(mktemp -d "$CACHE_DIR/install.XXXXXX")"
  (cd "$work" && curl -fL "$url" -o package && file package >/dev/null
    if [[ "$url" == *.zip ]]; then unzip -q package; else tar -xzf package; fi
    install -m 0755 $(find . -path "$pattern" -type f | head -1) "/usr/local/bin/$binary")
  rm -rf "$work"
}

install_docker() { setup_docker_repo; apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; systemctl enable --now docker || true; }
install_kubectl() { curl -fL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl; install -m 0755 /tmp/kubectl /usr/local/bin/kubectl; rm -f /tmp/kubectl; }
install_terraform() { setup_hashicorp_repo; apt-get install -y terraform; }
install_packer() { setup_hashicorp_repo; apt-get install -y packer; }
install_vagrant() { setup_hashicorp_repo; apt-get install -y vagrant; }
install_vault() { setup_hashicorp_repo; apt-get install -y vault; }
install_consul() { setup_hashicorp_repo; apt-get install -y consul; }
install_jenkins() { setup_jenkins_repo; apt-get install -y fontconfig openjdk-17-jre jenkins; systemctl enable --now jenkins || true; }
install_ansible() { apt-get install -y ansible; }
install_grafana() { setup_grafana_repo; apt-get install -y grafana; systemctl enable --now grafana-server || true; }
install_git() { apt-get install -y git; }
install_awscli() { local w; w="$(mktemp -d)"; (cd "$w" && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip && unzip -q awscliv2.zip && ./aws/install --update); rm -rf "$w"; }
install_azurecli() { curl -sL https://aka.ms/InstallAzureCLIDeb | bash; }
install_gcloud() { curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg; echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list; apt-get update; apt-get install -y google-cloud-cli; }
install_helm() { curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; }
install_lynis() { apt-get install -y lynis; }
install_minikube() { curl -Lo /tmp/minikube-linux-amd64 https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64; install /tmp/minikube-linux-amd64 /usr/local/bin/minikube; rm -f /tmp/minikube-linux-amd64; }
install_prometheus() { install_archive_bin "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" "*/prometheus" prometheus; install_archive_bin "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" "*/promtool" promtool; }
install_node_exporter() { install_archive_bin "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" "*/node_exporter" node_exporter; }
install_maven() { local d="/opt/apache-maven-${MAVEN_VERSION}"; curl -fL "https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -o /tmp/maven.tgz; tar -xzf /tmp/maven.tgz -C /opt; ln -sfn "$d/bin/mvn" /usr/local/bin/mvn; echo "export MAVEN_HOME=$d" >/etc/profile.d/maven.sh; rm -f /tmp/maven.tgz; }
install_gradle() { local d="/opt/gradle-${GRADLE_VERSION}"; curl -fL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip; unzip -q -o /tmp/gradle.zip -d /opt; ln -sfn "$d/bin/gradle" /usr/local/bin/gradle; echo "export GRADLE_HOME=$d" >/etc/profile.d/gradle.sh; rm -f /tmp/gradle.zip; }
install_dependency_check() { local d="/opt/dependency-check-${DEPENDENCY_CHECK_VERSION}"; curl -fL "https://github.com/dependency-check/DependencyCheck/releases/download/v${DEPENDENCY_CHECK_VERSION}/dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip" -o /tmp/dependency-check.zip; rm -rf "$d"; unzip -q /tmp/dependency-check.zip -d /opt; mv /opt/dependency-check "$d"; ln -sfn "$d/bin/dependency-check.sh" /usr/local/bin/dependency-check; rm -f /tmp/dependency-check.zip; }
install_istio() { curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -; install -m 0755 "istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin/istioctl; }
install_postgresql() { setup_postgresql_repo; apt-get install -y "postgresql-${POSTGRESQL_VERSION}" "postgresql-client-${POSTGRESQL_VERSION}" postgresql-contrib; systemctl enable --now postgresql || true; }
install_sqlite3() { apt-get install -y sqlite3 libsqlite3-dev; log WARN "SQLite installed from OS package. Latest upstream is ${SQLITE_VERSION}; compile from source if your distro package is older."; }
install_pgadmin() { setup_pgadmin_repo; apt-get install -y pgadmin4; }
install_dbeaver() { setup_dbeaver_repo; apt-get install -y dbeaver-ce; }
install_flyway() { curl -fL "https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz" -o /tmp/flyway.tgz; tar -xzf /tmp/flyway.tgz -C /opt; ln -sfn "/opt/flyway-${FLYWAY_VERSION}/flyway" /usr/local/bin/flyway; rm -f /tmp/flyway.tgz; }
install_openshift() { curl -fsSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz -o /tmp/oc.tar.gz; tar -xzf /tmp/oc.tar.gz -C /usr/local/bin oc kubectl; rm -f /tmp/oc.tar.gz; }

version_cmd() {
  case "$1" in
    docker) docker --version ;;
    kubectl) kubectl version --client 2>/dev/null | head -1 ;;
    terraform) terraform version | head -1 ;;
    jenkins) jenkins --version 2>/dev/null || systemctl is-active jenkins ;;
    ansible) ansible --version | head -1 ;;
    grafana) grafana-server -v ;;
    prometheus) prometheus --version 2>&1 | head -1 ;;
    node_exporter) node_exporter --version 2>&1 | head -1 ;;
    maven) mvn -v | head -1 ;;
    gradle) gradle --version | grep Gradle | head -1 ;;
    dependency_check) dependency-check --version ;;
    vault) vault version ;;
    consul) consul version | head -1 ;;
    git) git --version ;;
    awscli) aws --version ;;
    azurecli) az version --output table 2>/dev/null | head -2 | tail -1 ;;
    gcloud) gcloud --version | head -1 ;;
    helm) helm version --short ;;
    lynis) lynis --version ;;
    minikube) minikube version --short ;;
    packer) packer version ;;
    vagrant) vagrant --version ;;
    istio) istioctl version --remote=false 2>/dev/null | head -1 ;;
    openshift) oc version --client 2>/dev/null | head -1 ;;
    postgresql) psql --version ;;
    sqlite3) sqlite3 --version ;;
    pgadmin) pgadmin4 --version 2>/dev/null || echo "pgAdmin4 installed" ;;
    dbeaver) dbeaver --version 2>/dev/null || echo "DBeaver installed" ;;
    flyway|flyway-cli) flyway -v | head -1 ;;
    *) echo "No version command" ;;
  esac
}

install_one() {
  local tool="$1" normalized version
  normalized="${tool//-/_}"
  [[ "$normalized" == "flyway_cli" ]] && normalized="flyway"
  if ! declare -F "install_${normalized}" >/dev/null; then
    log WARN "No installer defined for: $tool"
    return 0
  fi
  log INFO "Installing/updating $tool..."
  record_status "$tool" "" "pending"
  if retry "install_${normalized}"; then
    version="$(version_cmd "$normalized" 2>/dev/null | head -1 || true)"
    record_status "$tool" "$version" "success"
    log SUCCESS "$tool installed/updated: ${version:-version unavailable}"
  else
    record_status "$tool" "" "failed" "installer command failed"
    log ERROR "$tool installation failed"
    return 1
  fi
}

install_tools_serial() {
  local failed=0
  for tool in "$@"; do install_one "$tool" || failed=1; done
  return "$failed"
}

install_tools_parallel() {
  local tools=("$@") pids=() failed=0
  for tool in "${tools[@]}"; do
    while (( $(jobs -rp | wc -l) >= MAX_PARALLEL_JOBS )); do sleep 2; done
    ( install_one "$tool" ) & pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  return "$failed"
}

report_status() {
  echo
  log INFO "Installation status:"
  sqlite3 -header -column "$STATE_DB" "SELECT tool_name, version, status, install_timestamp FROM installations ORDER BY tool_name;" || true
}

declare -A PROFILE=(
  [ci_cd]="jenkins git maven gradle dependency_check"
  [k8s]="kubectl helm minikube istio openshift"
  [cloud]="awscli azurecli gcloud"
  [monitoring]="grafana prometheus node_exporter"
  [infra]="terraform packer vagrant ansible"
  [security]="vault consul lynis dependency_check"
  [database]="postgresql sqlite3 pgadmin dbeaver flyway"
  [database_full]="postgresql sqlite3 pgadmin dbeaver flyway"
  [full]="docker kubectl helm minikube istio terraform packer vagrant ansible jenkins git grafana prometheus node_exporter maven gradle dependency_check vault consul lynis postgresql sqlite3 pgadmin dbeaver flyway awscli azurecli"
)

show_versions() {
  cat <<EOF
Latest versions configured:
  kubectl: $KUBECTL_VERSION
  terraform: $TERRAFORM_VERSION
  prometheus: $PROMETHEUS_VERSION
  node_exporter: $NODE_EXPORTER_VERSION
  maven: $MAVEN_VERSION
  gradle: $GRADLE_VERSION
  dependency-check: $DEPENDENCY_CHECK_VERSION
  packer: $PACKER_VERSION
  vagrant: $VAGRANT_VERSION
  istio: $ISTIO_VERSION
  vault: $VAULT_VERSION
  consul: $CONSUL_VERSION
  PostgreSQL: $POSTGRESQL_VERSION.x
  SQLite upstream: $SQLITE_VERSION
  pgAdmin: $PGADMIN_VERSION
  DBeaver: $DBEAVER_VERSION
  Flyway: $FLYWAY_VERSION
EOF
}

show_help() {
  cat <<EOF
Usage: sudo ./Dev-Ops-tools_install_PRODUCTION_latest.sh [OPTIONS]

Options:
  --profile=NAME       Preset: ci_cd, k8s, cloud, monitoring, infra, security, database, database_full, full
  --tool=a,b,c         Install comma-separated tools
  --serial             Install one-by-one instead of parallel
  --dry-run            Print selected tools and versions only
  --versions           Print configured latest versions
  --help               Show this help

Examples:
  sudo ./Dev-Ops-tools_install_PRODUCTION_latest.sh --profile=k8s
  sudo ./Dev-Ops-tools_install_PRODUCTION_latest.sh --tool=terraform,kubectl,helm --serial
  sudo ./Dev-Ops-tools_install_PRODUCTION_latest.sh --profile=database
EOF
}

main() {
  local selection="" serial=false dry_run=false
  for arg in "$@"; do
    case "$arg" in
      --profile=*) selection="${PROFILE[${arg#*=}]:-}"; [[ -n "$selection" ]] || { log ERROR "Unknown profile: ${arg#*=}"; exit 1; } ;;
      --tool=*) selection="${arg#*=}" ;;
      --serial) serial=true ;;
      --dry-run) dry_run=true ;;
      --versions) show_versions; exit 0 ;;
      --help|-h) show_help; exit 0 ;;
      *) log ERROR "Unknown argument: $arg"; show_help; exit 1 ;;
    esac
  done

  [[ -n "$selection" ]] || { show_help; exit 1; }
  selection="${selection//,/ }"

  log INFO "Production DevOps Tools Installer v3.0"
  log INFO "Log file: $LOG_FILE"
  show_versions | tee -a "$LOG_FILE"

  if [[ "$dry_run" == true ]]; then
    echo "Selected tools: $selection"
    exit 0
  fi

  acquire_lock
  preflight_checks
  install_base_dependencies
  init_state_db

  if [[ "$serial" == true ]]; then
    install_tools_serial $selection
  else
    install_tools_parallel $selection
  fi

  report_status
  log SUCCESS "Installation/update process completed. Logs: $LOG_DIR"
}

main "$@"
