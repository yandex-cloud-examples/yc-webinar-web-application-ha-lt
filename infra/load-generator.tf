locals {
  lg_sa_id           = var.lg_sa_id == null ? yandex_iam_service_account.load_generator.0.id : var.lg_sa_id
}

resource "yandex_iam_service_account" "load_generator" {
  count       = var.lg_sa_id == null ? 1 : 0
  name        = "${var.lg_sa_name}${local.name_suffix}"
  description = var.lg_sa_description
  folder_id   = local.folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "load_generator_roles" {
  for_each  = toset(var.lg_sa_id == null ? ["loadtesting.generatorClient", "logging.writer", "storage.viewer"] : [])
  folder_id = local.folder_id

  role   = each.key
  member = "serviceAccount:${yandex_iam_service_account.load_generator.0.id}"
}

resource "yandex_vpc_security_group" "load_generator" {
  name        = "load-generator${local.name_suffix}"
  description = "Security group for load-generator"
  network_id  = local.network_id
  folder_id   = local.folder_id

  ingress {
    protocol       = "ICMP"
    description    = "icmp"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "ssh"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "TCP"
    description    = "Access to api"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  egress {
    protocol       = "TCP"
    description    = "Target"
#    v4_cidr_blocks = ["${local.ip_addr}/32"]
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_loadtesting_agent" "load_generator" {
  name = "load-generator"
  description = "${var.lg_cores} core ${var.lg_memory} GB RAM agent"
  folder_id = local.folder_id

  compute_instance {
    zone_id = data.yandex_vpc_subnet.aux_subnet.zone
    service_account_id = local.lg_sa_id
    resources {
        memory = var.lg_memory
        cores = var.lg_cores
    }
    boot_disk {
        initialize_params {
            size = var.lg_disk
        }
        auto_delete = true
    }
    network_interface {
      subnet_id = var.aux_subnet_id
    }
  }
}

resource "yandex_iam_service_account" "lg_storage_owner" {
  folder_id = local.folder_id
  name      = "lg-storage-owner${local.name_suffix}"
}

resource "yandex_resourcemanager_folder_iam_member" "lg_storage_owner" {
  folder_id = local.folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.lg_storage_owner.id}"
}

resource "yandex_iam_service_account_static_access_key" "lg_storage_owner_key" {
  service_account_id = yandex_iam_service_account.lg_storage_owner.id
  description        = "Static access key for load generator object storage"
}

resource "yandex_storage_bucket" "load_generator" {
  folder_id = local.folder_id
  bucket = "load-generator${local.name_suffix}"
  access_key = yandex_iam_service_account_static_access_key.lg_storage_owner_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.lg_storage_owner_key.secret_key
  anonymous_access_flags {
    list = false
    read = true
  }
}

resource "yandex_storage_object" "scenario" {
  bucket = yandex_storage_bucket.load_generator.bucket
  key    = "test.hcl"
  source = "files/test1.hcl"
  access_key = yandex_iam_service_account_static_access_key.lg_storage_owner_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.lg_storage_owner_key.secret_key
}

resource "yandex_storage_object" "data" {
  bucket = yandex_storage_bucket.load_generator.bucket
  key    = "test-data.csv"
  source = "files/test1-data.csv"
  access_key = yandex_iam_service_account_static_access_key.lg_storage_owner_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.lg_storage_owner_key.secret_key
}

resource "local_file" "load_generator_config" {
  count                = var.lg_config == null ? 0 : 1
  filename             = pathexpand(var.lg_config)
  directory_permission = "0750"
  file_permission      = "0640"
  content              = <<-EOT
    uploader:
      enabled: true
      package: yandextank.plugins.DataUploader
      job_name: test
      job_dsc: ''
      ver: ''
      api_address: loadtesting.api.cloud.yandex.net:443
    pandora:
      enabled: true
      package: yandextank.plugins.Pandora
      resources:
        - src: https://storage.yandexcloud.net/${yandex_storage_bucket.load_generator.bucket}/${yandex_storage_object.scenario.id}
          dst: ./${yandex_storage_object.scenario.id}
        - src: https://storage.yandexcloud.net/${yandex_storage_bucket.load_generator.bucket}/${yandex_storage_object.data.id}
          dst: ./${yandex_storage_object.data.id}
      config_content:
        pools:
          - id: HTTP
            gun:
              type: http/scenario
              target: ${var.fqdn}:443
              ssl: true
            ammo:
              file: ${yandex_storage_object.scenario.id}
              type: http/scenario
            result:
              type: phout
              destination: ./phout.log
            startup:
              type: once
              times: 1000
            rps:
              - type: const
                ops: ${var.lg_rps}
                duration: ${var.lg_duration}
            discard_overflow: false
        log:
          level: error
        monitoring:
          expvar:
            enabled: true
            port: 1234
    core: {}
  EOT
}

