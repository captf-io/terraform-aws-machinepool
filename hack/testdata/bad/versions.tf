# Fixture: a backend, a second terraform block and a provider.
terraform {
  backend "s3" {}
}

terraform {
  required_version = ">= 1.5.0"
}

provider "fixture" {}
