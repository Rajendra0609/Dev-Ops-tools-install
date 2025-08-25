✅ Kubernetes v1.32 Setup — Real-Time Environment (Step-by-Step)
🔧 Prerequisites
Component	Requirement
OS	Ubuntu 20.04 / 22.04 (same version on all nodes)
RAM	2 GB minimum per node (4 GB recommended)
CPUs	2+ per node
Internet Access	Yes (for pulling container images)
Hostnames	Unique for each node (e.g., k8s-master, k8s-worker1)
Users	Run all commands as root or with sudo

🖥️ 1. Set Hostnames and /etc/hosts
Set unique hostname for each node:

bash
Copy
Edit
sudo hostnamectl set-hostname k8s-master  # or k8s-worker1
Edit /etc/hosts on all nodes:

bash
Copy
Edit
sudo nano /etc/hosts
Add all nodes here (example):

Copy
Edit
192.168.0.100  k8s-master
192.168.0.101  k8s-worker1
🔧 2. Disable Swap (on all nodes)
bash
Copy
Edit
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
🔧 3. Install container runtime (containerd) [Recommended]
bash
Copy
Edit
sudo apt-get update && sudo apt-get install -y containerd
Configure containerd:

bash
Copy
Edit
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
Set correct cgroup driver:

bash
Copy
Edit
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
Restart containerd:

bash
Copy
Edit
sudo systemctl restart containerd
sudo systemctl enable containerd
🔧 4. Load Kernel Modules & Sysctl Settings (on all nodes)
bash
Copy
Edit
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
bash
Copy
Edit
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
🔧 5. Install Kubernetes v1.32 (on all nodes)
bash
Copy
Edit
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Add Kubernetes GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes v1.32 repo
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install specific version
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
✅ 6. Initialize the Control Plane (on Master only)
bash
Copy
Edit
sudo kubeadm init --pod-network-cidr=192.168.0.0/16
After it completes, you'll see a kubeadm join command — save it!

Configure kubectl:

bash
Copy
Edit
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
🌐 7. Install a CNI Plugin (Calico for production)
bash
Copy
Edit
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.5/manifests/calico.yaml
Wait a minute, then check:

bash
Copy
Edit
kubectl get pods -n kube-system
All pods (CoreDNS, Calico, etc.) should be Running.

🧩 8. Join Worker Nodes
Run this on each worker node (use the kubeadm join command output from step 6):

bash
Copy
Edit
sudo kubeadm join 192.168.0.100:6443 --token <your-token> \
    --discovery-token-ca-cert-hash sha256:<your-hash>
✅ 9. Verify the Cluster (on master)
bash
Copy
Edit
kubectl get nodes
You should see:

pgsql
Copy
Edit
NAME         STATUS   ROLES           AGE     VERSION
k8s-master   Ready    control-plane   5m      v1.32.7
worker1      Ready    <none>          2m      v1.32.7
🎯 That's It — Your Kubernetes v1.32 Cluster is Ready!
✅ Summary Checklist
Task	Done? ✅
Swap Disabled	✅
containerd installed	✅
Kernel modules configured	✅
Kubernetes v1.32 installed	✅
Master initialized	✅
Calico applied	✅
Worker nodes joined	✅
Nodes are Ready	✅



##############################################################to remove it #################################################################
Step-by-Step: Clean Remove Kubernetes (Ubuntu/Debian)
Run all commands as root or with sudo

🔹 1. Reset Kubernetes with kubeadm
This undoes the changes made by kubeadm init or kubeadm join:

bash
Copy
Edit
sudo kubeadm reset -f
If asked about iptables, type y.

🔹 2. Stop and disable Kubernetes services
bash
Copy
Edit
sudo systemctl stop kubelet
sudo systemctl disable kubelet
🔹 3. Remove Kubernetes packages
bash
Copy
Edit
sudo apt-get purge -y kubeadm kubectl kubelet kubernetes-cni kube*
sudo apt-get autoremove -y
🔹 4. Remove Kubernetes configuration and data directories
bash
Copy
Edit
sudo rm -rf ~/.kube
sudo rm -rf /etc/kubernetes
sudo rm -rf /var/lib/etcd
sudo rm -rf /var/lib/kubelet
sudo rm -rf /etc/cni
sudo rm -rf /opt/cni
sudo rm -rf /run/flannel
🔹 5. (Optional) Remove container runtime state
If you're using containerd:

bash
Copy
Edit
sudo systemctl stop containerd
sudo rm -rf /var/lib/containerd
If you're using Docker:

bash
Copy
Edit
sudo systemctl stop docker
sudo rm -rf /var/lib/docker
You can reinstall Docker/Containerd later if needed.

🔹 6. Clean up iptables/net config (Optional)
bash
Copy
Edit
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X
sudo systemctl restart networking
🔹 7. Reboot (Recommended)
bash
Copy
Edit
sudo reboot

#####################################workernode reset#########################

sudo rm -rf /etc/kubernetes/kubelet.conf
sudo rm -rf /etc/kubernetes/pki
sudo kubeadm reset -f


#######################################master node reset@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sudo rm -rf /etc/cni/net.d

sudo rm -rf /var/lib/kubelet/*
sudo rm -rf /etc/kubernetes
rm -rf $HOME/.kube
sudo rm -rf $HOME/.kube/config file
sudo kubeadm reset -f
