# EC2 Auto Scaling Module

Provisions EC2 instances with Auto Scaling Groups, Load Balancing, and CloudWatch monitoring.
Supports both public-facing and internal applications with automatic scaling based on CPU utilization.

## Features

### Security & Compliance
- **IMDSv2 enforcement** (mandatory, http_put_response_hop_limit=1)
- **Encrypted EBS volumes** (KMS-backed, gp3, 30GB default)
- **No SSH keys in prod** (use Systems Manager Session Manager)
- **IAM Instance Profile** with SSM, CloudWatch, Secrets Manager permissions
- **Security Group** with least-privilege ingress rules

### Compute & Scaling
- **Launch Template** with IMDSv2 hardening and encrypted storage
- **Auto Scaling Group** across 3 AZs (private subnets)
- **Instance Refresh** for rolling updates (MinHealthyPercentage=80)
- **Target tracking scaling** (CPU utilization target 70%)
- **Health check** via ELB

### Load Balancing & Networking
- **Internal Application Load Balancer** (or internet-facing if configured)
- **Target Group** with health check path configuration
- **Listener** on HTTP 80 (or HTTPS 443 with ACM cert)
- **VPC** and multi-AZ subnet distribution

### Monitoring & Observability
- **CloudWatch agent** auto-installed and configured
- **Centralized logging** to CloudWatch Log Groups
- **CPU utilization alarms** (high/low thresholds)
- **Unhealthy host count alarm** (pages on < 1 healthy)
- **Custom metrics** from application logs

### Systems Management
- **Systems Manager Session Manager** for instance access (no SSH keys)
- **Systems Manager Parameter Store** for CloudWatch agent config
- **AutoScaling notifications** for lifecycle events

## Implementation

Generated automatically by the CI/CD pipeline when:
- Application `infra.yaml` specifies `compute.type: ec2`
- Pipeline invokes this module with variables from merged configuration

### Key Variables
- `app_name`, `environment`, `instance_type` (default: t3.medium)
- `ami_id` (required), `min_size`/`max_size`/`desired_capacity`
- `vpc_id`, `private_subnet_ids`, `public_subnet_ids`
- `key_name` (optional, omitted in prod), `user_data_b64`
- `enable_ssm` (default: true), `alarm_cpu_threshold` (default: 80)

See `variables.tf` for complete definitions.

### Outputs
- `alb_dns_name` - ALB DNS for service access
- `asg_name` - Auto Scaling Group identifier
- `instance_sg_id` - Security Group for compute instances
- `instance_profile_arn` - IAM Instance Profile ARN

See `outputs.tf` for complete output definitions.
