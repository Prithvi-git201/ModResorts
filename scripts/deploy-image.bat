@echo off
setlocal enabledelayedexpansion

REM ECS Fargate Deployment Script for ModResorts Application (Windows)
REM Deploys containerized application to AWS ECS Fargate

echo ==========================================
echo ModResorts - ECS Fargate Deployment
echo ==========================================
echo.

REM Prompt for AWS region
set /p AWS_REGION="Enter AWS region (e.g., us-east-1): "
if "!AWS_REGION!"=="" (
    echo Error: AWS region is required
    exit /b 1
)

REM Prompt for ECS cluster name
set /p CLUSTER_NAME="Enter ECS cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo Error: ECS cluster name is required
    exit /b 1
)

REM Prompt for VPC ID
set /p VPC_ID="Enter VPC ID: "
if "!VPC_ID!"=="" (
    echo Error: VPC ID is required
    exit /b 1
)

REM Prompt for subnet IDs
set /p SUBNETS_INPUT="Enter subnet IDs (comma-separated, at least 2): "
if "!SUBNETS_INPUT!"=="" (
    echo Error: At least 2 subnet IDs are required for high availability
    exit /b 1
)

REM Parse subnets (simple split by comma)
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_INPUT!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)

set SUBNET_1=!SUBNET_1: =!
set SUBNET_2=!SUBNET_2: =!

if "!SUBNET_1!"=="" (
    echo Error: At least 2 subnet IDs are required
    exit /b 1
)
if "!SUBNET_2!"=="" (
    echo Error: At least 2 subnet IDs are required
    exit /b 1
)

REM Prompt for security group ID
set /p SECURITY_GROUP="Enter security group ID (must allow inbound traffic on port 8080): "
if "!SECURITY_GROUP!"=="" (
    echo Error: Security group ID is required
    exit /b 1
)

REM Prompt for ECR image URI
set /p IMAGE_URI="Enter ECR image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest): "
if "!IMAGE_URI!"=="" (
    echo Error: Image URI is required
    exit /b 1
)

REM Get AWS Account ID
echo.
echo Getting AWS account ID...
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
if "!ACCOUNT_ID!"=="" (
    echo Error: Failed to get AWS account ID
    exit /b 1
)
echo AWS Account ID: !ACCOUNT_ID!

REM Check if ECS cluster exists, create if not
echo.
echo Checking if ECS cluster exists...
aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Cluster does not exist. Creating ECS cluster: !CLUSTER_NAME!
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo Error: Failed to create ECS cluster
        exit /b 1
    )
)

REM Prompt for load balancer
echo.
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

if /i "!NEED_LB!"=="y" (
    echo.
    echo Creating Application Load Balancer and Target Group...
    
    REM Create ALB
    set ALB_NAME=modresorts-alb
    echo Creating Application Load Balancer: !ALB_NAME!
    for /f "tokens=*" %%i in ('aws elbv2 create-load-balancer --name !ALB_NAME! --subnets !SUBNET_1! !SUBNET_2! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --ip-address-type ipv4 --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    
    if "!ALB_ARN!"=="" (
        echo Error: Failed to create Application Load Balancer
        exit /b 1
    )
    echo ALB created: !ALB_ARN!
    
    REM Get ALB DNS name
    for /f "tokens=*" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    
    REM Create Target Group with target-type ip
    set TG_NAME=modresorts-tg
    echo Creating Target Group: !TG_NAME!
    for /f "tokens=*" %%i in ('aws elbv2 create-target-group --name !TG_NAME! --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-enabled --health-check-protocol HTTP --health-check-path "/health" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    
    if "!TARGET_GROUP_ARN!"=="" (
        echo Error: Failed to create Target Group
        exit /b 1
    )
    echo Target Group created: !TARGET_GROUP_ARN!
    
    REM Create Listener
    echo Creating ALB Listener...
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION! >nul
    
    echo Load balancer setup complete
    
    REM Update service definition with load balancer
    powershell -Command "(Get-Content ecs\service-definition.json) -replace '{{TARGET_GROUP_ARN}}', '!TARGET_GROUP_ARN!' | Set-Content ecs\service-definition.json"
) else (
    echo Skipping load balancer creation
    REM Note: Manual removal of loadBalancers section may be needed
)

REM Create CloudWatch log group
echo.
echo Creating CloudWatch log group...
aws logs create-log-group --log-group-name "/ecs/modresorts" --region !AWS_REGION! 2>nul
if !ERRORLEVEL! neq 0 (
    echo Log group already exists or creation skipped
)

REM Replace placeholders in task definition
echo.
echo Preparing task definition...
copy ecs\task-definition.json ecs\task-definition-temp.json >nul
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{AWS_REGION}}', '!AWS_REGION!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{ACCOUNT_ID}}', '!ACCOUNT_ID!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_HOST}}', 'localhost' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_PORT}}', '5432' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_NAME}}', 'modresorts' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_USER}}', 'admin' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_PASSWORD}}', 'changeme' | Set-Content ecs\task-definition-temp.json"

REM Register task definition
echo Registering ECS task definition...
for /f "tokens=*" %%i in ('aws ecs register-task-definition --cli-input-json file://ecs/task-definition-temp.json --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i

if "!TASK_DEF_ARN!"=="" (
    echo Error: Failed to register task definition
    del ecs\task-definition-temp.json
    exit /b 1
)

echo Task definition registered: !TASK_DEF_ARN!
del ecs\task-definition-temp.json

REM Replace placeholders in service definition
echo.
echo Preparing service definition...
copy ecs\service-definition.json ecs\service-definition-temp.json >nul
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{CLUSTER_NAME}}', '!CLUSTER_NAME!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SUBNET_1}}', '!SUBNET_1!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SUBNET_2}}', '!SUBNET_2!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SECURITY_GROUP}}', '!SECURITY_GROUP!' | Set-Content ecs\service-definition-temp.json"

REM Check if service exists
set SERVICE_NAME=modresorts-service
echo Checking if service exists...
for /f "tokens=*" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[?status==`ACTIVE`].serviceName" --output text') do set EXISTING_SERVICE=%%i

if "!EXISTING_SERVICE!"=="" (
    REM Create new service
    echo Creating new ECS service...
    aws ecs create-service --cli-input-json file://ecs/service-definition-temp.json --region !AWS_REGION! >nul
    if !ERRORLEVEL! neq 0 (
        echo Error: Failed to create ECS service
        del ecs\service-definition-temp.json
        exit /b 1
    )
    echo Service created successfully
) else (
    REM Update existing service
    echo Updating existing ECS service...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEF_ARN! --desired-count 2 --region !AWS_REGION! >nul
    if !ERRORLEVEL! neq 0 (
        echo Error: Failed to update ECS service
        del ecs\service-definition-temp.json
        exit /b 1
    )
    echo Service updated successfully
)

del ecs\service-definition-temp.json

REM Wait for service to stabilize
echo.
echo Waiting for service to stabilize (this may take a few minutes)...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!
if !ERRORLEVEL! neq 0 (
    echo Warning: Service did not stabilize within the expected time
) else (
    echo Service is stable
)

REM Verify deployment
echo.
echo ==========================================
echo Deployment Summary
echo ==========================================
aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].[serviceName,status,runningCount,desiredCount]" --output table

echo.
echo CloudWatch Logs: /ecs/modresorts
echo Region: !AWS_REGION!

if /i "!NEED_LB!"=="y" (
    echo.
    echo Application Load Balancer DNS: !ALB_DNS!
    echo Access your application at: http://!ALB_DNS!
)

echo.
echo ==========================================
echo Deployment Complete!
echo ==========================================

endlocal
