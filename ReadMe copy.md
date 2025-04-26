 aws cloudformation deploy --template-file betterwellness-vpc.yaml --stack-name betterwellness-vpc   --capabilities CAPABILITY_NAMED_IAM

aws eks update-kubeconfig --region ap-southeast-1 --name betterwellness-cluster


eksctl utils associate-iam-oidc-provider --region ap-southeast-1  --cluster betterwellness-cluster  --approve

eksctl create iamserviceaccount --cluster betterwellness-cluster  --region ap-southeast-1  --namespace kube-system --name aws-load-balancer-controller --attach-policy-arn arn:aws:iam::529088268162:policy/AWSLoadBalancerControllerIAMPolicy --approve


// create document db cluster 

// get subnet ids from created VPC 
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0903a20d009b6fa7f" --query "Subnets[*].SubnetId"  --output text

// create subnet group for enable doc db access to EKS 
aws docdb create-db-subnet-group --db-subnet-group-name eks-docdb-subnet-group --db-subnet-group-description "Subnet group for DocumentDB in EKS VPC" --subnet-ids subnet-0d19b9c85d132afd2 subnet-0d00ce9d068b1e341

// then create Document DB cluster selecting EKS VPC and created subnet Group

// while creating a redis cluster want to select "Design your own cache" and "Create a new subnet group"
then select VPC ID which created for EKS
add inbound rule with port 6379 , source to EKS SG


.\deploy-all.ps1

// install metrix server for HPA 
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml


kubectl apply -f hpa.yaml

kubectl get pods
kubectl get svc
kubectl get hpa


// get VPC id and set to vpcId
aws cloudformation describe-stacks --stack-name betterwellness-vpc --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" --output text

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=betterwellness-cluster --set region=ap-southeast-1   --set vpcId=vpc-0903a20d009b6fa7f   --set serviceAccount.create=false   --set serviceAccount.name=aws-load-balancer-controller

//check
kubectl get pods -n kube-system

execute ingress deployment
kubectl apply -f .\ingress.yaml 


// get ALB DNS
kubectl get ingress betterwellness-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

// deploy API Gateway
aws cloudformation deploy --template-file betterwellness-routing.yaml --stack-name betterwellness-api-gateway --parameter-overrides ALBDnsName=k8s-default-betterwe-4524c49168-922186776.ap-southeast-1.elb.amazonaws.com --capabilities CAPABILITY_IAM


aws apigatewayv2 update-route  --api-id bdoazp5j9b  --route-id j86i6ok  --authorization-type JWT  --authorizer-id d33q6c   --region ap-southeast-1
aws apigatewayv2 update-route  --api-id bdoazp5j9b  --route-id 4r3f0r9  --authorization-type JWT  --authorizer-id d33q6c   --region ap-southeast-1
aws apigatewayv2 update-route  --api-id bdoazp5j9b  --route-id 0wyu2ha  --authorization-type JWT  --authorizer-id d33q6c   --region ap-southeast-1
aws apigatewayv2 update-route  --api-id bdoazp5j9b  --route-id m5ruais  --authorization-type JWT  --authorizer-id d33q6c   --region ap-southeast-1



  
make route 53 - A Record for with  ALB DNS to Domain 


-- To find your AWS EKS cluster's OIDC provider ID (<OIDC_ID>), follow one of the methods below:
 aws eks describe-cluster --name betterwellness-cluster --query "cluster.identity.oidc.issuer" --output text

aws iam create-role --role-name BetterwellnessExternalSecretsRole  --assume-role-policy-document file://trust-policy.json

 Attach IAM Policy to Access SecretsManager
 
 aws iam put-role-policy  --role-name BetterwellnessExternalSecretsRole  --policy-name ExternalSecretsAccess  --policy-document file://secretsmanager-policy.json


---- ECR Connecting 
 
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com

docker build -t betterwellness-booking-service .
docker tag betterwellness-booking-service:latest 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/booking-service:latest
docker push 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/booking-service:latest

docker build -t betterwellness-counsellor-service .
docker tag betterwellness-counsellor-service:latest 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/counsellor-service:latest
docker push 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/counsellor-service:latest

docker build -t betterwellness-messaging-service .
docker tag betterwellness-messaging-service:latest 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/messaging-service:latest
docker push 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/messaging-service:latest

docker build -t betterwellness-user-service .
docker tag betterwellness-user-service:latest 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/user-service:latest
docker push 529088268162.dkr.ecr.ap-southeast-1.amazonaws.com/betterwellness/user-service:latest

-- rollout restart deployments
kubectl rollout restart deployment betterwellness-booking
kubectl rollout restart deployment betterwellness-counsellor
kubectl rollout restart deployment betterwellness-messaging
kubectl rollout restart deployment betterwellness-user


---- MNITRING -----
--- Install Prometheus in Your EKS Cluster

helm upgrade --install loki grafana/loki-stack  --namespace monitoring --create-namespace   --set promtail.enabled=true   --set grafana.enabled=true   --set grafana.sidecar.datasources.enabled=true

helm install prometheus prometheus-community/prometheus  --namespace monitoring --create-namespace   --set server.persistentVolume.enabled=false


helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/prometheus --namespace monitoring --create-namespace

kubectl port-forward -n monitoring svc/loki-grafana 3000:80

GRAPHANA Password
$secret = kubectl get secret --namespace monitoring loki-grafana `
  -o jsonpath="{.data.admin-password}"

[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secret))

admin
2ZaG1WXAmTARzu9Rso8KGH6C5jE2puahQtXgq25w





----- DELETING INFRA

DELETE DEPLOYMENTS

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

DELETE cloudformation stacks
------------------------------------
aws cloudformation delete-stack --stack-name betterwellness-api-gateway
aws cloudformation delete-stack --stack-name eksctl-betterwellness-cluster-addon-iamserviceaccount-kube-system-aws-load-balancer-controller
aws cloudformation delete-stack --stack-name betterwellness-vpc
