@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo ModResorts Backend - ECS Fargate Deployment
echo ==========================================
echo.

REM Configuration
set PROJECT_NAME=modresorts-backend
set TASK_FAMILY=modresorts-backend-task
set SERVICE_NAME=modresorts-backend-service

REM Prompt for AWS Region
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set AWS_DEFAULT_REGION=!AWS_REGION!

echo.
echo Getting AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
echo AWS Account ID: !ACCOUNT_ID!

REM Prompt for ECS Cluster Name
echo.
set /p CLUSTER_NAME="Enter ECS Cluster Name: "

REM Check if cluster exists, create if not
echo.
echo Checking if ECS cluster exists...
for /f "delims=" %%i in ('aws ecs describe-clusters --clusters !CLUSTER_NAME! --query "clusters[0].clusterName" --output text 2^>nul') do set CLUSTER_EXISTS=%%i

if "!CLUSTER_EXISTS!"=="None" (
    echo Cluster does not exist. Creating ECS cluster: !CLUSTER_NAME!
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    echo ECS cluster created successfully
) else (
    echo ECS cluster already exists: !CLUSTER_NAME!
)

REM Prompt for VPC and Network Configuration
echo.
echo === Network Configuration ===
set /p VPC_ID="Enter VPC ID: "
set /p SUBNET_1="Enter Subnet ID 1: "
set /p SUBNET_2="Enter Subnet ID 2: "
set /p SECURITY_GROUP="Enter Security Group ID: "

REM Prompt for Docker Image URI
echo.
set /p IMAGE_URI="Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts-backend:latest): "

REM Prompt for database configuration
echo.
echo === Database Configuration ===
set /p DB_HOST="Enter Database Host [localhost]: "
if "!DB_HOST!"=="" set DB_HOST=localhost
set /p DB_PORT="Enter Database Port [5432]: "
if "!DB_PORT!"=="" set DB_PORT=5432
set /p DB_NAME="Enter Database Name [modresorts]: "
if "!DB_NAME!"=="" set DB_NAME=modresorts
set /p DB_USER="Enter Database User [admin]: "
if "!DB_USER!"=="" set DB_USER=admin
set /p DB_PASSWORD="Enter Database Password: "

REM Prompt for Load Balancer
echo.
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

if /i "!NEED_LB!"=="y" (
    echo.
    echo Creating Application Load Balancer and Target Group...
    
    REM Create Target Group
    echo Creating Target Group...
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name !PROJECT_NAME!-tg --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-enabled --health-check-path "/health" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text 2^>nul') do set TARGET_GROUP_ARN=%%i
    
    if "!TARGET_GROUP_ARN!"=="" (
        echo Target Group may already exist. Fetching existing Target Group ARN...
        for /f "delims=" %%i in ('aws elbv2 describe-target-groups --names !PROJECT_NAME!-tg --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text 2^>nul') do set TARGET_GROUP_ARN=%%i
    )
    
    if "!TARGET_GROUP_ARN!"=="" (
        echo ERROR: Failed to create or find Target Group
        exit /b 1
    )
    
    echo Target Group ARN: !TARGET_GROUP_ARN!
    
    REM Create Application Load Balancer
    echo Creating Application Load Balancer...
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name !PROJECT_NAME!-alb --subnets !SUBNET_1! !SUBNET_2! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --ip-address-type ipv4 --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text 2^>nul') do set ALB_ARN=%%i
    
    if "!ALB_ARN!"=="" (
        echo Load Balancer may already exist. Fetching existing ALB ARN...
        for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --names !PROJECT_NAME!-alb --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text 2^>nul') do set ALB_ARN=%%i
    )
    
    if "!ALB_ARN!"=="" (
        echo ERROR: Failed to create or find Application Load Balancer
        exit /b 1
    )
    
    echo Application Load Balancer ARN: !ALB_ARN!
    
    REM Create Listener
    echo Creating ALB Listener...
    for /f "delims=" %%i in ('aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION! --query "Listeners[0].ListenerArn" --output text 2^>nul') do set LISTENER_ARN=%%i
    
    if "!LISTENER_ARN!"=="" (
        echo Listener may already exist. Continuing...
    ) else (
        echo Listener created: !LISTENER_ARN!
    )
    
    REM Get ALB DNS Name
    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    
    echo Load Balancer DNS: !ALB_DNS!
) else (
    echo Skipping load balancer creation
    set TARGET_GROUP_ARN=
)

REM Create CloudWatch Log Group
echo.
echo Creating CloudWatch Log Group...
aws logs create-log-group --log-group-name "/ecs/!PROJECT_NAME!" --region !AWS_REGION! 2>nul
if !ERRORLEVEL! neq 0 (
    echo Log group already exists
)

REM Update task definition with actual values
echo.
echo Preparing task definition...
copy ecs\task-definition.json ecs\task-definition-temp.json >nul

powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{ACCOUNT_ID}}','!ACCOUNT_ID!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{IMAGE_URI}}','!IMAGE_URI!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{AWS_REGION}}','!AWS_REGION!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_HOST}}','!DB_HOST!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_PORT}}','!DB_PORT!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_NAME}}','!DB_NAME!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_USER}}','!DB_USER!' | Set-Content ecs\task-definition-temp.json"
powershell -Command "(Get-Content ecs\task-definition-temp.json) -replace '{{DB_PASSWORD}}','!DB_PASSWORD!' | Set-Content ecs\task-definition-temp.json"

REM Register task definition
echo.
echo Registering ECS task definition...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json file://ecs/task-definition-temp.json --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEFINITION_ARN=%%i

echo Task Definition registered: !TASK_DEFINITION_ARN!

REM Clean up temporary file
del ecs\task-definition-temp.json

REM Update service definition with actual values
echo.
echo Preparing service definition...
copy ecs\service-definition.json ecs\service-definition-temp.json >nul

powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{CLUSTER_NAME}}','!CLUSTER_NAME!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SUBNET_1}}','!SUBNET_1!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SUBNET_2}}','!SUBNET_2!' | Set-Content ecs\service-definition-temp.json"
powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{SECURITY_GROUP}}','!SECURITY_GROUP!' | Set-Content ecs\service-definition-temp.json"

if "!TARGET_GROUP_ARN!"=="" (
    REM Remove loadBalancers section if no load balancer
    powershell -Command "$content = Get-Content ecs\service-definition-temp.json -Raw; $content = $content -replace '(?s),\s*\"loadBalancers\":\s*\[.*?\],',''; $content = $content -replace ',\s*\"healthCheckGracePeriodSeconds\":\s*\d+',''; $content | Set-Content ecs\service-definition-temp.json"
) else (
    powershell -Command "(Get-Content ecs\service-definition-temp.json) -replace '{{TARGET_GROUP_ARN}}','!TARGET_GROUP_ARN!' | Set-Content ecs\service-definition-temp.json"
)

REM Check if service exists
echo.
echo Checking if ECS service exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].serviceName" --output text 2^>nul') do set SERVICE_EXISTS=%%i

if "!SERVICE_EXISTS!"=="None" (
    echo Service does not exist. Creating ECS service...
    aws ecs create-service --cli-input-json file://ecs/service-definition-temp.json --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS service
        exit /b 1
    )
    echo ECS service created successfully
) else (
    echo Service already exists. Updating ECS service...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEFINITION_ARN! --desired-count 2 --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to update ECS service
        exit /b 1
    )
    echo ECS service updated successfully
)

REM Clean up temporary file
del ecs\service-definition-temp.json

REM Wait for service to stabilize
echo.
echo Waiting for service to become stable (this may take a few minutes)...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!

echo.
echo ==========================================
echo Deployment Completed Successfully
echo ==========================================
echo.
echo Cluster: !CLUSTER_NAME!
echo Service: !SERVICE_NAME!
echo Task Definition: !TASK_DEFINITION_ARN!
echo Region: !AWS_REGION!

if not "!ALB_DNS!"=="" (
    echo.
    echo Application URL: http://!ALB_DNS!
    echo Health Check: http://!ALB_DNS!/health
)

echo.
echo CloudWatch Logs: /ecs/!PROJECT_NAME!
echo.
echo To view service details:
echo aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!
echo.
echo To view running tasks:
echo aws ecs list-tasks --cluster !CLUSTER_NAME! --service-name !SERVICE_NAME! --region !AWS_REGION!
echo.

endlocal
