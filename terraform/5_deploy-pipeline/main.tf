terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.38.0"
    }
  }
}

# create GCS bucket to store Cloud Build and Cloud Deploy logs
resource "google_storage_bucket" "logging" {
  project       = var.project_cicd
  name          = var.gcs_log_bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
}

# create Artifact Registry repo to store images
resource "google_artifact_registry_repository" "pop-stats" {
  project       = var.project_cicd
  location      = var.region
  repository_id = "pop-stats"
  format        = "DOCKER"
}

# allocate IP range to be used by Cloud Build private pool
resource "google_compute_global_address" "cloudbuild" {
  project       = var.project_cicd
  name          = "cloudbuild-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = var.vpc_id
}

# connect allocated IP range
resource "google_service_networking_connection" "cloudbuild" {
  network = var.vpc_id
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [
    google_compute_global_address.cloudbuild.name
  ]
}

# create Cloud Build private pool
resource "google_cloudbuild_worker_pool" "my-private-pool" {
  project  = var.project_cicd
  name     = "my-private-pool"
  location = var.region

  worker_config {
    disk_size_gb   = 100
    machine_type   = "e2-standard-4"
    no_external_ip = true
  }

  network_config {
    peered_network = var.vpc_id
  }

  depends_on = [
    google_service_networking_connection.cloudbuild
  ]
}

# create cloudbuild.yaml from template
resource "null_resource" "cloudbuild_spec_create" {
  triggers = {
      project = var.project_cicd
      region = var.region
      gcs2 = var.gcs_log_bucket_name
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      sed "s/<PROJECT>/${var.project_cicd}/g" templates/cloudbuild.yaml.template > cloudbuild.yaml
      sed -i "s/<REGION>/${var.region}/g" cloudbuild.yaml
      sed -i "s/<GCS>/${var.gcs_log_bucket_name}/g" cloudbuild.yaml
    EOT
  }
}

# create clouddeploy.yaml from template
resource "null_resource" "clouddeploy_spec_create" {
  triggers = {
      project = var.project_cicd
      region = var.region
      gke_test = var.gke_test_name
      gke_stage = var.gke_stage_name
      gke_prod = var.gke_prod_name
      service_account_clouddeploy = var.service_account_clouddeploy_email
  }
  

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      sed "s/<PROJECT_CICD>/${var.project_cicd}/g" templates/clouddeploy.yaml.template > clouddeploy.yaml
      sed -i "s/<REGION>/${var.region}/" clouddeploy.yaml
      sed -i "s/<GKE_TEST>/${var.gke_test_name}/g" clouddeploy.yaml
      sed -i "s/<GKE_STAGE>/${var.gke_stage_name}/g" clouddeploy.yaml
      sed -i "s/<GKE_PROD>/${var.gke_prod_name}/g" clouddeploy.yaml
      sed -i "s/<SA_CLOUDDEPLOY_EMAIL>/${var.service_account_clouddeploy_email}/g" clouddeploy.yaml
    EOT
  }
}

# apply clouddeploy.yaml
resource "null_resource" "clouddeploy_spec_apply" {
  triggers = {
      spec_created = null_resource.clouddeploy_spec_create.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      gcloud deploy apply \
        --file clouddeploy.yaml \
        --region ${var.region} \
        --project ${var.project_cicd}
    EOT
  }
}

# create Cloud Build trigger
resource "google_cloudbuild_trigger" "my-trigger" {
  project  = var.project_cicd
  location = var.region

  trigger_template {
    branch_name = "main"
    repo_name   = var.repo
  }

  filename        = "cloudbuild.yaml"
  service_account = "projects/${var.project_cicd}/serviceAccounts/${var.service_account_cloudbuild_email}"
}

# register the clusters to gke hub
resource "null_resource" "register_gke_hub_test" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      gcloud container hub memberships register ${var.gke_test_name} \
        --project ${var.project_cicd} \
        --gke-uri=https://container.googleapis.com/v1/projects/${var.project_gke}/locations/${var.region}/clusters/${var.gke_test_name} \
        --enable-workload-identity
        --install-connect-agent
    EOT
  }
}
resource "null_resource" "register_gke_hub_stage" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      gcloud container hub memberships register ${var.gke_stage_name} \
        --project ${var.project_cicd} \
        --gke-uri=https://container.googleapis.com/v1/projects/${var.project_gke}/locations/${var.region}/clusters/${var.gke_stage_name} \
        --enable-workload-identity
        --install-connect-agent
    EOT
  }
}
resource "null_resource" "register_gke_hub_prod" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      gcloud container hub memberships register ${var.gke_prod_name} \
        --project ${var.project_cicd} \
        --gke-uri=https://container.googleapis.com/v1/projects/${var.project_gke}/locations/${var.region}/clusters/${var.gke_prod_name} \
        --enable-workload-identity
        --install-connect-agent
    EOT
  }
}

# register impersonate RBAC in each cluster
resource "null_resource" "generate_gateway_rbac_test" {
  triggers = {
      registered = null_resource.register_gke_hub_test.id
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      gcloud container hub memberships get-credentials ${var.gke_test_name} --project ${var.project_cicd}
      gcloud beta container hub memberships generate-gateway-rbac \
        --membership ${var.gke_test_name} \
        --role clusterrole/cluster-admin \
        --users ${var.service_account_clouddeploy_email} \
        --project=${var.project_cicd} \
        --kubeconfig ~/.kube/config \
        --context connectgateway_${var.project_cicd}_global_${var.gke_test_name} \
        --apply
    EOT
  }
}
resource "null_resource" "generate_gateway_rbac_stage" {
  triggers = {
      registered = null_resource.register_gke_hub_stage.id
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      gcloud container hub memberships get-credentials ${var.gke_stage_name} --project ${var.project_cicd}
      gcloud beta container hub memberships generate-gateway-rbac \
        --membership ${var.gke_stage_name} \
        --role clusterrole/cluster-admin \
        --users ${var.service_account_clouddeploy_email} \
        --project=${var.project_cicd} \
        --kubeconfig ~/.kube/config \
        --context connectgateway_${var.project_cicd}_global_${var.gke_stage_name} \
        --apply
    EOT
  }
}
resource "null_resource" "generate_gateway_rbac_prod" {
  triggers = {
      registered = null_resource.register_gke_hub_prod.id
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      gcloud container hub memberships get-credentials ${var.gke_prod_name} --project ${var.project_cicd}
      gcloud beta container hub memberships generate-gateway-rbac \
        --membership ${var.gke_prod_name} \
        --role clusterrole/cluster-admin \
        --users ${var.service_account_clouddeploy_email} \
        --project=${var.project_cicd} \
        --kubeconfig ~/.kube/config \
        --context connectgateway_${var.project_cicd}_global_${var.gke_prod_name} \
        --apply
    EOT
  }
}
