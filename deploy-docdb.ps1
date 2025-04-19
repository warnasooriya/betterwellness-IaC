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
