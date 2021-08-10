# Instructions to setup Borneo SAAS

TODO: add 1-2 lines about Borneo SAAS

## Prerequisite
- Tools: 
  - [kubectl](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)
  - [terraform](https://www.terraform.io/downloads.html) -Use terraform when skip the eksctl tool to setup eks cluster
  - [eksctl](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)
  - [awscli](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html) - Have access to the target AWS account with aws cli. 
  To get help on how to configure the aws cli tool for an account, please visit this [official documentation](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html). After configuring, run the command below to check which AWS account is configured. The output of the command should show your user id and account id. 
    ```
    aws sts get-caller-identity
    ```
  - [helm 3](https://helm.sh/docs/intro/install/)
  - [curl](https://www.tecmint.com/install-curl-in-linux/)
  - Cognito. [This section](#create-cognito-user-pool) describes how to launch Cognito in AWS.
  - IAM policy for Resulting Load balancer. [This section](#create-iam-policy-for-lb) instructs to create IAM policy
  - A S3 bucket should present in the given AWS account. This S3 bucket will be used to store Loki logs with index
  - Urls for various values.yaml files.

  _Please note users should have basic knowledge of all these mentioned tools to set up the Borneo-SASS helm chart._

---

## Resources Created in the entire Process:
Detailed description on which resources gets created while installing Borneo-SASS solution described [here](./resources.md)

---

### Kubernetes Cluster Installation with EKSCTL Tool:
----
At the end of this step, we will have a running EKS cluster. Fill free to skip this step if you already have an EKS cluster.

We can create an EKS cluster with help of the `eksctl` tool. We need to create a cluster config file that we can pass to `eksctl` commands as a config file.

#### Cluster config file
`eksctl` requires to pass parameters in the command line for any operation, Optionally we can maintain all params in a config file and pass this file in `eksctl` commands. 

Below is an example cluster config file.  Create a cluster-config file as per your use case. Inline comments added which explain parameters. Visit [eksctl documentation](https://eksctl.io/) page to learn more about all possible params.

```
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  # Update CLUSTER_NAME with desired name. 
  name: CLUSTER_NAME
  # Update the region name. eg. us-east-1.
  region: REGION
  # tags need to added for all assets created by eksctl eg. 
  tags: { owner: 'OWNER', purpose: 'Purpose' }
  # EKS control plane version number. Specify value as a string. As of now default value for version is 1.19
  # version: "1.19"

iam:
  # Enable OIDC provider
  withOIDC: true
  # Add service accounts in EKS cluster. 
  serviceAccounts:
  - metadata:
      # name and namespace of the service account
      name: aws-load-balancer-controller 
      namespace: kube-system
    # Which AWS role need to map to this service account.
    roleName: aws-load-balancer-controller
    # Policy ARN's in AWS. 
    attachPolicyARNs:
    - POLICY_ARN
  - metadata:
      name: s3-read-write
      namespace: borneo
    attachPolicyARNs:
    - "arn:aws:iam::aws:policy/AmazonS3FullAccess"
# Node group settings.
nodeGroups:
  - name: cloudhedge-cluster-ng-01 # node group name
    instanceType: m5.large # instance type 
    # labels need to add to EKS nodes
    labels: { role: workers, owner: '****', purpose: 'borneo' }
    # tags need to add to EC2 machines
    tags:
      nodegroup-role: worker
      owner: 'gsane@cloudhedge.io'
      purpose: 'Borneo Trial'
    # min, max and desired number of nodes
    minSize: 1
    maxSize: 3
    desiredCapacity: 2
    # volume need to be attached to the nodes (in GB's)
    volumeSize: 80
    # which SSH key need to be configure for instances. 
    ssh:
      allow: true # will use ~/.ssh/id_rsa.pub as the default ssh key
    # Do we need to start instances in private subnets? (true/false)
    privateNetworking: true
# Which Az's we need to use.
availabilityZones: ['us-east-1a','us-east-1b','us-east-1c']

```
After updating the cluster config file, Run the below command to start the fresh EKS cluster. The command will take approx 15 minutes to set up the cluster.

```
eksctl create cluster -f <path cluster config file>
```

#### Access the EKS cluster. 
To access the EKS cluster from the command-line tool,  we require to have the aws cli tool installed. We also need an eksctl tool installed on our workstation.

[This section](#cluster-access-with-kubectl-tool) explains how to configure aws cli and access the cluster with user accounts created in the same/different AWS accounts. 

---

## k8s Cluster Install with Terraform tool
###### First Change variables in 0-0-variables.tf file with your own variables, variable file we can control subnets, disk size , capacity type , instance type etc.. 
### Service account and Roles setup files :
###### 5-node-autoscaler-sa.tf ( file for setup Node Autoscaler Feature )
###### 3-aws-alb-sa.tf ( file for setup aws-load-balancer-controller)
###### 4-s3-read-write-sa.tf ( file for setup s3 bucket role for borneo namespace )

##### Run Terraform:

```
terraform init
terraform apply
```
###### Set kubectl context to the new cluster: `aws eks update-kubeconfig --name cluster_name`

###### Check that there is a node that is `Ready`:
---

```
$ kubectl get nodes
NAME                                        STATUS   ROLES    AGE     VERSION
<node name>                                 Ready    <none>   6m39s   <version>
```
---

#### Setup Cluster Autoscaler : 
###### To Enable cluster Autoscaler Please Follow the below instructions :

---

###### IAM Roles for Service Accounts
---
It create an IAM role to be used for a Kubernetes `ServiceAccount`. It will create a policy and role to be used by the [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) using the [public Helm chart](https://github.com/kubernetes/autoscaler/tree/master/charts/cluster-autoscaler-chart).
The AWS documentation for IRSA is here: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
Replace `<ACCOUNT ID>` with your AWS account ID in `cluster-autoscaler.yaml`. There is output from terraform for this.
Install the chart using the provided values file.
```
$ helm repo add autoscaler https://kubernetes.github.io/autoscaler
$ helm repo update
$ helm install cluster-autoscaler --namespace kube-system autoscaler/cluster-autoscaler --values ./values/cluster-autoscaler.yaml
```

Verify Ensure the cluster-autoscaler pod is running. 

```
$ kubectl --namespace=kube-system get pods -l "app.kubernetes.io/name=aws-cluster-autoscaler-chart"
NAME                                                              READY   STATUS    RESTARTS   AGE
cluster-autoscaler-aws-cluster-autoscaler-chart-5545d4b97-9ztpm   1/1     Running   0          3m
```

Observe the `AWS_*` environment variables that were added to the pod automatically by EKS.
```
kubectl --namespace=kube-system get pods -l "app.kubernetes.io/name=aws-cluster-autoscaler-chart" -o yaml | grep -A3 AWS_ROLE_ARN

- name: AWS_ROLE_ARN
  value: arn:aws:iam::xxxxxxxxx:role/cluster-autoscaler
- name: AWS_WEB_IDENTITY_TOKEN_FILE
  value: /var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

Verify it is working by checking the logs, you should see that it has discovered the autoscaling group successfully:

```
kubectl --namespace=kube-system logs -l "app.kubernetes.io/name=aws-cluster-autoscaler-chart"

I0128 14:59:00.901513       1 auto_scaling_groups.go:354] Regenerating instance to ASG map for ASGs: [test-eks-irsa-worker-group-12020012814125354700000000e]
I0128 14:59:00.969875       1 auto_scaling_groups.go:138] Registering ASG test-eks-irsa-worker-group-12020012814125354700000000e
I0128 14:59:00.969906       1 aws_manager.go:263] Refreshed ASG list, next refresh after 2020-01-28 15:00:00.969901767 +0000 UTC m=+61.310501783
```

---

##### Install Ingress controller: 
---
_Make sure you have a running EKS cluster and the cluster is accessible from your terminal. [Last section](#Access-the-EKS-cluster) describes how to access the EKS cluster. 
We are using the AWS ingress controller to expose the Borneo SAAS application along with other tools with the AWS application Load balancer. Please visit [This official documenting](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) for more information._ 
---
##### Create IAM Policy For LB  
##### (Skip when we use terraform to install eks cluster) 
We need an IAM policy for the resulting Loadbalancer.
A policy document is available [here](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json). Download it and create IAM policy by running bellow commands. Skip this step if you have the resulting policy in your AWS account.
```
curl -o /tmp/iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file:///tmp/iam_policy.json
```
Capture the Policy ARN with help of the below command. We required this ARN in the next steps. ( same will work with eks installed with terraform )

```
aws iam list-policies | jq -cr '.Policies[] | select (.PolicyName == "AWSLoadBalancerControllerIAMPolicy").Arn'
```
_Please make sure you have [jq](https://stedolan.github.io/jq/download/) utility is available on your workstation_
#### Rest steps will be same for both( terrafor and ekctl ) created cluster
---
##### Install the TargetGroupBinding custom resource definitions. 
###### Install TargetGroupBinding CRD (custom resource definitions) by running a command:
---
```
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
```

##### Install the AWS Load Balancer Controller  
_Please note `AWS Load balancer controller` gets installed in the kube-system namespace. Make sure you have access to create required resources to this namespace._
We are using the helm chart to install the Load Balancer Controller. Make sure the helm-3 utility is installed on your workstation. 
Add the eks-charts helm chart repository as a local repository, and update your local repo to make sure that you have the most recent charts locally

```
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```
Install the AWS Load Balancer Controller helm chart. Please update the cluster name and service account name in the below command and run the updated command. 
```
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=${SERVICE_ACCOUNT_NAME} \
  -n kube-system
```
After few minutes, verify the controller is up and running by running the command 
```
kubectl get deployment -n kube-system aws-load-balancer-controller
```
---
##### Create Cognito User pool. 
We use Cognito to authenticate our users to access various tools exposed on the AWS Application Load balancer. 
In order to launch cognito, we use [this](./cfn-stack-templates/cognito.yaml) cloudformation template.
To create a cloud formation stack run the bellow command. 

_1. Please update REGION and make sure to use the correct template path._

_2. Make sure to update parameters default values in the template file before creating the stack_

```
aws cloudformation --region $REGION deploy --stack-name borneo-cognito --template-file ./cfn-stack-templates/cognito.yaml --no-fail-on-empty-changeset
```

---
##### Limit Resources on Borneo namespace
We can add limits on Resources used by assets running in the borneo namespace. 

_Please note, after creating quota object, it is required to give resources limits and requests to each pod,  otherwise, the Kubernetes scheduler will not schedule the pod and pods will goes in pending._

[This file](./quotas/borneo-resource-quotas.yaml) defines `ResourceQuota` object. Update this file in order to set correct resources limits and requests with help of this [official documentation](https://kubernetes.io/docs/concepts/policy/resource-quotas/).
Create the `ResourceQuota` object by running the following command. 

```
kubectl -n borneo apply -f ./quotas
```
---
## Installing of the Borneo SAAS application.
###### We use 8 helm charts to set up supportive applications and the Borneo SAAS application itself. 
---
To add required helm repositories, run the below commands. 

```
helm repo add runix https://helm.runix.net
helm repo add airflow-stable https://airflow-helm.github.io/charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add eks https://aws.github.io/eks-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

```

To fetch updates from helm repositories, run the below command.
```
helm repo update
```

##### Creating metadata
We use 2 k8s secrets and 3 config map objects to store metadata and secret metadata

##### K8s Secrets
- [pgsecret.yaml](./manifests/pgsecret.yaml) This secret holds username, password, and database name which is required for postgress helm chart.
- [grafana-creds.yaml](./manifests/grafana-creds.yaml) this secret holds the credentials to access the grafana dashboards. _Not required if planning to not use monitoring solution_

_Make sure to update secret values in the files, as per your choice_

##### Config maps
- [metrics-dashboard.yaml](./manifests/metrics-dashboard.yaml): Grafana helm chart uses this config map and create metrics dashboard. _Not required if planning to not use monitoring solution_
- [logs-dashboard.yaml](./manifests/logs-dashboard.yaml): Grafana helm chart uses this config map and create logs dashboard. _Not required if planning to not use monitoring solution_
- [grafana-datasourse.yaml](./manifests/grafana-datasourse.yaml): Grafana helm chart uses this config and add required data source. We add 2 data sources to this config map. The first one is Loki which collects logs and another one is Prometheus which collects metrics. _Not required if planning to not use monitoring solution_

_One can add more dashboards and data sources similarly, by creating/updating same config maps make sure to add all required labels for config maps, grafana pods pick config maps with required labels attached_ 

Create these config maps and secret in the Borneo namespace by running a command 
```
kubectl -n borneo apply -f ./manifests
```
_make sure, given cluster has Borneo namespace available and your user has required access to launch the assets in borneo namespace_ 

##### Installing monitoring tools. 
We are using Grafana-Prometheus-Loki Stack to collect logs and metrics. We need to install each tool with a dedicated helm chart. This way customizing each tool becomes simple and we get more control over each tool. for metrics server we use manifests file directly instead of helm charts.

_make sure, given cluster has borneo namespace available and your user has required access to launch the assets in borneo namespace_ 

Below are the instructions to set up each tool.
- `Loki`: We are using this [official helm chart](https://github.com/grafana/helm-charts/tree/main/charts/loki) from the grafana team. This is a default [values.yaml](https://raw.githubusercontent.com/grafana/helm-charts/main/charts/loki/values.yaml) file. We customized this file as per requirements. You may have a URL for the updated loki-values.yaml file (_the URL is valid for certain time_). 

  Install Loki helm chart by running the command 
  ```
  helm -n borneo upgrade -i -f <URL loki-values.yaml file> loki grafana/loki --version 2.5.0 
  ```
 Loki helm chart creates statefulset. Make sure Loki pod become ready. If you not see a loki pod in borneo namespace, get details stateful set named loki and check the errors/events. One may need to adjust quotas applied on namespace.

  ##### If we want to push logs to S3 make sure you have following settings added in the values file.*

  `persistence.enabled` = false

  `config.schema_config.object_store` = aws

  `config.storage_config.boltdb_shipper.shared_store` = aws

  `config.storage_config.aws.s3` = s3 bucket name like this s3://us-east-1/cloudhedge

  `serviceAccount.name` = s3-read-write _make sure s3-read-write account is created in previous . In this Readme the service account is created while spinning up the cluster with eks cluster and config file_

  ##### If we want to push logs to ebs make sure you have following settings added in the values file.

  `persistence.enabled` = true

  `config.schema_config.object_store` = filesystem

  `config.storage_config.boltdb_shipper.shared_store` = filesystem

  `config.storage_config.filesystem.directory` = /data/loki/chunks

- `Grafana`: We are using this [official helm chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana) from grafana team. This is a default [values.yaml](https://raw.githubusercontent.com/grafana/helm-charts/main/charts/grafana/values.yaml) file. We customized this file as per requirements. You may have URL for the updated grafana-values.yaml file (_the url is valid for creation time_)

  Install grafana helm chart by running the command 
  ```
  helm -n borneo upgrade -i -f <URL grafana-values.yaml file> grafana grafana/grafana --version 6.9.1
  ```

  Grafana helm chart creates deployment object in AWS EKS. Make sure grafana pod become ready after few minutes. If you not see a grafana pod in borneo namespace, get details of deployment object and check the errors/events. One may need to adjust quotas applied on namespace. 

- `Promtail`: We are using this [official helm chart](https://github.com/grafana/helm-charts/tree/main/charts/promtail) from grafana team. This is a default [values.yaml](https://raw.githubusercontent.com/grafana/helm-charts/main/charts/promtail/values.yaml) file. We customized this file as per requirements. You may have URL for the updated promtail-values.yaml file (_the url is valid for creation time_)

  Install Promtail helm chart by running the command 
  ```
  helm -n borneo upgrade -i -f <URL promtail-values.yaml file>  promtail grafana/promtail --version 3.5.1
  ```
  
  promtail helm chart creates daemon set object in AWS EKS. Make sure promtail pods become ready after few minutes. If you not see a promtail pods in borneo namespace, get details of deamon set object and check the errors/events. One may need to adjust quotas applied on namespace. 


- `Prometheus`: We are using this [official helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus) from prometheus community. This is a default [values.yaml](https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/prometheus/values.yaml) file. We customized this file as per requirements. You may have URL for the updated prometheus-values.yaml file (_the url is valid for creation time_)

  Install Prometheus helm chart by running the command 
  ```
  helm -n borneo upgrade -i -f <URL prometheus-values.yaml file> prometheus prometheus-community/prometheus --version 14.1.0
  ```

  prometheus helm chart creates daemon set object and 4 deployment objects in AWS EKS. Make sure all prometheus pods become ready after few minutes. If you not see a prometheus pods in borneo namespace, get details of deamon set and deployment object and check the errors/events. One may need to adjust quotas applied on namespace.


- `Metrics server`: We do not use the helm chart for the metrics server. We are using the official [manifest file](https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml) from the Kubernetes community. 
  Run the below command to set up the metrics server. 
  ```
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  ```

Please wait for few minutes and make sure all pods in borneo namespace are healthy. To check pods status run the command 
``` 
kubectl get pods -n borneo 
```

---
##### Install Postgress
We are using bitnami [helm chart](https://github.com/bitnami/charts/tree/master/bitnami/postgresql) for postgress. This is a default [values.yaml](https://github.com/bitnami/charts/blob/master/bitnami/postgresql/values.yaml) file. We customized this file as per requirements. You may have URL for the updated postgress-values.yaml file (_the url is valid for creation time_). We are referring some secret names in values file, the secret should be created already in [this section](#Creating-metadata)). 

Install Postgress helm chart by running a command 
```
helm -n borneo upgrade -i -f <URL postgress-values.yaml file> postgress bitnami/postgresql --version 10.3.14
```

##### Install Pgadmin 
We are using community [helm chart](https://github.com/rowanruseler/helm-charts/tree/master/charts/pgadmin4) for pgadmin. This is a default [values.yaml](https://github.com/rowanruseler/helm-charts/blob/master/charts/pgadmin4/values.yaml) file. We customized this file as per requirements. You may have URL for the updated pgadmin-values.yaml file (_the url is valid for creation time_)

Install pgadmin helm chart by running the command 
```
helm upgrade -i -f <URL pgadmin-values.yaml file> pgadmin runix/pgadmin4 --namespace borneo --version 1.6.0    
```

##### Install airflow
We are using official [helm chart](https://github.com/airflow-helm/charts/tree/main/charts/airflow) for airflow. We customized this file as per requirements. You may have URL for the updated airflow-values.yaml file (_the url is valid for creation time_)

Install airflow helm chart by running the command 
```
helm upgrade -i -f <URL airflow-values.yaml file> airflow airflow-stable/airflow --namespace borneo --version 7.16.0
```

##### Borneo helm chart
You will receive required URL for values.yaml file, Please use this url and run bellow command.
```
helm -n borneo upgrade -i ch ./borneo-saas-0.1.0.tgz  -f <URL values.yaml file>
```

Please wait for few minutes and make sure all pods in the borneo namespace are healthy. To check pods status run the command 
``` 
kubectl get pods -n borneo 
```

##### Access the application
- `Webapp With AWS ALB`:
  One can access the webapp and its tools with help of Application Loadbalancer. If you used value `global.awsAlb.enabled` is to `true` while installing borneo-saas helm chart, chat sets up ingress resources. We need to fetch the AWS Loadbalancer endpoint and add correct Route53 entries to access the app. 
  Get AWS LB endpoint by running the command: 
  ```
  kubectl -n borneo get ingress ch-borneo-ingress -o "jsonpath={.status.loadBalancer.ingress[].hostname}" 
  ```
  After adding correct entries in Route53, One can access the application on the following paths from the browser. 
  - http://<BASE_URL>/ : Borneo-SAAS webapp.
  - http://<BASE_URL>/airflow: Airflow webapp.
  - http://<BASE_URL>/pgadmin: Pgadmin4 webapp
  - http://<BASE_URL>/grafana: Grafana Dashboard page

  One required correct Cognito and tool-specific credentials to access the tools.

- ##### Cluster access with kubectl tool
    
    First of all, we need to set up Kubernetes (EKS) roles and role bindings in the borneo namespace and then Map AWS roles / User to Kubernetes Roles.

    We have a Kubernetes manifests file for Kubernetes Roles and Role-bindings. Run the following command to create k8s Roles and Role-bindings.
    ```
    kubectl -n borneo apply -f ./rbac/k8s-manifests  
    ```
    It will create 2 roles and 2 role-bindings in borneo namespace as described bellow
    - Roles
      - borneo-read-only: this role grant get, list, and watch actions on all namespaced API's ([This is a list of all namespaced apis](#namespaced-resources-list))
      - borneo-read-write: this role grants get, list, watch, create, update, patch, delete actions on all namespaced API's ([This is a list of all namespaced apis](#namespaced-resources-list))
    - Role-bindings
      - borneo-read-only-binding: this binding assign borneo-read-only role to borneo-read-only-user
      - borneo-read-write-binding: this binding assign borneo-read-write role to borneo-read-write-user
      #### namespaced resources list
      - v1
      - apps
      - authorization.k8s.io
      - autoscaling
      - batch
      - coordination.k8s.io
      - discovery.k8s.io
      - elbv2.k8s.aws
      - events.k8s.io
      - metrics.k8s.io
      - networking.k8s.io
      - policy
      - rbac.authorization.k8s.io
      - vpcresources.k8s.aws

    One may need access to kube-api server to manage resources in the EKS cluster or check pods logs with the `kubectl` tool. To get access to the EKS cluster users need an AWS account. The user account may be created in same AWS account where EKS is created / In different AWS account. 

  - If a user AWS account is created in a different AWS account then, We required the following steps:
    - setup AWS roles by which Users can get AWS account access by assume-role command. These steps need to perform in the source account (where the EKS cluster is setup) 
    
    _Please note, your user account in different AWS account should have `assume role` permissions in source AWS account._
      
      We have a cloudformation template ready which creates:
      - IAM policy named `EKSCrossAccountPolicy`
        which grant bellow actions on all eks clusters in a given AWS account. 
        - eks:DescribeIdentityProviderConfig
        - eks:AccessKubernetesApi
        - eks:DescribeCluster

      - IAM Role for Read-only users named `ReadOnlyRole`
      - IAM Role for Reading and write access users named `ReadWriteRole`

      launch cloud formation stack by running the following command in the source account where the EKS cluster is running. 
      ```
      aws cloudformation deploy --region $REGION \
        --stack-name ${CLUSTER_NAME}-cross-account-iam-roles \
        --template-file ./rbac/cloudformation/iam-roles.yaml \
        --parameter-overrides Cluster=${CLUSTER_NAME} AccountId=720029083713 \
        --capabilities CAPABILITY_NAMED_IAM
      ```
      

  - Update `aws-auth` config map in the kube-system namespace. 

    - If the given user account is in a different AWS account where the EKS cluster is running then: 
    
      Edit the aws-auth config map in the kube-system namespace with the command 
      ```
      kubectl -n kube-system edit cm aws-auth  
      ```
      
      Find the `mapRoles` section and add the following entries in the section.  Then Save the file and exit with `:wq` option

      ```
      - rolearn: <role-arn-read-only-user>
        username: borneo-read-only-user
      - rolearn: <role-arn-read-write-user>
        username: borneo-read-write-user
      ```
      
      Please update the role ARN in each entry. to get the role ARN of the read-only users run the following command. 
      ```
      ReadOnlyRoleARN=$(aws cloudformation --region $REGION describe-stacks --stack-name ${CLUSTER_NAME}-cross-account-iam-roles | jq -cr '.Stacks[0].Outputs[] | select(.OutputKey == "ReadOnlyRole").OutputValue')

      ReadWriteRoleARN=$(aws cloudformation --region $REGION describe-stacks --stack-name ${CLUSTER_NAME}-cross-account-iam-roles | jq -cr '.Stacks[0].Outputs[] | select(.OutputKey == "ReadWriteRole").OutputValue')

      echo "ReadOnlyRoleARN is ${ReadOnlyRoleARN} and ReadWriteRoleARN is ${ReadWriteRoleARN}
      ```

    - If the given user account is in the same AWS account where the EKS cluster is running then: 
      Edit the aws-auth config map in the kube-system namespace with the command 
      ```
      kubectl -n kube-system edit cm aws-auth  
      ```
      
      Find the `mapUsers` section and add the following entries in the section.  Then Save the file and exit with `:wq` option

      ```
      - userarn: <ARN of the user>
        username: borneo-read-only-user
      - userarn: <ARN of the user>
        username: borneo-read-write-user
      ```
      Please update the user ARN in each entry. 

  - Setup AWS cli
    _[This official documentation page](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) has more information about how to configure aws cli. This page explains required steps only_
    1. configure aws cli: to configure aws cli, run the command 
        ```
        aws configure
        ``` 
        Provide your AWS access key and secret key as prompted. 

        If your user account is set up in the same AWS account where the EKS cluster is running then skip the next step

    2. Create a profile.
      Create/edit the config file in your `.aws` directory located in your home directory. 

        ```
        vi ~/.aws/config
        ```

        add bellow section at the end of the file
        ```
        [profile borneo]
        role_arn=<role ARN of read / write user>
        role_session_name=borneo
        source_profile=default
        ```

        Set the env variable, so that aws cli picks correct keys. Run the command below to set profile

        ```
        export AWS_PROFILE=borneo
        ```
    3. Validate access:

        Get your aws profile by running the command
        ```
        aws sts get-caller-identity  
        ```
        It should output the correct account id where your EKS cluster is running

    4. Get/update kubeconfig file. 
        To authenticate the EKS cluster, we need a kubeconfig file. Run the below command to update context in your kubeconfig file.
        ```
          aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
        ```
        Update CLUSTER_NAME and REGION in the below command. 

        After the successful output of the last command, run the below command to make sure the EKS cluster is accessible and your user is authenticated.
        ```
        kubectl cluster-info
        ```
        This command should output cluster endpoint.

### Cleanup
  One can clean up resources created by helm by uninstalling the helm chart. Run the below command to remove all helm charts.
  ```
  helm -n borneo delete airflow pgadmin postgress prometheus promtail grafana loki ch
  ```
  
  We also installed an AWS LB controller with the helm chart in kube-system namespace. Uninstall the helm chart by running the command
  ```
  helm -n kube-system delete aws-load-balancer-controller
  ```

  We created a few config maps and secrets without a helm chart. Remove the same with command
  ```
  kubectl -n borneo delete -f ./manifests
  ```

  Helm chart does not remove PVC's on its own. We can remove the same by running the command

  ```
  kubectl delete pvc --all -n borneo
  ```

  We also created cloudformation stacks for cognito and cross-account roles. Remove both of them by running the below commands. Change CLUSTER_NAME in the command

  ```
  aws cloudformation delete-stack --stack-name ${CLUSTER_NAME}-borneo-cognito --region $REGION
  aws cloudformation delete-stack --stack-name ${CLUSTER_NAME}-cross-account-iam-roles --region $REGION
  ```

  Finally, remove the cluster by running the command
  ```
  eksctl delete cluster -f /tmp/borneo/cluster.yaml
  ```

### Create cluster with the script. 
We have [create.sh](./create.sh) and [delete.sh](./delete.sh) scripts written.

[create.sh](./create.sh) script spins up new eks cluster and configure all tools on it. on the other hand, [delete.sh](./delete.sh) scripts remove all tools and EKS cluster. 

_Make sure to place all configuration files in correct place before running the scripts_
