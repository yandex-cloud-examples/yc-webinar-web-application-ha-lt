locals {
  k8s_node_pubkey   = var.k8s_node_pubkey_file == null ? var.k8s_node_pubkey : file(var.k8s_node_pubkey_file)
  k8s_node_metadata = local.k8s_node_pubkey == null ? null : { "ssh-keys" : "${var.k8s_node_username}:${local.k8s_node_pubkey}" }
  k8s_master_zone   = element(var.zones, 0)
}

module "k8s_cluster" {
  source = "../modules/terraform-yc-kubernetes"

  cluster_name         = var.k8s_cluster_name
  cluster_version      = var.k8s_cluster_version
  release_channel      = "RAPID"
  folder_id            = local.folder_id
  network_id           = local.network_id
  public_access        = true
  create_kms           = true
  enable_cilium_policy = false
  network_policy_provider = null
  cluster_ipv4_range   = var.k8s_cluster_ipv4_range
  service_ipv4_range   = var.k8s_service_ipv4_range
  service_account_name = "${var.k8s_cluster_name}-service-account"
  node_account_name    = "${var.k8s_cluster_name}-node-account"
  unique_id            = var.name_suffix
  enable_default_rules = false
  security_groups_ids_master = [ yandex_vpc_security_group.k8s_master.id ] 
  security_groups_ids_nodes = [ yandex_vpc_security_group.k8s_nodes.id ]

  master_locations = [
    {
        zone      = module.network.subnets["k8s-ru-central1-c"].zone
        subnet_id = module.network.subnets["k8s-ru-central1-c"].id
    },
    {
        zone      = module.network.subnets["k8s-ru-central1-b"].zone
        subnet_id = module.network.subnets["k8s-ru-central1-b"].id
    },
    {
        zone      = module.network.subnets["k8s-ru-central1-a"].zone
        subnet_id = module.network.subnets["k8s-ru-central1-a"].id
    }
  ]

  master_maintenance_windows = [{
    day        = "saturday"
    start_time = "04:00"
    duration   = "2h"
  }]

  node_groups_defaults = {
    node_cores             = 4
    node_memory            = 8
    disk_type              = "network-ssd-nonreplicated"
    disk_size              = 93
    preemptible            = false
    maintenance_day        = "sunday"
    maintenance_start_time = "04:00"
    maintenance_duration   = "2h"
    metadata               = local.k8s_node_metadata
  }

  node_groups = merge(
    {
      for zone in var.zones : "system-${zone}" => 
      {
        description = "System node group in ${zone}"
        node_cores  = 2
        node_memory = 4
        disk_type   = "network-ssd"
        disk_size   = 65
        fixed_scale = {
          size = 1
        }
        node_locations = [{
          zone      = module.network.subnets["k8s-${zone}"].zone
          subnet_id = module.network.subnets["k8s-${zone}"].id
        }]
      } 
    },
    { 
      for zone in var.zones : "ft-${zone}" => 
      {
        description = "Failure testing workers in ${zone}"
        fixed_scale = {
          size = var.k8s_workers_per_zone
        }
        node_locations = [{
          zone      = module.network.subnets["k8s-${zone}"].zone
          subnet_id = module.network.subnets["k8s-${zone}"].id
        }]
        node_taints = ["FailureTesting=:NoSchedule"]
        node_labels = {
          "failure-testing" = "true"
        }
        preemptible = true
      } 
    }
  )
  depends_on = [
    yandex_vpc_security_group.k8s_master,
    yandex_vpc_security_group.k8s_nodes
  ]
}

data "yandex_kubernetes_cluster" "k8s_cluster" {
  folder_id  = local.folder_id
  cluster_id = module.k8s_cluster.cluster_id
}

resource "yandex_container_registry_iam_binding" "cr_pusher" {
  count       = var.cr_id == null ? 0 : 1
  registry_id = var.cr_id
  role        = "container-registry.images.puller"

  members = [
    "serviceAccount:${data.yandex_kubernetes_cluster.k8s_cluster.node_service_account_id}",
  ]
}

resource "kubernetes_service_account_v1" "admin" {
  count = var.k8s_static_kubeconfig == null ? 0 : 1
  metadata {
    name      = var.k8s_admin_name
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding_v1" "cluster_admin" {
  count = var.k8s_static_kubeconfig == null ? 0 : 1
  metadata {
    name = "${kubernetes_service_account_v1.admin.0.metadata.0.name}-cluster-admin"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.admin.0.metadata.0.name
    namespace = kubernetes_service_account_v1.admin.0.metadata.0.namespace
  }
}

