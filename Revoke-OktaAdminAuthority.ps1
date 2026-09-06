# ==============================================================================
# SCRIPT: Revoke-OktaAdminAuthority.ps1
# PURPOSE: Unified Identity Governance Engine
#          1. Terminates accounts with expired contractor dates (JML Leaver)
#          2. Revokes admin roles from accounts with expired admin leases (PIM/JIT)
# ==============================================================================

# --- CONFIGURATION ---
# Managed via environment variables to prevent hardcoded credential exposure
$orgUrl = $env:OKTA_ORG_URL   # e.g., "https://dev-identity.okta.com"
$token  = $env:OKTA_API_TOKEN # Managed via environment variable for credential hygiene

if (-not $orgUrl) { $orgUrl = "https://dev-identity.okta.com" }
if (-not $token)  { $token  = "REPLACE_WITH_OKTA_API_TOKEN" }

$headers = @{
    "Authorization" = "SSWS $token"
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
}

$today = (Get-Date).Date
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " STARTING IDENTITY GOVERNANCE AUDIT: $($today.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
Write-Host "==========================================================`n" -ForegroundColor Cyan

# 1. Fetch active and staged users from Okta
$uri = "$orgUrl/api/v1/users?limit=200"
$users = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers

Write-Host "Loaded $($users.Count) identities for policy evaluation.`n" -ForegroundColor White

foreach ($user in $users) {
    $login = $user.profile.login
    $userId = $user.id
    # Aligned directly with Okta Profile Editor variable names
    $contractEnd = $user.profile.contractEndDate
    $adminExpiry = $user.profile.adminExpirationDate

    # -------------------------------------------------------------
    # POLICY 1: CONTRACTOR LIFECYCLE (LEAVER ENFORCEMENT)
    # -------------------------------------------------------------
    if (-not [string]::IsNullOrWhiteSpace($contractEnd)) {
        $contractDate = [datetime]::Parse($contractEnd).Date

        if ($contractDate -le $today) {
            Write-Host "[EXPIRED CONTRACT] $login expired on $contractEnd." -ForegroundColor Yellow
            $deactivateUri = "$orgUrl/api/v1/users/$userId/lifecycle/deactivate"

            try {
                Invoke-RestMethod -Method Post -Uri $deactivateUri -Headers $headers
                Write-Host "  -> [DEACTIVATED] Account disabled." -ForegroundColor Red
            }
            catch {
                Write-Error "  -> Failed to deactivate ${login}: $($_.Exception.Message)"
            }
            # Skip checking admin roles if the user is already deactivated
            continue
        }
        else {
            Write-Host "[ACTIVE CONTRACT] $login valid until $contractEnd." -ForegroundColor Green
        }
    }

    # -------------------------------------------------------------
    # POLICY 2: PRIVILEGE ACCESS GOVERNANCE (ADMIN LEASE CLEANUP)
    # -------------------------------------------------------------
    if (-not [string]::IsNullOrWhiteSpace($adminExpiry)) {
        $adminDate = [datetime]::Parse($adminExpiry).Date

        if ($adminDate -le $today) {
            Write-Host "[EXPIRED ADMIN LEASE] $login admin lease expired on $adminExpiry. Checking roles..." -ForegroundColor Yellow

            $rolesUri = "$orgUrl/api/v1/users/$userId/roles"
            $roles = Invoke-RestMethod -Method Get -Uri $rolesUri -Headers $headers

            foreach ($role in $roles) {
                # Ensure only directly assigned roles are revoked via API
                if ($role.assignmentType -eq "USER") {
                    $deleteRoleUri = "$orgUrl/api/v1/users/$userId/roles/$($role.id)"
                    
                    try {
                        Invoke-RestMethod -Method Delete -Uri $deleteRoleUri -Headers $headers
                        Write-Host "  -> [REVOKED] Admin role '$($role.type)' stripped." -ForegroundColor Red
                    }
                    catch {
                        Write-Error "  -> Failed to revoke role from ${login}: $($_.Exception.Message)"
                    }
                }
            }
        }
        else {
            Write-Host "[ACTIVE ADMIN LEASE] $login admin rights valid until $adminExpiry." -ForegroundColor Green
        }
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " GOVERNANCE AUDIT COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
