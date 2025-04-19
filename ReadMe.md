
# BetterWellness Kubernetes Infrastructure Deployment Guide

This guide walks through the full infrastructure setup, deployment, and teardown process for the BetterWellness platform using AWS CloudFormation, EKS, DocumentDB, Redis, API Gateway, and other integrated services.

---


## 🐳 ECR + Docker Deployment

### Login to ECR
```bash
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin <your-ecr-url>
```

### Build, Tag & Push Microservices
Repeat for each service:

```bash
docker build -t betterwellness-<service-name> .
docker tag betterwellness-<service-name>:latest <your-ecr-url>/betterwellness/<service-name>:latest
docker push <your-ecr-url>/betterwellness/<service-name>:latest
```


## 📦 Infrastructure Setup

### 1. Provision VPC
```bash
aws cloudformation deploy   --template-file betterwellness-vpc.yaml   --stack-name betterwellness-vpc   --capabilities CAPABILITY_NAMED_IAM
```

### 📄 `betterwellness-vpc.yaml`

```powershell
# ------------------------------
# betterwellness-core.yaml (Updated)
# Step 1: Create VPC, IAM Roles, and EKS Cluster (Multi-AZ)
# ------------------------------

AWSTemplateFormatVersion: '2010-09-09'
Description: Core infrastructure for BetterWellness platform (VPC, IAM, EKS)

Parameters:
  ClusterName:
    Type: String
    Default: betterwellness-cluster
  NodeInstanceType:
    Type: String
    Default: t3.medium

Resources:

  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true

  PublicSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: !Select [ 0, !GetAZs '' ]
      MapPublicIpOnLaunch: true
      Tags:
        - Key: kubernetes.io/role/elb
          Value: "1"
        - Key: !Sub kubernetes.io/cluster/${ClusterName}
          Value: "owned"

  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.2.0/24
      AvailabilityZone: !Select [ 1, !GetAZs '' ]
      MapPublicIpOnLaunch: true
      Tags:
        - Key: kubernetes.io/role/elb
          Value: "1"
        - Key: !Sub kubernetes.io/cluster/${ClusterName}
          Value: "owned"

  InternetGateway:
    Type: AWS::EC2::InternetGateway

  AttachGateway:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  RouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC

  Route:
    Type: AWS::EC2::Route
    DependsOn: AttachGateway
    Properties:
      RouteTableId: !Ref RouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  SubnetRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet
      RouteTableId: !Ref RouteTable

  SubnetRouteTableAssociation2:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet2
      RouteTableId: !Ref RouteTable

  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

  NodeInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SubnetIds: [!Ref PublicSubnet, !Ref PublicSubnet2]
        EndpointPublicAccess: true

  NodeGroup:
    Type: AWS::EKS::Nodegroup
    Properties:
      ClusterName: !Ref EKSCluster
      NodeRole: !GetAtt NodeInstanceRole.Arn
      Subnets: [!Ref PublicSubnet, !Ref PublicSubnet2]
      ScalingConfig:
        DesiredSize: 2
        MinSize: 1
        MaxSize: 3
      InstanceTypes: [!Ref NodeInstanceType]

Outputs:
  ClusterName:
    Description: Name of the EKS Cluster
    Value: !Ref ClusterName

  VPCId:
    Value: !Ref VPC
    Description: VPC ID for future use

  Subnet1:
    Value: !Ref PublicSubnet
    Description: Public Subnet 1

  Subnet2:
    Value: !Ref PublicSubnet2
    Description: Public Subnet 2

  NodeRole:
    Value: !GetAtt NodeInstanceRole.Arn
    Description: Node IAM Role

  ClusterEndpoint:
    Value: !GetAtt EKSCluster.Endpoint
    Description: EKS API Server endpoint URL
```



### 2. Configure EKS Access
```bash
aws eks update-kubeconfig --region ap-southeast-1 --name betterwellness-cluster
```

---

## ⚙️ Load Balancer Controller Setup

### 1. Associate IAM OIDC Provider
```bash
eksctl utils associate-iam-oidc-provider   --region ap-southeast-1   --cluster betterwellness-cluster   --approve
```

### 2. Create IAM Service Account
```bash
eksctl create iamserviceaccount   --cluster betterwellness-cluster   --region ap-southeast-1   --namespace kube-system   --name aws-load-balancer-controller   --attach-policy-arn arn:aws:iam::529088268162:policy/AWSLoadBalancerControllerIAMPolicy   --approve
```

---

## 🛢️ DocumentDB Setup

### 1. Get Subnet IDs
```bash
aws ec2 describe-subnets   --filters "Name=vpc-id,Values=<VPC_ID>"   --query "Subnets[*].SubnetId"   --output text
```

### 2. Create DB Subnet Group
```bash
aws docdb create-db-subnet-group   --db-subnet-group-name eks-docdb-subnet-group   --db-subnet-group-description "Subnet group for DocumentDB in EKS VPC"   --subnet-ids subnet-xxxx subnet-yyyy
```

### 3. Deploy DocumentDB Stack
Use CloudFormation to deploy the DocumentDB stack using documentdb_full_stack.yaml template.

### 📄 `documentdb_full_stack.yaml`

```powershell
AWSTemplateFormatVersion: '2010-09-09'
Description: >
  AWS CloudFormation Template for Amazon DocumentDB Cluster and Instance with Subnet Group and VPC Security Groups.

Parameters:
  DBClusterName:
    Type: String
    Default: "MyCluster"
    Description: "DocumentDB Cluster Name"
    MinLength: 1
    MaxLength: 64
    AllowedPattern: "[a-zA-Z][a-zA-Z0-9]*(-[a-zA-Z0-9]+)*"
    ConstraintDescription: "Must begin with a letter and contain only alphanumeric characters."

  DBInstanceName:
    Type: String
    Default: "MyInstance"
    Description: "DocumentDB Instance Name"
    MinLength: 1
    MaxLength: 64
    AllowedPattern: "[a-zA-Z][a-zA-Z0-9]*(-[a-zA-Z0-9]+)*"
    ConstraintDescription: "Must begin with a letter and contain only alphanumeric characters."

  MasterUser:
    NoEcho: true
    Type: String
    Description: "Master username"
    MinLength: 1
    MaxLength: 16
    AllowedPattern: "[a-zA-Z][a-zA-Z0-9]*"
    ConstraintDescription: "Must begin with a letter and contain only alphanumeric characters."

  MasterPassword:
    NoEcho: true
    Type: String
    Description: "Master password"
    MinLength: 1
    MaxLength: 41
    AllowedPattern: "[a-zA-Z0-9]+"
    ConstraintDescription: "Must contain only alphanumeric characters."

  DBInstanceClass:
    Type: String
    Default: db.t3.medium
    Description: "DocumentDB Instance Class"
    AllowedValues:
      - db.t3.medium
      - db.r5.large
      - db.r5.xlarge
      - db.r5.2xlarge
      - db.r5.4xlarge
      - db.r5.12xlarge
      - db.r5.24xlarge
    ConstraintDescription: "Must be a valid DocumentDB instance class."

  DBSubnetGroupName:
    Type: String
    Description: "Existing DocumentDB Subnet Group Name"

  VPCSecurityGroupIds:
    Type: List<AWS::EC2::SecurityGroup::Id>
    Description: "List of VPC Security Group IDs to associate with DocumentDB"

Resources:
  DBCluster:
    Type: "AWS::DocDB::DBCluster"
    DeletionPolicy: Delete
    Properties:
      DBClusterIdentifier: !Ref DBClusterName
      MasterUsername: !Ref MasterUser
      MasterUserPassword: !Ref MasterPassword
      EngineVersion: 4.0.0
      DBSubnetGroupName: !Ref DBSubnetGroupName
      VpcSecurityGroupIds: !Ref VPCSecurityGroupIds

  DBInstance:
    Type: "AWS::DocDB::DBInstance"
    Properties:
      DBClusterIdentifier: !Ref DBCluster
      DBInstanceIdentifier: !Ref DBInstanceName
      DBInstanceClass: !Ref DBInstanceClass
    DependsOn: DBCluster

Outputs:
  ClusterId:
    Value: !Ref DBCluster
  ClusterEndpoint:
    Value: !GetAtt DBCluster.Endpoint
  ClusterPort:
    Value: !GetAtt DBCluster.Port
  EngineVersion:
    Value: "4.0.0"

```

### 📄 `deploy-docdb.ps1`

```powershell
# Set parameters
$VpcId = "vpc-0eeaedfc633ff1f06"                     # <-- Your VPC ID
$EksNodeSg = "sg-042e3bc9f9e1123a9"                  # <-- EKS Node SG ID
$StackName = "betterwellness-docdb-stack"
$TemplateFile = "documentdb_full_stack.yaml"

# DocumentDB parameters
$DbClusterName = "betterwellness-cluster"
$DbInstanceName = "betterwellness-db"
$MasterUser = "admin"
$MasterPassword = "MyStrongPassword123"
$DbInstanceClass = "db.t3.medium"
$DbSubnetGroupName = "eks-docdb-subnet-group"

Write-Host "Creating DocumentDB security group..."
$DocDbSgId = aws ec2 create-security-group `
    --group-name documentdb-access-sg `
    --description "Allow EKS to access DocumentDB on port 27017" `
    --vpc-id $VpcId `
    --query 'GroupId' `
    --output text

Write-Host "Security Group ID: $DocDbSgId"

Write-Host "Authorizing inbound port 27017 from EKS Node SG..."
aws ec2 authorize-security-group-ingress `
    --group-id $DocDbSgId `
    --protocol tcp `
    --port 27017 `
    --source-group $EksNodeSg

Write-Host "Deploying CloudFormation stack: $StackName"
aws cloudformation deploy `
    --template-file $TemplateFile `
    --stack-name $StackName `
    --capabilities CAPABILITY_NAMED_IAM `
    --parameter-overrides `
        DBClusterName=$DbClusterName `
        DBInstanceName=$DbInstanceName `
        MasterUser=$MasterUser `
        MasterPassword=$MasterPassword `
        DBInstanceClass=$DbInstanceClass `
        DBSubnetGroupName=$DbSubnetGroupName `
        VPCSecurityGroupIds=$DocDbSgId

Write-Host "`n✅ Deployment complete. DocumentDB Security Group ID: $DocDbSgId"
```

Update parameters for DocumentDB stack in the deploy-docdb.ps1 script  such as VpcId,EKSNodeSecurityGroupId,Database Username and Password and execute the script.



```bash
.\deploy-docdb.ps1
```

---

## 🔁 Redis Cluster Setup

- Choose: "Design your own cache"
- Create a new subnet group
- Select the EKS VPC
- Add an **Inbound Rule**: Port `6379`, Source: **EKS Node Security Group**

---

## 🔐 Grant EKS Access via aws-auth ConfigMap

To allow your IAM user or role to access the EKS cluster via `kubectl` or from the AWS Console:

### 1. Prepare `aws-auth` ConfigMap

Create a file called `aws-auth.yaml` with the following content:

```yaml
apiVersion: v1
data:
  mapRoles: |
    - rolearn: arn:aws:iam::529088268162:role/betterwellness-vpc-NodeInstanceRole-D9H3IwXROX1q
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: arn:aws:iam::529088268162:role/AWSCodePipelineServiceRole-ap-southeast-1-betterwellness-bookin
      username: codepipeline
      groups:
        - system:masters
  mapUsers: |
    - userarn: arn:aws:iam::529088268162:user/ravindra
      username: ravindra
      groups:
        - system:masters
    - userarn: arn:aws:iam::529088268162:root
      username: root
      groups:
        - system:masters
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system


```


### 2. Apply `aws-auth` ConfigMap

```bash
kubectl apply -f aws-auth.yaml
```

 
## BetterWellness EKS Deployment with AWS Secrets Manager Integration
### 🔐 Using AWS Secrets Manager with External Secrets

This setup allows your EKS workloads to securely fetch environment variables from AWS Secrets Manager using External Secrets Operator (ESO).

---

### ✅ 1. Create AWS Secret

Example:
```bash
aws secretsmanager create-secret \
  --name betterwellness-config \
  --description "App config for BetterWellness" \
  --secret-string '{
    "MONGODB_URI": "mongo-uri",
    "COGNITO_REGION": "ap-southeast-1",
    "COGNITO_USER_POOL_ID": "user-pool-id",
    "AWS_ACCESS_KEY_ID": "access-key",
    "AWS_SECRET_ACCESS_KEY": "secret-key",
    "SES_EMAIL": "email@example.com",
    "AWS_REGION": "ap-southeast-1",
    "SQS_QUEUE_URL": "https://sqs.ap-southeast-1.amazonaws.com/account-id/sqs-queue-url",
    "REDIS_HOST": "redis-host",
    "REDIS_PORT": "6379"
  }'
```

### ✅ 2.  Create IAM Role and Trust Policy (IRSA)
#### Create a trust policy (replace <ACCOUNT_ID>, <REGION>, and <OIDC_ID>):

```bash
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>:sub": "system:serviceaccount:default:eso-irsa"
      }
    }
  }]
}
```
#### Create the IAM Role:

```bash
aws iam create-role \
  --role-name BetterwellnessExternalSecretsRole \
  --assume-role-policy-document file://trust-policy.json
```

### ✅ 3. Attach SecretsManager Permissions

```bash
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["secretsmanager:GetSecretValue"],
    "Resource": "arn:aws:secretsmanager:<REGION>:<ACCOUNT_ID>:secret:betterwellness-config*"
  }]
}
```

#### Attach it:

```bash
aws iam put-role-policy \
  --role-name BetterwellnessExternalSecretsRole \
  --policy-name ExternalSecretsAccess \
  --policy-document file://secretsmanager-policy.json
```

### ✅ 4. Create IRSA-Enabled Kubernetes ServiceAccount

```bash
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eso-irsa
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/BetterwellnessExternalSecretsRole
```

#### Apply:

```bash
kubectl apply -f serviceaccount.yaml
```
### ✅ 5. Create SecretStore Resource

```bash
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-store
  namespace: default
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-southeast-1
      auth:
        jwt:
          serviceAccountRef:
            name: eso-irsa
```
#### Apply:

```bash
kubectl apply -f secretstore.yaml
```

### ✅ 6. Create ExternalSecret Resource

```bash
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: betterwellness-config
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-store
    kind: SecretStore
  target:
    name: betterwellness-config
  dataFrom:
    - extract:
        key: betterwellness-config

```
#### Apply:

```bash
kubectl apply -f external-secret.yaml
```

## 🚀 Deploy Microservices 


###  Deploy Booking-Service

### 📄 `booking-deployment.yaml`

```powershell
apiVersion: apps/v1
kind: Deployment
metadata:
  name: betterwellness-booking
spec:
  replicas: 2
  selector:
    matchLabels:
      app: betterwellness-booking
  template:
    metadata:
      labels:
        app: betterwellness-booking
    spec:
      imagePullSecrets:
        - name: regcred
      containers:
        - name: betterwellness-booking
          image: 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/booking-service:latest
          ports:
            - containerPort: 5002
          envFrom:
            - secretRef:
                name: betterwellness-config
          resources:
            limits:
              memory: "512Mi"
              cpu: "500m"
            requests:
              memory: "256Mi"
              cpu: "250m"
---
apiVersion: v1
kind: Service
metadata:
  name: betterwellness-booking-service
spec:
  selector:
    app: betterwellness-booking
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 5002
  type: ClusterIP
```


```bash
kubectl apply -f .\booking-deployment.yaml
```


### Deploy Counsellor-Service

### 📄 counsellor-deployment.yaml

```powershell
apiVersion: apps/v1
kind: Deployment
metadata:
  name: betterwellness-counsellor
spec:
  replicas: 2
  selector:
    matchLabels:
      app: betterwellness-counsellor
  template:
    metadata:
      labels:
        app: betterwellness-counsellor
    spec:
      imagePullSecrets:
        - name: regcred
      containers:
        - name: betterwellness-counsellor
          image: 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/counsellor-service:latest
          ports:
            - containerPort: 5000
          envFrom:
            - secretRef:
                name: betterwellness-config
          resources:
            limits:
              memory: "512Mi"
              cpu: "500m"
            requests:
              memory: "256Mi"
              cpu: "250m"
---
apiVersion: v1
kind: Service
metadata:
  name: betterwellness-counsellor-service
spec:
  selector:
    app: betterwellness-counsellor
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 5000
  type: ClusterIP

```
```bash
kubectl apply -f .\counsellor-deployment.yaml
```

### Deploy Messaging-Service

### 📄 messaging-deployment.yaml

```powershel
apiVersion: apps/v1
kind: Deployment
metadata:
  name: betterwellness-messaging
spec:
  replicas: 2
  selector:
    matchLabels:
      app: betterwellness-messaging
  template:
    metadata:
      labels:
        app: betterwellness-messaging
    spec:
      imagePullSecrets:
        - name: regcred
      containers:
        - name: betterwellness-messaging
          image: 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/messaging-service:latest
          ports:
            - containerPort: 5003
          envFrom:
            - secretRef:
                name: betterwellness-config
          resources:
            limits:
              memory: "512Mi"
              cpu: "500m"
            requests:
              memory: "256Mi"
              cpu: "250m"
---
apiVersion: v1
kind: Service
metadata:
  name: betterwellness-messaging-service
spec:
  selector:
    app: betterwellness-messaging
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 5003
  type: ClusterIP
```


```bash
kubectl apply -f  .\messaging-deployment.yaml
```

### Deploy User-Service

### 📄 user-deployment.yam

```powershel
apiVersion: apps/v1
kind: Deployment
metadata:
  name: betterwellness-user
spec:
  replicas: 2
  selector:
    matchLabels:
      app: betterwellness-user
  template:
    metadata:
      labels:
        app: betterwellness-user
    spec:
      imagePullSecrets:
        - name: regcred
      containers:
        - name: betterwellness-user
          image: 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/user-service:latest
          ports:
            - containerPort: 5001
          envFrom:
            - secretRef:
                name: betterwellness-config
          resources:
            limits:
              memory: "512Mi"
              cpu: "500m"
            requests:
              memory: "256Mi"
              cpu: "250m"
---
apiVersion: v1
kind: Service
metadata:
  name: betterwellness-user-service
spec:
  selector:
    app: betterwellness-user
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 5001
  type: ClusterIP
```

```bash
kubectl apply -f .\user-deployment.yaml
```

## 📊 Monitoring Setup (HPA + Metrics Server)

### 1. Install Metrics Server
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 2. Deploy HPAs

### 📄 hpa.yam

```powershe
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: betterwellness-booking-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: betterwellness-booking
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: betterwellness-counsellor-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: betterwellness-counsellor
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: betterwellness-messaging-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: betterwellness-messaging
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: betterwellness-user-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: betterwellness-user
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

```

```bash
kubectl apply -f hpa.yaml
```

---

## 🌐 Ingress and API Gateway

### 1. Get VPC ID
```bash
aws cloudformation describe-stacks   --stack-name betterwellness-vpc   --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue"   --output text
```

### 2. Install Load Balancer Controller via Helm
```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller   -n kube-system   --set clusterName=betterwellness-cluster   --set region=ap-southeast-1   --set vpcId=<VPC_ID>   --set serviceAccount.create=false   --set serviceAccount.name=aws-load-balancer-controller
```

### 3. Apply Ingress Configuration

### 📄 ingress.yaml

```powershell
# ingress-updated.yaml (For AWS ALB Ingress Controller)

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: betterwellness-ingress
  namespace: default
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}, {"HTTP": 80}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-southeast-1:529088268162:certificate/40a3caca-654e-4f0e-a36e-8dee4055255f
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=3600
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /booking
            pathType: Prefix
            backend:
              service:
                name: betterwellness-booking-service
                port:
                  number: 8080
          - path: /counsellor
            pathType: Prefix
            backend:
              service:
                name: betterwellness-counsellor-service
                port:
                  number: 8080
          - path: /user
            pathType: Prefix
            backend:
              service:
                name: betterwellness-user-service
                port:
                  number: 8080
          - path: /messaging
            pathType: Prefix
            backend:
              service:
                name: betterwellness-messaging-service
                port:
                  number: 8080
          - path: /socket.io
            pathType: Prefix
            backend:
              service:
                name: betterwellness-messaging-service
                port:
                  number: 8080
```


```bash
kubectl apply -f .\ingress.yaml
kubectl get ingress betterwellness-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 4. Deploy API Gateway
```bash
aws cloudformation deploy   --template-file betterwellness-routing.yaml   --stack-name betterwellness-api-gateway   --parameter-overrides ALBDnsName=<ALB_DNS>   --capabilities CAPABILITY_IAM
```

###  📄 betterwellness-routing.yaml

```powershell
AWSTemplateFormatVersion: '2010-09-09'
Description: API Gateway HTTP API with multiple routes to ALB

Parameters:
  ALBDnsName:
    Type: String
    Description: DNS name of the ALB (without http://)

Resources:

  # Create the HTTP API
  HttpApi:
    Type: AWS::ApiGatewayV2::Api
    Properties:
      Name: BetterWellnessAPI
      ProtocolType: HTTP
      CorsConfiguration:
        AllowMethods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
        AllowOrigins:
          - "https://master.d2awhgnsgb5r2e.amplifyapp.com"
        AllowHeaders:
          - "Content-Type"
          - "Authorization"
          - "X-Requested-With"
          - "Searchtext"
        AllowCredentials: true

  # -------- INTEGRATIONS --------
  CounsellorIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref HttpApi
      IntegrationType: HTTP_PROXY
      IntegrationMethod: ANY
      IntegrationUri: !Sub "http://${ALBDnsName}/counsellor/{proxy}"
      PayloadFormatVersion: "1.0"
      ConnectionType: INTERNET

  BookingIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref HttpApi
      IntegrationType: HTTP_PROXY
      IntegrationMethod: ANY
      IntegrationUri: !Sub "http://${ALBDnsName}/booking/{proxy}"
      PayloadFormatVersion: "1.0"
      ConnectionType: INTERNET

  UserIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref HttpApi
      IntegrationType: HTTP_PROXY
      IntegrationMethod: ANY
      IntegrationUri: !Sub "http://${ALBDnsName}/user/{proxy}"
      PayloadFormatVersion: "1.0"
      ConnectionType: INTERNET

  MessagingIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref HttpApi
      IntegrationType: HTTP_PROXY
      IntegrationMethod: ANY
      IntegrationUri: !Sub "http://${ALBDnsName}/messaging/{proxy}"
      PayloadFormatVersion: "1.0"
      ConnectionType: INTERNET

  SocketIOIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref HttpApi
      IntegrationType: HTTP_PROXY
      IntegrationMethod: ANY
      IntegrationUri: !Sub "http://${ALBDnsName}/socket.io/{proxy}"
      PayloadFormatVersion: "1.0"
      ConnectionType: INTERNET
      
  # -------- ROUTES --------
  CounsellorRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "ANY /counsellor/{proxy+}"
      Target: !Sub "integrations/${CounsellorIntegration}"

  BookingRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "ANY /booking/{proxy+}"
      Target: !Sub "integrations/${BookingIntegration}"

  UserRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "ANY /user/{proxy+}"
      Target: !Sub "integrations/${UserIntegration}"

  MessagingRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "ANY /messaging/{proxy+}"
      Target: !Sub "integrations/${MessagingIntegration}"
  SocketIORoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "ANY /socket.io/{proxy+}"
      Target: !Sub "integrations/${SocketIOIntegration}"
      
  # -------- OPTIONS ROUTES FOR CORS --------
  CounsellorOptionsRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "OPTIONS /counsellor/{proxy+}"
      Target: !Sub "integrations/${CounsellorIntegration}"

  BookingOptionsRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "OPTIONS /booking/{proxy+}"
      Target: !Sub "integrations/${BookingIntegration}"

  UserOptionsRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "OPTIONS /user/{proxy+}"
      Target: !Sub "integrations/${UserIntegration}"

  MessagingOptionsRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "OPTIONS /messaging/{proxy+}"
      Target: !Sub "integrations/${MessagingIntegration}"

  SocketIOOptionsRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref HttpApi
      RouteKey: "OPTIONS /socket.io/{proxy+}"
      Target: !Sub "integrations/${SocketIOIntegration}"

  # -------- STAGE --------
  HttpApiStage:
    Type: AWS::ApiGatewayV2::Stage
    Properties:
      ApiId: !Ref HttpApi
      StageName: "$default"
      AutoDeploy: true

Outputs:
  ApiEndpoint:
    Description: Base URL of the deployed API Gateway
    Value: !Sub "https://${HttpApi}.execute-api.${AWS::Region}.amazonaws.com"

```


## 🌐 DNS Setup

- Create an **A Record** in **Route 53**
- Point it to the **ALB DNS name**
---

### Restart Deployments
```bash
kubectl rollout restart deployment betterwellness-booking
kubectl rollout restart deployment betterwellness-counsellor
kubectl rollout restart deployment betterwellness-messaging
kubectl rollout restart deployment betterwellness-user
```

---

## 📈 Monitoring via Grafana (Loki)

### Setup Loki Stack + Grafana
```bash
 kubectl create namespace monitoring

 helm repo update

 helm upgrade --install loki grafana/loki-stack --namespace monitoring --create-namespace --set promtail.enabled=true --set grafana.enabled=true --set grafana.sidecar.datasources.enabled=true
```

### Port forwarding to Grafana UI

```bash
kubectl port-forward -n monitoring svc/loki-grafana 3000:80
```

### Access Grafana UI

```bash
http://localhost:3000

```

### Retrieve Admin Password
```powershell
$secret = kubectl get secret --namespace monitoring loki-grafana `
  -o jsonpath="{.data.admin-password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secret))
```

---

## 🗑️ Teardown / Cleanup

### Delete HPAs and Deployments
```bash
kubectl delete hpa betterwellness-booking-hpa
kubectl delete hpa betterwellness-counsellor-hpa
kubectl delete hpa betterwellness-messaging-hpa
kubectl delete hpa betterwellness-user-hpa

kubectl delete deployment betterwellness-booking
kubectl delete deployment betterwellness-counsellor
kubectl delete deployment betterwellness-messaging
kubectl delete deployment betterwellness-user
kubectl delete deployment redis

kubectl delete ingress betterwellness-ingress
```

### Delete CloudFormation Stacks
```bash
aws cloudformation delete-stack --stack-name betterwellness-api-gateway
aws cloudformation delete-stack --stack-name eksctl-betterwellness-cluster-addon-iamserviceaccount-kube-system-aws-load-balancer-controller
aws cloudformation delete-stack --stack-name betterwellness-vpc
```