packer {
  required_plugins {
    amazon = {
      version = "~> 1"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = "~> 1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "region" { default = "us-east-1" }
locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

# --- COMMON BASE (SOURCE) ---
# We define a single generic source, which we will derive 3 times.

source "amazon-ebs" "layer" {
  instance_type = "t3.micro"
  region        = var.region
  ssh_username  = "ubuntu"

  # MAGIC: We start from OUR Base Image created earlier
  source_ami_filter {
    filters = {
      "tag:BaseImage" = "True"       # We look for the tag we set
      "tag:Project"   = "AWS-3Tier-App"
    }
    most_recent = true
    owners      = ["self"]
  }
}

# --- 3 PARALLEL BUILDS ---

build {
  name = "layers"
  
  # 1. Image WEB
  source "source.amazon-ebs.layer" {
    name     = "web"
    ami_name = "alexandre-web-${local.timestamp}"
    tags     = { Role = "Web", Project = "AWS-3Tier-App" }
  }

  # 2. Image APP
  source "source.amazon-ebs.layer" {
    name     = "app"
    ami_name = "alexandre-app-${local.timestamp}"
    tags     = { Role = "App", Project = "AWS-3Tier-App" }
  }

  # 3. Image DB
  source "source.amazon-ebs.layer" {
    name     = "db"
    ami_name = "alexandre-db-${local.timestamp}"
    tags     = { Role = "DB", Project = "AWS-3Tier-App" }
  }

  # --- COMMON PROVISIONING ---
  # Packer is smart enough to run the right role according to the source name!
  
  provisioner "ansible" {
    playbook_file = "../ansible/playbook_layers.yml"
    user          = "ubuntu"
    ansible_env_vars = ["ANSIBLE_SSH_PIPELINING=True"]
    # We pass the source name (web, app, or db) as a variable to Ansible
    extra_arguments = ["--extra-vars", "target_role=${source.name}"]
  }
}