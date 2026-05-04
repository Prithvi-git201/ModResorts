@echo off
setlocal enabledelayedexpansion

REM ============================================
REM AWS ECS Fargate Deployment Script for ModResorts
REM Platform: Windows
REM ============================================

echo ============================================
echo ModResorts - AWS ECS Fargate Deployment
echo ============================================
echo.

REM Configuration
set PROJECT_NAME=modresorts
set TASK_FAMILY=modresorts-task
set SERVICE_NAME=modresorts-service

REM Prompt for AWS configuration
echo === AWS Configuration ===
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter ECS Cluster Name: "

REM Get AWS Account ID
echo Retrieving AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
echo Account ID: !ACCOUNT_ID!
echo.

REM Check/Create ECS Cluster
echo Checking ECS cluster...
aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Cluster does not exist. Creating...
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo Failed to create cluster.
        exit /b 1
    )
    echo Cluster created successfully!
)
echo.

REM Prompt for network configuration
echo === Network Configuration ===
set /p VPC_ID="Enter VPC ID: "
set /p SUBNETS_INPUT="Enter Subnet IDs (comma-separated, at least 2): "
set /p SECURITY_GROUP="Enter Security Group ID: "

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_INPUT!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)
set SUBNET_1=!SUBNET_1: =!
set SUBNET_2=!SUBNET_2: =!

echo.

REM Prompt for image URI
echo === Container Image ===
set /p IMAGE_URI="Enter ECR Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest): "
echo.

REM Prompt for database configuration
echo === Database Configuration ===
set /p DB_URL="Enter Database URL (default: jdbc:h2:mem:testdb): "
if "!DB_URL!"=="" set DB_URL=jdbc:h2:mem:testdb
set /p DB_USERNAME="Enter Database Username (default: sa): "
if "!DB_USERNAME!"=="" set DB_USERNAME=sa
set /p DB_PASSWORD="Enter Database Password (default: empty): "
set /p DB_DRIVER="Enter Database Driver (default: org.h2.Driver): "
if "!DB_DRIVER!"=="" set DB_DRIVER=org.h2.Driver
echo.

REM Prompt for Redis configuration
echo === Redis Configuration ===
set /p REDIS_HOST="Enter Redis Host (default: localhost): "
if "!REDIS_HOST!"=="" set REDIS_HOST=localhost
set /p REDIS_PORT="Enter Redis Port (default: 6379): "
if "!REDIS_PORT!"=="" set REDIS_PORT=6379
set /p REDIS_PASSWORD="Enter Redis Password (default: empty): "
echo.

REM Load balancer configuration
echo === Load Balancer Configuration ===
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

if /i "!NEED_LB!"=="y" (
    echo Creating Application Load Balancer and Target Group...
    
    REM Create ALB
    set ALB_NAME=!PROJECT_NAME!-alb
    echo Creating ALB: !ALB_NAME!
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name !ALB_NAME! --subnets !SUBNET_1! !SUBNET_2! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --ip-address-type ipv4 --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    
    if !ERRORLEVEL! neq 0 (
        echo Failed to create ALB.
        exit /b 1
    )
    
    echo ALB created: !ALB_ARN!
    
    REM Get ALB DNS name
    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    
    REM Create Target Group with target-type ip
    set TG_NAME=!PROJECT_NAME!-tg
    echo Creating Target Group: !TG_NAME!
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name !TG_NAME! --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-enabled --health-check-protocol HTTP --health-check-path "/actuator/health" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    
    if !ERRORLEVEL! neq 0 (
        echo Failed to create Target Group.
        exit /b 1
    )
    
    echo Target Group created: !TARGET_GROUP_ARN!
    
    REM Create Listener
    echo Creating ALB Listener...
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION! >nul
    
    if !ERRORLEVEL! neq 0 (
        echo Failed to create Listener.
        exit /b 1
    )
    
    echo Listener created successfully!
    echo.
) else (
    echo Skipping load balancer creation.
    set TARGET_GROUP_ARN=
    echo.
)

REM Create CloudWatch Log Group
echo Creating CloudWatch Log Group...
aws logs create-log-group --log-group-name "/ecs/!PROJECT_NAME!" --region !AWS_REGION! 2>nul
echo.

REM Replace placeholders in task definition
echo Preparing task definition...
set TASK_DEF_FILE=ecs\task-definition.json
set TASK_DEF_TEMP=ecs\task-definition-temp.json

copy !TASK_DEF_FILE! !TASK_DEF_TEMP! >nul

powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{AWS_REGION}}', '!AWS_REGION!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{ACCOUNT_ID}}', '!ACCOUNT_ID!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{DB_URL}}', '!DB_URL!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{DB_USERNAME}}', '!DB_USERNAME!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{DB_PASSWORD}}', '!DB_PASSWORD!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{DB_DRIVER}}', '!DB_DRIVER!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{REDIS_HOST}}', '!REDIS_HOST!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{REDIS_PORT}}', '!REDIS_PORT!' | Set-Content !TASK_DEF_TEMP!"
powershell -Command "(Get-Content !TASK_DEF_TEMP!) -replace '{{REDIS_PASSWORD}}', '!REDIS_PASSWORD!' | Set-Content !TASK_DEF_TEMP!"

REM Register task definition
echo Registering task definition...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json file://!TASK_DEF_TEMP! --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i

if !ERRORLEVEL! neq 0 (
    echo Failed to register task definition.
    del !TASK_DEF_TEMP!
    exit /b 1
)

echo Task definition registered: !TASK_DEF_ARN!
del !TASK_DEF_TEMP!
echo.

REM Prepare service definition
echo Preparing service definition...
set SERVICE_DEF_FILE=ecs\service-definition.json
set SERVICE_DEF_TEMP=ecs\service-definition-temp.json

copy !SERVICE_DEF_FILE! !SERVICE_DEF_TEMP! >nul

powershell -Command "(Get-Content !SERVICE_DEF_TEMP!) -replace '{{CLUSTER_NAME}}', '!CLUSTER_NAME!' | Set-Content !SERVICE_DEF_TEMP!"
powershell -Command "(Get-Content !SERVICE_DEF_TEMP!) -replace '{{SUBNET_1}}', '!SUBNET_1!' | Set-Content !SERVICE_DEF_TEMP!"
powershell -Command "(Get-Content !SERVICE_DEF_TEMP!) -replace '{{SUBNET_2}}', '!SUBNET_2!' | Set-Content !SERVICE_DEF_TEMP!"
powershell -Command "(Get-Content !SERVICE_DEF_TEMP!) -replace '{{SECURITY_GROUP}}', '!SECURITY_GROUP!' | Set-Content !SERVICE_DEF_TEMP!"

if /i "!NEED_LB!"=="y" (
    powershell -Command "(Get-Content !SERVICE_DEF_TEMP!) -replace '{{TARGET_GROUP_ARN}}', '!TARGET_GROUP_ARN!' | Set-Content !SERVICE_DEF_TEMP!"
) else (
    REM Remove loadBalancers section if no LB needed
    powershell -Command "$json = Get-Content !SERVICE_DEF_TEMP! | ConvertFrom-Json; $json.PSObject.Properties.Remove('loadBalancers'); $json.PSObject.Properties.Remove('healthCheckGracePeriodSeconds'); $json | ConvertTo-Json -Depth 10 | Set-Content !SERVICE_DEF_TEMP!"
)

REM Check if service exists
echo Checking if service exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[?status==`ACTIVE`].serviceName" --output text 2^>nul') do set SERVICE_EXISTS=%%i

if "!SERVICE_EXISTS!"=="" (
    REM Create new service
    echo Creating new ECS service...
    aws ecs create-service --cli-input-json file://!SERVICE_DEF_TEMP! --region !AWS_REGION! >nul
    
    if !ERRORLEVEL! neq 0 (
        echo Failed to create service.
        del !SERVICE_DEF_TEMP!
        exit /b 1
    )
    
    echo Service created successfully!
) else (
    REM Update existing service
    echo Service already exists. Updating...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEF_ARN! --desired-count 2 --region !AWS_REGION! >nul
    
    if !ERRORLEVEL! neq 0 (
        echo Failed to update service.
        del !SERVICE_DEF_TEMP!
        exit /b 1
    )
    
    echo Service updated successfully!
)

del !SERVICE_DEF_TEMP!
echo.

REM Wait for service stability
echo Waiting for service to become stable...
echo This may take several minutes...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!

if !ERRORLEVEL! neq 0 (
    echo Service failed to stabilize.
    exit /b 1
)

echo Service is stable!
echo.

REM Display deployment information
echo ============================================
echo Deployment Successful!
echo ============================================
echo.
echo Cluster: !CLUSTER_NAME!
echo Service: !SERVICE_NAME!
echo Task Definition: !TASK_DEF_ARN!
echo Region: !AWS_REGION!

if /i "!NEED_LB!"=="y" (
    echo Load Balancer DNS: http://!ALB_DNS!
    echo.
    echo Access your application at: http://!ALB_DNS!
)

echo.
echo CloudWatch Logs: /ecs/!PROJECT_NAME!
echo.
echo Verify deployment:
echo aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!
echo.
echo View logs:
echo aws logs tail /ecs/!PROJECT_NAME! --follow --region !AWS_REGION!
echo.

endlocal
