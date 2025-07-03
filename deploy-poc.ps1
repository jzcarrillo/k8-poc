# deploy-poc.ps1

$ErrorActionPreference = "Stop"

# CONFIG
$namespace = "lra-poc"
$services = @("frontend", "api-gateway", "lambda-producer", "lambda-consumer", "backend")
$ports = @(
    @{ Name = "frontend"; Local = 8080; Remote = 8080 },
    @{ Name = "api-gateway"; Local = 8081; Remote = 8081 },
    @{ Name = "lambda-producer"; Local = 4000; Remote = 4000 },
    @{ Name = "lambda-consumer"; Local = 4001; Remote = 4001 },
    @{ Name = "backend"; Local = 3000; Remote = 3000 },
    @{ Name = "postgres"; Local = 5432; Remote = 5432 },
    @{ Name = "redis"; Local = 6379; Remote = 6379 },
    @{ Name = "rabbitmq"; Local = 5672; Remote = 5672 }
)
$yamlDir = "./k8s"

Write-Host "STEP 1: Build Local Docker Images"
foreach ($service in $services) {
    $dockerfileFolder = ".\$service"
    if (Test-Path $dockerfileFolder) {
        Write-Host "Building image for $service from inside $dockerfileFolder..."
        Push-Location $dockerfileFolder

        $tag = "$service`:latest"  # Use backtick to escape colon inside strings
        if (![string]::IsNullOrWhiteSpace($tag)) {
            $args = "build -t $tag ."
            Write-Host "Running: docker $args"
            Start-Process "docker" -ArgumentList $args -NoNewWindow -Wait
        } else {
            Write-Warning "⚠️ Image tag for $service is invalid or empty."
        }

        Pop-Location
    } else {
        Write-Warning "Skipping $service - folder not found: $dockerfileFolder"
    }
}

Write-Host "STEP 2: Delete Old Pods by Label"
foreach ($service in $services) {
    Write-Host "Deleting pods with label app=$service..."
    kubectl delete pod -l "app=$service" -n $namespace --ignore-not-found
}

Start-Sleep -Seconds 2

Write-Host "STEP 3: Apply All K8s YAMLs (Deployment and Service)"

$deploymentFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*-deployment.yaml"
$serviceFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*-service.yaml"

foreach ($file in $deploymentFiles) {
    Write-Host "Applying deployment: $($file.FullName)"
    kubectl apply -f $file.FullName -n $namespace
}

foreach ($file in $serviceFiles) {
    Write-Host "Applying service: $($file.FullName)"
    kubectl apply -f $file.FullName -n $namespace
}

Write-Host "STEP 4: Wait for Pods to be Ready"
foreach ($app in $services) {
    Write-Host "Waiting for pod with label app=$app..."
    try {
        kubectl wait --for=condition=ready pod -l "app=$app" -n $namespace --timeout=120s
    } catch {
        Write-Host "Warning: Timeout or error waiting for pod $app"
    }
}

Write-Host "STEP 5: Clean Up Previous port-forward Sessions"
Get-Process | Where-Object { $_.ProcessName -eq "kubectl" } | Stop-Process -Force

Write-Host "STEP 6: Manual Port Forwarding for All Services"
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-Command",
    "kubectl port-forward svc/frontend-service 80:80 -n $namespace"
)
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-Command",
    "kubectl port-forward svc/backend-service 3000:3000 -n $namespace"
)
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-Command",
    "kubectl port-forward svc/api-gateway-service 8081:8081 -n $namespace"
)
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-Command",
    "kubectl port-forward svc/lambda-producer-service 4000:4000 -n $namespace"
)
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-Command",
    "kubectl port-forward svc/lambda-consumer-service 4001:4001 -n $namespace"
)
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-Command",
    "kubectl port-forward svc/redis-service 6379:6379 -n $namespace"
)
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile",
    "-Command",
    "kubectl port-forward svc/rabbitmq-service 15672:15672 -n $namespace"
)

Write-Host "`nDEPLOYMENT COMPLETE - Ready for Testing"

Write-Host "Starting API Test Validation..." -ForegroundColor Cyan

# Define test data and endpoint
$uri = "http://localhost:4000/submit"
$headers = @{ "Content-Type" = "application/json" }
$body = '{"message":"Hello from test validation"}'

try {
    $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -TimeoutSec 5

    if ($response -ne $null) {
        Write-Host "[PASS] API Test Passed: Received valid response" -ForegroundColor Green
        Write-Host "Response: $($response | ConvertTo-Json -Depth 5)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[FAIL] API Test Failed: No response body" -ForegroundColor Red
    }
}
catch {
    Write-Host "[FAIL] API Test Failed: $($_.Exception.Message)" -ForegroundColor Red
}

