# deploy-all.ps1

Write-Host " Verifying EKS cluster connection..."
if (-not (kubectl get nodes)) {
    Write-Error " Could not connect to EKS. Run:
aws eks update-kubeconfig --region ap-southeast-1 --name betterwellness-cluster"
    exit 1
}

Write-Host " Applying ConfigMap..."
kubectl apply -f configmap.yaml

$services = @(
    "user-deployment.yaml",
    "booking-deployment.yaml",
    "counsellor-deployment.yaml",
    "messaging-deployment.yaml"
)

Write-Host " Deploying services..."
foreach ($svc in $services) {
    Write-Host " Applying $svc"
    kubectl apply -f $svc
}

Write-Host "... Waiting for LoadBalancer EXTERNAL-IP..."
kubectl get svc --watch
