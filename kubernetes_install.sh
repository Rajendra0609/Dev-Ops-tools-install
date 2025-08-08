#!/bin/bash

# Function to set hostname
set_hostname() {
    sudo hostnamectl set-hostname $1
}

# Function to update /etc/hosts file
update_hosts_file() {
    sudo tee -a /etc/hosts > /dev/null <<EOL
$1 $2
EOL
}

# Function to set up Docker Engine and containerd
setup_docker() {
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    sudo sysctl --system

    sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update

    VERSION_STRING=5:23.0.1-1~ubuntu.20.04~focal
    sudo apt-get install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin

    sudo usermod -aG docker $USER

    sudo sed -i 's/disabled_plugins/#disabled_plugins/' /etc/containerd/config.toml

    sudo systemctl restart containerd
}

# Function to install Kubernetes components
install_kubernetes() {
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33.3/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33.3/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
}

# Main script

# Set hostnames
set_hostname "k8s-control"
set_hostname "k8s-worker1"
set_hostname "k8s-worker2"

# Update /etc/hosts file
update_hosts_file "<control plane node private IP>" "k8s-control"
update_hosts_file "<worker node 1 private IP>" "k8s-worker1"
update_hosts_file "<worker node 2 private IP>" "k8s-worker2"

# Setup Docker Engine and containerd
setup_docker

# Disable swap on all nodes
sudo swapoff -a

# Install Kubernetes components
install_kubernetes

# Initialize the cluster on control plane node
sudo kubeadm init --pod-network-cidr 192.168.0.0/16 --kubernetes-version 1.29.1

# Configure kubectl for current user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico network add-on
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.5/manifests/calico.yaml   ==> check for latest version.

# Get the join command
echo "Run the join command on each worker node as root:"
sudo kubeadm token create --print-join-command

# Verify all nodes in the cluster are ready
echo "Verify all nodes in the cluster are ready:"
kubectl get nodes


sudo kubeadm reset -f
sudo kubeadm init --pod-network-cidr=192.168.0.0/16
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


