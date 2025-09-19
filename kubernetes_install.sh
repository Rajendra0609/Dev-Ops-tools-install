#!/bin/bash

# Kubernetes v1.32 Setup and Removal Script
# Run as root or with sudo

echo "Kubernetes v1.32 Management Script"
echo "Choose an option:"
echo "1. Install Kubernetes"
echo "2. Uninstall Kubernetes"
read -p "Enter your choice (1 or 2): " choice

if [ "$choice" == "1" ]; then
    echo "Starting Kubernetes Installation..."

    # Prerequisites check (assuming Ubuntu)
    echo "Ensuring prerequisites..."
    # Add hostname and hosts editing if needed, but prompt user
    read -p "Set hostname (e.g., k8s-master): " hostname
    sudo hostnamectl set-hostname $hostname
    echo "Edit /etc/hosts manually if needed."

    # Disable Swap
    sudo swapoff -a
    sudo sed -i '/ swap / s/^/#/' /etc/fstab

    # Install containerd
    sudo apt-get update && sudo apt-get install -y containerd
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd

    # Load Kernel Modules & Sysctl
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter

    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system

    # Install Kubernetes
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

    echo "Installation complete. For master node, run 'sudo kubeadm init --pod-network-cidr=192.168.0.0/16'"
    echo "For worker nodes, use the join command from master."

elif [ "$choice" == "2" ]; then
    echo "Starting Kubernetes Uninstallation..."

    # Reset Kubernetes
    sudo kubeadm reset -f

    # Stop and disable services
    sudo systemctl stop kubelet
    sudo systemctl disable kubelet

    # Remove packages
    sudo apt-get purge -y kubeadm kubectl kubelet kubernetes-cni kube*
    sudo apt-get autoremove -y

    # Remove directories
    sudo rm -rf ~/.kube
    sudo rm -rf /etc/kubernetes
    sudo rm -rf /var/lib/etcd
    sudo rm -rf /var/lib/kubelet
    sudo rm -rf /etc/cni
    sudo rm -rf /opt/cni
    sudo rm -rf /run/flannel

    # Optional: Remove containerd state
    read -p "Remove containerd state? (y/n): " remove_containerd
    if [ "$remove_containerd" == "y" ]; then
        sudo systemctl stop containerd
        sudo rm -rf /var/lib/containerd
    fi

    # Clean iptables
    sudo iptables -F
    sudo iptables -t nat -F
    sudo iptables -t mangle -F
    sudo iptables -X
    sudo systemctl restart networking

    echo "Uninstallation complete. Reboot recommended."

else
    echo "Invalid choice. Exiting."
    exit 1
fi
