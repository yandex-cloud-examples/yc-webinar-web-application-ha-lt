#  user_pubkey_filename      = "~/.ssh/id_rsa.pub"
#  username                  = "ubuntu"
#  worker_image_id           = "fd8xxxxxxxxxxxx"

locals {
  gitlab_runner_sa_name        = "gitlab-docker-machine${local.name_suffix}"
  gitlab_runner_subnet_id      = module.network.subnets["gitlab-runner-${var.gitlab_runner_zone}"].id
  gitlab_runner_user_pubkey    = var.gitlab_runner_user_pubkey_file == null ? var.gitlab_runner_user_pubkey : file(var.gitlab_runner_user_pubkey_file)

  template_vars = {
    cloud_id               = local.cloud_id
    folder_id              = local.folder_id
    subnet_id              = local.gitlab_runner_subnet_id
    security_groups        = yandex_vpc_security_group.security_group_worker.0.id
    zone                   = var.gitlab_runner_zone
    worker_runners_limit   = var.worker_runners_limit
    worker_use_internal_ip = var.worker_use_internal_ip
    worker_image_family    = var.worker_image_family
    worker_image_id        = var.worker_image_id
    worker_cores           = var.worker_cores
    worker_disk_type       = var.worker_disk_type
    worker_disk_size       = var.worker_disk_size
    worker_memory          = var.worker_memory
    worker_preemptible     = var.worker_preemptible
    worker_platform_id     = var.worker_platform_id
    secret_id              = yandex_lockbox_secret.gitlab_token.id
  }
}

resource "yandex_iam_service_account" "gitlab_docker_machine" {
  name        = local.gitlab_runner_sa_name
  folder_id   = local.folder_id
  description = local.gitlab_runner_sa_name
}

resource "yandex_resourcemanager_folder_iam_member" "gitlab_docker_machine_roles" {
  for_each  = toset(["compute.admin", "vpc.user", "lockbox.payloadViewer"])
  folder_id = local.folder_id

  role   = each.key
  member = "serviceAccount:${yandex_iam_service_account.gitlab_docker_machine.id}"
}

resource "yandex_kms_symmetric_key_iam_binding" "gitlab_docker_machine_kms_roles" {
  symmetric_key_id = yandex_kms_symmetric_key.gitlab_token_key.id

  role = "kms.keys.encrypterDecrypter"
  members = [
    "serviceAccount:${yandex_iam_service_account.gitlab_docker_machine.id}"
  ]
}

data "yandex_compute_image" "ubuntu_lts" {
  family = "ubuntu-2204-lts"
}

resource "yandex_compute_instance" "gitlab_docker_machine" {
  name                      = "gitlab-docker-machine${local.name_suffix}"
  hostname                  = "gitlab-docker-machine${local.name_suffix}"
  platform_id               = "standard-v3"
  zone                      = var.gitlab_runner_zone
  folder_id                 = local.folder_id
  allow_stopping_for_update = true

  service_account_id = yandex_iam_service_account.gitlab_docker_machine.id
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 50
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image_id   = data.yandex_compute_image.ubuntu_lts.id
      block_size = 4096
      size       = 20
      type       = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = local.gitlab_runner_subnet_id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.securtiy_group_master.0.id]
  }

  metadata = {
    user-data          = <<-USERDATA
      #cloud-config
      users:
        - name: ${var.gitlab_runner_username}
          groups: sudo
          shell: /bin/bash
          sudo: ['ALL=(ALL) NOPASSWD:ALL']
          ssh-authorized-keys:
            - ${local.gitlab_runner_user_pubkey}
      write_files:
        - path: /root/postinstall.sh
          owner: root:root
          permissions: 0o750
          encoding: base64
          defer: true
          content: |
            ${filebase64("${path.module}/files/postinstall.sh")}
        - path: /root/gitlab-runner-config.toml
          owner: root:root
          permissions: 0o640
          encoding: base64
          defer: true
          content: |
            ${base64encode(templatefile("${path.module}/files/gitlab-runner-config.tftpl", local.template_vars))}
        - path: /root/secret_id
          owner: root:root
          permissions: 0o600
          encoding: base64
          defer: true
          content: |
            ${base64encode(yandex_lockbox_secret.gitlab_token.id)}
      runcmd:
        - [ bash, /root/postinstall.sh ]
    USERDATA
    serial-port-enable = 0
  }

  scheduling_policy {
    preemptible = false
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.gitlab_docker_machine_roles,
    yandex_lockbox_secret_version.gitlab_token_version
  ]
}

resource "yandex_vpc_security_group" "securtiy_group_master" {
  count       = 1
  name        = "gitlab-runner-master${local.name_suffix}"
  description = "Security group for gitlab-runner master"
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
    protocol       = "ANY"
    description    = "Allow any"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "security_group_worker" {
  count       = 1
  name        = "gitlab-runner-worker${local.name_suffix}"
  description = "Security group for docker-machine worker"
  network_id  = local.network_id
  folder_id   = local.folder_id

  ingress {
    protocol       = "ICMP"
    description    = "icmp"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol          = "TCP"
    description       = "ssh"
    security_group_id = yandex_vpc_security_group.securtiy_group_master[0].id
    port              = 22
  }

  ingress {
    protocol          = "TCP"
    description       = "docker"
    security_group_id = yandex_vpc_security_group.securtiy_group_master[0].id
    port              = 2376
  }

  egress {
    protocol       = "ANY"
    description    = "Allow any"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_kms_symmetric_key" "gitlab_token_key" {
  name              = "gitlab-token-key"
  folder_id         = local.folder_id
  description       = "gitlab token ecryption key"
  default_algorithm = "AES_256"
  rotation_period   = "8760h"
}

resource "yandex_lockbox_secret" "gitlab_token" {
  folder_id  = local.folder_id
  name       = "gitlab-runner-token"
  kms_key_id = yandex_kms_symmetric_key.gitlab_token_key.id
}

resource "yandex_lockbox_secret_version" "gitlab_token_version" {
  secret_id = yandex_lockbox_secret.gitlab_token.id
  entries {
    key        = "gitlab_token"
    text_value = local.gitlab_project.runners_token
  }
  entries {
    key        = "gitlab_url"
    text_value = var.gitlab_url
  }
  entries {
    key        = "gitlab_runner_tags"
    text_value = var.gitlab_runner_tags == "" ? "-" : var.gitlab_runner_tags
  }
}

