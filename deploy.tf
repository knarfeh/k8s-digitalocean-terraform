###############################################################################
#
# A simple K8s cluster in DO
#
###############################################################################


###############################################################################
#
# Get variables from command line or environment
#
###############################################################################


variable "do_token" {}
variable "do_region" {
    default = "sfo2"
}
variable "ssh_fingerprint" {}
variable "ssh_private_key" {
    default = "~/.ssh/id_rsa"
}

variable "number_of_workers" {}

variable "prefix" {
    default = ""
}

variable "size_master" {
    default = "s-2vcpu-4gb"
}

variable "size_worker" {
    default = "s-2vcpu-4gb"
}


###############################################################################
#
# Specify provider
#
###############################################################################


provider "digitalocean" {
    token = "${var.do_token}"
}


###############################################################################
#
# Master host
#
###############################################################################


resource "digitalocean_droplet" "k8s_master" {
    image = "ubuntu-16-04-x64"
    name = "${var.prefix}k8s-master"
    region = "${var.do_region}"
    private_networking = true
    size = "${var.size_master}"
    ssh_keys = ["${split(",", var.ssh_fingerprint)}"]

    provisioner "file" {
        source = "./00-master.sh"
        destination = "/tmp/00-master.sh"
        connection {
            type = "ssh",
            user = "root",
            private_key = "${file(var.ssh_private_key)}"
        }
    }

    provisioner "file" {
        source = "./install-kubeadm.sh"
        destination = "/tmp/install-kubeadm.sh"
        connection {
            type = "ssh",
            user = "root",
            private_key = "${file(var.ssh_private_key)}"
        }
    }

    provisioner "file" {
        source = "./kubeadm_config.yaml"
        destination = "/tmp/kubeadm_config.yaml"
        connection {
            type = "ssh",
            user = "root",
            private_key = "${file(var.ssh_private_key)}"
        }
    }

    # Install dependencies and set up cluster
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/install-kubeadm.sh",
            "sudo /tmp/install-kubeadm.sh",
            "export MASTER_PRIVATE_IP=\"${self.ipv4_address_private}\"",
            "export MASTER_PUBLIC_IP=\"${self.ipv4_address}\"",
            "chmod +x /tmp/00-master.sh",
            "sudo -E /tmp/00-master.sh"
        ]
        connection {
            type = "ssh",
            user = "root",
            private_key = "${file(var.ssh_private_key)}"
        }
    }

    # copy secrets to local
    provisioner "local-exec" {
        command =<<EOF
            scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.ssh_private_key} root@${digitalocean_droplet.k8s_master.ipv4_address}:"/tmp/kubeadm_join /etc/kubernetes/admin.conf" ${path.module}/secrets/
            sed -i '.bak' "s/${self.ipv4_address_private}/${self.ipv4_address}/" ${path.module}/secrets/admin.conf
EOF
    }

}


###############################################################################
#
# Worker hosts
#
###############################################################################


resource "digitalocean_droplet" "k8s_worker" {
    count = "${var.number_of_workers}"
    image = "ubuntu-16-04-x64"
    name = "${var.prefix}${format("k8s-worker-%02d", count.index + 1)}"
    region = "${var.do_region}"
    size = "${var.size_worker}"
    private_networking = true
    # user_data = "${data.template_file.worker_yaml.rendered}"
    ssh_keys = ["${split(",", var.ssh_fingerprint)}"]
    depends_on = ["digitalocean_droplet.k8s_master"]

    # Start kubelet
    provisioner "file" {
        source = "./01-worker.sh"
        destination = "/tmp/01-worker.sh"
        connection {
            type = "ssh",
            user = "root",
            private_key = "${file(var.ssh_private_key)}"
        }
    }

    provisioner "file" {
        source = "./install-kubeadm.sh"
        destination = "/tmp/install-kubeadm.sh"
        connection {
            type = "ssh",
            user = "root",
            private_key = "${file(var.ssh_private_key)}"
        }
    }

    provisioner "file" {
        source = "./secrets/kubeadm_join"
        destination = "/tmp/kubeadm_join"
        connection {
            type = "ssh",
            user = "root",
            private_key = "${file(var.ssh_private_key)}"
        }
    }

    # Install dependencies and join cluster
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/install-kubeadm.sh",
            "sudo /tmp/install-kubeadm.sh",
            "export NODE_PRIVATE_IP=\"${self.ipv4_address_private}\"",
            "chmod +x /tmp/01-worker.sh",
            "sudo -E /tmp/01-worker.sh"
        ]
        connection {
            type = "ssh",
            user = "root",
            private_key = "${file(var.ssh_private_key)}"
        }
    }
}

# use kubeconfig retrieved from master
/*
resource "null_resource" "node-ready" {
   depends_on = ["digitalocean_droplet.k8s_worker"]
   provisioner "local-exec" {
       command = <<EOF
            export KUBECONFIG=${path.module}/secrets/admin.conf
            kubectl taint nodes --all node.kubernetes.io/not-ready-
EOF
   }
}
*/

resource "null_resource" "deploy_nginx_ingress" {
   depends_on = ["digitalocean_droplet.k8s_worker"]
   provisioner "local-exec" {
       command = <<EOF
            export KUBECONFIG=${path.module}/secrets/admin.conf
            kubectl create -f ./03-ingress-controller.yaml
            kubectl create clusterrolebinding serviceaccounts-cluster-admin --clusterrole=cluster-admin --group=system:serviceaccounts:default --namespace=default

EOF
   }
}

resource "null_resource" "deploy_hello" {
   depends_on = ["digitalocean_droplet.k8s_worker"]
   provisioner "local-exec" {
       command = <<EOF
            export KUBECONFIG=${path.module}/secrets/admin.conf
            sed -e "s/\$DO_ACCESS_TOKEN/${var.do_token}/" < ${path.module}/02-do-secret.yaml > ./secrets/02-do-secret.rendered.yaml 
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            sed -e "s/\$HELLO_ING_HOST/${digitalocean_droplet.k8s_worker.ipv4_address}.xip.io/" < ${path.module}/04-hello.yaml > ./05-xip-hello.yaml
            kubectl create -f ./05-xip-hello.yaml

EOF
   }
}

resource "null_resource" "deploy_digitalocean_cloud_controller_manager" {
    depends_on = ["digitalocean_droplet.k8s_worker"]
    provisioner "local-exec" {
        command = <<EOF
            export KUBECONFIG=${path.module}/secrets/admin.conf
            sed -e "s/\$DO_ACCESS_TOKEN/${var.do_token}/" < ${path.module}/02-do-secret.yaml > ./secrets/02-do-secret.rendered.yaml
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f ./secrets/02-do-secret.rendered.yaml
            kubectl create -f https://raw.githubusercontent.com/digitalocean/digitalocean-cloud-controller-manager/master/releases/v0.1.6.yml
EOF
    }
}
