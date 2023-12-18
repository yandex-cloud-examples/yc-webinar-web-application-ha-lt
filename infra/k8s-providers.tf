provider "helm" {
  debug = true
  kubernetes {
    host                   = local.k8s_endpoint
    cluster_ca_certificate = module.k8s_cluster.cluster_ca_certificate
    token                  = data.yandex_client_config.client.iam_token
  }
  registry {
    url      = "oci://cr.yandex"
    username = "iam"
    password = data.yandex_client_config.client.iam_token
  }
}

provider "kubernetes" {
  host                   = local.k8s_endpoint
  cluster_ca_certificate = module.k8s_cluster.cluster_ca_certificate
  token                  = data.yandex_client_config.client.iam_token
}

