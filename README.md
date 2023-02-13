# Demo: Google Cloud CI/CD for GKE
This repo is based off of this [demo](https://github.com/vszal/pop-kustomize), with modifications made to incorporate Cloud Build and Cloud Deploy private pools, usage of Anthos Connect Gateway for connecting to GKE clusters, and other security-focused changes.

This repo demostrates CI/CD for GKE with Google Cloud tools Google Cloud Deploy, Cloud Build, and Artifact Registry. The example app is based on a simple Python Flask example app named "Population Stats" and uses Kustomize overlays to enable configuration differences across three different environments: test, staging, and prod..

[![Demo flow](https://user-images.githubusercontent.com/76225123/145627874-86971a34-768b-4fc0-9e96-d7a769961321.png)](https://user-images.githubusercontent.com/76225123/145627874-86971a34-768b-4fc0-9e96-d7a769961321.png)

![New Arch](arch.png)

## Fork this repo
This demo relies on you making git check-ins to simulate a developer workflow. So you'll need your own copy of these files in your own Github.com repo.

[Fork this repo on Github](https://github.com/Enzyme3/pop-kustomize/fork)

If you've already done that, you can start the setup tutorial below.

## Setup
The demo assumes that we are working in a semi-locked down environment that follows certain security-best practices, such as not using default service accounts(SAs), limiting access granted to SAs/admins, and enforcing key organization policy constraints

Deploying this demo is split into the following steps:
### Step 1: Fork Repo
If you haven't already, [fork this repo on Github](https://github.com/Enzyme3/pop-kustomize/fork)
While 

### Step 2: Setup pre-reqs
The demo assumes the following about the environment the pipeline will be deployed into:
* 2X projects:
  * 1X to contain the CI/CD pipeline (aka CI/CD project)
  * 1X to contain the target GKE clusters (aka GKE project)
* Org policies applied on both projects:
  * constraints/compute.vmExternalIpAccess
  * constraints/iam.allowedPolicyMemberDomains
  * constraints/compute.skipDefaultNetworkCreation
* services enabled in both projects:
  * compute.googleapis.com
* service enable in GKE project:
  * container.googleapis.com
* Custom VPC/subnet created in both projects
* 3X private GKE clusters created in GKE project
  * workload identity enabled in each cluster
  * clusters use a custom service account
  * control plane should be accessible to the machine running the deployment scripts, either by running the script in a network peered with the control plane, or by using [authorized network](https://cloud.google.com/kubernetes-engine/docs/how-to/authorized-networks)

If needed, a terraform script under `./terraform/2_env-foundations` has been provided to build out the above environment. To use, make a copy of `./terraform/2_env-foundations/terraform.tvars.template`, rename it to `./terraform/2_env-foundations/terraform.tvars`, and update the file with info specific to your environment.

### Step #3: Enable Services and Setup IAM 
Before deploying the pipeline, the following services have to be enabled and IAM permissions have to be granted:

#### Enable Services
| Service to Enable        | Project           |
| ------------- |:-------------:| 
| sourcerepo.googleapis.com      | CI/CD Project | 
| cloudbuild.googleapis.com      | CI/CD Project | 
| artifactregistry.googleapis.com | CI/CD Project | 
| containerscanning.googleapis.com | CI/CD Project | 
| servicenetworking.googleapis.com | CI/CD Project | 
| artifactregistry.googleapis.com | CI/CD Project | 
| cloudbuild.googleapis.com | CI/CD Project | 
| clouddeploy.googleapis.com | CI/CD Project | 
| cloudresourcemanager.googleapis.com | CI/CD Project | 
| gkehub.googleapis.com | CI/CD Project | 
| serviceusage.googleapis.com | CI/CD Project | 
| connectgateway.googleapis.com | CI/CD Project | 
| anthos.googleapis.com | CI/CD Project | 
| gkeconnect.googleapis.com | CI/CD Project | 

#### IAM
* Create 3X service accounts(SAs) in the CI/CD project: 
  * SA for cloud build
  * SA for cloud deploy 
  * generate GCP-managed SA for gkehub by running: `gcloud beta services identity create --service=gkehub.googleapis.com`

Next, grant the permissions as indicated below:

| Member        | Role           | Resource
| ------------- |:-------------|:-------------:| 
| admin | roles/source.admin | CI/CD Project |
| Cloud Build SA | roles/source.reader | CI/CD Project |
| admin | roles/cloudbuild.builds.editor | CI/CD Project |
| admin | roles/storage.admin | CI/CD Project |
| Cloud Build SA | roles/storage.admin | CI/CD Project |
| Cloud Deploy SA | roles/storage.admin | CI/CD Project |
| admin | roles/serviceusage.serviceUsageConsumer | CI/CD Project |
| admin | roles/artifactregistry.admin | CI/CD Project |
| Cloud Build SA | roles/artifactregistry.writer | CI/CD Project |
| admin | roles/compute.networkAdmin | CI/CD Project |
| admin | roles/cloudbuild.workerPoolOwner | CI/CD Project |
| admin | roles/clouddeploy.admin | CI/CD Project |
| Cloud Build SA | roles/clouddeploy.releaser | CI/CD Project |
| Cloud Build SA | roles/logging.logWriter | CI/CD Project |
| Cloud Deploy SA | roles/logging.logWriter | CI/CD Project |
| admin | roles/gkehub.admin | CI/CD Project |
| Cloud Deploy SA | roles/gkehub.admin | CI/CD Project |
| admin | roles/container.admin | GKE Project |
| admin | roles/gkehub.gatewayAdmin | CI/CD Project |
| Cloud Deploy SA | roles/gkehub.gatewayAdmin | CI/CD Project |
| GKE SA | roles/artifactregistry.reader | CI/CD Project |
| admin | roles/iam.serviceAccountUser | Cloud Build SA |
| admin | roles/iam.serviceAccountUser | Cloud Deploy SA |
| Cloud Build SA | roles/iam.serviceAccountUser | Cloud Deploy SA |
| GKE Hub SA | roles/gkehub.serviceAgent | CI/CD Project |
| GKE Hub SA | roles/gkehub.serviceAgent | GKE Project |

If needed, a terraform script under `./terraform/3_enable-services-and-set-IAM` has been provided to apply the above configs. To use, make a copy of `./terraform/3_enable-services-and-set-IAM/terraform.tvars.template`, rename it to `./terraform/3_enable-services-and-set-IAM/terraform.tvars`, and update the file with info specific to your environment.

### Step #4: Mirror Github repo into Cloud Source Repositories
* in the GCP console, navigate to [Cloud Build > Triggers](https://console.cloud.google.com/cloud-build/triggers)
* Click on the `MANAGE REPOSITORIES` button
* Select the `global (non-regional)` region and then click on the `CONNECT REPOSITORY` button
  * 1) Select Source: Click on the `SHOW MORE` dropdown, select the `Github(legacy)` radio button, and check-mark the consent box
  * 2) Authenticate: If prompted, authenticate to Github
  * 3) Select repository: select the fork you created of this [repo](https://github.com/Enzyme3/pop-kustomize)
  * Don't follow prompts to create a trigger

### Step #5: Deploy Pipeline
Pipeline can be deployed by either following the manual steps below, or by running the terraform script. 

If going the terraform route, a terraform script under `./terraform/5_deploy_pipeline` has been provided. To use, make a copy of `./terraform/5_deploy-pipeline/terraform.tvars.template`, rename it to `./terraform/5_deploy-pipeline/terraform.tvars`, and update the file with info specific to your environment


#### Manual Steps to Deploy Pipeline
```
# fill-env specific vars and run in shell to set env vars
PROJECT_GKE=<project-id>
PROJECT_CICD=<project-id>
REGION=<region>
VPC=<name of VPC in CICD project>
SUBNET=<name>
SA_CLOUDBUILD_EMAIL=<email of SA used by Cloud Build>
SA_CLOUDDEPLOY_EMAIL=<email of SA used by Cloud Deploy>
GKE_TEST=<name of test GKE cluster>
GKE_STAGE=<name of test GKE cluster>
GKE_PROD=<name of test GKE cluster>
GCS_LOGS=<name of bucket that will be created to store logs>
GH_REPO_NAME=<pop-kustomize, or name of your fork>
GH_REPO_FORK_OWNER=<the GH account you used to fork repo>
CSR=github_${GH_REPO_FORK_OWNER}_${GH_REPO_NAME}

# create GCS bucket to store build/deploy logs
gcloud storage buckets create gs://$GCS_LOGS \
  --project $PROJECT_CICD \
  --location $REGION

# create Artifact Registry repo
gcloud artifacts repositories create pop-stats \
  --project $PROJECT_CICD \
  --location $REGION \
  --repository-format docker

# allocate named IP range for cloudbuild to use
gcloud compute addresses create cloudbuildrange \
  --project $PROJECT_CICD \
  --global \
  --purpose VPC_PEERING \
  --prefix-length 24 \
  --description "range for cloud build private pool" \
  --network projects/${PROJECT_CICD}/global/networks/${VPC}

# create private connection
gcloud services vpc-peerings connect \
  --service servicenetworking.googleapis.com \
  --ranges cloudbuildrange \
  --network $VPC \
  --project $PROJECT_CICD

# create cloud build private pool
gcloud builds worker-pools create my-private-pool \
  --project $PROJECT_CICD \
  --region $REGION \
  --peered-network projects/${PROJECT_CICD}/global/networks/${VPC} \
  --no-public-egress

# create cloudbuild.yaml and fill in env-specific vars
sed "s/<PROJECT>/$PROJECT_CICD/g" cloudbuild.yaml.template > cloudbuild.yaml
sed -i "s/<REGION>/$REGION/g" cloudbuild.yaml
sed -i "s/<GCS>/$GCS_LOGS/g" cloudbuild.yaml

# create build trigger
gcloud beta builds triggers create cloud-source-repositories \
  --name my-trigger \
  --region $REGION \
  --build-config cloudbuild.yaml \
  --service-account projects/${PROJECT_CICD}/serviceAccounts/${SA_CLOUDBUILD_EMAIL} \
  --branch-pattern "^main$" \
  --project $PROJECT_CICD \
  --repo $CSR

# create clouddeploy.yaml and fill in env-specific vars
sed "s/<PROJECT_CICD>/$PROJECT_CICD/g" clouddeploy.yaml.template > clouddeploy.yaml
sed -i "s/<REGION>/$REGION/g" clouddeploy.yaml
sed -i "s/<GKE_TEST>/$GKE_TEST/g" clouddeploy.yaml
sed -i "s/<GKE_STAGE>/$GKE_STAGE/g" clouddeploy.yaml
sed -i "s/<GKE_PROD>/$GKE_PROD/g" clouddeploy.yaml
sed -i "s/<SA_CLOUDDEPLOY_EMAIL>/$SA_CLOUDDEPLOY_EMAIL/g" clouddeploy.yaml

# create cloud deploy pipeline
gcloud deploy apply \
  --file clouddeploy.yaml \
  --region $REGION \
  --project $PROJECT_CICD

# register test cluster to fleet
 gcloud container hub memberships register $GKE_TEST \
 --gke-uri=https://container.googleapis.com/v1/projects/${PROJECT_GKE}/locations/$REGION/clusters/$GKE_TEST \
 --enable-workload-identity \
 --install-connect-agent \
 --project $PROJECT_CICD

# register stage cluster to fleet
 gcloud container hub memberships register $GKE_STAGE \
 --gke-uri=https://container.googleapis.com/v1/projects/${PROJECT_GKE}/locations/$REGION/clusters/$GKE_STAGE \
 --enable-workload-identity \
 --install-connect-agent \
 --project $PROJECT_CICD

# register prod cluster to fleet
 gcloud container hub memberships register $GKE_PROD \
 --gke-uri=https://container.googleapis.com/v1/projects/${PROJECT_GKE}/locations/$REGION/clusters/$GKE_PROD \
 --enable-workload-identity \
 --install-connect-agent \
 --project $PROJECT_CICD

# get context for test cluster
gcloud container hub memberships get-credentials $GKE_TEST \
  --project $PROJECT_CICD

# get context for stage cluster
gcloud container hub memberships get-credentials $GKE_STAGE \
  --project $PROJECT_CICD

# get context for prod cluster
gcloud container hub memberships get-credentials $GKE_PROD \
  --project $PROJECT_CICD

# set RBAC for test cluster
gcloud beta container hub memberships generate-gateway-rbac \
  --membership $GKE_TEST \
  --role clusterrole/cluster-admin \
  --users ${SA_CLOUDDEPLOY_EMAIL} \
  --project=$PROJECT_CICD \
  --kubeconfig ~/.kube/config \
  --context connectgateway_${PROJECT_CICD}_global_${GKE_TEST} \
  --apply

# set RBAC for stage cluster
gcloud beta container hub memberships generate-gateway-rbac \
  --membership $GKE_STAGE \
  --role clusterrole/cluster-admin \
  --users ${SA_CLOUDDEPLOY_EMAIL} \
  --project=$PROJECT_CICD \
  --kubeconfig ~/.kube/config \
  --context connectgateway_${PROJECT_CICD}_global_${GKE_STAGE} \
  --apply

# set RBAC for prod cluster
gcloud beta container hub memberships generate-gateway-rbac \
  --membership $GKE_PROD \
  --role clusterrole/cluster-admin \
  --users ${SA_CLOUDDEPLOY_EMAIL} \
  --project=$PROJECT_CICD \
  --kubeconfig ~/.kube/config \
  --context connectgateway_${PROJECT_CICD}_global_${GKE_PROD} \
  --apply
```

### Step #6: Test Pipeline
If you completed Step #5 using the provided terraform script, move the `./terraform/5_deploy-pipeline/cloudbuild.yaml` file to the root of the this repo. If you completed Step #5 using the manual steps, the file should already be at the root.

Push `cloudbuild.yaml` to your fork's main branch. Note that the `cloudbuild.yaml` file MUST be at the root of the repo. Once the push is completed, Cloud Build will trigger and begin building the sample app and deploying it to the test cluster. Navigate to Cloud Deploy to promote the code to the higher environments.
