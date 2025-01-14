# Terraform Project: Azure Kubernetes Service (AKS) with Keycloak and Cert Manager

This project deploys an Azure Kubernetes Service (AKS) cluster with Keycloak, Cert Manager, and supporting resources using Terraform. The deployment includes configurations for DNS zones, role assignments, Helm releases, and Kubernetes services.

---

## **Prerequisites**

Ensure the following tools are installed:
- [Terraform](https://www.terraform.io/downloads.html) >= 1.4.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [Helm](https://helm.sh/docs/intro/install/)

You also need:
- An active Azure subscription.
- Access to manage DNS zones in your Azure subscription.
- A domain name for DNS configuration.

---

## **Terraform Structure**

### **Providers**
The following providers are configured in this project:
- Azure Resource Manager (`azurerm`)
- Kubernetes (`kubernetes`)
- Helm (`helm`)
- Kubectl (`kubectl`)
- Random string generator (`random`)

### **Main Components**
- **Resource Group**: A dedicated resource group for managing all resources.
- **AKS Cluster**: A Kubernetes cluster with system-assigned identity and workload identity enabled.
- **Cert Manager**: Installed via Helm to manage TLS certificates.
- **Keycloak**: Installed via Helm with a LoadBalancer service and a DNS CNAME record.
- **DNS Zone**: Configured to manage DNS records for the domain.
- **PostgreSQL Database**: Installed via Helm as the backend database for Keycloak.

---

## **Usage**

### **1. Clone the Repository**
Clone the Git repository containing the Terraform code:
```bash
git clone <repository-url>
cd <repository-directory>
```

### **2. Initialize Terraform**
Run the following command to initialize the Terraform workspace and download required providers:
```bash
terraform init
```

### **3. Customize Variables**
Update variables in `variables.tf` or pass them directly via a `.tfvars` file or command line.

Key variables:
- `dns_zone_name`: Name of the DNS zone.
- `dns_zone_resource_group_name`: Resource group for the DNS zone.

Example `.tfvars` file:
```hcl
dns_zone_name = "example.com"
dns_zone_resource_group_name = "my-dns-group"
```

### **4. Plan the Deployment**
Preview the changes Terraform will make:
```bash
terraform plan -var-file=<your-tfvars-file>.tfvars
```

### **5. Apply the Configuration**
Deploy the resources:
```bash
terraform apply -var-file=<your-tfvars-file>.tfvars
```

### **6. Outputs**
Once the deployment is complete, Terraform provides the following outputs:
- `deployment_prefix`: Random prefix for resources.
- `aks_cluster_name`: Name of the AKS cluster.
- `keycloak_url`: URL for accessing the Keycloak service.

Example:
```plaintext
Apply complete! Resources: 20 added, 0 changed, 0 destroyed.

Outputs:
aks_cluster_name = "aks-abc12345"
keycloak_url = "https://abc12345.example.com"
```

---

## **File Structure**

```plaintext
.
├── cert-manager/
│   ├── certificate.yaml          # Cert Manager Certificate definition
│   ├── cluster-issuer.yaml       # Cluster Issuer configuration
│   └── cert-manager-values.yaml  # Helm values for Cert Manager
├── keycloak/
│   ├── https-keycloak-server-values.yaml # Helm values for Keycloak
│   └── keycloak-db-values.yaml           # Helm values for PostgreSQL
├── main.tf                       # Main Terraform configuration
├── variables.tf                  # Input variables
├── outputs.tf                    # Output values
├── .gitignore                    # Files to ignore in version control
└── README.md                     # Project documentation
```


---

## **Cleaning Up**
To destroy all resources created by this project, run:
```bash
terraform destroy -var-file=<your-tfvars-file>.tfvars
```

