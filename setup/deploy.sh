#!/bin/bash
# ================================================================
#  Baker App — FULL AWS Deploy Script
#  Creates: VPC, Subnets, IGW, Route Tables, Security Groups,
#           IAM Roles, ALB, Auto Scaling Group, RDS, S3,
#           Lambda, Rekognition, SNS
#
#  Person 3 runs this at the start of EVERY session.
#  Runtime: ~8-10 minutes
# ================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
head() { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────${NC}"; }

# ── CONFIG — Edit these ─────────────────────────────────────────
REGION="us-east-1"
AZ1="us-east-1a"
AZ2="us-east-1b"
YOUR_PHONE="+91XXXXXXXXXX"        # ← Replace with real number
DB_PASSWORD="BakerApp2026!"       # ← Change this
APP_NAME="baker-app"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${APP_NAME}-${ACCOUNT_ID}"
# ───────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   🥐 Baker App — Full AWS Deployment         ║${NC}"
echo -e "${BOLD}║   VPC + ALB + ASG + RDS + S3 + Lambda        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Account: $ACCOUNT_ID  |  Region: $REGION"
echo ""

# ════════════════════════════════════════════════════════════════
head "PHASE 1: VPC & NETWORKING"
# ════════════════════════════════════════════════════════════════

# ── VPC ─────────────────────────────────────────────────────────
info "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region $REGION \
  --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="${APP_NAME}-vpc"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
log "VPC: $VPC_ID (10.0.0.0/16)"

# ── Internet Gateway ─────────────────────────────────────────────
info "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="${APP_NAME}-igw"
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
log "Internet Gateway: $IGW_ID (attached to VPC)"

# ── Public Subnets (for ALB) ─────────────────────────────────────
info "Creating public subnets..."
PUB_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 \
  --availability-zone $AZ1 \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUB_SUBNET_1 --tags Key=Name,Value="${APP_NAME}-public-1a"
aws ec2 modify-subnet-attribute --subnet-id $PUB_SUBNET_1 --map-public-ip-on-launch

PUB_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 \
  --availability-zone $AZ2 \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUB_SUBNET_2 --tags Key=Name,Value="${APP_NAME}-public-1b"
aws ec2 modify-subnet-attribute --subnet-id $PUB_SUBNET_2 --map-public-ip-on-launch
log "Public Subnets: $PUB_SUBNET_1 (1a), $PUB_SUBNET_2 (1b)"

# ── Private Subnets (for EC2 App) ────────────────────────────────
info "Creating private app subnets..."
PRIV_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 \
  --availability-zone $AZ1 \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PRIV_SUBNET_1 --tags Key=Name,Value="${APP_NAME}-private-1a"

PRIV_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.4.0/24 \
  --availability-zone $AZ2 \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PRIV_SUBNET_2 --tags Key=Name,Value="${APP_NAME}-private-1b"
log "Private App Subnets: $PRIV_SUBNET_1 (1a), $PRIV_SUBNET_2 (1b)"

# ── DB Subnets (for RDS) ─────────────────────────────────────────
info "Creating DB subnets..."
DB_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.5.0/24 \
  --availability-zone $AZ1 \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $DB_SUBNET_1 --tags Key=Name,Value="${APP_NAME}-db-1a"

DB_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.6.0/24 \
  --availability-zone $AZ2 \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $DB_SUBNET_2 --tags Key=Name,Value="${APP_NAME}-db-1b"
log "DB Subnets: $DB_SUBNET_1 (1a), $DB_SUBNET_2 (1b)"

# ── Public Route Table ────────────────────────────────────────────
info "Configuring route tables..."
PUB_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $PUB_RT --tags Key=Name,Value="${APP_NAME}-public-rt"
aws ec2 create-route --route-table-id $PUB_RT \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID > /dev/null
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_SUBNET_1 > /dev/null
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_SUBNET_2 > /dev/null
log "Public Route Table → IGW (0.0.0.0/0)"

# ── NAT Gateway (for private subnets outbound) ────────────────────
info "Creating NAT Gateway (takes ~60s)..."
EIP=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NAT_GW=$(aws ec2 create-nat-gateway \
  --subnet-id $PUB_SUBNET_1 \
  --allocation-id $EIP \
  --query 'NatGateway.NatGatewayId' --output text)
aws ec2 create-tags --resources $NAT_GW --tags Key=Name,Value="${APP_NAME}-nat" 2>/dev/null || true
info "Waiting for NAT Gateway to be available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW
log "NAT Gateway: $NAT_GW"

# Private Route Table → NAT
PRIV_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $PRIV_RT --tags Key=Name,Value="${APP_NAME}-private-rt"
aws ec2 create-route --route-table-id $PRIV_RT \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW > /dev/null
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_SUBNET_1 > /dev/null
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_SUBNET_2 > /dev/null
log "Private Route Table → NAT Gateway"

# ════════════════════════════════════════════════════════════════
head "PHASE 2: SECURITY GROUPS & IAM"
# ════════════════════════════════════════════════════════════════

# ── ALB Security Group ────────────────────────────────────────────
info "Creating Security Groups..."
ALB_SG=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-alb-sg" \
  --description "Baker App ALB - allows HTTP/HTTPS from internet" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)
aws ec2 create-tags --resources $ALB_SG --tags Key=Name,Value="${APP_NAME}-alb-sg"
aws ec2 authorize-security-group-ingress --group-id $ALB_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $ALB_SG \
  --protocol tcp --port 443 --cidr 0.0.0.0/0
log "ALB-SG: $ALB_SG (80/443 from 0.0.0.0/0)"

# ── App Security Group (EC2) ─────────────────────────────────────
APP_SG=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-app-sg" \
  --description "Baker App EC2 - only from ALB" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)
aws ec2 create-tags --resources $APP_SG --tags Key=Name,Value="${APP_NAME}-app-sg"
aws ec2 authorize-security-group-ingress --group-id $APP_SG \
  --protocol tcp --port 80 --source-group $ALB_SG
aws ec2 authorize-security-group-ingress --group-id $APP_SG \
  --protocol tcp --port 8080 --source-group $ALB_SG
log "App-SG: $APP_SG (port 80/8080 from ALB-SG only)"

# ── DB Security Group (RDS) ──────────────────────────────────────
DB_SG=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-db-sg" \
  --description "Baker App RDS - only from App SG" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)
aws ec2 create-tags --resources $DB_SG --tags Key=Name,Value="${APP_NAME}-db-sg"
aws ec2 authorize-security-group-ingress --group-id $DB_SG \
  --protocol tcp --port 3306 --source-group $APP_SG
log "DB-SG: $DB_SG (port 3306 from App-SG only)"

# ── IAM Role for EC2 ─────────────────────────────────────────────
info "Creating IAM roles..."
aws iam create-role \
  --role-name "${APP_NAME}-ec2-role" \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]
  }' 2>/dev/null || true

for P in \
  "arn:aws:iam::aws:policy/AmazonS3FullAccess" \
  "arn:aws:iam::aws:policy/AmazonRekognitionFullAccess" \
  "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" \
  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"; do
  aws iam attach-role-policy --role-name "${APP_NAME}-ec2-role" --policy-arn "$P" 2>/dev/null || true
done

aws iam create-instance-profile \
  --instance-profile-name "${APP_NAME}-ec2-profile" 2>/dev/null || true
aws iam add-role-to-instance-profile \
  --instance-profile-name "${APP_NAME}-ec2-profile" \
  --role-name "${APP_NAME}-ec2-role" 2>/dev/null || true
log "EC2 IAM Role: ${APP_NAME}-ec2-role"

# ── IAM Role for Lambda ──────────────────────────────────────────
aws iam create-role \
  --role-name "${APP_NAME}-lambda-role" \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
  }' 2>/dev/null || true

for P in \
  "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
  "arn:aws:iam::aws:policy/AmazonS3FullAccess" \
  "arn:aws:iam::aws:policy/AmazonRekognitionFullAccess" \
  "arn:aws:iam::aws:policy/AmazonSNSFullAccess" \
  "arn:aws:iam::aws:policy/AmazonRDSDataFullAccess" \
  "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"; do
  aws iam attach-role-policy --role-name "${APP_NAME}-lambda-role" --policy-arn "$P" 2>/dev/null || true
done
log "Lambda IAM Role: ${APP_NAME}-lambda-role"

info "Waiting 15s for IAM to propagate..."
sleep 15

# ════════════════════════════════════════════════════════════════
head "PHASE 3: S3 BUCKET"
# ════════════════════════════════════════════════════════════════

info "Creating S3 bucket: $BUCKET_NAME..."
aws s3api create-bucket --bucket "$BUCKET_NAME" --region $REGION 2>/dev/null || true
aws s3api put-object --bucket "$BUCKET_NAME" --key "uploads/" 2>/dev/null || true
aws s3api put-object --bucket "$BUCKET_NAME" --key "results/" 2>/dev/null || true

aws s3api put-bucket-cors --bucket "$BUCKET_NAME" \
  --cors-configuration '{
    "CORSRules":[{"AllowedOrigins":["*"],"AllowedMethods":["GET","PUT","POST","DELETE"],"AllowedHeaders":["*"],"MaxAgeSeconds":3000}]
  }'

# Enable static website hosting
aws s3api put-bucket-website --bucket "$BUCKET_NAME" \
  --website-configuration '{"IndexDocument":{"Suffix":"index.html"}}'

# Public read for website files only
aws s3api put-bucket-policy --bucket "$BUCKET_NAME" \
  --policy "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{
      \"Effect\":\"Allow\",\"Principal\":\"*\",
      \"Action\":\"s3:GetObject\",
      \"Resource\":\"arn:aws:s3:::${BUCKET_NAME}/index.html\"
    }]
  }"
log "S3 Bucket: $BUCKET_NAME"

# ════════════════════════════════════════════════════════════════
head "PHASE 4: SNS"
# ════════════════════════════════════════════════════════════════

info "Creating SNS topic..."
SNS_TOPIC_ARN=$(aws sns create-topic \
  --name "${APP_NAME}-burnt-alerts" \
  --query 'TopicArn' --output text)

if [ "$YOUR_PHONE" != "+91XXXXXXXXXX" ]; then
  aws sns subscribe \
    --topic-arn "$SNS_TOPIC_ARN" \
    --protocol sms \
    --notification-endpoint "$YOUR_PHONE" > /dev/null
  log "SNS: $SNS_TOPIC_ARN (SMS → $YOUR_PHONE)"
else
  warn "SNS topic created but no phone set. Update YOUR_PHONE in this script."
fi

# ════════════════════════════════════════════════════════════════
head "PHASE 5: RDS DATABASE"
# ════════════════════════════════════════════════════════════════

info "Creating RDS subnet group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name "${APP_NAME}-db-subnet-group" \
  --db-subnet-group-description "Baker App DB Subnet Group" \
  --subnet-ids "$DB_SUBNET_1" "$DB_SUBNET_2" 2>/dev/null || true
log "RDS Subnet Group created"

info "Launching RDS MySQL (takes 3-5 mins)..."
aws rds create-db-instance \
  --db-instance-identifier "${APP_NAME}-db" \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version "8.0" \
  --master-username bakerapp \
  --master-user-password "$DB_PASSWORD" \
  --db-name bakerapp \
  --allocated-storage 20 \
  --db-subnet-group-name "${APP_NAME}-db-subnet-group" \
  --vpc-security-group-ids "$DB_SG" \
  --no-multi-az \
  --no-publicly-accessible \
  --backup-retention-period 1 \
  --region $REGION 2>/dev/null || true
log "RDS launching in background (db.t3.micro, MySQL 8.0)"
info "RDS takes ~5 mins — script continues while it provisions"

# ════════════════════════════════════════════════════════════════
head "PHASE 6: LAMBDA FUNCTION"
# ════════════════════════════════════════════════════════════════

LAMBDA_ROLE_ARN=$(aws iam get-role \
  --role-name "${APP_NAME}-lambda-role" \
  --query 'Role.Arn' --output text)

info "Packaging Lambda..."
cd "$(dirname "$0")/../lambda"
zip -q function.zip handler.py

aws lambda delete-function \
  --function-name "${APP_NAME}-handler" \
  --region $REGION 2>/dev/null || true

aws lambda create-function \
  --function-name "${APP_NAME}-handler" \
  --runtime python3.12 \
  --role "$LAMBDA_ROLE_ARN" \
  --handler handler.lambda_handler \
  --zip-file fileb://function.zip \
  --timeout 60 \
  --memory-size 256 \
  --region $REGION \
  --environment "Variables={
    SNS_TOPIC_ARN=$SNS_TOPIC_ARN,
    BUCKET_NAME=$BUCKET_NAME,
    DB_HOST=pending,
    DB_NAME=bakerapp,
    DB_USER=bakerapp,
    DB_PASS=$DB_PASSWORD
  }" > /dev/null
log "Lambda deployed: ${APP_NAME}-handler"

# Add S3 trigger
aws lambda add-permission \
  --function-name "${APP_NAME}-handler" \
  --statement-id "s3-invoke-$(date +%s)" \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
  --region $REGION > /dev/null 2>&1 || true

aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET_NAME" \
  --notification-configuration "{
    \"LambdaFunctionConfigurations\":[{
      \"LambdaFunctionArn\":\"arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${APP_NAME}-handler\",
      \"Events\":[\"s3:ObjectCreated:*\"],
      \"Filter\":{\"Key\":{\"FilterRules\":[{\"Name\":\"prefix\",\"Value\":\"uploads/\"}]}}
    }]
  }"
log "S3 → Lambda trigger configured"

# ════════════════════════════════════════════════════════════════
head "PHASE 7: EC2 LAUNCH TEMPLATE + ALB + AUTO SCALING"
# ════════════════════════════════════════════════════════════════

# Get latest Amazon Linux 2023 AMI
info "Finding latest Amazon Linux 2023 AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*" "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
  --output text)
log "AMI: $AMI_ID"

EC2_PROFILE_ARN="arn:aws:iam::${ACCOUNT_ID}:instance-profile/${APP_NAME}-ec2-profile"

# User Data script — installs app on EC2 boot
USER_DATA=$(cat <<'USERDATA'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip git
pip3 install flask boto3 pymysql gunicorn

# Create app directory
mkdir -p /app
cat > /app/app.py << 'PYEOF'
from flask import Flask, jsonify, request
import boto3, json, os

app = Flask(__name__)
s3 = boto3.client('s3', region_name='us-east-1')
BUCKET = os.environ.get('BUCKET_NAME', '')

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "Baker App"})

@app.route('/results/<filename>')
def get_result(filename):
    try:
        result_key = f"results/{filename}_result.json"
        obj = s3.get_object(Bucket=BUCKET, Key=result_key)
        return jsonify(json.loads(obj['Body'].read()))
    except Exception as e:
        return jsonify({"error": str(e)}), 404

@app.route('/')
def index():
    return "Baker App Backend Running!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
PYEOF

# Set bucket env var
echo "export BUCKET_NAME=${BUCKET_NAME}" >> /etc/environment
source /etc/environment

# Start app
cd /app && gunicorn -w 2 -b 0.0.0.0:80 app:app --daemon
USERDATA
)

ENCODED_USERDATA=$(echo "$USER_DATA" | base64 -w 0)

info "Creating EC2 Launch Template..."
LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "${APP_NAME}-lt" \
  --version-description "Baker App v1" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"IamInstanceProfile\": {\"Arn\": \"$EC2_PROFILE_ARN\"},
    \"SecurityGroupIds\": [\"$APP_SG\"],
    \"UserData\": \"$ENCODED_USERDATA\",
    \"TagSpecifications\": [{
      \"ResourceType\": \"instance\",
      \"Tags\": [{\"Key\": \"Name\", \"Value\": \"${APP_NAME}-server\"}]
    }]
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)
log "Launch Template: $LT_ID"

# ── ALB ──────────────────────────────────────────────────────────
info "Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${APP_NAME}-alb" \
  --subnets $PUB_SUBNET_1 $PUB_SUBNET_2 \
  --security-groups $ALB_SG \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)
log "ALB: $ALB_DNS"

# ── Target Group ──────────────────────────────────────────────────
TG_ARN=$(aws elbv2 create-target-group \
  --name "${APP_NAME}-tg" \
  --protocol HTTP --port 80 \
  --vpc-id $VPC_ID \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
log "Target Group created"

# ── ALB Listener ──────────────────────────────────────────────────
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN > /dev/null
log "ALB Listener: HTTP:80 → Target Group"

# ── Auto Scaling Group ────────────────────────────────────────────
info "Creating Auto Scaling Group..."
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${APP_NAME}-asg" \
  --launch-template "LaunchTemplateId=$LT_ID,Version=\$Latest" \
  --min-size 2 --max-size 5 --desired-capacity 2 \
  --target-group-arns $TG_ARN \
  --vpc-zone-identifier "${PRIV_SUBNET_1},${PRIV_SUBNET_2}" \
  --health-check-type ELB \
  --health-check-grace-period 120 \
  --tags "Key=Name,Value=${APP_NAME}-server,PropagateAtLaunch=true"

# Scale-out policy: CPU > 70%
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "${APP_NAME}-asg" \
  --policy-name "${APP_NAME}-scale-out" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},
    "TargetValue":70.0
  }' > /dev/null
log "Auto Scaling Group: min=2, max=5, scale on CPU>70%"

# ── Upload frontend to S3 ─────────────────────────────────────────
info "Uploading frontend..."
cd "$(dirname "$0")/../frontend"
# Inject ALB DNS into the HTML
sed "s|ALB_DNS_PLACEHOLDER|$ALB_DNS|g" index.html > /tmp/index_deploy.html
aws s3 cp /tmp/index_deploy.html "s3://${BUCKET_NAME}/index.html" \
  --content-type "text/html" > /dev/null
log "Frontend uploaded to S3"

WEBSITE_URL="http://${BUCKET_NAME}.s3-website-${REGION}.amazonaws.com"

# ════════════════════════════════════════════════════════════════
# Wait for RDS and update Lambda env
# ════════════════════════════════════════════════════════════════
head "PHASE 8: WAITING FOR RDS + FINAL CONFIG"

info "Waiting for RDS to be available (this takes ~5 mins)..."
aws rds wait db-instance-available \
  --db-instance-identifier "${APP_NAME}-db" \
  --region $REGION

DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "${APP_NAME}-db" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
log "RDS available: $DB_HOST"

# Update Lambda with real DB host
aws lambda update-function-configuration \
  --function-name "${APP_NAME}-handler" \
  --environment "Variables={
    SNS_TOPIC_ARN=$SNS_TOPIC_ARN,
    BUCKET_NAME=$BUCKET_NAME,
    DB_HOST=$DB_HOST,
    DB_NAME=bakerapp,
    DB_USER=bakerapp,
    DB_PASS=$DB_PASSWORD
  }" --region $REGION > /dev/null
log "Lambda updated with RDS endpoint"

# ════════════════════════════════════════════════════════════════
# DONE
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║         ✅ FULL DEPLOYMENT COMPLETE!                ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║  🏗️  VPC:        $VPC_ID${NC}"
echo -e "${GREEN}║  🌐 IGW:        $IGW_ID${NC}"
echo -e "${GREEN}║  🔒 ALB-SG:     $ALB_SG${NC}"
echo -e "${GREEN}║  🔒 App-SG:     $APP_SG${NC}"
echo -e "${GREEN}║  🔒 DB-SG:      $DB_SG${NC}"
echo -e "${GREEN}║  ⚖️  ALB:        $ALB_DNS${NC}"
echo -e "${GREEN}║  📦 S3 Bucket:  $BUCKET_NAME${NC}"
echo -e "${GREEN}║  🗄️  RDS Host:   $DB_HOST${NC}"
echo -e "${GREEN}║  📱 SNS Topic:  $SNS_TOPIC_ARN${NC}"
echo -e "${GREEN}║  🌐 Website:    $WEBSITE_URL${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║  ⚠️  SAVE THESE — share with your team!              ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🧪 Quick test:${NC}"
echo "   aws s3 cp cake.jpg s3://${BUCKET_NAME}/uploads/cake.jpg"
echo "   aws logs tail /aws/lambda/${APP_NAME}-handler --follow"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Before session ends, run:${NC}"
echo "   ./setup/cleanup.sh   (stops RDS + NAT to save credits)"
echo ""

# Save config to file for teammates
cat > "$(dirname "$0")/session-config.txt" << CONFIG
BUCKET_NAME=$BUCKET_NAME
ALB_DNS=$ALB_DNS
WEBSITE_URL=$WEBSITE_URL
SNS_TOPIC_ARN=$SNS_TOPIC_ARN
DB_HOST=$DB_HOST
VPC_ID=$VPC_ID
REGION=$REGION
CONFIG
log "Config saved to setup/session-config.txt — share this with your team!"
