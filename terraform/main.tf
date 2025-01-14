terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.14.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.16.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.3"
    }
  }
}

data "azurerm_subscription" "current" {
}

provider "azurerm" {
  features {}
}

resource "random_string" "deployment_prefix" {
  length  = 8
  upper   = false
  special = false
}

variable "tags" {
  default = {}
}

# Variables for DNS Zone configuration
variable "dns_zone_name" {
  description = "The name of the DNS zone"
  type        = string
  default     = "demo-trustorbs.com"
}

variable "dns_zone_resource_group_name" {
  description = "The name of the resource group containing the DNS zone"
  type        = string
  default     = "test_trustorbs"
}

data "azurerm_dns_zone" "domain" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${random_string.deployment_prefix.result}"
  location = "eastus"

  tags = merge(var.tags, {
    "Deployment" = random_string.deployment_prefix.result
  })
}

# User Assigned Identity for Cert Manager
resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "cert-manager-${random_string.deployment_prefix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# DNS Zone Contributor Role Assignment
resource "azurerm_role_assignment" "dns_contributor" {
  scope                = data.azurerm_dns_zone.domain.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                      = "aks-${random_string.deployment_prefix.result}"
  location                  = azurerm_resource_group.rg.location
  resource_group_name       = azurerm_resource_group.rg.name
  dns_prefix                = random_string.deployment_prefix.result
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_B2s"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = merge(var.tags, {
    "Deployment" = random_string.deployment_prefix.result
  })
}

# Federated Identity Credential for Cert Manager
resource "azurerm_federated_identity_credential" "cert_manager" {
  name                = "cert-manager-federated-credential"
  resource_group_name = azurerm_resource_group.rg.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.cert_manager.id
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# Cert Manager Installation
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  chart            = "jetstack/cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.16.2"
  wait             = true
  timeout          = 900

  values = [
    file("${path.module}/cert-manager/cert-manager-values.yaml")
  ]

  set {
    name  = "crds.enabled"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.azure\\.workload\\.identity/client-id"
    value = azurerm_user_assigned_identity.cert_manager.client_id
  }
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# Keycloak LoadBalancer Service
resource "kubernetes_service" "keycloak_loadbalancer" {
  metadata {
    name      = "keycloak-loadbalancer"
    namespace = "default"
    annotations = {
      "service.beta.kubernetes.io/azure-dns-label-name" = "keycloak-loadbalancer-${random_string.deployment_prefix.result}"
    }
  }
  spec {
    selector = {
      "app.kubernetes.io/instance" = "keycloak"
      "app.kubernetes.io/name"     = "keycloakx"
    }
    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }
    port {
      port        = 443
      target_port = 8443
      protocol    = "TCP"
      name        = "https"
    }
    type = "LoadBalancer"
  }
}

# ClusterIssuer for Let's Encrypt
resource "kubectl_manifest" "cluster_issuer" {
  yaml_body = templatefile(("${path.module}/cert-manager/cluster-issuer.yaml"), {
    subscriptionID : data.azurerm_subscription.current.subscription_id,
    tenantId: data.azurerm_subscription.current.tenant_id,
    resourceGroupName : var.dns_zone_resource_group_name,
    hostedZoneName : var.dns_zone_name,
    clientID : azurerm_user_assigned_identity.cert_manager.client_id
  })

  depends_on = [helm_release.cert_manager]
}

# DNS CNAME Record
resource "azurerm_dns_cname_record" "keycloak" {
  name                = random_string.deployment_prefix.result
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
  ttl                 = 300
  record              = "keycloak-loadbalancer-${random_string.deployment_prefix.result}.eastus.cloudapp.azure.com"

  depends_on = [kubernetes_service.keycloak_loadbalancer]
}

# Certificate for Keycloak
resource "kubectl_manifest" "certificate" {
  yaml_body = templatefile(("${path.module}/cert-manager/certificate.yaml"), {
    commonName : "${random_string.deployment_prefix.result}.${var.dns_zone_name}",
    dnsNames : "${random_string.deployment_prefix.result}.${var.dns_zone_name}"
  })

  depends_on = [azurerm_dns_cname_record.keycloak, helm_release.cert_manager]
}

# PostgreSQL Installation
resource "helm_release" "keycloak-db" {
  name       = "keycloak-db"
  chart      = "bitnami/postgresql"
  version    = "16.3.5"
  namespace  = "default"
  values     = [file("${path.module}/keycloak/keycloak-db-values.yaml")]
  depends_on = [kubectl_manifest.cluster_issuer]
  wait       = true
  timeout    = 300
}

# Keycloak Installation
resource "helm_release" "keycloak" {
  name      = "keycloak"
  chart     = "codecentric/keycloakx"
  namespace = "default"
  values = [templatefile("${path.module}/keycloak/https-keycloak-server-values.yaml", {
    hostname = "${random_string.deployment_prefix.result}.${var.dns_zone_name}"
  })]
  depends_on = [helm_release.keycloak-db, kubectl_manifest.certificate]
}

output "deployment_prefix" {
  value = random_string.deployment_prefix.result
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "keycloak_url" {
  value = "https://${random_string.deployment_prefix.result}.${var.dns_zone_name}"
}