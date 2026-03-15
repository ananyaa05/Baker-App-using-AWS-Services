#!/bin/bash
# ================================================================
#  Baker App — FIXED Deploy Script (all sandbox issues resolved)
#  Fixes: LabRole, S3 public access, no ! in passwords
#  Runtime: ~8-10 minutes
# ================================================================

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
head() { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────${NC}"; }

REGION="us-east-1"
AZ1="us-east-1a"
AZ2="us-east-1b"
YOUR_PHONE="+919582223942"
DB_PASSWORD="BakerApp2026"
APP_NAME="baker-app"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${APP_NAME}-${ACCOUNT_ID}"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   🥐 Baker App — Full AWS Deployment         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
info "Account: $ACCOUNT_ID | Region: $REGION"

head "PHASE 1: VPC & NETWORKING"
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region $REGION --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="${APP_NAME}-vpc"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
log "VPC: $VPC_ID"

IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="${APP_NAME}-igw"
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
log "Internet Gateway: $IGW_ID"

PUB_SUBNET_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUB_SUBNET_1 --tags Key=Name,Value="${APP_NAME}-public-1a"
aws ec2 modify-subnet-attribute --subnet-id $PUB_SUBNET_1 --map-public-ip-on-launch

PUB_SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone $AZ2 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUB_SUBNET_2 --tags Key=Name,Value="${APP_NAME}-public-1b"
aws ec2 modify-subnet-attribute --subnet-id $PUB_SUBNET_2 --map-public-ip-on-launch

PRIV_SUBNET_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PRIV_SUBNET_1 --tags Key=Name,Value="${APP_NAME}-private-1a"

PRIV_SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.4.0/24 --availability-zone $AZ2 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PRIV_SUBNET_2 --tags Key=Name,Value="${APP_NAME}-private-1b"

DB_SUBNET_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.5.0/24 --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $DB_SUBNET_1 --tags Key=Name,Value="${APP_NAME}-db-1a"

DB_SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.6.0/24 --availability-zone $AZ2 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $DB_SUBNET_2 --tags Key=Name,Value="${APP_NAME}-db-1b"
log "6 Subnets created"

PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $PUB_RT --tags Key=Name,Value="${APP_NAME}-public-rt"
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID > /dev/null
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_SUBNET_1 > /dev/null
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_SUBNET_2 > /dev/null
log "Public Route Table -> IGW"

info "Creating NAT Gateway (~60s)..."
EIP=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NAT_GW=$(aws ec2 create-nat-gateway --subnet-id $PUB_SUBNET_1 --allocation-id $EIP --query 'NatGateway.NatGatewayId' --output text)
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW
log "NAT Gateway: $NAT_GW"

PRIV_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $PRIV_RT --tags Key=Name,Value="${APP_NAME}-private-rt"
aws ec2 create-route --route-table-id $PRIV_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW > /dev/null
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_SUBNET_1 > /dev/null
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_SUBNET_2 > /dev/null
log "Private Route Table -> NAT"

head "PHASE 2: SECURITY GROUPS"
ALB_SG=$(aws ec2 create-security-group --group-name "${APP_NAME}-alb-sg" --description "Baker ALB SG" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $ALB_SG --tags Key=Name,Value="${APP_NAME}-alb-sg"
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0
log "ALB-SG: $ALB_SG"

APP_SG=$(aws ec2 create-security-group --group-name "${APP_NAME}-app-sg" --description "Baker App SG" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $APP_SG --tags Key=Name,Value="${APP_NAME}-app-sg"
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 80 --source-group $ALB_SG
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 8080 --source-group $ALB_SG
log "App-SG: $APP_SG"

DB_SG=$(aws ec2 create-security-group --group-name "${APP_NAME}-db-sg" --description "Baker DB SG" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $DB_SG --tags Key=Name,Value="${APP_NAME}-db-sg"
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 3306 --source-group $APP_SG
log "DB-SG: $DB_SG"

head "PHASE 3: IAM (using LabRole - sandbox restriction)"
LAMBDA_ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)
log "LabRole ARN: $LAMBDA_ROLE_ARN"

head "PHASE 4: S3 BUCKET"
aws s3api create-bucket --bucket "$BUCKET_NAME" --region $REGION 2>/dev/null || true
aws s3api put-object --bucket "$BUCKET_NAME" --key "uploads/" 2>/dev/null || true
aws s3api put-object --bucket "$BUCKET_NAME" --key "results/" 2>/dev/null || true

# FIX: Unblock public access BEFORE bucket policy
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

aws s3api put-bucket-cors --bucket "$BUCKET_NAME" \
  --cors-configuration '{"CORSRules":[{"AllowedOrigins":["*"],"AllowedMethods":["GET","PUT","POST","DELETE"],"AllowedHeaders":["*"],"MaxAgeSeconds":3000}]}'

aws s3api put-bucket-website --bucket "$BUCKET_NAME" \
  --website-configuration '{"IndexDocument":{"Suffix":"index.html"}}'

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" \
  --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::${BUCKET_NAME}/index.html\"}]}"
log "S3 Bucket: $BUCKET_NAME"

head "PHASE 5: SNS"
SNS_TOPIC_ARN=$(aws sns create-topic --name "${APP_NAME}-burnt-alerts" --query 'TopicArn' --output text)
aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol sms --notification-endpoint "$YOUR_PHONE" > /dev/null
log "SNS Topic + Phone subscribed"

head "PHASE 6: RDS"
aws rds create-db-subnet-group \
  --db-subnet-group-name "${APP_NAME}-db-subnet-group" \
  --db-subnet-group-description "Baker App DB Subnet Group" \
  --subnet-ids "$DB_SUBNET_1" "$DB_SUBNET_2" 2>/dev/null || true

info "Launching RDS MySQL (script continues while it provisions)..."
aws rds create-db-instance \
  --db-instance-identifier "${APP_NAME}-db" \
  --db-instance-class db.t3.micro \
  --engine mysql --engine-version "8.0" \
  --master-username bakerapp \
  --master-user-password "$DB_PASSWORD" \
  --db-name bakerapp --allocated-storage 20 \
  --db-subnet-group-name "${APP_NAME}-db-subnet-group" \
  --vpc-security-group-ids "$DB_SG" \
  --no-multi-az --no-publicly-accessible \
  --backup-retention-period 1 --region $REGION 2>/dev/null || true
log "RDS launching in background"

head "PHASE 7: LAMBDA"
cd "$(dirname "$0")/../lambda"
zip -q function.zip handler.py
aws lambda delete-function --function-name "${APP_NAME}-handler" --region $REGION 2>/dev/null || true
sleep 3
aws lambda create-function \
  --function-name "${APP_NAME}-handler" \
  --runtime python3.12 --role "$LAMBDA_ROLE_ARN" \
  --handler handler.lambda_handler \
  --zip-file fileb://function.zip \
  --timeout 60 --memory-size 256 --region $REGION \
  --environment "Variables={SNS_TOPIC_ARN=${SNS_TOPIC_ARN},BUCKET_NAME=${BUCKET_NAME},DB_HOST=pending,DB_NAME=bakerapp,DB_USER=bakerapp,DB_PASS=${DB_PASSWORD}}" > /dev/null
log "Lambda deployed"

aws lambda add-permission \
  --function-name "${APP_NAME}-handler" \
  --statement-id "s3-trigger" \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
  --region $REGION > /dev/null 2>&1 || true

aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET_NAME" \
  --notification-configuration "{\"LambdaFunctionConfigurations\":[{\"LambdaFunctionArn\":\"arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${APP_NAME}-handler\",\"Events\":[\"s3:ObjectCreated:*\"],\"Filter\":{\"Key\":{\"FilterRules\":[{\"Name\":\"prefix\",\"Value\":\"uploads/\"}]}}}]}"
log "S3 trigger connected"

head "PHASE 8: ALB + AUTO SCALING"
AMI_ID=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*" "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
log "AMI: $AMI_ID"

aws ec2 create-launch-template \
  --launch-template-name "${APP_NAME}-lt" \
  --launch-template-data "{\"ImageId\":\"${AMI_ID}\",\"InstanceType\":\"t3.micro\",\"SecurityGroupIds\":[\"${APP_SG}\"],\"TagSpecifications\":[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${APP_NAME}-server\"}]}]}" > /dev/null
log "Launch Template created"

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${APP_NAME}-alb" \
  --subnets $PUB_SUBNET_1 $PUB_SUBNET_2 \
  --security-groups $ALB_SG --scheme internet-facing --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)
log "ALB: $ALB_DNS"

TG_ARN=$(aws elbv2 create-target-group \
  --name "${APP_NAME}-tg" --protocol HTTP --port 80 \
  --vpc-id $VPC_ID --health-check-path /health \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN > /dev/null
log "Target Group + Listener created"

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${APP_NAME}-asg" \
  --launch-template "LaunchTemplateName=${APP_NAME}-lt,Version=\$Latest" \
  --min-size 2 --max-size 5 --desired-capacity 2 \
  --target-group-arns $TG_ARN \
  --vpc-zone-identifier "${PRIV_SUBNET_1},${PRIV_SUBNET_2}" \
  --health-check-type ELB --health-check-grace-period 120
log "Auto Scaling Group: min=2, max=5"

head "PHASE 9: WAITING FOR RDS"
info "Waiting for RDS (~5 mins)..."
aws rds wait db-instance-available --db-instance-identifier "${APP_NAME}-db" --region $REGION
DB_HOST=$(aws rds describe-db-instances --db-instance-identifier "${APP_NAME}-db" --query 'DBInstances[0].Endpoint.Address' --output text)
log "RDS ready: $DB_HOST"

aws lambda update-function-configuration \
  --function-name "${APP_NAME}-handler" \
  --environment "Variables={SNS_TOPIC_ARN=${SNS_TOPIC_ARN},BUCKET_NAME=${BUCKET_NAME},DB_HOST=${DB_HOST},DB_NAME=bakerapp,DB_USER=bakerapp,DB_PASS=${DB_PASSWORD}}" \
  --region $REGION > /dev/null
log "Lambda updated with RDS endpoint"

head "PHASE 10: UPLOAD FRONTEND"
cd "$(dirname "$0")/../frontend"
sed "s|ALB_DNS_PLACEHOLDER|${ALB_DNS}|g" index.html > /tmp/index_deploy.html
aws s3 cp /tmp/index_deploy.html "s3://${BUCKET_NAME}/index.html" --content-type "text/html" > /dev/null
log "Frontend uploaded"

WEBSITE_URL="http://${BUCKET_NAME}.s3-website-${REGION}.amazonaws.com"

cat > "$(dirname "$0")/session-config.txt" << CONFIG
BUCKET_NAME=$BUCKET_NAME
ALB_DNS=$ALB_DNS
WEBSITE_URL=$WEBSITE_URL
SNS_TOPIC_ARN=$SNS_TOPIC_ARN
DB_HOST=$DB_HOST
VPC_ID=$VPC_ID
ACCOUNT_ID=$ACCOUNT_ID
REGION=$REGION
CONFIG

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║         ✅ DEPLOYMENT COMPLETE!                     ║${NC}"
echo -e "${GREEN}║  🌐 Website:  $WEBSITE_URL ${NC}"
echo -e "${GREEN}║  ⚖️  ALB:      $ALB_DNS ${NC}"
echo -e "${GREEN}║  🗄️  RDS:      $DB_HOST ${NC}"
echo -e "${GREEN}║  📦 S3:       $BUCKET_NAME ${NC}"
echo -e "${YELLOW}║  ⚠️  Run cleanup.sh before session ends!             ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
log "Config saved to setup/session-config.txt"
