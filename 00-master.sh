#!/bin/bash
set -o nounset -o errexit

export KUBECONFIG=/etc/kubernetes/admin.conf

sed -i "s/{{MASTER_PUBLIC_IP}}/$MASTER_PUBLIC_IP/g" /tmp/kubeadm_config.yaml
sed -i "s/{{MASTER_PRIVATE_IP}}/$MASTER_PRIVATE_IP/g" /tmp/kubeadm_config.yaml

kubeadm init --config /tmp/kubeadm_config.yaml
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.11.0/Documentation/kube-flannel.yml
systemctl enable docker kubelet

# used to join nodes to the cluster
kubeadm token create --print-join-command > /tmp/kubeadm_join

# kubectl taint nodes --all node.kubernetes.io/not-ready-
kubectl taint nodes k8s-master node-role.kubernetes.io/master:NoSchedule-

# install helm
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
kubectl create namespace tiller-deploy
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init
kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'

