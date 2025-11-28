# ☁️ Automated 3-Tier Architecture on AWS

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

### 1. Build Images (Packer)

```bash
cd packer
packer init layers.pkr.hcl
packer build layers.pkr.hcl
```

### 2. Infrastructure Deployment (Terraform)

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