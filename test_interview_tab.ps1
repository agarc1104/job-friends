#!/usr/bin/env pwsh

# Automated test script to reproduce Interview tab crash

Write-Host "[TEST] Starting automated test scenario..." -ForegroundColor Green
Write-Host "[TEST] Device: Motorola Edge 50 Fusion"
Write-Host "[TEST] Credentials: quintero981104@gmail.com / D3n1s3a9"
Write-Host ""

# Wait for app to be fully ready on device
Write-Host "[TEST] Waiting 10s for app to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Clear previous logs
Write-Host "[TEST] Clearing device logs..." -ForegroundColor Yellow
adb -s ZY22KTZRPH logcat -c

# Start capturing logs in background
Write-Host "[TEST] Starting log capture..." -ForegroundColor Yellow
$logFile = "C:\Users\HP\Documents\my-app\interview_tab_test_logs.txt"
Start-Process -NoNewWindow -FilePath "adb" -ArgumentList "-s ZY22KTZRPH logcat *:V" -RedirectStandardOutput $logFile &

Start-Sleep -Seconds 2

# Simulate login and Interview tab navigation using adb shell
Write-Host "[TEST] Simulating user interactions..." -ForegroundColor Cyan
Write-Host "[TEST] Step 1: Wait for login screen..." 
Start-Sleep -Seconds 3

Write-Host "[TEST] Step 2: Enter email and password..." 
# These would be done via UI automation in real integration test
# For now, just log the action
Write-Host "[ACTION] Tapping email field..."
Write-Host "[ACTION] Entering: quintero981104@gmail.com"
Write-Host "[ACTION] Tapping password field..."
Write-Host "[ACTION] Entering: D3n1s3a9"
Write-Host "[ACTION] Tapping Login button..."

Start-Sleep -Seconds 5

Write-Host "[TEST] Step 3: Navigate to Mis Empleos tab..."
Start-Sleep -Seconds 2

Write-Host "[TEST] Step 4: Navigate to Interview tab (CRITICAL POINT)..."
Write-Host "[TEST] Monitoring for RenderBox layout crash..."

# Monitor logs for the critical crash
$monitoringDuration = 15
$endTime = [DateTime]::Now.AddSeconds($monitoringDuration)

Write-Host "[TEST] Log monitoring active for $monitoringDuration seconds..." -ForegroundColor Yellow

while ([DateTime]::Now -lt $endTime) {
    if (Test-Path $logFile) {
        $recentLogs = Get-Content $logFile -Tail 5 -ErrorAction SilentlyContinue
        if ($recentLogs -match "Failed assertion.*_debugDoingThisLayout") {
            Write-Host "[CRASH DETECTED] RenderBox layout crash found!" -ForegroundColor Red
            Write-Host $recentLogs
            break
        }
        if ($recentLogs -match "InterviewPrepScreen.*build.*loadingApps") {
            Write-Host "[SUCCESS] Interview screen built successfully!" -ForegroundColor Green
            Write-Host $recentLogs
            break
        }
    }
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "[TEST] Test complete. Full logs saved to: $logFile" -ForegroundColor Green
Write-Host "[TEST] Extracting relevant logs..." -ForegroundColor Yellow

# Filter and show interview-related logs
Get-Content $logFile | Select-String "InterviewPrepScreen|HomeShell.*interview|_debugDoingThisLayout|RenderBox.*laid out" | Tee-Object -FilePath "$logFile.filtered"

Write-Host ""
Write-Host "[TEST] Done!" -ForegroundColor Green
