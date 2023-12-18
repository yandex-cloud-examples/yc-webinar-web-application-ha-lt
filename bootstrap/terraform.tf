terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "> 16.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "> 3.3"
    }
  }

  #   backend "http" {
  #   }

  required_version = ">= 0.13"
}
