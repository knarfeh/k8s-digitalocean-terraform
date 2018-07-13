#!/bin/bash
set -o nounset -o errexit

export KUBECONFIG=/etc/kubernetes/admin.conf

kubeadm init --feature-gates=CoreDNS=true --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=${MASTER_PRIVATE_IP} --apiserver-cert-extra-sans=${MASTER_PUBLIC_IP}
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
systemctl enable docker kubelet

# used to join nodes to the cluster
kubeadm token create --print-join-command > /tmp/kubeadm_join

# install helm
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
kubectl create namespace tiller-deploy
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init
kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'

# used to setup kubectl 
# chown core /etc/kubernetes/admin.conf
