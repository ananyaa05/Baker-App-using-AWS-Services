# 🥐 Baker App using Full AWS Architecture
> Upload a cake photo → AI identifies it → get a recipe → SMS if burnt

**All required AWS services included:**
VPC · Internet Gateway · Subnets · Security Groups · IAM · ALB · Auto Scaling · RDS · S3 · Lambda · Rekognition · SNS

---
Website: http://baker-app-917283673359.s3-website-us-east-1.amazonaws.com

ALB: baker-app-alb-1690844298.us-east-1.elb.amazonaws.com

RDS: baker-app-db.cveky4ocex4y.us-east-1.rds.amazonaws.com

---

## How It All Works Together

```
Internet
   ↓
Internet Gateway (VPC entry point)
   ↓
ALB — public subnets (load balances traffic)
   ↓
EC2 instances — private subnets (Flask app, Auto Scaling Group)
   ↓
S3 ← EC2 uploads photo here
   ↓ (ObjectCreated trigger)
Lambda — auto fires
   ↓
Rekognition — identifies the pastry
   ↓
RDS — Lambda saves detection result
   ↓
SNS — SMS if burnt detected
   ↓
Result JSON saved back to S3
   ↓
EC2 reads result → returns to frontend → User sees recipe
```

## File Structure
```
baker-app/
├── frontend/
│   └── index.html          ← Upload UI 
├── lambda/
│   └── handler.py          ← Rekognition + SNS + RDS logic 
├── backend/
│   └── app.py              ← Flask API on EC2 
├── setup/
│   ├── deploy.sh           ← Creates ALL AWS resources 
│   ├── cleanup.sh          ← Destroys expensive resources 
│   └── session-config.txt  ← Auto-generated after deploy
└── README.md
```
---
