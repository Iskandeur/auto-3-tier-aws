# ☁️ AWS 3-Tier Architecture

This project deploys a highly available and secure Web infrastructure on AWS, fully automated following **Infrastructure as Code** and **Immutable Infrastructure** principles.

## 🏗️ Architecture

The project strictly follows a 3-Tier architecture with network segregation via Security Groups:

- **Tier 1 (Load Balancer):** Public entry point (HTTP/80).
- **Tier 2 (Web):** Nginx cluster (based on a hardened image). Accepts traffic only from the LB.
- **Tier 3 (App):** Node.js Backend. Accepts traffic only from the Web Tier.
- **Tier 4 (Data):** PostgreSQL Database. Accepts traffic only from the App Tier.

## 🛠️ Tech Stack

- **Cloud Provider:** AWS (EC2, ALB, VPC, Security Groups)
- **IaC (Provisioning):** Terraform (Modularized)
- **Images (Build):** Packer (HashiCorp)
- **Configuration:** Ansible (Roles & Playbooks)
- **OS Base:** Ubuntu 22.04 LTS

## 🚀 "Immutable" Methodology

Unlike a classic approach (runtime configuration), this project uses the **Golden Image** pattern:

1. **Packer** launches 3 parallel builds on AWS.
2. **Ansible** provisions each image (Web, App, DB) during the build process.
3. **Terraform** deploys the generated AMIs (Amazon Machine Images).

## 📦 Project Structure

```
.
├── ansible/          # Ansible Roles (Nginx, Node, Postgres)
├── app/              # Application source code (Node.js)
├── packer/           # Packer Templates (Multi-layer build)
└── terraform/        # Infrastructure code
    └── environments/
        └── prod/     # Production Environment
```

## 🔧 How to Deploy

### Prerequisites

- Terraform >= 1.0
- Packer >= 1.8
- AWS Account with access keys configured

### 1. Setup Environment

Before starting, you need to configure your AWS credentials and SSH keys.

#### A. Export AWS Credentials
Make sure your AWS credentials are available in your shell:

```bash
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
```

#### B. Setup SSH Keys
Terraform requires an SSH key pair to inject into the instances.

1. **Generate a key pair** (if you don't have one):
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_aws_3tier -C "aws-3tier-key" -N ""
   ```

2. **Update `terraform/environments/prod/main.tf`**:
   Open the file and find the `aws_key_pair` resource. Update the path to match your public key location (use an absolute path):

   ```hcl
   resource "aws_key_pair" "admin_key" {
     key_name   = "admin-key-3tier"
     # REPLACE with your actual path, e.g., /home/youruser/.ssh/id_aws_3tier.pub
     public_key = file("/home/youruser/.ssh/id_aws_3tier.pub")
   }
   ```

### 2. Build Images (Packer)

This project uses a two-stage build process:
1. **Base Image:** A common hardened base (Ubuntu + common tools).
2. **Layer Images:** 3 specialized images (Web, App, DB) derived from the base.

**Important:** Run these commands sequentially to avoid variable conflicts.

#### Step A: Build the Base Image
```bash
cd packer
packer init base.pkr.hcl
packer build base.pkr.hcl
```

#### Step B: Build the Layer Images
```bash
# Wait for the base build to finish first
packer init layers.pkr.hcl
packer build layers.pkr.hcl
```

### 3. Infrastructure Deployment (Terraform)

```bash
cd terraform/environments/prod
terraform init
terraform apply
```

## 🛡️ Security

- No public SSH access to databases.
- Network flows strictly limited by Security Groups (Principle of Least Privilege).
- No hardcoded secrets (usage of environment variables).

_Project realized as part of a DevOps Bootcamp._