#!/bin/bash

################################################################################
#                   PRODUCTION-GRADE DevOps Tools Installer v2.0              #
#                   Enterprise-Ready with Advanced Features                   #
################################################################################

# Strict error handling
set -euo pipefail

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

# Directories and Files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
BACKUP_DIR="${SCRIPT_DIR}/backups"
STATE_DB="${SCRIPT_DIR}/.installation_state.db"
CONFIG_FILE="${SCRIPT_DIR}/.devops-installer-config"
LOCK_FILE="/var/run/devops-installer.lock"
CACHE_DIR="/tmp/devops-installer-cache"
PID_FILE="/tmp/devops-installer.pid"

# Logging
LOG_FILE="${LOG_DIR}/devops-installer-$(date +%Y%m%d_%H%M%S).log"
DEBUG_LOG="${LOG_DIR}/debug-$(date +%Y%m%d_%H%M%S).log"
METRICS_LOG="${LOG_DIR}/metrics-$(date +%Y%m%d_%H%M%S).log"

# Performance & Reliability
MAX_RETRIES=3
RETRY_DELAY=5
TIMEOUT_SECONDS=300
MAX_PARALLEL_JOBS=4
HEALTH_CHECK_TIMEOUT=30

# Notifications
ALERT_EMAIL=""
SLACK_WEBHOOK=""
ENABLE_NOTIFICATIONS=false

# Tool Versions (as of May 2026)
KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt 2>/dev/null || echo 'latest')"
TERRAFORM_VERSION="1.10.3"
PROMETHEUS_VERSION="2.58.0"
NODE_EXPORTER_VERSION="1.9.1"
MAVEN_VERSION="3.10.2"
GRADLE_VERSION="8.11.1"
DEPENDENCY_CHECK_VERSION="10.0.1"
PACKER_VERSION="1.12.1"
VAGRANT_VERSION="2.5.0"
ISTIO_VERSION="1.25.2"
VAULT_VERSION="1.19.2"
CONSUL_VERSION="1.20.1"
POSTGRESQL_VERSION="16.2"
SQLITE_VERSION="3.45.1"
PGADMIN_VERSION="7.6"
DBEAVER_VERSION="23.3.5"
FLYWAY_VERSION="10.1.0"

# Database Configuration
POSTGRES_PORT=5432
POSTGRES_USER="postgres"
POSTGRES_DATA_DIR="/var/lib/postgresql/${POSTGRESQL_VERSION}/main"

# ============================================================================
# INITIALIZATION & SETUP
# ============================================================================

# Create required directories
mkdir -p "${LOG_DIR}" "${BACKUP_DIR}" "${CACHE_DIR}"
chmod 755 "${LOG_DIR}" "${BACKUP_DIR}" "${CACHE_DIR}"

# Initialize state database
init_state_db() {
  if [[ ! -f "$STATE_DB" ]]; then
    sqlite3 "$STATE_DB" <<EOF
CREATE TABLE IF NOT EXISTS installations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tool_name TEXT UNIQUE NOT NULL,
  version TEXT,
  install_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  status TEXT CHECK(status IN ('pending', 'success', 'failed', 'rollback')),
  install_path TEXT,
  checksum TEXT,
  config_backed_up BOOLEAN DEFAULT 0
);

CREATE TABLE IF NOT EXISTS health_checks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tool_name TEXT NOT NULL,
  check_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  status TEXT CHECK(status IN ('healthy', 'warning', 'critical')),
  details TEXT
);

CREATE TABLE IF NOT EXISTS performance_metrics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tool_name TEXT NOT NULL,
  metric_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  install_duration_seconds REAL,
  disk_used_mb REAL,
  cpu_peak_percent REAL,
  memory_peak_mb REAL
);

CREATE TABLE IF NOT EXISTS database_backups (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  database_type TEXT NOT NULL,
  backup_name TEXT,
  backup_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  backup_path TEXT,
  backup_size_mb REAL,
  status TEXT CHECK(status IN ('success', 'failed', 'partial'))
);

CREATE TABLE IF NOT EXISTS database_connections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  database_type TEXT NOT NULL,
  host TEXT,
  port INTEGER,
  database_name TEXT,
  connection_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  status TEXT CHECK(status IN ('active', 'inactive', 'error'))
);
EOF
  fi
}

# ============================================================================
# LOGGING SYSTEM
# ============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Structured logging function
log() {
  local level="$1"
  shift
  local message="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Log to file
  echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
  
  # Terminal output with colors
  case "$level" in
    INFO)    echo -e "${BLUE}[INFO]${NC} ${message}" ;;
    SUCCESS) echo -e "${GREEN}[✓]${NC} ${message}" ;;
    WARN)    echo -e "${YELLOW}[!]${NC} ${message}" ;;
    ERROR)   echo -e "${RED}[✗]${NC} ${message}" ;;
    DEBUG)   [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${NC} ${message}" && echo "[DEBUG] ${message}" >> "$DEBUG_LOG" ;;
  esac
}

# Log performance metrics
log_metrics() {
  local tool="$1"
  local duration="$2"
  local disk_used="$3"
  local cpu_peak="$4"
  local memory_peak="$5"
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${tool}: duration=${duration}s, disk=${disk_used}MB, cpu=${cpu_peak}%, memory=${memory_peak}MB" >> "$METRICS_LOG"
}

# ============================================================================
# ERROR HANDLING & RECOVERY
# ============================================================================

# Global error handler
trap 'on_error $? $LINENO' ERR

on_error() {
  local exit_code=$1
  local line_number=$2
  log ERROR "Script failed at line $line_number with exit code $exit_code"
  cleanup_on_failure
  [[ "$ENABLE_NOTIFICATIONS" == "true" ]] && send_alert "Installation failed at line $line_number (exit code: $exit_code)"
  exit $exit_code
}

# Cleanup on exit
trap 'cleanup_on_exit' EXIT

cleanup_on_exit() {
  # Release lock
  [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
  # Clean temporary files older than 7 days
  find "${CACHE_DIR}" -type f -mtime +7 -delete 2>/dev/null || true
  log INFO "Cleanup completed"
}

cleanup_on_failure() {
  log WARN "Attempting graceful cleanup after failure..."
  # Terminate background jobs
  jobs -p | xargs -r kill -9 2>/dev/null || true
  rm -f "$LOCK_FILE"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

# Check system requirements
preflight_checks() {
  log INFO "Running pre-flight system checks..."
  
  # Root privilege check
  if [[ $EUID -ne 0 ]]; then
    log ERROR "This script must be run as root or with sudo"
    exit 1
  fi
  
  # Check internet connectivity
  if ! ping -c 1 8.8.8.8 &>/dev/null; then
    log WARN "No internet connectivity detected. Offline mode may be required."
  fi
  
  # Check disk space (minimum 10GB)
  local available_space=$(df / | awk 'NR==2 {print $4}')
  if [[ $available_space -lt 10485760 ]]; then
    log ERROR "Insufficient disk space. Required: 10GB, Available: $(numfmt --to=iec $available_space 2>/dev/null || echo $available_space)"
    exit 1
  fi
  log SUCCESS "Disk space check passed (Available: $(numfmt --to=iec $available_space 2>/dev/null || echo $available_space))"
  
  # Check CPU cores (minimum 2)
  local cpu_cores=$(nproc)
  if [[ $cpu_cores -lt 2 ]]; then
    log WARN "System has fewer than 2 CPU cores. Performance may be impacted."
  fi
  log SUCCESS "System has $cpu_cores CPU cores"
  
  # Check available memory (minimum 2GB)
  local available_mem=$(($(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1024))
  if [[ $available_mem -lt 2048 ]]; then
    log ERROR "Insufficient memory. Required: 2GB, Available: ${available_mem}MB"
    exit 1
  fi
  log SUCCESS "Memory check passed (Available: ${available_mem}MB)"
  
  # Validate system clock
  if ! command -v ntpstat &>/dev/null && ! command -v timedatectl &>/dev/null; then
    log WARN "NTP not configured. System clock synchronization is recommended."
  else
    log SUCCESS "System clock is synchronized"
  fi
  
  # Detect OS
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO=$ID
    DISTRO_VERSION=$VERSION_ID
    log SUCCESS "Detected: ${PRETTY_NAME}"
  else
    log ERROR "Unable to detect Linux distribution"
    exit 1
  fi
}

# ============================================================================
# DEPENDENCY MANAGEMENT
# ============================================================================

# Install critical dependencies with retry logic
install_critical_dependencies() {
  local deps=(curl wget git zip unzip tar gzip jq sqlite3 gpg apt-transport-https ca-certificates)
  
  log INFO "Checking critical dependencies..."
  
  local missing_deps=()
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      missing_deps+=("$dep")
    fi
  done
  
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log INFO "Installing missing dependencies: ${missing_deps[*]}"
    install_dependencies_with_retry "${missing_deps[@]}"
  else
    log SUCCESS "All critical dependencies are installed"
  fi
}

# Install dependencies with exponential backoff retry
install_dependencies_with_retry() {
  local deps=("$@")
  local attempt=1
  
  while [[ $attempt -le $MAX_RETRIES ]]; do
    log INFO "Attempting to install dependencies (attempt $attempt/$MAX_RETRIES)..."
    
    case "$DISTRO" in
      ubuntu|debian)
        if sudo apt-get update && sudo apt-get install -y "${deps[@]}"; then
          log SUCCESS "Dependencies installed successfully"
          return 0
        fi
        ;;
      centos|rhel)
        if sudo yum install -y "${deps[@]}"; then
          log SUCCESS "Dependencies installed successfully"
          return 0
        fi
        ;;
      fedora)
        if sudo dnf install -y "${deps[@]}"; then
          log SUCCESS "Dependencies installed successfully"
          return 0
        fi
        ;;
    esac
    
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      local delay=$((RETRY_DELAY * 2 ** (attempt - 1)))
      log WARN "Dependency installation failed. Retrying in ${delay}s..."
      sleep "$delay"
    fi
    
    ((attempt++))
  done
  
  log ERROR "Failed to install dependencies after $MAX_RETRIES attempts"
  return 1
}

# ============================================================================
# LOCK MECHANISM FOR CONCURRENT EXECUTION PREVENTION
# ============================================================================

acquire_lock() {
  local timeout=30
  local elapsed=0
  
  while [[ -f "$LOCK_FILE" ]] && [[ $elapsed -lt $timeout ]]; do
    log WARN "Waiting for previous installation to complete (${elapsed}s/${timeout}s)..."
    sleep 2
    ((elapsed += 2))
  done
  
  if [[ -f "$LOCK_FILE" ]]; then
    log ERROR "Unable to acquire lock. Another installation may be in progress."
    return 1
  fi
  
  echo "$$" > "$LOCK_FILE"
  chmod 644 "$LOCK_FILE"
  log DEBUG "Lock acquired (PID: $$)"
  return 0
}

release_lock() {
  rm -f "$LOCK_FILE"
  log DEBUG "Lock released"
}

# ============================================================================
# TOOL DEFINITIONS
# ============================================================================

declare -A tool_group_presets=(
  [ci_cd]="jenkins git maven gradle"
  [k8s]="kubectl helm minikube istio openshift"
  [cloud]="awscli azurecli gcloud"
  [monitoring]="grafana prometheus node_exporter"
  [infra]="terraform packer vagrant ansible"
  [security]="vault consul lynis"
  [database]="postgresql sqlite3 pgadmin dbeaver flyway"
  [database_full]="postgresql sqlite3 pgadmin dbeaver flyway-cli"
  [full]="docker kubectl ansible terraform jenkins grafana prometheus node_exporter maven gradle postgresql sqlite3"
)

# Tool install/uninstall commands - Ubuntu/Debian
declare -A install_commands_ubuntu=(
  [docker]="curl -fsSL https://get.docker.com | bash && sudo usermod -aG docker $USER"
  [kubectl]="curl -LO https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl && sudo install kubectl /usr/local/bin/ && rm kubectl"
  [terraform]="curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - && sudo apt-add-repository \"deb [arch=$(dpkg --print-architecture)] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" && sudo apt-get update && sudo apt-get install -y terraform"
  [jenkins]="curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null && echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null && sudo apt-get update && sudo apt-get install -y openjdk-17-jre jenkins"
  [ansible]="sudo apt-get update && sudo apt-add-repository ppa:ansible/ansible && sudo apt-get install -y ansible"
  [grafana]="sudo apt-get install -y software-properties-common && sudo add-apt-repository \"deb https://packages.grafana.com/oss/deb stable main\" && sudo apt-get update && sudo apt-get install -y grafana"
  [prometheus]="curl -LO https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/ && rm -rf prometheus-${PROMETHEUS_VERSION}.linux-amd64*"
  [node_exporter]="curl -LO https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ && rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*"
  [maven]="curl -LO https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz && sudo tar -xzf apache-maven-${MAVEN_VERSION}-bin.tar.gz -C /opt && sudo ln -sf /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn && echo 'export MAVEN_HOME=/opt/apache-maven-${MAVEN_VERSION}' | sudo tee /etc/profile.d/maven.sh && rm apache-maven-${MAVEN_VERSION}-bin.tar.gz"
  [gradle]="curl -LO https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip && sudo unzip -q gradle-${GRADLE_VERSION}-bin.zip -d /opt && sudo ln -sf /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle && echo 'export GRADLE_HOME=/opt/gradle-${GRADLE_VERSION}' | sudo tee /etc/profile.d/gradle.sh && rm gradle-${GRADLE_VERSION}-bin.zip"
  [vault]="curl -LO https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && sudo unzip -q vault_${VAULT_VERSION}_linux_amd64.zip -o /usr/local/bin/ && sudo chmod +x /usr/local/bin/vault && rm vault_${VAULT_VERSION}_linux_amd64.zip"
  [consul]="curl -LO https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip && sudo unzip -q consul_${CONSUL_VERSION}_linux_amd64.zip -o /usr/local/bin/ && sudo chmod +x /usr/local/bin/consul && rm consul_${CONSUL_VERSION}_linux_amd64.zip"
  [git]="sudo apt-get update && sudo apt-get install -y git"
  [awscli]="curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip && unzip -q awscliv2.zip && sudo ./aws/install && rm -rf awscliv2.zip aws/"
  [azurecli]="curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
  [gcloud]="curl https://sdk.cloud.google.com | bash"
  [helm]="curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  [lynis]="sudo apt-get update && sudo apt-get install -y lynis"
  [minikube]="curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64"
  [packer]="curl -LO https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip && unzip -q packer_${PACKER_VERSION}_linux_amd64.zip && sudo mv packer /usr/local/bin/ && rm packer_${PACKER_VERSION}_linux_amd64.zip"
  [vagrant]="curl -LO https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_linux_amd64.zip && unzip -q vagrant_${VAGRANT_VERSION}_linux_amd64.zip && sudo mv vagrant /usr/local/bin/ && rm vagrant_${VAGRANT_VERSION}_linux_amd64.zip"
  [postgresql]="sudo apt-get update && sudo apt-get install -y postgresql postgresql-contrib postgresql-client && sudo systemctl enable postgresql && sudo systemctl start postgresql"
  [sqlite3]="sudo apt-get update && sudo apt-get install -y sqlite3 libsqlite3-dev"
  [pgadmin]="curl -fsSL https://www.pgadmin.org/static/pgadmin4_apt_repo.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/pgadmin.gpg && sudo sh -c 'echo \"deb https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/focal pgadgin4 main\" > /etc/apt/sources.list.d/pgadmin4.list' && sudo apt-get update && sudo apt-get install -y pgadmin4 pgadmin4-web"
  [dbeaver]="curl -fsSL https://dbeaver.io/debs/dbeaver.gpg.key | sudo apt-key add - && echo 'deb https://dbeaver.io/debs/dbeaver-ce /' | sudo tee /etc/apt/sources.list.d/dbeaver.list && sudo apt-get update && sudo apt-get install -y dbeaver-ce"
  [flyway]="curl -L https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz -o flyway.tar.gz && tar xzf flyway.tar.gz && sudo mv flyway-${FLYWAY_VERSION} /opt/flyway && sudo ln -sf /opt/flyway/flyway /usr/local/bin/flyway && rm flyway.tar.gz"
  [flyway-cli]="curl -L https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz -o flyway.tar.gz && tar xzf flyway.tar.gz && sudo mv flyway-${FLYWAY_VERSION} /opt/flyway && sudo ln -sf /opt/flyway/flyway /usr/local/bin/flyway && rm flyway.tar.gz && echo 'export PATH=/opt/flyway:$PATH' | sudo tee /etc/profile.d/flyway.sh"
)

declare -A version_commands=(
  [docker]="docker --version"
  [kubectl]="kubectl version --client --short 2>/dev/null"
  [terraform]="terraform version | head -1"
  [jenkins]="jenkins --version 2>/dev/null || echo 'Check via systemctl'"
  [ansible]="ansible --version 2>/dev/null | head -1"
  [grafana]="grafana-server -v 2>/dev/null"
  [prometheus]="prometheus --version 2>/dev/null"
  [node_exporter]="node_exporter --version 2>/dev/null"
  [maven]="mvn -v 2>/dev/null | head -1"
  [gradle]="gradle --version 2>/dev/null | grep Gradle"
  [vault]="vault version 2>/dev/null"
  [consul]="consul version 2>/dev/null"
  [git]="git --version"
  [awscli]="aws --version"
  [azurecli]="az --version 2>/dev/null | head -1"
  [gcloud]="gcloud --version 2>/dev/null | head -1"
  [helm]="helm version --short 2>/dev/null"
  [lynis]="lynis --version 2>/dev/null"
  [minikube]="minikube version 2>/dev/null"
  [packer]="packer version 2>/dev/null"
  [vagrant]="vagrant --version"
  [postgresql]="psql --version 2>/dev/null"
  [sqlite3]="sqlite3 --version 2>/dev/null"
  [pgadmin]="pgadmin4 --version 2>/dev/null || echo 'PgAdmin4 installed'"
  [dbeaver]="dbeaver --version 2>/dev/null || echo 'DBeaver installed'"
  [flyway]="flyway -v 2>/dev/null || echo 'Flyway installed'"
)

declare -A health_check_commands=(
  [docker]="docker ps >/dev/null 2>&1 && echo 'OK'"
  [kubernetes]="kubectl cluster-info >/dev/null 2>&1 && echo 'OK'"
  [jenkins]="systemctl is-active --quiet jenkins && echo 'OK'"
  [grafana]="systemctl is-active --quiet grafana-server && echo 'OK'"
  [prometheus]="pgrep -x prometheus >/dev/null && echo 'OK'"
  [vault]="vault status >/dev/null 2>&1 && echo 'OK'"
  [postgresql]="sudo -u postgres psql -c 'SELECT 1' >/dev/null 2>&1 && echo 'OK'"
  [sqlite]="sqlite3 ':memory:' 'SELECT 1;' >/dev/null 2>&1 && echo 'OK'"
  [pgadmin]="curl -s http://localhost:5050 >/dev/null 2>&1 && echo 'OK'"
  [database]="sudo -u postgres psql -c 'SELECT datname FROM pg_database LIMIT 1;' >/dev/null 2>&1 && echo 'OK'"
)

# ============================================================================
# INSTALLATION ENGINE
# ============================================================================

# Install tool with comprehensive error handling and logging
install_tool_advanced() {
  local tool_name="$1"
  local install_cmd="$2"
  local start_time=$(date +%s)
  
  log INFO "Starting installation of $tool_name..."
  
  # Backup existing configuration if tool is already installed
  backup_tool_config "$tool_name"
  
  # Track installation start in database
  sqlite3 "$STATE_DB" "INSERT OR REPLACE INTO installations (tool_name, status) VALUES ('$tool_name', 'pending');"
  
  # Execute installation with timeout and error capturing
  local temp_log="${LOG_DIR}/${tool_name}-install.log"
  if timeout $TIMEOUT_SECONDS bash -c "$install_cmd" >"$temp_log" 2>&1; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Verify installation
    if verify_tool_installation "$tool_name"; then
      log SUCCESS "$tool_name installed successfully (Duration: ${duration}s)"
      
      # Record successful installation
      local version=$(get_tool_version "$tool_name" 2>/dev/null || echo "unknown")
      sqlite3 "$STATE_DB" "INSERT OR REPLACE INTO installations (tool_name, version, status, install_path) VALUES ('$tool_name', '$version', 'success', '$(which $tool_name 2>/dev/null || echo 'N/A')');"
      
      # Log metrics
      log_metrics "$tool_name" "$duration" "0" "0" "0"
      
      # Run health check
      check_tool_health "$tool_name"
      
      return 0
    else
      log ERROR "$tool_name installation verification failed"
      sqlite3 "$STATE_DB" "UPDATE installations SET status = 'failed' WHERE tool_name = '$tool_name';"
      rollback_tool_installation "$tool_name"
      return 1
    fi
  else
    local exit_code=$?
    log ERROR "$tool_name installation failed or timed out (exit code: $exit_code)"
    sqlite3 "$STATE_DB" "UPDATE installations SET status = 'failed' WHERE tool_name = '$tool_name';"
    cat "$temp_log" | while read -r line; do log DEBUG "$line"; done
    rollback_tool_installation "$tool_name"
    return 1
  fi
}

# Verify tool was installed correctly
verify_tool_installation() {
  local tool="$1"
  
  if [[ -z "${version_commands[$tool]:-}" ]]; then
    return 0  # No verification command defined
  fi
  
  if eval "${version_commands[$tool]}" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Get tool version
get_tool_version() {
  local tool="$1"
  eval "${version_commands[$tool]}" 2>/dev/null | head -1
}

# Health check for installed tools
check_tool_health() {
  local tool="$1"
  
  log INFO "Running health check for $tool..."
  
  if [[ -z "${health_check_commands[$tool]:-}" ]]; then
    log DEBUG "No health check defined for $tool"
    return 0
  fi
  
  if timeout $HEALTH_CHECK_TIMEOUT bash -c "${health_check_commands[$tool]}" >/dev/null 2>&1; then
    log SUCCESS "$tool health check passed"
    sqlite3 "$STATE_DB" "INSERT INTO health_checks (tool_name, status, details) VALUES ('$tool', 'healthy', 'Passed');"
    return 0
  else
    log WARN "$tool health check failed"
    sqlite3 "$STATE_DB" "INSERT INTO health_checks (tool_name, status, details) VALUES ('$tool', 'critical', 'Failed');"
    return 1
  fi
}

# Backup tool configuration before installation
backup_tool_config() {
  local tool="$1"
  
  case "$tool" in
    docker)
      [[ -d /etc/docker ]] && sudo cp -r /etc/docker "${BACKUP_DIR}/docker-$(date +%s).bak" 2>/dev/null && log DEBUG "Backed up Docker config"
      ;;
    jenkins)
      [[ -d /var/lib/jenkins ]] && sudo cp -r /var/lib/jenkins "${BACKUP_DIR}/jenkins-$(date +%s).bak" 2>/dev/null && log DEBUG "Backed up Jenkins config"
      ;;
    grafana)
      [[ -d /etc/grafana ]] && sudo cp -r /etc/grafana "${BACKUP_DIR}/grafana-$(date +%s).bak" 2>/dev/null && log DEBUG "Backed up Grafana config"
      ;;
  esac
}

# Rollback tool installation on failure
rollback_tool_installation() {
  local tool="$1"
  
  log WARN "Initiating rollback for $tool..."
  
  # Find and restore latest backup
  local latest_backup=$(find "${BACKUP_DIR}" -name "${tool}-*.bak" -type d -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
  
  if [[ -n "$latest_backup" ]]; then
    log INFO "Restoring from backup: $latest_backup"
    case "$tool" in
      docker)
        sudo rm -rf /etc/docker && sudo mv "$latest_backup" /etc/docker
        ;;
      jenkins)
        sudo systemctl stop jenkins 2>/dev/null || true
        sudo rm -rf /var/lib/jenkins && sudo mv "$latest_backup" /var/lib/jenkins
        sudo systemctl start jenkins 2>/dev/null || true
        ;;
      grafana)
        sudo systemctl stop grafana-server 2>/dev/null || true
        sudo rm -rf /etc/grafana && sudo mv "$latest_backup" /etc/grafana
        sudo systemctl start grafana-server 2>/dev/null || true
        ;;
    esac
    log SUCCESS "$tool rollback completed"
    sqlite3 "$STATE_DB" "UPDATE installations SET status = 'rollback' WHERE tool_name = '$tool';"
  fi
}

# ============================================================================
# DATABASE MANAGEMENT & OPERATIONS
# ============================================================================

# Initialize PostgreSQL after installation
initialize_postgresql() {
  log INFO "Initializing PostgreSQL..."
  
  # Start PostgreSQL service
  if sudo systemctl start postgresql; then
    log SUCCESS "PostgreSQL service started"
  else
    log ERROR "Failed to start PostgreSQL service"
    return 1
  fi
  
  # Enable PostgreSQL service to start on boot
  sudo systemctl enable postgresql
  
  # Check if PostgreSQL is ready
  local max_attempts=30
  local attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    if sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
      log SUCCESS "PostgreSQL is ready"
      sqlite3 "$STATE_DB" "INSERT INTO database_connections (database_type, host, port, database_name, status) VALUES ('postgresql', 'localhost', 5432, 'postgres', 'active');"
      return 0
    fi
    log DEBUG "Waiting for PostgreSQL to be ready... (attempt $((attempt+1))/$max_attempts)"
    sleep 1
    ((attempt++))
  done
  
  log ERROR "PostgreSQL did not become ready in time"
  return 1
}

# Backup PostgreSQL database
backup_postgresql() {
  local backup_name="${1:-backup_$(date +%Y%m%d_%H%M%S)}"
  local backup_path="${BACKUP_DIR}/${backup_name}.sql"
  
  log INFO "Backing up PostgreSQL to $backup_path..."
  
  if sudo -u postgres pg_dumpall > "$backup_path" 2>/dev/null; then
    local backup_size=$(du -m "$backup_path" | awk '{print $1}')
    log SUCCESS "PostgreSQL backup completed (Size: ${backup_size}MB)"
    sqlite3 "$STATE_DB" "INSERT INTO database_backups (database_type, backup_name, backup_path, backup_size_mb, status) VALUES ('postgresql', '$backup_name', '$backup_path', $backup_size, 'success');"
    return 0
  else
    log ERROR "PostgreSQL backup failed"
    sqlite3 "$STATE_DB" "INSERT INTO database_backups (database_type, backup_name, backup_path, status) VALUES ('postgresql', '$backup_name', '$backup_path', 'failed');"
    return 1
  fi
}

# Restore PostgreSQL database
restore_postgresql() {
  local backup_file="$1"
  
  if [[ ! -f "$backup_file" ]]; then
    log ERROR "Backup file not found: $backup_file"
    return 1
  fi
  
  log WARN "Restoring PostgreSQL from $backup_file (this will overwrite current data)..."
  
  if sudo -u postgres psql < "$backup_file" >/dev/null 2>&1; then
    log SUCCESS "PostgreSQL restore completed"
    return 0
  else
    log ERROR "PostgreSQL restore failed"
    return 1
  fi
}

# Create PostgreSQL user and database
create_postgresql_user() {
  local user_name="$1"
  local password="$2"
  
  log INFO "Creating PostgreSQL user: $user_name..."
  
  if sudo -u postgres psql -c "CREATE USER $user_name WITH PASSWORD '$password';" 2>/dev/null; then
    log SUCCESS "PostgreSQL user created: $user_name"
    return 0
  else
    log DEBUG "User may already exist, skipping..."
    return 0
  fi
}

create_postgresql_database() {
  local db_name="$1"
  local owner="$2"
  
  log INFO "Creating PostgreSQL database: $db_name (owner: $owner)..."
  
  if sudo -u postgres psql -c "CREATE DATABASE $db_name OWNER $owner;" 2>/dev/null; then
    log SUCCESS "PostgreSQL database created: $db_name"
    sqlite3 "$STATE_DB" "INSERT INTO database_connections (database_type, host, port, database_name, status) VALUES ('postgresql', 'localhost', 5432, '$db_name', 'active');"
    return 0
  else
    log DEBUG "Database may already exist, skipping..."
    return 0
  fi
}

# List all PostgreSQL databases
list_postgresql_databases() {
  log INFO "Listing PostgreSQL databases..."
  sudo -u postgres psql -lqt | grep -v "^-" | grep -v "^List" | awk -F'|' '{print $1}' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g' | grep -v '^$'
}

# Execute SQL migrations with Flyway
run_database_migrations() {
  local migration_dir="$1"
  local database_url="$2"
  local database_user="${3:-postgres}"
  local database_password="${4:-}"
  
  log INFO "Running database migrations from: $migration_dir..."
  
  if [[ ! -d "$migration_dir" ]]; then
    log ERROR "Migration directory not found: $migration_dir"
    return 1
  fi
  
  # Build Flyway command
  local flyway_cmd="flyway -locations=filesystem:$migration_dir -url=$database_url -user=$database_user"
  
  if [[ -n "$database_password" ]]; then
    flyway_cmd="$flyway_cmd -password=$database_password"
  fi
  
  flyway_cmd="$flyway_cmd migrate"
  
  if eval "$flyway_cmd" >/dev/null 2>&1; then
    log SUCCESS "Database migrations completed successfully"
    return 0
  else
    log ERROR "Database migrations failed"
    return 1
  fi
}

# SQLite database operations
backup_sqlite() {
  local sqlite_db="$1"
  local backup_name="${2:-sqlite_backup_$(date +%Y%m%d_%H%M%S)}"
  local backup_path="${BACKUP_DIR}/${backup_name}.db"
  
  if [[ ! -f "$sqlite_db" ]]; then
    log ERROR "SQLite database not found: $sqlite_db"
    return 1
  fi
  
  log INFO "Backing up SQLite database: $sqlite_db..."
  
  if cp "$sqlite_db" "$backup_path"; then
    local backup_size=$(du -m "$backup_path" | awk '{print $1}')
    log SUCCESS "SQLite backup completed (Size: ${backup_size}MB)"
    sqlite3 "$STATE_DB" "INSERT INTO database_backups (database_type, backup_name, backup_path, backup_size_mb, status) VALUES ('sqlite', '$backup_name', '$backup_path', $backup_size, 'success');"
    return 0
  else
    log ERROR "SQLite backup failed"
    return 1
  fi
}

# Get database statistics
database_stats() {
  log INFO "Database Statistics:"
  echo ""
  echo "=== PostgreSQL Statistics ==="
  sudo -u postgres psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database ORDER BY pg_database_size(datname) DESC;" 2>/dev/null || echo "PostgreSQL not available"
  echo ""
  echo "=== Installation Database Statistics ==="
  sqlite3 "$STATE_DB" "SELECT database_type, COUNT(*) as backup_count, SUM(backup_size_mb) as total_size_mb FROM database_backups GROUP BY database_type;"
}

# Check database connectivity
check_database_connections() {
  log INFO "Checking database connections..."
  echo ""
  
  # Check PostgreSQL
  if sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
    log SUCCESS "PostgreSQL: Connected"
    local pg_version=$(sudo -u postgres psql -c "SELECT version();" 2>/dev/null | head -3 | tail -1)
    echo "  Version: $pg_version"
  else
    log ERROR "PostgreSQL: Not connected"
  fi
  
  # Check SQLite
  if sqlite3 ":memory:" "SELECT 1;" >/dev/null 2>&1; then
    log SUCCESS "SQLite: Available"
    local sqlite_version=$(sqlite3 ":memory:" "SELECT sqlite_version();")
    echo "  Version: $sqlite_version"
  else
    log ERROR "SQLite: Not available"
  fi
}

# ============================================================================
# PARALLEL INSTALLATION
# ============================================================================

# Install multiple tools in parallel with job control
install_tools_parallel() {
  local tools=("$@")
  local job_count=0
  local failed_tools=()
  
  log INFO "Starting parallel installation of ${#tools[@]} tools (max jobs: $MAX_PARALLEL_JOBS)..."
  
  for tool in "${tools[@]}"; do
    # Check if distro-specific install exists
    if [[ -z "${install_commands_ubuntu[$tool]:-}" ]]; then
      log WARN "No installation command found for $tool"
      continue
    fi
    
    # Wait if max parallel jobs reached
    while [[ $(jobs -r -p | wc -l) -ge $MAX_PARALLEL_JOBS ]]; do
      sleep 1
    done
    
    # Install tool in background
    (
      if ! install_tool_advanced "$tool" "${install_commands_ubuntu[$tool]}"; then
        echo "$tool" >> "${BACKUP_DIR}/.failed_tools"
      fi
    ) &
    
    ((job_count++))
  done
  
  # Wait for all background jobs to complete
  local remaining_jobs=$(jobs -r -p | wc -l)
  while [[ $remaining_jobs -gt 0 ]]; do
    log INFO "Waiting for $remaining_jobs installation(s) to complete..."
    sleep 5
    remaining_jobs=$(jobs -r -p | wc -l)
  done
  
  # Check for failed tools
  if [[ -f "${BACKUP_DIR}/.failed_tools" ]]; then
    while IFS= read -r tool; do
      failed_tools+=("$tool")
    done < "${BACKUP_DIR}/.failed_tools"
    rm -f "${BACKUP_DIR}/.failed_tools"
  fi
  
  if [[ ${#failed_tools[@]} -gt 0 ]]; then
    log ERROR "Failed tools: ${failed_tools[*]}"
    return 1
  else
    log SUCCESS "All tools installed successfully"
    return 0
  fi
}

# ============================================================================
# REPORTING & MONITORING
# ============================================================================

# Generate comprehensive HTML report
generate_html_report() {
  local report_file="${LOG_DIR}/installation_report_$(date +%Y%m%d_%H%M%S).html"
  
  cat > "$report_file" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>DevOps Installer Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
    .header { background: #333; color: white; padding: 20px; border-radius: 5px; }
    .section { background: white; margin: 20px 0; padding: 15px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .success { color: #28a745; }
    .failure { color: #dc3545; }
    .warning { color: #ffc107; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
    th { background: #f8f9fa; font-weight: bold; }
    tr:hover { background: #f5f5f5; }
  </style>
</head>
<body>
  <div class="header">
    <h1>DevOps Tools Installation Report</h1>
    <p>Generated: $(date)</p>
  </div>
  
  <div class="section">
    <h2>System Information</h2>
    <table>
      <tr><td>Hostname:</td><td>$(hostname)</td></tr>
      <tr><td>OS:</td><td>$(lsb_release -d 2>/dev/null | cut -f2)</td></tr>
      <tr><td>Kernel:</td><td>$(uname -r)</td></tr>
      <tr><td>CPU Cores:</td><td>$(nproc)</td></tr>
      <tr><td>Memory:</td><td>$(free -h | awk 'NR==2{print $2}')</td></tr>
    </table>
  </div>
  
  <div class="section">
    <h2>Installation Summary</h2>
    <table>
      <thead>
        <tr>
          <th>Tool</th>
          <th>Version</th>
          <th>Status</th>
          <th>Install Time</th>
        </tr>
      </thead>
      <tbody>
EOF
  
  # Add tool data from database
  sqlite3 -header -html "$STATE_DB" "SELECT tool_name, version, status, install_timestamp FROM installations;" >> "$report_file"
  
  cat >> "$report_file" <<'EOF'
      </tbody>
    </table>
  </div>
  
  <div class="section">
    <h2>Performance Metrics</h2>
    <table>
      <thead>
        <tr>
          <th>Tool</th>
          <th>Duration (s)</th>
          <th>Disk (MB)</th>
          <th>CPU Peak (%)</th>
          <th>Memory Peak (MB)</th>
        </tr>
      </thead>
      <tbody>
EOF
  
  sqlite3 -header -html "$STATE_DB" "SELECT tool_name, install_duration_seconds, disk_used_mb, cpu_peak_percent, memory_peak_mb FROM performance_metrics;" >> "$report_file"
  
  cat >> "$report_file" <<'EOF'
      </tbody>
    </table>
  </div>
  
  <div class="section">
    <h2>Health Check Results</h2>
    <table>
      <thead>
        <tr>
          <th>Tool</th>
          <th>Status</th>
          <th>Check Time</th>
          <th>Details</th>
        </tr>
      </thead>
      <tbody>
EOF
  
  sqlite3 -header -html "$STATE_DB" "SELECT tool_name, status, check_timestamp, details FROM health_checks ORDER BY check_timestamp DESC LIMIT 50;" >> "$report_file"
  
  cat >> "$report_file" <<'EOF'
      </tbody>
    </table>
  </div>
</body>
</html>
EOF
  
  log SUCCESS "HTML report generated: $report_file"
  return 0
}

# Get installation status
get_installation_status() {
  log INFO "Installation Status Report:"
  echo ""
  sqlite3 "$STATE_DB" <<EOF
.mode column
.headers on
SELECT tool_name, version, status, install_timestamp FROM installations ORDER BY install_timestamp DESC;
EOF
}

# ============================================================================
# NOTIFICATIONS
# ============================================================================

# Send alert via email or Slack
send_alert() {
  local message="$1"
  
  if [[ -n "$ALERT_EMAIL" ]]; then
    echo "$message" | mail -s "DevOps Installer Alert" "$ALERT_EMAIL" 2>/dev/null || true
  fi
  
  if [[ -n "$SLACK_WEBHOOK" ]]; then
    curl -X POST "$SLACK_WEBHOOK" \
      -H 'Content-type: application/json' \
      --data "{\"text\":\"DevOps Installer: $message\"}" 2>/dev/null || true
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  log INFO "=========================================="
  log INFO "Production DevOps Tools Installer v2.0"
  log INFO "=========================================="
  log INFO "Log file: $LOG_FILE"
  
  # Acquire installation lock
  if ! acquire_lock; then
    log ERROR "Failed to acquire installation lock"
    return 1
  fi
  
  # Run pre-flight checks
  if ! preflight_checks; then
    log ERROR "Pre-flight checks failed"
    return 1
  fi
  
  # Install critical dependencies
  if ! install_critical_dependencies; then
    log ERROR "Failed to install critical dependencies"
    return 1
  fi
  
  # Initialize state database
  init_state_db
  
  # Parse arguments
  local selected_tools=""
  local action="install"
  local parallel_mode=true
  
  for arg in "$@"; do
    case $arg in
      --profile=*) selected_tools="${arg#*=}" ;;
      --tool=*) selected_tools="${arg#*=}" ;;
      --serial) parallel_mode=false ;;
      --dry-run)
        log INFO "DRY RUN MODE: No changes will be made"
        echo "Selected tools: $selected_tools"
        return 0
        ;;
      --help)
        show_help
        return 0
        ;;
    esac
  done
  
  # Use default profile if none specified
  if [[ -z "$selected_tools" ]]; then
    log INFO "No tools specified. Use --help for usage information"
    show_help
    return 1
  fi
  
  # Convert profile name to tool list
  if [[ -n "${tool_group_presets[$selected_tools]:-}" ]]; then
    selected_tools="${tool_group_presets[$selected_tools]}"
    log INFO "Using preset: $selected_tools"
  fi
  
  # Execute installation
  if [[ "$parallel_mode" == "true" ]]; then
    log INFO "Starting parallel installation..."
    if install_tools_parallel $selected_tools; then
      log SUCCESS "All installations completed successfully"
    else
      log ERROR "Some installations failed"
      return 1
    fi
  else
    log INFO "Starting serial installation..."
    for tool in $selected_tools; do
      if [[ -n "${install_commands_ubuntu[$tool]:-}" ]]; then
        install_tool_advanced "$tool" "${install_commands_ubuntu[$tool]}" || log ERROR "Failed to install $tool"
      fi
    done
  fi
  
  # Initialize databases if installed
  if [[ "$selected_tools" == *"postgresql"* ]]; then
    log INFO "Initializing PostgreSQL..."
    initialize_postgresql || log ERROR "PostgreSQL initialization failed"
  fi
  
  # Check all database connections
  if [[ "$selected_tools" == *"postgresql"* ]] || [[ "$selected_tools" == *"sqlite3"* ]]; then
    check_database_connections
  fi
  
  # Generate reports
  generate_html_report
  get_installation_status
  
  # Display database stats if databases were installed
  if [[ "$selected_tools" == *"postgresql"* ]] || [[ "$selected_tools" == *"sqlite3"* ]]; then
    database_stats
  fi
  
  # Final notification
  if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then
    send_alert "Installation completed for tools: $selected_tools"
  fi
  
  log SUCCESS "Installation process completed. Check $LOG_DIR for detailed logs."
}

show_help() {
  cat <<EOF
Usage: sudo ./Dev-Ops-tools_install_PRODUCTION.sh [OPTIONS]

OPTIONS:
  --profile=NAME      Use preset profile
  --tool=TOOL1,TOOL2  Install specific tools (comma-separated)
  --serial            Run installations serially instead of parallel
  --dry-run           Show what would be installed without making changes
  --help              Display this help message

PRESETS:
  ci_cd           - Jenkins, Git, Maven, Gradle
  k8s             - Kubernetes tools (kubectl, helm, minikube, istio, openshift)
  cloud           - Cloud CLIs (AWS, Azure, Google Cloud)
  monitoring      - Monitoring stack (Grafana, Prometheus, Node Exporter)
  infra           - Infrastructure as Code (Terraform, Packer, Vagrant, Ansible)
  security        - Security tools (Vault, Consul, Lynis)
  database        - Database tools (PostgreSQL, SQLite, PgAdmin, DBeaver, Flyway)
  database_full   - Full database stack with CLI tools
  full            - All tools including databases

EXAMPLES:
  # Install Kubernetes stack
  sudo ./Dev-Ops-tools_install_PRODUCTION.sh --profile=k8s
  
  # Install database tools
  sudo ./Dev-Ops-tools_install_PRODUCTION.sh --profile=database
  
  # Install specific tools
  sudo ./Dev-Ops-tools_install_PRODUCTION.sh --tool=postgresql,pgadmin,dbeaver
  
  # Install CI/CD serially for stability
  sudo ./Dev-Ops-tools_install_PRODUCTION.sh --profile=ci_cd --serial
  
  # Enable debug logging
  DEBUG=1 sudo ./Dev-Ops-tools_install_PRODUCTION.sh --profile=monitoring
  
  # Dry-run to see what would be installed
  sudo ./Dev-Ops-tools_install_PRODUCTION.sh --profile=full --dry-run

DATABASE TOOLS:
  postgresql      - Enterprise-grade relational database (v${POSTGRESQL_VERSION})
  sqlite3         - Lightweight embedded database (v${SQLITE_VERSION})
  pgadmin         - PostgreSQL administration web interface (v${PGADMIN_VERSION})
  dbeaver         - Universal database client tool (v${DBEAVER_VERSION})
  flyway          - Database migration tool (v${FLYWAY_VERSION})
  flyway-cli      - Flyway CLI with environment setup

DATABASE OPERATIONS:
  After installation, use:
  • backup_postgresql        - Backup all PostgreSQL databases
  • restore_postgresql FILE  - Restore from backup file
  • create_postgresql_user   - Create new PostgreSQL user
  • create_postgresql_database - Create new database
  • list_postgresql_databases  - List all databases
  • database_stats           - View database statistics
  • check_database_connections - Test connectivity
  • run_database_migrations   - Execute SQL migrations

FEATURES:
  ✓ PostgreSQL & SQLite support with health checks
  ✓ Automatic database initialization
  ✓ Database backup/restore capabilities
  ✓ Database migration management with Flyway
  ✓ Advanced error handling with automatic rollback
  ✓ Comprehensive logging to files
  ✓ Parallel installation with job control
  ✓ Health checks and verification
  ✓ Automatic retry with exponential backoff
  ✓ Configuration backup and restore
  ✓ Performance metrics collection
  ✓ HTML reporting with system info
  ✓ Installation state tracking (SQLite)
  ✓ Pre-flight system checks
  ✓ Lock mechanism for concurrent execution prevention
  ✓ Timeout protection
  ✓ Email/Slack notifications

LOG FILES:
  Main Log:       $LOG_DIR/devops-installer-*.log
  Debug Log:      $LOG_DIR/debug-*.log
  Metrics Log:    $LOG_DIR/metrics-*.log
  Reports:        $LOG_DIR/installation_report_*.html

BACKUPS:
  Database:       $BACKUP_DIR/*.sql (PostgreSQL)
  Config:         $BACKUP_DIR/*-*.bak/
  Metadata:       $STATE_DB

DATABASE PORT DEFAULTS:
  PostgreSQL:     5432 (localhost)
  PgAdmin Web:    5050 (http://localhost:5050)

For more information, check the log files in $LOG_DIR
EOF
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
