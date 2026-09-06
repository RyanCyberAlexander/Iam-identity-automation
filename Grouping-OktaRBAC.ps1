# ==============================================================================
# SCRIPT: Sync-OktaRBAC.ps1
# PURPOSE: Automatically create enterprise security groups and dynamically
#          assign users based on their Department and Contractor status.
# ==============================================================================

# --- CONFIGURATION ---
$orgUrl =$env:OKTA_ORG_URL   # e.g., "https://dev-identity.okta.com"
$token  =$env:OKTA_API_TOKEN # Managed via environment variable for credential hygiene

if (-not $orgUrl) {$orgUrl = "https://dev-identity.okta.com" }
if (-not $token)  {$token  = "REPLACE_WITH_OKTA_API_TOKEN" }

$headers = @{
    "Authorization" = "SSWS $token"
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " STARTING DYNAMIC RBAC & GROUP SYNCHRONIZATION" -ForegroundColor Cyan
Write-Host "==========================================================`n" -ForegroundColor Cyan

# 1. Define required security groups
$requiredGroups = @(
    "Dept-Engineering",
    "Dept-IT",
    "Dept-Finance",
    "Dept-Sales",
    "Type-Contractors"
)

# 2. Fetch existing groups from Okta
$existingGroups = Invoke-RestMethod -Method Get -Uri "$orgUrl/api/v1/groups" -Headers $headers
$groupMap = @{}

foreach ($g in $existingGroups) {
    $groupMap[$g.profile.name] = $g.id
}

# 3. Ensure all required groups exist; create if missing
foreach ($gName in $requiredGroups) {
    if (-not $groupMap.ContainsKey($gName)) {
        Write-Host "[CREATING GROUP] $gName..." -ForegroundColor Yellow
        $body = @{
            profile = @{
                name        = $gName
                description = "Automated RBAC group for $gName"
            }
        } | ConvertTo-Json

        $newGroup = Invoke-RestMethod -Method Post -Uri "$orgUrl/api/v1/groups" -Headers $headers -Body $body
        $groupMap[$gName] = $newGroup.id
        Write-Host "  -> Created with ID: $($newGroup.id)" -ForegroundColor Green
    }
    else {
        Write-Host "[EXISTS] Group '$gName' is ready." -ForegroundColor Gray
    }
}

Write-Host "`nFetching directory users for group assignment...`n" -ForegroundColor White

# 4. Fetch users without restrictive status filter
$users = Invoke-RestMethod -Method Get -Uri "$orgUrl/api/v1/users?limit=200" -Headers $headers

foreach ($user in $users) {
    # Skip deactivated users
    if ($user.status -eq "DEPROVISIONED") {
        continue
    }

    $userId = $user.id
    $login  = $user.profile.login
    $dept   = $user.profile.department
    $isContractor = -not [string]::IsNullOrWhiteSpace($user.profile.contractEndDate)

    # Determine target group based on department
    $targetDeptGroup = "Dept-$dept"

    # Add to Department Group
    if ($groupMap.ContainsKey($targetDeptGroup)) {
        $groupId = $groupMap[$targetDeptGroup]
        $assignUri = "$orgUrl/api/v1/groups/$groupId/users/$userId"

        try {
            Invoke-RestMethod -Method Put -Uri $assignUri -Headers $headers
            Write-Host "[ASSIGNED] ${login} -> $targetDeptGroup" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to add ${login} to ${targetDeptGroup}: $($_.Exception.Message)"
        }
    }

    # Add to Contractors Group if contractEndDate is populated
    if ($isContractor) {
        $contractorGroupId = $groupMap["Type-Contractors"]
        $assignUri = "$orgUrl/api/v1/groups/$contractorGroupId/users/$userId"

        try {
            Invoke-RestMethod -Method Put -Uri $assignUri -Headers $headers
            Write-Host "[ASSIGNED] ${login} -> Type-Contractors" -ForegroundColor Yellow
        }
        catch {
            Write-Error "Failed to add ${login} to Type-Contractors: $($_.Exception.Message)"
        }
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " RBAC SYNCHRONIZATION COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
