@echo off
setlocal enabledelayedexpansion

REM Deploy Script for ModResorts Application to AWS ECS Fargate (Windows)
REM This script deploys the Docker image to AWS ECS Fargate

echo ==========================================
echo ModResorts - AWS ECS Fargate Deployment
echo ==========================================
echo.

REM Project configuration
set PROJECT_NAME=modresorts
set TASK_FAMILY=modresorts-task
set SERVICE_NAME=modresorts-service

REM Prompt for AWS configuration
echo === AWS Configuration ===
set /p AWS_REGION="Enter AWS region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter ECS cluster name: "
echo.

REM Get AWS Account ID
echo Getting AWS account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i

if "!ACCOUNT_ID!"=="" (
    echo Error: Failed to get AWS account ID. Please check AWS CLI configuration.
    exit /b 1
)

echo AWS Account ID: !ACCOUNT_ID!
echo.

REM Check if cluster exists, create if it doesn't
echo Checking if ECS cluster exists...
aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Cluster does not exist. Creating ECS cluster...
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo Error: Failed to create ECS cluster
        exit /b 1
    )
    echo ECS cluster created successfully
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
echo === Container Image Configuration ===
set /p IMAGE_URI="Enter Docker image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest): "
echo.

REM Ask about load balancer
echo === Load Balancer Configuration ===
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

if /i "!NEED_LB!"=="y" (
    echo Creating Application Load Balancer and Target Group...
    
    REM Create ALB
    set ALB_NAME=modresorts-alb
    echo Creating Application Load Balancer: !ALB_NAME!
    
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name !ALB_NAME! --subnets !SUBNET_1! !SUBNET_2! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --ip-address-type ipv4 --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    
    if "!ALB_ARN!"=="" (
        echo Error: Failed to create Application Load Balancer
        exit /b 1
    )
    
    echo ALB created successfully
    echo ALB ARN: !ALB_ARN!
    
    REM Get ALB DNS name
    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    
    REM Create Target Group with target-type ip
    set TG_NAME=modresorts-tg
    echo Creating Target Group: !TG_NAME!
    
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name !TG_NAME! --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-enabled --health-check-protocol HTTP --health-check-path "/health" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    
    if "!TARGET_GROUP_ARN!"=="" (
        echo Error: Failed to create Target Group
        exit /b 1
    )
    
    echo Target Group created successfully
    echo Target Group ARN: !TARGET_GROUP_ARN!
    
    REM Create listener
    echo Creating ALB Listener...
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION! >nul
    
    echo ALB Listener created successfully
    echo.
    
    set USE_LB=true
) else (
    echo Skipping load balancer configuration
    set USE_LB=false
)

echo.

REM Create CloudWatch log group
echo Creating CloudWatch log group...
set LOG_GROUP=/ecs/!PROJECT_NAME!
aws logs create-log-group --log-group-name !LOG_GROUP! --region !AWS_REGION! 2>nul
echo CloudWatch log group ready: !LOG_GROUP!
echo.

REM Update task definition JSON
echo Preparing task definition...
set TASK_DEF_FILE=ecs\task-definition.json

REM Create temporary file with replacements
powershell -Command "(Get-Content !TASK_DEF_FILE!) -replace '{{IMAGE_URI}}','!IMAGE_URI!' -replace '{{AWS_REGION}}','!AWS_REGION!' -replace '{{ACCOUNT_ID}}','!ACCOUNT_ID!' | Set-Content !TASK_DEF_FILE!.tmp"
move /y !TASK_DEF_FILE!.tmp !TASK_DEF_FILE! >nul

REM Register task definition
echo Registering task definition...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json file://!TASK_DEF_FILE! --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i

if "!TASK_DEF_ARN!"=="" (
    echo Error: Failed to register task definition
    exit /b 1
)

echo Task definition registered successfully
echo Task Definition ARN: !TASK_DEF_ARN!
echo.

REM Update service definition JSON
echo Preparing service definition...
set SERVICE_DEF_FILE=ecs\service-definition.json

REM Replace placeholders
powershell -Command "(Get-Content !SERVICE_DEF_FILE!) -replace '{{CLUSTER_NAME}}','!CLUSTER_NAME!' -replace '{{SUBNET_1}}','!SUBNET_1!' -replace '{{SUBNET_2}}','!SUBNET_2!' -replace '{{SECURITY_GROUP}}','!SECURITY_GROUP!' | Set-Content !SERVICE_DEF_FILE!.tmp"

if "!USE_LB!"=="true" (
    powershell -Command "(Get-Content !SERVICE_DEF_FILE!.tmp) -replace '{{TARGET_GROUP_ARN}}','!TARGET_GROUP_ARN!' | Set-Content !SERVICE_DEF_FILE!"
) else (
    REM Remove loadBalancers section
    powershell -Command "$json = Get-Content !SERVICE_DEF_FILE!.tmp | ConvertFrom-Json; $json.PSObject.Properties.Remove('loadBalancers'); $json.PSObject.Properties.Remove('healthCheckGracePeriodSeconds'); $json | ConvertTo-Json -Depth 10 | Set-Content !SERVICE_DEF_FILE!"
)

del !SERVICE_DEF_FILE!.tmp 2>nul

REM Check if service exists
echo Checking if service exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[?status==`ACTIVE`].serviceName" --output text 2^>nul') do set EXISTING_SERVICE=%%i

if "!EXISTING_SERVICE!"=="" (
    REM Create new service
    echo Creating new ECS service...
    aws ecs create-service --cli-input-json file://!SERVICE_DEF_FILE! --region !AWS_REGION! >nul
    
    if !ERRORLEVEL! neq 0 (
        echo Error: Failed to create ECS service
        exit /b 1
    )
    
    echo ECS service created successfully
) else (
    REM Update existing service
    echo Updating existing ECS service...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEF_ARN! --force-new-deployment --region !AWS_REGION! >nul
    
    if !ERRORLEVEL! neq 0 (
        echo Error: Failed to update ECS service
        exit /b 1
    )
    
    echo ECS service updated successfully
)

echo.

REM Wait for service to stabilize
echo Waiting for service to stabilize (this may take a few minutes)...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!

if !ERRORLEVEL! neq 0 (
    echo Warning: Service stabilization check timed out or failed
) else (
    echo Service is stable
)

echo.

REM Get service details
echo Retrieving service details...
for /f "delims=" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].runningCount" --output text') do set RUNNING_COUNT=%%i
for /f "delims=" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].desiredCount" --output text') do set DESIRED_COUNT=%%i

echo.
echo ==========================================
echo Deployment completed successfully!
echo ==========================================
echo.
echo Service Details:
echo   Cluster: !CLUSTER_NAME!
echo   Service: !SERVICE_NAME!
echo   Task Definition: !TASK_FAMILY!
echo   Running Tasks: !RUNNING_COUNT! / !DESIRED_COUNT!
echo   Region: !AWS_REGION!
echo.

if "!USE_LB!"=="true" (
    echo Load Balancer:
    echo   DNS Name: !ALB_DNS!
    echo   URL: http://!ALB_DNS!
    echo.
)

echo CloudWatch Logs:
echo   Log Group: !LOG_GROUP!
echo   View logs: aws logs tail !LOG_GROUP! --follow --region !AWS_REGION!
echo.

echo Useful Commands:
echo   View service: aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!
echo   List tasks: aws ecs list-tasks --cluster !CLUSTER_NAME! --service-name !SERVICE_NAME! --region !AWS_REGION!
echo   Scale service: aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --desired-count ^<count^> --region !AWS_REGION!
echo.

endlocal
