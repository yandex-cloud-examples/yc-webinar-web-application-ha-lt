# Security groups

locals {
    k8s_master_subnet_cidrs = flatten([for s in module.network.subnets: s.v4_cidr_blocks if startswith(s.name, "k8s-") && s.zone != var.disabled_zone])
    k8s_nodes_subnet_cidrs = flatten([for s in module.network.subnets: s.v4_cidr_blocks if startswith(s.name, "k8s-") && s.zone != var.disabled_zone])
    db_subnet_cidrs = flatten([for s in module.network.subnets: s.v4_cidr_blocks if startswith(s.name, "db-") && s.zone != var.disabled_zone])
    all_subnet_cidrs =  flatten([ for s in module.network.subnets: s.v4_cidr_blocks if s.zone != var.disabled_zone ])

    k8s_master_allowed_ips = concat(var.k8s_master_allowed_ips, local.k8s_master_subnet_cidrs, local.k8s_nodes_subnet_cidrs, local.aux_subnet_cidr)
    k8s_nodes_allowed_ips  = concat(var.k8s_nodes_allowed_ips, local.k8s_nodes_subnet_cidrs, local.aux_subnet_cidr)
}

resource "yandex_vpc_security_group" "k8s_master" {
  folder_id   = local.folder_id
  name        = "k8s-master${local.name_suffix}"
  description = "Allow access to Kubernetes API from internet."
  network_id  = var.network_id

  ingress {
    protocol          = "TCP"
    description       = "Availability checks from nlb address range"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow access to Kubernetes API via port 6443 from subnet."
    v4_cidr_blocks = local.k8s_master_allowed_ips
    port           = 6443
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow access to Kubernetes API via port 443 from subnet."
    v4_cidr_blocks = local.k8s_master_allowed_ips
    port           = 443
  }

  egress {
    protocol       = "TCP"
    description    = "Allows all outgoing traffic"
    v4_cidr_blocks = local.k8s_nodes_subnet_cidrs
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "k8s_nodes" {
  folder_id   = local.folder_id
  name        = "k8s-nodes${local.name_suffix}"
  description = "K8s nodes security group"
  network_id  = var.network_id

  ingress {
    protocol       = "ANY"
    description    = "All incoming access"
    v4_cidr_blocks = local.k8s_nodes_allowed_ips
    port           = -1
  }

#  ingress {
#    protocol          = "ANY"
#    description       = "Allows master-node and node-node communication inside a security group."
#    predefined_target = "self_security_group"
#    from_port         = 0
#    to_port           = 65535
#  }

  ingress {
    protocol       = "ANY"
    description    = "Allows pod-pod and pod-service communication inside"
    v4_cidr_blocks = [var.k8s_cluster_ipv4_range, var.k8s_service_ipv4_range]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol       = "ICMP"
    description    = "Allows debugging ICMP packets from internal subnets."
    v4_cidr_blocks = local.k8s_nodes_allowed_ips
  }

  ingress {
    protocol       = "TCP"
    description    = "Allows incomming traffic from the Internet to the NodePort port range"
    v4_cidr_blocks = local.k8s_nodes_allowed_ips
    from_port      = 30000
    to_port        = 32767
  }

  ingress {
    protocol       = "TCP"
    description    = "Allows incomming heathchecks from the ALB"
    v4_cidr_blocks = local.k8s_nodes_allowed_ips
    port           = 10501
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow access to worker nodes via SSH from IP's."
    v4_cidr_blocks = var.k8s_nodes_ssh_allowed_ips == null ? var.k8s_nodes_allowed_ips : var.k8s_nodes_ssh_allowed_ips
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Allows all outgoing traffic"
    v4_cidr_blocks = [ "84.201.181.26/32", "213.180.193.243/32", 
        "84.201.171.239/32", ## cr.yandex
        "54.236.113.205/32", "84.201.144.177/32",
        "104.16.104.207/32", "104.16.101.207/32", "104.16.103.207/32", "104.16.100.207/32", "104.16.102.207/32",
        "213.180.204.183/32" ## mirror.yandex.ru
    ]
    port           = 443
  }

  egress {
    protocol       = "ANY"
    description    = "Allows traffic to master"
    v4_cidr_blocks = local.k8s_master_allowed_ips
    port           = 443
  }

  egress {
    protocol       = "ANY"
    description    = "Allows all outgoing traffic"
    v4_cidr_blocks = local.k8s_nodes_allowed_ips
    from_port      = 0
    to_port        = 65535
  }

  egress {
    protocol       = "ANY"
    description    = "Allows pod-pod and pod-service communication inside"
    v4_cidr_blocks = [var.k8s_cluster_ipv4_range, var.k8s_service_ipv4_range]
    from_port      = 0
    to_port        = 65535
  }


  egress {
    protocol       = "TCP"
    description    = "Allows access to DB"
    v4_cidr_blocks = local.db_subnet_cidrs
    port           = 6432
  }

  egress {
    protocol       = "UDP"
    description    = "Allows access to DNS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 53
  }

  ###TODO: ingress/egress between nodes and  master with different subnet
}

resource "yandex_vpc_security_group" "db" {
  name        = "db${local.name_suffix}"
  description = "database security group"
  network_id  = local.network_id
  folder_id   = local.folder_id

  ingress {
    protocol       = "ICMP"
    description    = "ping"
    v4_cidr_blocks = local.all_subnet_cidrs
  }

  ingress {
    protocol       = "TCP"
    description    = "database host"
    v4_cidr_blocks = local.db_subnet_cidrs
    port           = 6432
  }

  ingress {
    protocol       = "TCP"
    description    = "allow form k8s"
    v4_cidr_blocks = local.k8s_nodes_subnet_cidrs
    port           = 6432
  }

  ingress {
    protocol          = "TCP"
    description       = "Allows availability checks. It is required"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }
}

resource "yandex_vpc_security_group" "alb" {
  name        = "k8s-alb${local.name_suffix}"
  description = "alb security group"
  network_id  = local.network_id
  folder_id   = local.folder_id

  ingress {
    protocol       = "ICMP"
    description    = "ping"
    v4_cidr_blocks = local.all_subnet_cidrs
  }

  ingress {
    protocol       = "TCP"
    description    = "http"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "https"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol          = "TCP"
    description       = "Rule allows availability checks of load balancer"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }

  egress {
    protocol    = "TCP"
    description = "Enable traffic from ALB to K8s services"
    v4_cidr_blocks = local.k8s_nodes_subnet_cidrs
    from_port      = 30000
    to_port        = 32767
  }

  egress {
    protocol       = "TCP"
    description    = "Enable probes from ALB to K8s"
    v4_cidr_blocks = local.k8s_nodes_subnet_cidrs
    port           = 10501
  }
}

