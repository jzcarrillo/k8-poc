Write-Host "Starting API Test Validation..." -ForegroundColor Cyan

# Define test data and endpoint
$uri = "http://localhost:8081/submit"
$headers = @{ "Content-Type" = "application/json" }
$body = '{"message":"Hello from test validation"}'

# Counter variables
$passCount = 0
$failCount = 0

# Optional: Wait before sending the first request
Write-Host "Waiting for services to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

for ($i = 1; $i -le 1000; $i++) {
    Write-Host "`nRequest #$i"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -TimeoutSec 5

        if ($response -ne $null) {
            Write-Host "[PASS] Request #$i succeeded." -ForegroundColor Green
            $passCount++
        }
        else {
            Write-Host "[FAIL] Request #${i}: No response body" -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        # Extract HTTP status if available
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "[FAIL] Request #${i}: HTTP $statusCode - $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }

    # Delay between requests to avoid flooding
    Start-Sleep -Milliseconds 200
}

# Summary
Write-Host "`n--- Test Summary ---"
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
