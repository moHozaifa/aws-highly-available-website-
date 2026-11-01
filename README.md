# Fault-Tolerant Multi-AZ Web Application on AWS

A highly available web application deployed across 2 Availability Zones
using an Application Load Balancer and Auto Scaling Group.

## Architecture
![Architecture](architecture/architecture-diagram.png)

## Services Used
VPC, EC2, Application Load Balancer, Auto Scaling, S3, IAM, CloudWatch, SNS

## What I Built
- Custom VPC with 2 public subnets in different AZs, Internet Gateway, route table
- Auto Scaling Group (min 2, max 4) with a launch template and Nginx user-data script
- Application Load Balancer with health checks
- Least-privilege IAM role (S3 read only), no hardcoded credentials
- Security group chaining: ALB -> EC2
- CloudWatch alarm + SNS email alert for unhealthy hosts

## Test Results
| Test | Result | Screenshot |
|---|---|---|
| Load balancing across 2 instances | Instance ID changed on refresh | screenshots/06-site-two-instances.png |
| Failover (terminated 1 instance) | Site stayed up, ASG launched replacement | screenshots/08-asg-replacement.png |
| Scale-out under CPU load | New instance launched | screenshots/09-scale-out.png |

## Problems Faced and Fixes
## Problems Faced and Fixes

### 1. Targets showed "Unhealthy" in the Target Group
- **Problem:** The ALB showed 503 and both instances stayed unhealthy.
- **Cause:** The web server security group did not allow HTTP from the ALB security group.
- **Fix:** Added an inbound HTTP rule on `ha-web-sg` with source `ha-alb-sg`.
- **Learning:** Security group chaining must allow the ALB, not just the internet.

### 2. Website showed the default Nginx page instead of my page
- **Problem:** The page said "Welcome to nginx".
- **Cause:** The S3 download in the user-data script failed because the bucket name was wrong.
- **Fix:** Corrected the bucket name in the launch template and the IAM policy ARN, then refreshed the instances.
- **Learning:** I checked `/var/log/cloud-init-output.log` via Session Manager to find the error.

### 3. Page loaded but showed "INSTANCE_INFO" text
- **Problem:** The instance ID was not replaced on the page.
- **Cause:** The `sed` line in user data was copied incorrectly.
- **Fix:** Re-copied the script, created a new launch template version, and updated the Auto Scaling Group.
- **Learning:** Launch templates are versioned; changing one does not update running instances.

### 4. Site not opening in the browser
- **Problem:** Browser showed "site can't be reached".
- **Cause:** I used `https://` but the ALB listener only supports HTTP on port 80.
- **Fix:** Used `http://` with the ALB DNS name.
- **Learning:** HTTPS needs a certificate (ACM) and a 443 listener.

### 5. Instances were healthy but replacement took a while
- **Problem:** After terminating an instance, the new one took a few minutes to become healthy.
- **Cause:** Instance boot time plus health check grace period and thresholds.
- **Fix:** Reduced health check interval and thresholds in the Target Group.
- **Learning:** Health check settings directly affect recovery time.

### 6. Session Manager "Connect" button was disabled
- **Problem:** Could not open a terminal in the browser.
- **Cause:** The instance had not registered with Systems Manager yet, or the SSM policy was missing from the role.
- **Fix:** Attached `AmazonSSMManagedInstanceCore` to the IAM role and waited a few minutes.
- **Learning:** Session Manager avoids opening SSH port 22.


## Cost and Cleanup
All resources were deleted after testing to avoid charges.

## Files
- `user-data.sh`:
-  #!/bin/bash
# EC2 user-data script for the Launch Template (Amazon Linux 2023)
# Replace YOUR-BUCKET-NAME with your S3 bucket name before using.

# Save all script output to a log file (helps with troubleshooting)
exec > >(tee /var/log/user-data.log) 2>&1

# 1. Install and start Nginx
dnf install -y nginx
systemctl enable --now nginx

# 2. Download the website page from S3 (uses the instance's IAM role, no keys needed)
aws s3 cp s3://YOUR-BUCKET-NAME/index.html /usr/share/nginx/html/index.html

# 3. Ask the instance metadata service (IMDSv2) for this server's ID and AZ
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

# 4. Write the instance details into the page
sed -i "s/INSTANCE_INFO/Served by: $ID ($AZ)/" /usr/share/nginx/html/index.html

- `iam-policy.json`:
-  {
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*"
    }
  ]
}

-  `index.html`:
- <!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Highly Available Website on AWS</title>
  <style>
    :root {
      --bg: #f5f7fa;
      --card: #ffffff;
      --text: #1b2430;
      --muted: #5b6776;
      --accent: #0b6e4f;
      --border: #d9dee5;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #12171d;
        --card: #1b232c;
        --text: #e8edf2;
        --muted: #9aa7b5;
        --accent: #4fd1a1;
        --border: #2d3844;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      background: var(--bg);
      color: var(--text);
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, Arial, sans-serif;
      line-height: 1.6;
    }
    main {
      width: 100%;
      max-width: 560px;
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 32px;
    }
    h1 { margin: 0 0 8px; font-size: 1.6rem; }
    p { margin: 0 0 20px; color: var(--muted); }
    .server {
      border-left: 4px solid var(--accent);
      padding: 12px 16px;
      background: var(--bg);
      border-radius: 0 8px 8px 0;
      font-weight: 600;
      word-break: break-word;
    }
    small { display: block; margin-top: 20px; color: var(--muted); }
  </style>
</head>
<body>
  <main>
    <h1>Highly Available Website on AWS</h1>
    <p>This page travels from an S3 bucket to EC2 instances in two Availability Zones, behind an Application Load Balancer.</p>
    <div class="server">INSTANCE_INFO</div>
    <small>Refresh the page. If the load balancer sends you to another server, the instance ID changes.</small>
  </main>
</body>
</html>

## Author
Mohammad Hozaifa | [LinkedIn](https://linkedin.com/in/mohammad-hozaifa-710032226)
