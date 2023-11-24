#!/bin/bash

#open 2379, 6443, 10250 ports
echo -e "Opening ports 2379, 6443, 10250 \n"
echo -e "Port 2379 opened with $(firewall-cmd --zone=public --permanent --add-port=2379/tcp) \n" #APIetcd
echo -e "Port 2380 opened with $(firewall-cmd --zone=public --permanent --add-port=2380/tcp) \n" #etcd
echo -e "Port 6443 opened with $(firewall-cmd --zone=public --permanent --add-port=6443/tcp) \n" #API
echo -e "Port 10250 opened with $(firewall-cmd --zone=public --permanent --add-port=10250/tcp) \n" #kubeletAPI

echo -e "Reloading firewall \n"
echo -e "Firewall reloaded with $(firewall-cmd --reload) \n"

echo -e "Ports opened, firewall reloaded \n"

#disable swap
echo -e "Disabling swap \n"
sed -e '/swap/ s/^#*/#/' -i /etc/fstab
swapoff -a
echo -e "Swap disabled \n"

#enable forwarding
echo -e "Enable forwarding \n"
sysctl -w net.ipv4.ip_forward=1
sysctl -p
echo "Forwarding is set to $(sysctl net.ipv4.ip_forward)"

#add repo
echo -e "Configuring repos \n"
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
rpm --import https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
dnf config-manager --add-repo https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
echo -e "Repos configured \n"

#remove podman etc., if exists
echo -e "Removing existing container runtimes in order to install Docker \n"
dnf remove -y podman buildah

#install container runtime
echo -e "Installing and configuring container runtime \n"
dnf install -y containerd.io

#backup of original containerd config
cp /etc/containerd/config.toml /etc/containerd/config.toml.org

#generate containerd default config
echo -e "Generating default containerd configuration \n"
containerd config default > /etc/containerd/config.toml

echo -e "Configuring containerd \n"
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

#enable services
echo -e "Enabling containerd \n"
systemctl enable containerd.service && systemctl enable docker.service

#add info to k8s module
echo "Enable netfilter and overlay \n" 
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

echo -e "Installing Kubernetes utilities\n"
dnf install -y kubeadm kubectl kubelet

echo -e "Enabling kubelet \n"
systemctl enable kubelet.service

echo -e "Job done :) Please reboot your machine \n"

cat <<EOF | sudo tee ./kube_readme
Initialize kubernetes cluster after reboot

kubeadm init --control-plane-endpoint "10.0.0.29:6443" --pod-network-cidr=10.244.0.0/16 --upload-certs --apiserver-advertise-address=10.0.0.30 --v=6
add config to user 
export KUBECONFIG=/etc/kubernetes/admin.conf
apply CNI
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
join master node
kubeadm join 10.0.0.29:6443 --token [TOKEN] \
        --discovery-token-ca-cert-hash sha256:[HASH] \
        --control-plane --certificate-key [KEY] --apiserver-advertise-address=10.0.0.30 --v=6

EOF

#curl https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/calico.yaml -O
#kubectl apply -f calico.yaml
