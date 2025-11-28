packer {
  required_plugins {
    amazon = {
      version = "~> 1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

locals { 
  timestamp = regex_replace(timestamp(), "[- TZ:]", "") 
}

source "amazon-ebs" "ubuntu-base" {
  ami_name      = "alexandre-base-${local.timestamp}"
  instance_type = "t3.micro"
  region        = var.region
  ssh_username  = "ubuntu"

  # On cherche l'Ubuntu 22.04 officielle
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }

  tags = {
    Project   = "Final-Portfolio"
    BaseImage = "True"
  }
}

build {
  sources = ["source.amazon-ebs.ubuntu-base"]

  # Installation des outils communs à TOUS les serveurs
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get install -y curl git htop vim python3-pip net-tools",
      # Installation d'Ansible SUR l'image pour qu'elle soit autonome si besoin
      "sudo apt-get install -y software-properties-common",
      "sudo add-apt-repository --yes --update ppa:ansible/ansible",
      "sudo apt-get install -y ansible"
    ]
  }
}