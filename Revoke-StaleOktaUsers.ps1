# ==============================================================================
# SCRIPT: Enforce-OktaLifecycle.ps1
# PURPOSE: Query Okta directory and automatically deactivate expired contractors
# ==============================================================================

# --- CONFIGURATION ---
$orgUrl  = $env:OKTA_ORG_URL   # e.g., "https://dev-identity.okta.com"
$token   = $env:OKTA_API_TOKEN # Managed via environment variable for credential hygiene

if (-not $orgUrl) { $orgUrl = "https://dev-identity.okta.com" }
if (-not $token)  { $token  = "REPLACE_WITH_OKTA_API_TOKEN" }

$headers = @{
    "Authorization" = "SSWS $token"
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
}

# 1. Fetch active/pending users from the Okta tenant
$uri = "$orgUrl/api/v1/users?limit=200"
$users = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers

$today = (Get-Date).Date
Write-Host "Evaluating $($users.Count) directory accounts against current date: $($today.ToString('yyyy-MM-dd'))...`n" -ForegroundColor Cyan

# 2. Iterate through profiles and check contract expiration
foreach ($user in $users) {
    # Aligned directly with Okta Profile Editor variable name
    $contractEnd = $user.profile.contractEndDate

    if (-not [string]::IsNullOrWhiteSpace($contractEnd)) {
        $endDate = [datetime]::Parse($contractEnd).Date

        if ($endDate -le $today) {
            Write-Host "[EXPIRED] $($user.profile.login) expired on $contractEnd. Terminating access..." -ForegroundColor Yellow

            # Okta API endpoint to deactivate an identity
            $deactivateUri = "$orgUrl/api/v1/users/$($user.id)/lifecycle/deactivate"

            try {
                Invoke-RestMethod -Method Post -Uri $deactivateUri -Headers $headers
                Write-Host "[DEACTIVATED] Access successfully revoked for $($user.profile.login)" -ForegroundColor Red
            }
            catch {
                Write-Error "Failed to deactivate $($user.profile.login): $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "[ACTIVE] $($user.profile.login) contract valid until $contractEnd." -ForegroundColor Green
        }
    }
}

Write-Host "`nLifecycle audit complete." -ForegroundColor Cyan
