data "yandex_client_config" "client" {}

locals {
  cloud_id     = var.cloud_id == null ? data.yandex_client_config.client.cloud_id : var.cloud_id
  folder_id    = var.folder_id == null ? data.yandex_client_config.client.folder_id : var.folder_id
  network_id   = var.network_id
  name_suffix  = var.name_suffix == null ? "" : "-${var.name_suffix}"
  k8s_endpoint = var.k8s_use_intendpoint ?  module.k8s_cluster.internal_v4_endpoint : module.k8s_cluster.external_v4_endpoint
}

resource "time_sleep" "wait_alb_destroy" {
  depends_on = [
    module.k8s_cluster,
    module.k8s_cluster.node_groups,
    module.db,
    helm_release.alb_ingress,
    helm_release.node_local_dns
  ]

  destroy_duration = "60s"
}

resource "null_resource" "infra" {
  depends_on = [
    time_sleep.wait_alb_destroy
  ]
}


resource "kubernetes_token_request_v1" "admin" {
  count = var.k8s_static_kubeconfig == null ? 0 : 1
  metadata {
    name      = kubernetes_service_account_v1.admin.0.metadata.0.name
    namespace = kubernetes_service_account_v1.admin.0.metadata.0.namespace
  }
  spec {
    expiration_seconds = 3600 #604800  one week
  }
  depends_on = [
    resource.null_resource.infra
  ]
}

resource "local_file" "kubeconfig" {
  count                = var.k8s_static_kubeconfig == null ? 0 : 1
  filename             = pathexpand(var.k8s_static_kubeconfig)
  directory_permission = "0750"
  file_permission      = "0640"
  content              = <<-EOT
    apiVersion: v1
    kind: Config
    preferences: {}
    current-context: ${kubernetes_service_account_v1.admin.0.metadata.0.name}@${module.k8s_cluster.cluster_name}
    clusters:
    - cluster:
        certificate-authority-data: ${base64encode(module.k8s_cluster.cluster_ca_certificate)}
        server: ${local.k8s_endpoint}
      name: ${module.k8s_cluster.cluster_name}
    contexts:
    - context:
        cluster: ${module.k8s_cluster.cluster_name}
        user: ${kubernetes_service_account_v1.admin.0.metadata.0.name}
      name: ${kubernetes_service_account_v1.admin.0.metadata.0.name}@${module.k8s_cluster.cluster_name}
    users:
    - name: ${kubernetes_service_account_v1.admin.0.metadata.0.name}
      user:
        token: ${kubernetes_token_request_v1.admin.0.token}
  EOT
}

