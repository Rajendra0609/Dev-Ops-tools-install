#!/bin/bash

set -e

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."; exit 1
fi

# Handle --help option
if [[ "$1" == "--help" ]]; then
  echo "Usage: ./installer.sh [options]"
  echo "Options:"
  echo "  --profile=NAME         Use a saved profile"
  echo "  --tool=TOOL           Install specific tool"
  echo "  --version=VERSION     Override tool version"
  echo "  --offline             Use offline packages"
  echo "  --remote=USER@HOST    Install on remote machine"
  echo "  --dry-run             Show planned actions only"
  echo "  --help                Show this help menu"
  exit 0
fi

# Tool Versions (as of May 2026, update below for latest)
KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
TERRAFORM_VERSION="1.15.7"
JENKINS_REPO="https://pkg.jenkins.io"
AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
GOOGLE_CLOUD_SDK_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-574.0.0-linux-x86_64.tar.gz"
HELM_SCRIPT="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"
GRAFANA_DEB_URL="https://dl.grafana.com/oss/release/grafana_13.1.0_amd64.deb"
GRAFANA_RPM_URL="https://dl.grafana.com/oss/release/grafana-13.1.0-1.x86_64.rpm"
PROMETHEUS_VERSION="3.12.0"
NODE_EXPORTER_VERSION="1.11.1"
MAVEN_VERSION="3.9.16"
GRADLE_VERSION="9.6.1"
DEPENDENCY_CHECK_VERSION="12.2.2"
PACKER_VERSION="1.15.4"
VAGRANT_VERSION="2.4.9"
ISTIO_VERSION="1.30.2"

clear
echo "############################################################################"
echo "#          DevOps Tool Installer/Uninstaller by RajaChowdary tech          #"
echo "############################################################################"
echo ""
echo "Automate the installation and uninstallation of essential DevOps tools on your Linux machine."
echo "Choose from a wide range of tools and get started quickly and easily."
echo ""

show_tool_profiles() {
  echo "Available tool group presets:"
  for profile in "${!tool_group_presets[@]}"; do
    echo "- $profile: ${tool_group_presets[$profile]}"
  done
}

get_linux_distribution() {
  echo "Select your Linux distribution:"
  echo "1. Ubuntu/Debian"
  echo "2. CentOS/RHEL"
  echo "3. Fedora"
  read -p "Enter the number corresponding to your distribution: " distro_choice

  case $distro_choice in
    1) DISTRO="ubuntu";;
    2) DISTRO="centos";;
    3) DISTRO="fedora";;
    *) echo "Invalid Linux distribution choice. Exiting." && exit 1;;
  esac
}

declare -A tool_images=(
  [docker]="https://www.docker.com/wp-content/uploads/2022/03/Moby-logo.png"
  [kubectl]="https://upload.wikimedia.org/wikipedia/commons/6/67/Kubernetes_logo.svg"
  [ansible]="https://upload.wikimedia.org/wikipedia/commons/2/24/Ansible_logo.svg"
  [terraform]="https://www.terraform.io/assets/images/og-image-8b3e4f7d.png"
  [jenkins]="https://www.jenkins.io/images/logos/jenkins/jenkins.png"
  [awscli]="https://a0.awsstatic.com/libra-css/images/logos/aws_logo_smile_1200x630.png"
  [azurecli]="https://azurecomcdn.azureedge.net/cvt-2e04e6e5d47e0e2a68b8b3ff2a9f7a4e62db8d3a993e3b9e5ac66dcd8e9c9813/images/page/services/cli/cli-og.png"
  [gcloud]="https://cloud.google.com/images/products/logo-gcloud.png"
  [helm]="https://helm.sh/img/helm.svg"
  [grafana]="https://grafana.com/static/img/menu/grafana2.svg"
  [gitlab-runner]="https://about.gitlab.com/images/press/logo/png/gitlab-icon-rgb.png"
  [vault]="https://www.vaultproject.io/assets/images/logo-vault-861c1c7f.svg"
  [consul]="https://www.consul.io/assets/images/logo-consul-8cbbfc6b.svg"
  [istio]="https://istio.io/latest/favicons/android-chrome-192x192.png"
  [openshift]="https://www.openshift.com/themes/custom/openshift/images/openshift-logo.svg"
  [minikube]="https://minikube.sigs.k8s.io/docs/images/logo.png"
  [packer]="https://www.packer.io/assets/images/og-image-8b3e4f7d.png"
  [vagrant]="https://www.vagrantup.com/assets/images/og-image.png"
  [lynis]="https://cisofy.com/images/lynis-logo.png"
  [maven]="https://maven.apache.org/images/maven-logo-black-on-white.png"
  [gradle]="https://gradle.org/images/gradle-phantom.svg"
  [dependency-check]="https://jeremylong.github.io/DependencyCheck/images/DependencyCheck_Logo.png"
  [java]="https://upload.wikimedia.org/wikipedia/en/3/30/Java_programming_language_logo.svg"
  [git]="https://git-scm.com/images/logos/downloads/Git-Logo-2Color.png"
)

declare -A version_commands=(
  [docker]="docker --version"
  [kubectl]="kubectl version --client --short"
  [ansible]="ansible --version | head -n1"
  [terraform]="terraform version | head -n1"
  [jenkins]="jenkins --version || echo 'Check via: systemctl status jenkins'"
  [awscli]="aws --version"
  [azurecli]="az version"
  [gcloud]="gcloud --version | head -n1"
  [helm]="helm version --short"
  [grafana]="grafana-server -v"
  [gitlab-runner]="gitlab-runner --version"
  [vault]="vault version"
  [consul]="consul version"
  [istio]="istioctl version --short"
  [openshift]="oc version --client"
  [minikube]="minikube version"
  [packer]="packer version"
  [vagrant]="vagrant --version"
  [lynis]="lynis --version"
  [maven]="mvn -version | head -n1"
  [gradle]="gradle --version | grep Gradle"
  [dependency-check]="/opt/dependency-check/bin/dependency-check.sh --version"
  [java]="java -version 2>&1 | head -n 1"
  [git]="git --version"
)

# Tool Group Presets (Roles/Profiles)
declare -A tool_group_presets=(
  [ci_cd]="jenkins git maven gradle"
  [k8s]="kubectl helm minikube istio openshift"
  [cloud]="awscli azurecli gcloud"
  [monitoring]="grafana prometheus node_exporter"
  [infra]="terraform packer vagrant ansible"
)

install_tool() {
  local tool_name="$1"
  local install_cmd="$2"
  echo "Installing $tool_name..."
  eval "$install_cmd"
  echo "$tool_name installed successfully."
  echo "For more options, run with --help."
  if [[ -n "${version_commands[$tool_name]}" ]]; then
    echo "Installed version of $tool_name:"
    eval "${version_commands[$tool_name]}"
  fi
}

uninstall_tool() {
  local tool_name="$1"
  local uninstall_cmd="$2"
  echo "Uninstalling $tool_name..."
  eval "$uninstall_cmd"
  echo "$tool_name uninstalled successfully."
  if [[ -n "${version_commands[$tool_name]}" ]]; then
    echo "Version info for $tool_name after uninstall (if any):"
    eval "${version_commands[$tool_name]}"
  fi
}

# Distro-specific installs
declare -A install_commands_ubuntu=(
  [docker]="sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg && sudo install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io"
  [terraform]="sudo apt-get update && sudo apt-get install software-properties-common gnupg2 -y && curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - && sudo apt-add-repository \"deb [arch=$(dpkg --print-architecture)] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" && sudo apt-get update -y && sudo apt-get install terraform -y && terraform --version"
  [grafana]="wget $GRAFANA_DEB_URL && sudo dpkg -i $(basename $GRAFANA_DEB_URL) && sudo apt-get install -f -y && rm $(basename $GRAFANA_DEB_URL)"
  [jenkins]="sudo mkdir -p /etc/apt/keyrings && sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key && echo \"deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/\" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null && sudo apt update && sudo apt install -y fontconfig openjdk-21-jre jenkins"
  [ansible]="sudo apt-get update && sudo apt-get install software-properties-common && sudo apt-add-repository ppa:ansible/ansible && sudo apt-get install -y ansible"
  [lynis]="sudo apt-get update && sudo apt-get install -y lynis"
  [azurecli]="curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
  [java]="echo 'java will be handled dynamically'"
  [git]="sudo apt-get update && sudo apt-get install -y git"
)
declare -A uninstall_commands_ubuntu=(
  [docker]="sudo apt-get remove -y docker-ce docker-ce-cli containerd.io && sudo apt-get purge -y docker-ce docker-ce-cli containerd.io && sudo rm -rf /var/lib/docker"
  [grafana]="sudo apt-get remove -y grafana && sudo apt-get purge -y grafana"
  [jenkins]="sudo apt-get remove -y jenkins && sudo apt-get purge -y jenkins"
  [ansible]="sudo apt-get remove -y ansible && sudo apt-get purge -y ansible"
  [lynis]="sudo apt-get remove -y lynis && sudo apt-get purge -y lynis"
  [azurecli]="sudo apt-get remove -y azure-cli && sudo apt-get purge -y azure-cli"
  [java]="echo 'java will be handled dynamically'"
  [git]="sudo apt-get remove -y git && sudo apt-get purge -y git"
)

declare -A install_commands_centos=(
  [docker]="sudo yum install -y yum-utils && sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo && sudo yum install -y docker-ce docker-ce-cli containerd.io && sudo systemctl enable --now docker"
  [grafana]="wget $GRAFANA_RPM_URL && sudo yum install -y $(basename $GRAFANA_RPM_URL) && rm $(basename $GRAFANA_RPM_URL)"
  [jenkins]="sudo yum install -y fontconfig java-21-openjdk && sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/rpm-stable/jenkins.repo && sudo yum upgrade && sudo yum install -y jenkins && sudo systemctl enable --now jenkins"
  [ansible]="sudo yum install -y epel-release && sudo yum install -y ansible"
  [lynis]="sudo yum install -y epel-release && sudo yum install -y lynis"
  [azurecli]="sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && sudo sh -c 'echo -e \"[azure-cli]\\nname=Azure CLI\\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\\nenabled=1\\ngpgcheck=1\\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\" > /etc/yum.repos.d/azure-cli.repo' && sudo yum install -y azure-cli"
  [java]="echo 'java will be handled dynamically'"
  [git]="sudo yum install -y git"
)
declare -A uninstall_commands_centos=(
  [docker]="sudo yum remove -y docker-ce docker-ce-cli containerd.io && sudo rm -rf /var/lib/docker"
  [grafana]="sudo yum remove -y grafana"
  [jenkins]="sudo yum remove -y jenkins"
  [ansible]="sudo yum remove -y ansible"
  [lynis]="sudo yum remove -y lynis"
  [azurecli]="sudo yum remove -y azure-cli"
  [java]="echo 'java will be handled dynamically'"
  [git]="sudo yum remove -y git"
)

declare -A install_commands_fedora=(
  [docker]="sudo dnf -y install dnf-plugins-core && sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo && sudo dnf install -y docker-ce docker-ce-cli containerd.io && sudo systemctl enable --now docker"
  [grafana]="wget $GRAFANA_RPM_URL && sudo dnf install -y $(basename $GRAFANA_RPM_URL) && rm $(basename $GRAFANA_RPM_URL)"
  [jenkins]="sudo dnf install -y fontconfig java-17-openjdk && sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo && sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key && sudo dnf install -y jenkins && sudo systemctl enable --now jenkins"
  [ansible]="sudo dnf install -y ansible"
  [lynis]="sudo dnf install -y lynis"
  [azurecli]="sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && sudo sh -c 'echo -e \"[azure-cli]\\nname=Azure CLI\\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\\nenabled=1\\ngpgcheck=1\\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\" > /etc/yum.repos.d/azure-cli.repo' && sudo dnf install -y azure-cli"
  [java]="echo 'java will be handled dynamically'"
  [git]="sudo dnf install -y git"
)
declare -A uninstall_commands_fedora=(
  [docker]="sudo dnf remove -y docker-ce docker-ce-cli containerd.io && sudo rm -rf /var/lib/docker"
  [grafana]="sudo dnf remove -y grafana"
  [jenkins]="sudo dnf remove -y jenkins"
  [ansible]="sudo dnf remove -y ansible"
  [lynis]="sudo dnf remove -y lynis"
  [azurecli]="sudo dnf remove -y azure-cli"
  [java]="echo 'java will be handled dynamically'"
  [git]="sudo dnf remove -y git"
)

# Cross-distro binary installs
declare -A binary_installs=(
  [kubectl]="curl -LO https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl && chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/"
  [awscli]="curl \"$AWS_CLI_URL\" -o \"awscliv2.zip\" && unzip awscliv2.zip && sudo ./aws/install && rm -rf awscliv2.zip aws/"
  [gcloud]="curl -O $GOOGLE_CLOUD_SDK_URL && tar -xvzf google-cloud-sdk-574.0.0-linux-x86_64.tar.gz && ./google-cloud-sdk/install.sh"
  [helm]="curl -fsSL -o get_helm.sh $HELM_SCRIPT && chmod 700 get_helm.sh && ./get_helm.sh"
  [prometheus]="curl -LO https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && tar xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/ && sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/ && rm -rf prometheus-${PROMETHEUS_VERSION}.linux-amd64*"
  [node_exporter]="curl -LO https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && tar xvf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ && rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*"
  [maven]="curl -LO https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz && sudo tar -xzf apache-maven-${MAVEN_VERSION}-bin.tar.gz -C /opt && sudo ln -sf /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn && rm apache-maven-${MAVEN_VERSION}-bin.tar.gz"
  [gradle]="curl -LO https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip && sudo unzip gradle-${GRADLE_VERSION}-bin.zip -d /opt && sudo ln -sf /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle && rm gradle-${GRADLE_VERSION}-bin.zip"
  [dependency-check]="curl -LO https://github.com/jeremylong/DependencyCheck/releases/download/v${DEPENDENCY_CHECK_VERSION}/dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip && unzip dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip && sudo mv dependency-check /opt/ && sudo ln -sf /opt/dependency-check/bin/dependency-check.sh /usr/local/bin/dependency-check && rm dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip"
  [gitlab-runner]="sudo curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64 && sudo chmod +x /usr/local/bin/gitlab-runner"
  [vault]="curl -LO https://releases.hashicorp.com/vault/2.0.3/vault_2.0.3_linux_amd64.zip && unzip vault_2.0.3_linux_amd64.zip && sudo mv vault /usr/local/bin/ && rm vault_2.0.3_linux_amd64.zip"
  [consul]="curl -LO https://releases.hashicorp.com/consul/2.0.1/consul_2.0.1_linux_amd64.zip && unzip consul_2.0.1_linux_amd64.zip && sudo mv consul /usr/local/bin/ && rm consul_2.0.1_linux_amd64.zip"
  [istio]="curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh - && sudo mv istio-$ISTIO_VERSION/bin/istioctl /usr/local/bin/"
  [openshift]="curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz && tar -xvf openshift-client-linux.tar.gz && sudo mv oc /usr/local/bin/ && sudo mv kubectl /usr/local/bin/"
  [minikube]="curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64"
  [packer]="curl -LO https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip && unzip packer_${PACKER_VERSION}_linux_amd64.zip && sudo mv packer /usr/local/bin/ && rm packer_${PACKER_VERSION}_linux_amd64.zip"
  [vagrant]="curl -LO https://releases.hashicorp.com/vagrant/$VAGRANT_VERSION/vagrant_${VAGRANT_VERSION}_linux_amd64.zip && unzip vagrant_${VAGRANT_VERSION}_linux_amd64.zip && sudo mv vagrant /usr/local/bin/ && rm vagrant_${VAGRANT_VERSION}_linux_amd64.zip"
)

declare -A binary_uninstalls=(
  [kubectl]="sudo rm /usr/local/bin/kubectl"
  [terraform]="sudo rm /usr/local/bin/terraform"
  [awscli]="sudo rm /usr/local/bin/aws && sudo rm -rf /usr/local/aws-cli"
  [gcloud]="sudo rm -rf google-cloud-sdk"
  [helm]="sudo rm /usr/local/bin/helm"
  [prometheus]="sudo rm /usr/local/bin/prometheus /usr/local/bin/promtool"
  [node_exporter]="sudo rm /usr/local/bin/node_exporter"
  [maven]="sudo rm /usr/local/bin/mvn && sudo rm -rf /opt/apache-maven-*"
  [gradle]="sudo rm /usr/local/bin/gradle && sudo rm -rf /opt/gradle-*"
  [dependency-check]="sudo rm /usr/local/bin/dependency-check && sudo rm -rf /opt/dependency-check"
  [gitlab-runner]="sudo rm /usr/local/bin/gitlab-runner"
  [vault]="sudo rm /usr/local/bin/vault"
  [consul]="sudo rm /usr/local/bin/consul"
  [istio]="sudo rm /usr/local/bin/istioctl"
  [openshift]="sudo rm /usr/local/bin/oc && sudo rm /usr/local/bin/kubectl"
  [minikube]="sudo rm /usr/local/bin/minikube"
  [packer]="sudo rm /usr/local/bin/packer"
  [vagrant]="sudo rm /usr/local/bin/vagrant"
)

# Phase 3: Advanced Tool Management
check_dependencies() {
  local deps=(curl unzip gnupg whiptail)
  for dep in "${deps[@]}"; do
    if ! command -v $dep &>/dev/null; then
      echo "$dep is missing. Installing..."
      case "$DISTRO" in
        ubuntu) sudo apt-get install -y $dep;;
        centos) sudo yum install -y $dep;;
        fedora) sudo dnf install -y $dep;;
      esac
    fi
  done
}

# Post-Install Configuration (stub)
post_install_config() {
  echo "Running post-install configuration..."
  # Add post-install steps here (e.g., enable/start services, set env vars)
}

# Generate Setup Report
generate_setup_report() {
  echo "\n######### Setup Report #########"
  for tool in $selected_tools; do
    if [[ -n "${version_commands[$tool]}" ]]; then
      echo -n "$tool: "
      eval "${version_commands[$tool]}"
    fi
  done
  echo "###############################\n"
}

# Parallel Install (Much faster in bulk)
parallel_install_tools() {
  local tools=("$@")
  local pids=()
  for tool in "${tools[@]}"; do
    (
      if [[ -v install_commands_ubuntu["$tool"] && "$DISTRO" == "ubuntu" ]]; then
        eval "${install_commands_ubuntu[$tool]}"
      elif [[ -v install_commands_centos["$tool"] && "$DISTRO" == "centos" ]]; then
        eval "${install_commands_centos[$tool]}"
      elif [[ -v install_commands_fedora["$tool"] && "$DISTRO" == "fedora" ]]; then
        eval "${install_commands_fedora[$tool]}"
      fi
      if [[ -v binary_installs["$tool"] ]]; then
        eval "${binary_installs[$tool]}"
      fi
      if [[ -n "${version_commands[$tool]}" ]]; then
        echo "Installed version of $tool:"
        eval "${version_commands[$tool]}"
      fi
    ) &
    pids+=("$!")
  done
  # Wait for all installs to finish
  for pid in "${pids[@]}"; do
    wait $pid
  done
}

read -p "Do you want to install or uninstall tools? (install/uninstall): " action
if [[ "$action" != "install" && "$action" != "uninstall" ]]; then
  echo "Invalid action selected. Exiting."
  exit 1
fi

get_linux_distribution

check_dependencies

# Show tool group presets first
show_tool_profiles
read -p "Do you want to use a tool group preset? (Enter preset name or leave blank): " preset_choice
if [[ -n "$preset_choice" && -n "${tool_group_presets[$preset_choice]}" ]]; then
  selected_tools="${tool_group_presets[$preset_choice]}"
  echo "Selected preset: $preset_choice -> $selected_tools"
else
  echo "Select tools to $action (separate with spaces):"
  for tool in "${!install_commands_ubuntu[@]}" "${!binary_installs[@]}"; do
    echo "- $tool"
  done
  read -p "Your selection: " selected_tools
  if [[ -z "$selected_tools" ]]; then
    echo "No tools selected. Exiting."
    exit 1
  fi
  for tool in $selected_tools; do
    if [[ ! -v install_commands_ubuntu["$tool"] && ! -v binary_installs["$tool"] ]]; then
      echo "Unknown tool: $tool"
      exit 1
    fi
  done
fi

# Prompt for Java version if java is selected
if [[ "$selected_tools" == *java* ]]; then
  echo "Select Java version to install:"
  echo "1. Java 21 (latest LTS)"
  echo "2. Java 17 (LTS)"
  echo "3. Java 11 (LTS)"
  read -p "Enter the number corresponding to your desired Java version [1/2/3, default: 1]: " java_choice
  java_choice=${java_choice:-1}
  case $java_choice in
    1) JAVA_VERSION=21;;
    2) JAVA_VERSION=17;;
    3) JAVA_VERSION=11;;
    *) echo "Invalid Java version choice. Exiting." && exit 1;;
  esac
  install_commands_ubuntu[java]="sudo apt-get update && sudo apt-get install -y openjdk-${JAVA_VERSION}-jdk"
  uninstall_commands_ubuntu[java]="sudo apt-get remove -y openjdk-${JAVA_VERSION}-jdk && sudo apt-get purge -y openjdk-${JAVA_VERSION}-jdk"
  install_commands_centos[java]="sudo yum install -y java-${JAVA_VERSION}-openjdk-devel"
  uninstall_commands_centos[java]="sudo yum remove -y java-${JAVA_VERSION}-openjdk && sudo yum remove -y java-${JAVA_VERSION}-openjdk-devel"
  install_commands_fedora[java]="sudo dnf install -y java-${JAVA_VERSION}-openjdk-devel"
  uninstall_commands_fedora[java]="sudo dnf remove -y java-${JAVA_VERSION}-openjdk && sudo dnf remove -y java-${JAVA_VERSION}-openjdk-devel"
fi

if [[ "$action" == "install" ]]; then
  for tool in $selected_tools; do
    case "$DISTRO" in
      ubuntu)
        [[ -v install_commands_ubuntu["$tool"] ]] && install_tool "$tool" "${install_commands_ubuntu[$tool]}"
        ;;
      centos)
        [[ -v install_commands_centos["$tool"] ]] && install_tool "$tool" "${install_commands_centos[$tool]}"
        ;;
      fedora)
        [[ -v install_commands_fedora["$tool"] ]] && install_tool "$tool" "${install_commands_fedora[$tool]}"
        ;;
    esac
    if [[ -v binary_installs["$tool"] ]]; then
      install_tool "$tool" "${binary_installs[$tool]}"
    fi
  done
elif [[ "$action" == "uninstall" ]]; then
  for tool in $selected_tools; do
    case "$DISTRO" in
      ubuntu)
        [[ -v uninstall_commands_ubuntu["$tool"] ]] && uninstall_tool "$tool" "${uninstall_commands_ubuntu[$tool]}"
        ;;
      centos)
        [[ -v uninstall_commands_centos["$tool"] ]] && uninstall_tool "$tool" "${uninstall_commands_centos[$tool]}"
        ;;
      fedora)
        [[ -v uninstall_commands_fedora["$tool"] ]] && uninstall_tool "$tool" "${uninstall_commands_fedora[$tool]}"
        ;;
    esac
    if [[ -v binary_uninstalls["$tool"] ]]; then
      uninstall_tool "$tool" "${binary_uninstalls[$tool]}"
    fi
  done
fi

echo "Operation completed successfully."

post_install_config
generate_setup_report

exit 0

# Tool Profiles (presets) Speeds up selection
show_tool_profiles() {
  echo "Available tool group presets:"
  for profile in "${!tool_group_presets[@]}"; do
    echo "- $profile: ${tool_group_presets[$profile]}"
  done
}

# Post-Install Configuration (stub)
post_install_config() {
  echo "Running post-install configuration..."
  # Add post-install steps here (e.g., enable/start services, set env vars)
}

# Update/Upgrade Option
update_upgrade_tools() {
  echo "Updating and upgrading system packages..."
  case "$DISTRO" in
    ubuntu)
      sudo apt-get update && sudo apt-get upgrade -y
      ;;
    centos)
      sudo yum update -y
      ;;
    fedora)
      sudo dnf upgrade --refresh -y
      ;;
  esac
}

# Generate Setup Report
generate_setup_report() {
  echo "\n######### Setup Report #########"
  for tool in $selected_tools; do
    if [[ -n "${version_commands[$tool]}" ]]; then
      echo -n "$tool: "
      eval "${version_commands[$tool]}"
    fi
  done
  echo "###############################\n"
}

# Prompt for tool group preset selection

# Update/Upgrade prompt
read -p "Do you want to update/upgrade system packages before install? (y/n): " update_choice
if [[ "$update_choice" == "y" ]]; then
  update_upgrade_tools
fi

# ...existing code...
# --- Full Automation Implementation ---
# Phase 2: Automation & Config Management
CONFIG_FILE=".devops-installer-config"
save_config() {
  echo "DISTRO=$DISTRO" > "$CONFIG_FILE"
  echo "TOOLS=$selected_tools" >> "$CONFIG_FILE"
  echo "PARALLEL=$parallel_choice" >> "$CONFIG_FILE"
  echo "Saved configuration to $CONFIG_FILE."
}
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    DISTRO="${DISTRO:-ubuntu}"
    selected_tools="${TOOLS:-}" 
    parallel_choice="${PARALLEL:-n}"
    echo "Loaded configuration from $CONFIG_FILE."
  fi
}

# Phase 3: Advanced Tool Management
check_dependencies() {
  local deps=(curl unzip gnupg whiptail software-properties-common wget tar zip jq apt-transport-https ca-certificates)
  for dep in "${deps[@]}"; do
    if ! command -v $dep &>/dev/null; then
      echo "$dep is missing. Installing..."
      case "$DISTRO" in
        ubuntu) sudo apt-get update && sudo apt-get install -y $dep;;
        centos) sudo yum install -y $dep;;
        fedora) sudo dnf install -y $dep;;
      esac
    fi
  done
}

update_tool() {
  local tool="$1"
  if [[ -v binary_installs["$tool"] ]]; then
    echo "Updating $tool (binary)..."
    eval "${binary_installs[$tool]}"
  elif [[ -v install_commands_ubuntu["$tool"] && "$DISTRO" == "ubuntu" ]]; then
    echo "Updating $tool (package)..."
    sudo apt-get install --only-upgrade -y $tool
  elif [[ -v install_commands_centos["$tool"] && "$DISTRO" == "centos" ]]; then
    sudo yum update -y $tool
  elif [[ -v install_commands_fedora["$tool"] && "$DISTRO" == "fedora" ]]; then
    sudo dnf upgrade -y $tool
  fi
}

rollback_on_failure() {
  local tool="$1"
  echo "Rolling back failed install for $tool..."
  cleanup_tool "$tool"
}

# Phase 4: Security & Permissions
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root or with sudo."; exit 1
  fi
}

verify_checksum() {
  local file="$1"; local checksum="$2"
  if [[ -f "$file" ]]; then
    local actual=$(sha256sum "$file" | awk '{print $1}')
    if [[ "$actual" == "$checksum" ]]; then
      echo "Checksum verified for $file."
    else
      echo "Checksum mismatch for $file!"; exit 1
    fi
  fi
}

dry_run() {
  echo "Dry run mode: showing planned actions only."
  echo "Tools to be installed: $selected_tools"
  echo "Distro: $DISTRO"
  echo "Parallel: $parallel_choice"
}

# Phase 5: Remote/Cloud Support
remote_install() {
  local remote="$1"; shift
  local tools="$@"
  echo "Installing on remote $remote: $tools"
  ssh $remote 'bash -s' < "$0" --tool="$tools"
}

dockerized_installer() {
  echo "Running installer in Docker container..."
  docker run --rm -v $(pwd):/workspace -w /workspace ubuntu:latest bash "$0"
}

# Phase 6: Testing, Debugging, Analytics
LOG_FILE="installer.log"
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

telemetry_opt_in=0
send_telemetry() {
  if [[ $telemetry_opt_in -eq 1 ]]; then
    echo "Sending anonymous telemetry..."
    # Example: curl -X POST ...
  fi
}

# Phase 7: Smart Recommendations
recommend_tools() {
  echo "What is your role?"
  echo "1. DevOps Engineer"
  echo "2. SRE"
  echo "3. Cloud Architect"
  read -p "Enter number: " role_choice
  case $role_choice in
    1) echo "Recommended: ${tool_group_presets[ci_cd]} ${tool_group_presets[infra]}";;
    2) echo "Recommended: ${tool_group_presets[monitoring]} ${tool_group_presets[k8s]}";;
    3) echo "Recommended: ${tool_group_presets[cloud]} ${tool_group_presets[k8s]}";;
  esac
}

# Phase 8: System Cleanup & Optimization
cleanup_tool() {
  local tool="$1"
  echo "Cleaning up $tool config and services..."
  case "$tool" in
    terraform) rm -rf ~/.terraform.d;;
    kubectl) rm -rf ~/.kube;;
    helm) rm -rf ~/.helm;;
    grafana) sudo systemctl stop grafana-server; sudo systemctl disable grafana-server;;
    jenkins) sudo systemctl stop jenkins; sudo systemctl disable jenkins;;
    docker) sudo systemctl stop docker; sudo systemctl disable docker;;
  esac
}

estimate_disk_space() {
  echo "Estimating disk space..."
  df -h .
}

# Phase 9: Documentation & Help
generate_markdown_report() {
  local mdfile="setup_report.md"
  echo "# Setup Report" > "$mdfile"
  echo "## Tools Installed" >> "$mdfile"
  for tool in $selected_tools; do
    echo "- $tool: $(${version_commands[$tool]})" >> "$mdfile"
  done
  echo "## System Info" >> "$mdfile"
  uname -a >> "$mdfile"
  echo "## Services Started" >> "$mdfile"
  for svc in docker jenkins grafana-server; do
    if systemctl is-active --quiet $svc; then
      echo "- $svc: active" >> "$mdfile"
    fi
  done
  echo "Report generated at $mdfile."
}

show_help() {
  echo "Usage: ./installer.sh [options]"
  echo "Options:"
  echo "  --profile=NAME         Use a saved profile"
  echo "  --tool=TOOL           Install specific tool"
  echo "  --version=VERSION     Override tool version"
  echo "  --offline             Use offline packages"
  echo "  --remote=USER@HOST    Install on remote machine"
  echo "  --dry-run             Show planned actions only"
  echo "  --help                Show this help menu"
}
# =============================
# Phase 2: Automation & Config Management
# =============================
CONFIG_FILE=".devops-installer-config"
save_config() {
  echo "DISTRO=$DISTRO" > "$CONFIG_FILE"
  echo "TOOLS=$selected_tools" >> "$CONFIG_FILE"
  echo "Saved configuration to $CONFIG_FILE."
}
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    DISTRO="${DISTRO:-ubuntu}"
    selected_tools="${TOOLS:-}" 
    echo "Loaded configuration from $CONFIG_FILE."
  fi
}

# CLI args for profile/tool/version override
for arg in "$@"; do
  case $arg in
    --profile=*)
      profile_name="${arg#*=}"
      if [[ -n "${tool_group_presets[$profile_name]}" ]]; then
        selected_tools="${tool_group_presets[$profile_name]}"
        echo "Profile override: $profile_name -> $selected_tools"
      fi
      ;;
    --tool=*)
      tool_override="${arg#*=}"
      selected_tools="$tool_override"
      ;;
    --version=*)
      version_override="${arg#*=}"
      # Example: override terraform version
      TERRAFORM_VERSION="$version_override"
      ;;
    --offline)
      OFFLINE_MODE=1
      ;;
  esac
done

# Offline Mode
use_offline_package() {
  local tool="$1"
  local pkg_dir="./packages"
  if [[ -d "$pkg_dir" ]]; then
    echo "Using offline package for $tool from $pkg_dir."
    # Add logic to use pre-downloaded files
  fi
}

# =============================
# Phase 3: Advanced Tool Management
# =============================
update_tool() {
  local tool="$1"
  echo "Updating $tool..."
  # Add update logic for each tool
}
check_dependencies() {
  local deps=(curl unzip gnupg)
  for dep in "${deps[@]}"; do
    if ! command -v $dep &>/dev/null; then
      echo "$dep is missing. Installing..."
      case "$DISTRO" in
        ubuntu) sudo apt-get install -y $dep;;
        centos) sudo yum install -y $dep;;
        fedora) sudo dnf install -y $dep;;
      esac
    fi
  done
}
validate_service() {
  local svc="$1"
  echo "Validating service $svc..."
  sudo systemctl status $svc
  sudo netstat -tulnp | grep $(sudo systemctl show -p MainPID --value $svc)
}

# =============================
# Phase 4: Security & Permissions
# =============================
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root or with sudo."; exit 1
  fi
}
verify_checksum() {
  local file="$1"; local checksum="$2"
  echo "Verifying checksum for $file..."
  sha256sum "$file"
  # Compare with expected $checksum
}
dry_run() {
  echo "Dry run mode: showing planned actions only."
  # List planned actions
}

# =============================
# Phase 5: Remote/Cloud Support
# =============================
remote_install() {
  local remote="$1"; shift
  local tools="$@"
  echo "Installing on remote $remote: $tools"
  # Example: ssh $remote 'bash -s' < installer.sh --tool=... 
}
dockerized_installer() {
  echo "Running installer in Docker container..."
  # Add Dockerfile and run logic
}

# =============================
# Phase 6: Testing, Debugging, Analytics
# =============================
LOG_FILE="installer.log"
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
rollback_on_failure() {
  local tool="$1"
  echo "Rolling back failed install for $tool..."
  # Remove partial files
}
telemetry_opt_in=0
send_telemetry() {
  if [[ $telemetry_opt_in -eq 1 ]]; then
    echo "Sending anonymous telemetry..."
    # Add logic to send data
  fi
}

# =============================
# Phase 7: Smart Recommendations
# =============================
recommend_tools() {
  echo "What is your role?"
  echo "1. DevOps Engineer"
  echo "2. SRE"
  echo "3. Cloud Architect"
  read -p "Enter number: " role_choice
  case $role_choice in
    1) echo "Recommended: ${tool_group_presets[ci_cd]} ${tool_group_presets[infra]}";;
    2) echo "Recommended: ${tool_group_presets[monitoring]} ${tool_group_presets[k8s]}";;
    3) echo "Recommended: ${tool_group_presets[cloud]} ${tool_group_presets[k8s]}";;
  esac
}
# AI-based suggestions (stub)
ai_suggest_tools() {
  echo "AI-based tool suggestions coming soon..."
}

# =============================
# Phase 8: System Cleanup & Optimization
# =============================
cleanup_tool() {
  local tool="$1"
  echo "Cleaning up $tool config and services..."
  # Remove config dirs, systemd services
}
estimate_disk_space() {
  echo "Estimating disk space..."
  df -h .
}

# =============================
# Phase 9: Documentation & Help
# =============================
generate_markdown_report() {
  local mdfile="setup_report.md"
  echo "# Setup Report" > "$mdfile"
  echo "## Tools Installed" >> "$mdfile"
  for tool in $selected_tools; do
    echo "- $tool: $(${version_commands[$tool]})" >> "$mdfile"
  done
  echo "## System Info" >> "$mdfile"
  uname -a >> "$mdfile"
  echo "## Services Started" >> "$mdfile"
  # List started services
  echo "Report generated at $mdfile."
}
show_help() {
  echo "Usage: ./installer.sh [options]"
  echo "Options:"
  echo "  --profile=NAME         Use a saved profile"
  echo "  --tool=TOOL           Install specific tool"
  echo "  --version=VERSION     Override tool version"
  echo "  --offline             Use offline packages"
  echo "  --remote=USER@HOST    Install on remote machine"
  echo "  --dry-run             Show planned actions only"
  echo "  --help                Show this help menu"
}
# Parallel Install (Much faster in bulk)
parallel_install_tools() {
  local tools=("$@")
  local pids=()
  for tool in "${tools[@]}"; do
    (
      if [[ -v install_commands_ubuntu["$tool"] && "$DISTRO" == "ubuntu" ]]; then
        eval "${install_commands_ubuntu[$tool]}"
      elif [[ -v install_commands_centos["$tool"] && "$DISTRO" == "centos" ]]; then
        eval "${install_commands_centos[$tool]}"
      elif [[ -v install_commands_fedora["$tool"] && "$DISTRO" == "fedora" ]]; then
        eval "${install_commands_fedora[$tool]}"
      fi
      if [[ -v binary_installs["$tool"] ]]; then
        eval "${binary_installs[$tool]}"
      fi
      if [[ -n "${version_commands[$tool]}" ]]; then
        echo "Installed version of $tool:"
        eval "${version_commands[$tool]}"
      fi
    ) &
    pids+=("$!")
  done
  # Wait for all installs to finish
  for pid in "${pids[@]}"; do
    wait $pid
  done
}

# Enhanced Auto Config/Post Setup
auto_config_post_setup() {
  echo "Running enhanced auto configuration/post setup..."
  # Example: Enable/start Docker, Jenkins, Grafana, etc.
  if command -v docker &>/dev/null; then
    sudo systemctl enable docker
    sudo systemctl start docker
  fi
  if command -v jenkins &>/dev/null; then
    sudo systemctl enable jenkins
    sudo systemctl start jenkins
  fi
  if command -v grafana-server &>/dev/null; then
    sudo systemctl enable grafana-server
    sudo systemctl start grafana-server
  fi
  # Add more auto config steps as needed
}
# Prompt for parallel install
read -p "Do you want to install tools in parallel for faster bulk setup? (y/n): " parallel_choice
if [[ "$parallel_choice" == "y" ]]; then
  parallel_install_tools ${selected_tools}
else
  for tool in $selected_tools; do
    # ...existing code for sequential install...
    if [[ "$action" == "install" ]]; then
      case "$DISTRO" in
        ubuntu)
          [[ -v install_commands_ubuntu["$tool"] ]] && install_tool "$tool" "${install_commands_ubuntu[$tool]}"
          ;;
        centos)
          [[ -v install_commands_centos["$tool"] ]] && install_tool "$tool" "${install_commands_centos[$tool]}"
          ;;
        fedora)
          [[ -v install_commands_fedora["$tool"] ]] && install_tool "$tool" "${install_commands_fedora[$tool]}"
          ;;
      esac
      if [[ -v binary_installs["$tool"] ]]; then
        install_tool "$tool" "${binary_installs[$tool]}"
      fi
    elif [[ "$action" == "uninstall" ]]; then
      case "$DISTRO" in
        ubuntu)
          [[ -v uninstall_commands_ubuntu["$tool"] ]] && uninstall_tool "$tool" "${uninstall_commands_ubuntu[$tool]}"
          ;;
        centos)
          [[ -v uninstall_commands_centos["$tool"] ]] && uninstall_tool "$tool" "${uninstall_commands_centos[$tool]}"
          ;;
        fedora)
          [[ -v uninstall_commands_fedora["$tool"] ]] && uninstall_tool "$tool" "${uninstall_commands_fedora[$tool]}"
          ;;
      esac
      if [[ -v binary_uninstalls["$tool"] ]]; then
        uninstall_tool "$tool" "${binary_uninstalls[$tool]}"
      fi
    fi
  done
fi

auto_config_post_setup

post_install_config
generate_setup_report
