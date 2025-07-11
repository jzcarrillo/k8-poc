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

Write-Host "STEP 3: Apply Deployment, Service, Config, PVC and Secret YAMLs"

# === PVCs ===
$pvcFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*pvc.yaml"

foreach ($file in $pvcFiles) {
    $content = Get-Content $file.FullName -Raw

    if ($content -match 'kind:\s*PersistentVolumeClaim') {
        Write-Host "Applying PVC: $($file.FullName)"
        kubectl apply -f $file.FullName -n $namespace
    } else {
        Write-Warning "Skipping: Not a PVC kind → $($file.FullName)"
    }
}

# === Secrets ===
$secretFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*secret.yaml"

foreach ($file in $secretFiles) {
    $content = Get-Content $file.FullName -Raw

    if ($content -match 'kind:\s*Secret') {
        Write-Host "Applying Secret: $($file.FullName)"
        kubectl apply -f $file.FullName -n $namespace
    } else {
        Write-Warning "Skipping: Not a Secret kind → $($file.FullName)"
    }
}

# === Deployments ===
$deploymentFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*-deployment.yaml"

foreach ($file in $deploymentFiles) {
    $content = Get-Content $file.FullName -Raw

    # 🔒 Safety check: prevent applying unintended lambda-producer-service deployment
    if ($content -match 'name:\s*lambda-producer-service' -and $file.Name -notlike "*lambda-producer-service*") {
        Write-Warning "Skipping suspicious deployment: $($file.FullName) → Declares lambda-producer-service"
        continue
    }

    Write-Host "Applying deployment: $($file.FullName)"
    kubectl apply -f $file.FullName -n $namespace
}

# === Services ===
$serviceFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*-service.yaml"

foreach ($file in $serviceFiles) {
    $content = Get-Content $file.FullName -Raw

    if ($content -match 'kind:\s*Service') {
        Write-Host "Applying service: $($file.FullName)"
        kubectl apply -f $file.FullName -n $namespace
    } else {
        Write-Warning "Skipping: Not a Service kind → $($file.FullName)"
    }
}

# === ConfigMaps and Custom Configs ===
$configFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*-config.yaml"

foreach ($file in $configFiles) {
    $content = Get-Content $file.FullName -Raw

    if ($content -match 'kind:\s*ConfigMap') {
        Write-Host "Applying ConfigMap: $($file.FullName)"
        kubectl apply -f $file.FullName -n $namespace
    } else {
        Write-Warning "Skipping: Not a ConfigMap kind → $($file.FullName)"
    }
}

# === Apply Prometheus Alert Rules (ConfigMaps with alert-rules.yaml inside) ===


$rulesFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*rules.yaml"

foreach ($file in $rulesFiles) {
    $content = Get-Content $file.FullName -Raw

    if ($content -match 'kind:\s*ConfigMap' -and $content -match 'alert-rules\.yaml') {
        Write-Host "Applying Alert Rule ConfigMap: $($file.FullName)"
        kubectl apply -f $file.FullName -n $namespace
    } else {
        Write-Warning "Skipping: Not a valid alert-rules ConfigMap → $($file.FullName)"
    }
}

# === Apply Prometheus RBAC Definitions (ServiceAccount, Role, RoleBinding, etc.) ===

# Look for filenames that are probably RBAC configs
$rbacFiles = Get-ChildItem -Recurse -Path $yamlDir -Filter "*rbac.yaml"

foreach ($file in $rbacFiles) {
    $content = Get-Content $file.FullName -Raw

    if ($content -match 'kind:\s*(ServiceAccount|Role|RoleBinding|ClusterRole|ClusterRoleBinding)') {
        Write-Host "Applying RBAC file: $($file.FullName)"
        kubectl apply -f $file.FullName -n $namespace
    } else {
        Write-Warning "⏭Skipping (no RBAC kind detected): $($file.FullName)"
    }
}

Write-Host "STEP 3.5: Apply HPA for api-gateway"
try {
    kubectl delete hpa api-gateway -n $namespace --ignore-not-found
    kubectl autoscale deployment api-gateway --cpu-percent=30 --min=1 --max=5 -n $namespace
    Write-Host "HPA for api-gateway created successfully"
} catch {
    Write-Warning "Failed to apply HPA: $($_.Exception.Message)"
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

Write-Host "STEP 7: Trigger Autoscaling via Load Generator (load-tester Pod)"

try {
    Write-Host "Deleting existing load-tester pod (if any)..."
    kubectl delete pod load-tester -n $namespace --ignore-not-found | Out-Null
    Start-Sleep -Seconds 2

    Write-Host "Deploying load-tester pod..."
    kubectl apply -f "$PSScriptRoot\load-test\load-tester.yaml" | Out-Null

    Write-Host "Waiting for load-tester pod to enter 'Running' state..."
    kubectl wait --for=condition=Ready pod/load-tester -n $namespace --timeout=60s

    Write-Host "Opening log stream from load-tester in a new terminal..."
    Start-Process powershell -ArgumentList @(
        "-NoProfile",
        "-NoExit",
        "-Command",
        "kubectl logs load-tester -n $namespace --follow --timestamps"
    )

    Write-Host "Watching HPA scaling behavior in another new terminal..."
    Start-Process powershell -ArgumentList @(
        "-NoProfile",
        "-NoExit",
        "-Command",
        "kubectl get hpa -n $namespace --watch"
    )
}
catch {
    Write-Warning ('Failed to deploy load-tester pod or monitor HPA: {0}' -f $_.Exception.Message)
}

Write-Host "`nSTEP 8: Smoke Test via Service LoadBalancer/NodePort"

$externalIP = "localhost"
$nodeIP     = "localhost"

Write-Host "DEBUG: externalIP = '$externalIP'"
Write-Host "DEBUG: nodeIP     = '$nodeIP'"

try {
    $ErrorActionPreference = "Stop"

    # LoadBalancer test
    $urlLB = "http://{0}:8081/submit" -f $externalIP
    Write-Host "Testing via LoadBalancer ($urlLB)..."
    $responseLB = Invoke-RestMethod -Uri $urlLB `
        -Method POST `
        -Headers @{ "Content-Type" = "application/json" } `
        -Body '{"message":"smoke test"}' `
        -TimeoutSec 5
    Write-Host "LoadBalancer Response:"
    if ($responseLB) {
        $responseLB | ConvertTo-Json -Depth 5 | Write-Host
    } else {
        Write-Host "No response body from LoadBalancer"
    }

    # NodePort test
    $urlNP = "http://{0}:30081/submit" -f $nodeIP
    Write-Host "`nTesting via NodePort ($urlNP)..."
    $responseNP = Invoke-RestMethod -Uri $urlNP `
        -Method POST `
        -Headers @{ "Content-Type" = "application/json" } `
        -Body '{"message":"smoke test"}' `
        -TimeoutSec 5
    Write-Host "NodePort Response:"
    if ($responseNP) {
        $responseNP | ConvertTo-Json -Depth 5 | Write-Host
    } else {
        Write-Host "No response body from NodePort"
    }

    Write-Host "`nSmoke test completed successfully" -ForegroundColor Cyan
}
catch {
    Write-Warning ('Smoke test failed: {0}' -f $_.Exception.Message)
}

Write-Host "STEP 9: Scale Prometheus Deployment to 4 Replicas"
try {
    kubectl scale deployment prometheus -n $namespace --replicas=4
    Write-Host "Successfully scaled Prometheus to 4 replicas" -ForegroundColor Green
} catch {
    Write-Warning "Failed to scale Prometheus: $($_.Exception.Message)"
}

Write-Host "`nSTEP 10: ALB HTTPS/HTTP Behavior Validation" -ForegroundColor Cyan

# Allow untrusted/self-signed SSL certs for local testing
if (-not ([System.Net.ServicePointManager]::CertificatePolicy -is [TrustAllCertsPolicy])) {
    Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}


# STEP 10.1: HTTPS Requests (Expect: Success)
Write-Host "`nSending 100 HTTPS requests to https://localhost:30443"
1..100 | ForEach-Object {
    try {
        Invoke-WebRequest -Uri "https://localhost:30443" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop | Out-Null
        Write-Host "[$_] HTTPS success"
    } catch {
        Write-Host "[$_]  HTTPS failed - $($_.Exception.Message)"
    }
}

# STEP 10.2: HTTP Requests (Expect: Blocked)
Write-Host "`n Sending 100 HTTP requests to http://localhost:30080"
1..100 | ForEach-Object {
    try {
        Invoke-WebRequest -Uri "http://localhost:30080" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop | Out-Null
        Write-Host "[$_] HTTP unexpectedly succeeded"
    } catch {
        Write-Host "[$_] HTTP blocked as expected"
    }
}

Write-Host “`nDeployment and Verification Complete.” -ForegroundColor Cyan

