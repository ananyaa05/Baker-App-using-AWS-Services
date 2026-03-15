#!/bin/bash
# ================================================================
#  Baker App — Cleanup Script
#  Run this BEFORE your session ends to save credits!
#  Deletes expensive resources (NAT GW, RDS, ALB, ASG, EC2)
#  Safe resources (S3, Lambda, SNS, IAM) are kept.
# ================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

REGION="us-east-1"
APP_NAME="baker-app"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║   🧹 Baker App — Cleanup (Save Credits)  ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Delete ASG ──────────────────────────────────────────────────
echo -e "${YELLOW}Deleting Auto Scaling Group...${NC}"
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name "${APP_NAME}-asg" \
  --force-delete 2>/dev/null && echo -e "${GREEN}✅ ASG deleted${NC}" || echo "ℹ️  ASG not found"

sleep 10

# ── Delete ALB + Target Group ────────────────────────────────────
echo -e "${YELLOW}Deleting Load Balancer...${NC}"
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "${APP_NAME}-alb" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ "$ALB_ARN" != "None" ] && [ -n "$ALB_ARN" ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" 2>/dev/null
  echo -e "${GREEN}✅ ALB deleted${NC}"
fi

TG_ARN=$(aws elbv2 describe-target-groups \
  --names "${APP_NAME}-tg" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
if [ "$TG_ARN" != "None" ] && [ -n "$TG_ARN" ]; then
  sleep 5
  aws elbv2 delete-target-group --target-group-arn "$TG_ARN" 2>/dev/null
  echo -e "${GREEN}✅ Target Group deleted${NC}"
fi

# ── Delete RDS ───────────────────────────────────────────────────
echo -e "${YELLOW}Deleting RDS instance (takes ~3 mins)...${NC}"
aws rds delete-db-instance \
  --db-instance-identifier "${APP_NAME}-db" \
  --skip-final-snapshot \
  --region $REGION 2>/dev/null && echo -e "${GREEN}✅ RDS deletion started${NC}" || echo "ℹ️  RDS not found"

# ── Delete NAT Gateway + release EIP ────────────────────────────
echo -e "${YELLOW}Deleting NAT Gateway...${NC}"
NAT_ID=$(aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=${APP_NAME}-nat" "Name=state,Values=available" \
  --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null)

if [ "$NAT_ID" != "None" ] && [ -n "$NAT_ID" ]; then
  aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" > /dev/null
  echo -e "${GREEN}✅ NAT Gateway deletion started: $NAT_ID${NC}"
  echo "ℹ️  Waiting 60s for NAT GW to delete before releasing EIP..."
  sleep 60
  # Release Elastic IP
  ALLOC_ID=$(aws ec2 describe-addresses \
    --query "Addresses[?AssociationId==null].AllocationId" \
    --output text 2>/dev/null | head -1)
  if [ -n "$ALLOC_ID" ]; then
    aws ec2 release-address --allocation-id "$ALLOC_ID" 2>/dev/null
    echo -e "${GREEN}✅ Elastic IP released${NC}"
  fi
fi

# ── Delete VPC resources ─────────────────────────────────────────
echo -e "${YELLOW}Cleaning up VPC...${NC}"
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${APP_NAME}-vpc" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  # Delete subnets
  for SUBNET in $(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].SubnetId' --output text); do
    aws ec2 delete-subnet --subnet-id "$SUBNET" 2>/dev/null || true
  done

  # Delete route tables (non-main)
  for RT in $(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text); do
    aws ec2 delete-route-table --route-table-id "$RT" 2>/dev/null || true
  done

  # Detach + delete IGW
  IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
  if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" 2>/dev/null || true
  fi

  # Delete security groups (non-default)
  for SG in $(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    aws ec2 delete-security-group --group-id "$SG" 2>/dev/null || true
  done

  # Delete VPC
  aws ec2 delete-vpc --vpc-id "$VPC_ID" 2>/dev/null && \
    echo -e "${GREEN}✅ VPC deleted${NC}" || echo "ℹ️  VPC still has dependencies — retry in 1 min"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ Cleanup done! Credits preserved.    ║${NC}"
echo -e "${GREEN}║   S3, Lambda, SNS, IAM kept intact.      ║${NC}"
echo -e "${GREEN}║   Run deploy.sh next session to rebuild. ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
