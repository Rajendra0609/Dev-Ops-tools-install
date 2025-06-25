#!/bin/bash

set -e

# Tool Versions (as of June 2025, update below for latest)
KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
TERRAFORM_VERSION="1.8.7"
JENKINS_REPO="https://pkg.jenkins.io"
AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
GOOGLE_CLOUD_SDK_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-479.0.0-linux-x86_64.tar.gz"
HELM_SCRIPT="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"
GRAFANA_DEB_URL="https://dl.grafana.com/oss/release/grafana_11.1.0_amd64.deb"
GRAFANA_RPM_URL="https://dl.grafana.com/oss/release/grafana-11.1.0-1.x86_64.rpm"
PROMETHEUS_VERSION="2.53.0"
NODE_EXPORTER_VERSION="1.8.2"
MAVEN_VERSION="3.9.8"
GRADLE_VERSION="8.8"
DEPENDENCY_CHECK_VERSION="9.1.0"
PACKER_VERSION="1.11.0"
VAGRANT_VERSION="2.4.2"
ISTIO_VERSION="1.24.0"

clear
echo "############################################################################"
echo "#          DevOps Tool Installer/Uninstaller by RajaChowdary tech          #"
echo "############################################################################"
echo ""
echo "Automate the installation and uninstallation of essential DevOps tools on your Linux machine."
echo "Choose from a wide range of tools and get started quickly and easily."
echo ""

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

install_tool() {
  local tool_name="$1"
  local install_cmd="$2"
  echo "Installing $tool_name..."
  eval "$install_cmd"
  echo "$tool_name installed successfully."
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
}

# Distro-specific installs
declare -A install_commands_ubuntu=(
  [docker]="sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg && sudo install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io"
  [grafana]="wget $GRAFANA_DEB_URL && sudo dpkg -i $(basename $GRAFANA_DEB_URL) && sudo apt-get install -f -y && rm $(basename $GRAFANA_DEB_URL)"
  [jenkins]="curl -fsSL $JENKINS_REPO/debian/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null && echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] $JENKINS_REPO/debian binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null && sudo apt-get update && sudo apt-get install -y fontconfig openjdk-17-jre jenkins"
  [ansible]="sudo apt-get update && sudo apt-get install -y ansible"
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
  [jenkins]="sudo yum install -y fontconfig java-17-openjdk && sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo && sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key && sudo yum install -y jenkins && sudo systemctl enable --now jenkins"
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
  [terraform]="curl -LO https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip && sudo mv terraform /usr/local/bin/ && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
  [awscli]="curl \"$AWS_CLI_URL\" -o \"awscliv2.zip\" && unzip awscliv2.zip && sudo ./aws/install && rm -rf awscliv2.zip aws/"
  [gcloud]="curl -O $GOOGLE_CLOUD_SDK_URL && tar -xvzf google-cloud-sdk-479.0.0-linux-x86_64.tar.gz && ./google-cloud-sdk/install.sh"
  [helm]="curl -fsSL -o get_helm.sh $HELM_SCRIPT && chmod 700 get_helm.sh && ./get_helm.sh"
  [prometheus]="curl -LO https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && tar xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/ && sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/ && rm -rf prometheus-${PROMETHEUS_VERSION}.linux-amd64*"
  [node_exporter]="curl -LO https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && tar xvf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ && rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*"
  [maven]="curl -LO https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz && sudo tar xzf apache-maven-${MAVEN_VERSION}-bin.tar.gz -C /opt && sudo ln -sf /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn && rm apache-maven-${MAVEN_VERSION}-bin.tar.gz"
  [gradle]="curl -LO https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip && sudo unzip gradle-${GRADLE_VERSION}-bin.zip -d /opt && sudo ln -sf /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle && rm gradle-${GRADLE_VERSION}-bin.zip"
  [dependency-check]="curl -LO https://github.com/jeremylong/DependencyCheck/releases/download/v${DEPENDENCY_CHECK_VERSION}/dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip && unzip dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip && sudo mv dependency-check /opt/ && sudo ln -sf /opt/dependency-check/bin/dependency-check.sh /usr/local/bin/dependency-check && rm dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip"
  [gitlab-runner]="sudo curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64 && sudo chmod +x /usr/local/bin/gitlab-runner"
  [vault]="curl -LO https://releases.hashicorp.com/vault/1.17.0/vault_1.17.0_linux_amd64.zip && unzip vault_1.17.0_linux_amd64.zip && sudo mv vault /usr/local/bin/ && rm vault_1.17.0_linux_amd64.zip"
  [consul]="curl -LO https://releases.hashicorp.com/consul/1.18.0/consul_1.18.0_linux_amd64.zip && unzip consul_1.18.0_linux_amd64.zip && sudo mv consul /usr/local/bin/ && rm consul_1.18.0_linux_amd64.zip"
  [istio]="curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh - && sudo mv istio-$ISTIO_VERSION/bin/istioctl /usr/local/bin/"
  [openshift]="curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz && tar -xvf openshift-client-linux.tar.gz && sudo mv oc /usr/local/bin/ && sudo mv kubectl /usr/local/bin/"
  [minikube]="curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64"
  [packer]="curl -LO https://releases.hashicorp.com/packer/$PACKER_VERSION/packer_$PACKER_VERSION_linux_amd64.zip && unzip packer_$PACKER_VERSION_linux_amd64.zip && sudo mv packer /usr/local/bin/ && rm packer_$PACKER_VERSION_linux_amd64.zip"
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

read -p "Do you want to install or uninstall tools? (install/uninstall): " action
if [[ "$action" != "install" && "$action" != "uninstall" ]]; then
  echo "Invalid action selected. Exiting."
  exit 1
fi

get_linux_distribution

echo "Select tools to $action (separate with spaces):"
for tool in "${!install_commands_ubuntu[@]}" "${!binary_installs[@]}"; do
  echo "- $tool"
done
read -p "Your selection: " selected_tools

JAVA_VERSION=""
for tool in $selected_tools; do
  # Prompt for Java version only if user selected java
  if [[ "$tool" == "java" && -z "$JAVA_VERSION" ]]; then
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

echo "Operation completed successfully."
