# ==============================================================================
# SCRIPT: Provision-OktaUsers.ps1
# PURPOSE: Automated JML identity provisioning engine via Okta REST API
# ==============================================================================

# --- CONFIGURATION ---
# Use relative path or environment variable for portability
$csvPath = ".\PROJECT.csv"
$orgUrl  = $env:OKTA_ORG_URL   # e.g. "https://your-domain.okta.com"
$token   = $env:OKTA_API_TOKEN # API Token stored securely in environment

# Fallback for manual local testing if environment variables are not set
if (-not $orgUrl) { $orgUrl = "https://dev-identity.okta.com" }
if (-not $token)  { $token  = "REPLACE_WITH_OKTA_API_TOKEN" }

$headers = @{
    "Authorization" = "SSWS $token"
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
}

# --- 1. VERIFY HRIS INPUT FEED ---
if (-not (Test-Path $csvPath)) {
    Write-Error "[ABORT] HRIS feed not found at path: $csvPath"
    exit
}

$users = Import-Csv -Path $csvPath
Write-Host "Found $($users.Count) records in identity feed. Starting JML processing..." -ForegroundColor Cyan

# --- 2. PROVISIONING & GOVERNANCE LOOP ---
foreach ($user in $users) {

    # Defensive validation: Catch malformed emails before API invocation
    if ($user.WorkEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        Write-Warning "[VALIDATION FAILED] Quarantining $($user.FirstName) $($user.LastName) (ID: $($user.EmployeeID)) - Malformed email: '$($user.WorkEmail)'"
        continue
    }

    # Core Okta profile attribute mapping
    $profileData = @{
        firstName      = $user.FirstName
        lastName       = $user.LastName
        email          = $user.WorkEmail
        login          = $user.WorkEmail
        title          = $user.JobTitle
        department     = $user.Department
        employeeNumber = $user.EmployeeID
    }

    # Lifecycle Rule: Map Contractor Expiration Date for time-bound access
    if (-not [string]::IsNullOrWhiteSpace($user.EndDate)) {
        $profileData["customContractEndDate"] = $user.EndDate
    }

    # Least Privilege Governance: Assign time-bound admin expiration
    if ($user.IsAdmin -eq "TRUE") {
        $durationDays = 30
        if ($user.PrivilegeDurationDays -and [int]::TryParse($user.PrivilegeDurationDays, [ref]$null)) {
            $durationDays = [int]$user.PrivilegeDurationDays
        }
        $profileData["customAdminExpirationDate"] = (Get-Date).AddDays($durationDays).ToString("yyyy-MM-dd")
    }

    $body = @{ profile = $profileData } | ConvertTo-Json -Depth 5
    $uri  = "$orgUrl/api/v1/users?activate=true"

    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
        Write-Host "[PROVISIONED] $($response.profile.login) | Role: $($user.JobTitle) | Okta ID: $($response.id)" -ForegroundColor Green
    }
    catch {
        Write-Error "[API REJECTED] Failed to provision $($user.WorkEmail): $($_.Exception.Message)"
    }
}

Write-Host "`nLifecycle processing cycle completed." -ForegroundColor Cyan
