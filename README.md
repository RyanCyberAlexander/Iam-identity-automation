# Iam-identity-automation

Automated Joiner-Mover-Leaver (JML) identity lifecycle and access governance engine using PowerShell.

---

## 1. Identity Data Modeling & HR Source of Truth

To simulate an enterprise identity lifecycle engine (Joiner-Mover-Leaver), I designed a synthetic HRIS dataset generated via a locally hosted LLM endpoint to model real-world employee and contractor lifecycles for automated provisioning into Okta.

The schema accounts for core enterprise attributes, contract expiration boundaries, privileged flags, and deliberate edge cases to test automation error-handling:

| EmployeeID | FirstName | LastName | WorkEmail | Department | JobTitle | EmploymentType | StartDate | EndDate | IsAdmin | PrivilegeDuration | ManagerEmail |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1001 | Stan | Marsh | smarsh@southpark.local | Sales | Account Rep | FTE | 2025-09-01 | | FALSE | | rmarsh@southpark.local |
| 1002 | Kyle | Broflovski | kbroflovski@southpark.local | Finance | Staff Accountant | FTE | 2025-09-01 | | FALSE | | gbroflovski@southpark.local |
| 1003 | Eric | Cartman | ecartman@southpark.local | IT | Lead Systems Admin | FTE | 2024-01-15 | | TRUE | | rmarsh@southpark.local |
| 1004 | Kenny | McCormick | kmccormick@southpark.local | IT | Temp Systems Admin | Contractor | 2025-07-01 | 2026-12-31 | TRUE | 30 | ecartman@southpark.local |
| 1005 | Butters | Stotch | bstotch@southpark.local | IT | Junior DevOps Engineer | FTE | 2025-09-01 | | TRUE | | ecartman@southpark.local |
| 1006 | Wendy | Testaburger | wtestaburger@southpark.local | Engineering | Full Stack Engineer | Contractor | 2025-08-01 | 2026-12-31 | FALSE | | ecartman@southpark.local |
| 1007 | Tolkien | Black | tblack@southpark.local | Marketing | Media Consultant | Contractor | 2025-01-10 | 2026-08-31 | FALSE | | rmarsh@southpark.local |
| 1008 | Clyde | Donovan | cdonovan@southpark.local | Support | Customer Support Rep | Contractor | 2025-03-01 | 2026-05-01 | FALSE | | rmarsh@southpark.local |
| 1009 | Randy | Marsh | rmarsh@southpark.local | Operations | Operations Director | FTE | 2023-05-15 | | FALSE | | executive@southpark.local |
| 1010 | Towelie | Dryer | invalid-email-placeholder | Facilities | Towel Consultant | Contractor | 2025-09-01 | 2026-09-15 | FALSE | | rmarsh@southpark.local |

### Schema & Governance Logic
* **JML Lifecycle Tracking (`StartDate` / `EndDate`):** Enables time-based automated provisioning for new hires and scheduled deprovisioning/account suspension for fixed-term contractors.
* **Privilege & Least Privilege Flags (`IsAdmin`, `PrivilegeDuration`):** Distinguishes between standard business users and elevated access candidates. Includes temporary privilege duration logic for time-bound contractor access reviews.
* **Manager Hierarchy (`ManagerEmail`):** Maps reporting lines required for automated access request routing, approval chains, and periodic access certifications.
* **Intentional Data Quality Edge Cases:** Includes deliberate malformed data (e.g., `invalid-email-placeholder` on ID 1010) and expired contractor dates (e.g., ID 1008) to test script input validation, error handling, and security quarantine workflows.

---

## 2. Okta Directory Schema Extension

By default, standard Okta user profiles only support baseline identity attributes (Name, Email, Department, Title). To enforce lifecycle governance and time-bound access, I extended the Universal Directory schema via the Okta Profile Editor:

| Display Name | Variable Name | Data Type | Governance Function |
|---|---|---|---|
| **Contract End Date** | `contractEndDate` | String (ISO 8601) | Ingests contract termination boundaries to automate deprovisioning/suspension for non-FTE identities. |
| **Admin Expiration Date** | `adminExpirationDate` | String (ISO 8601) | Establishes time-bound privileged access boundaries (e.g., 30-day auto-decay) to enforce least-privilege principles. |

Extending the schema at the directory level ensures that the REST API payload is validated and persisted, enabling downstream group rules and policy deprovisioning workflows.

> **Technical Note / Schema Dependency:**  
> In Okta, the API will reject any user payload containing undeclared profile attributes with an HTTP `400 Bad Request` error. Creating `contractEndDate` and `adminExpirationDate` inside Okta's Profile Editor first is a prerequisite; the directory schema must explicitly recognize these field names before the PowerShell script can write data to them.

---

## 3. Privileged API Governance & Network Zone Allowlisting

* **Operational Constraint:** Initial API token creation failed during service principal setup due to Okta's mandatory origin-network enforcement (`API calls made with this token must originate from`).
* **Investigation & Security Principle:** Researching Okta's token governance model highlighted the requirement for **Defense-in-Depth** via **Network Zone IP binding**. Rather than treating API tokens as static bearer secrets, Okta requires privileged tokens to be bound to trusted administrative CIDR ranges or specific egress public IPs. This ensures that even if a token credential were leaked, unauthorized external API invocations from untrusted origins are blocked at the perimeter.
* **Resolution:** Configured an authorized Okta Network Zone matching the administrative testing gateway, binding the token's origin scope strictly to trusted source IPs before executing automated provisioning calls.

---

## 4. Automated Deprovisioning & Zombie Account Mitigation

To eliminate orphaned "zombie" accounts and enforce time-bound governance, `Revoke-OktaAdminAuthority.ps1` evaluates directory identities against contract expiration timestamps and revokes access automatically.

### Automated Execution Log
When executed, the engine queries the directory, parses the schema-extended `contractEndDate`, and triggers Okta's deactivation endpoint (`/api/v1/users/${id}/lifecycle/deactivate`) for expired accounts:

```text
Evaluating 10 directory accounts against current date...

[ACTIVE]      smarsh@southpark.local contract valid (FTE / Active).
[EXPIRED]     tblack@southpark.local expired on 2025-08-31. Terminating access...
[DEACTIVATED] Access successfully revoked for tblack@southpark.local
[EXPIRED]     cdonovan@southpark.local expired on 2025-08-31. Terminating access...
[DEACTIVATED] Access successfully revoked for cdonovan@southpark.local

Lifecycle audit complete.
```

### Directory Verification & State Transition
Following execution, the directory state was audited via the Okta Admin API to verify that account lifecycles transitioned as intended:

| Identity | Username | Role / Type | Contract End | Post-Execution Status | Result |
|---|---|---|---|---|---|
| **Tolkien Black** | `tblack@southpark.local` | Media Consultant (Contractor) | `2025-08-31` | `Deactivated` | Account terminated; all application access revoked |
| **Clyde Donovan** | `cdonovan@southpark.local` | Customer Support Rep (Contractor) | `2025-08-31` | `Deactivated` | Account terminated; all application access revoked |
| **Wendy Testaburger** | `wtestaburger@southpark.local` | Full Stack Engineer (Contractor) | `2026-12-31` | `Pending user action` | Retained (Valid contract) |
| **Stan Marsh** | `smarsh@southpark.local` | Account Rep (FTE) | None | `Pending user action` | Retained (Active FTE lifecycle) |

---

## 5. Dynamic RBAC & Automated Group Synchronization

To enforce scalable access provisioning, `Sync-OktaRBAC.ps1` dynamically creates target security groups in Okta and evaluates identities based on department and contractor classifications.

### Execution Log: Automated Group Membership
```text
STARTING DYNAMIC RBAC & GROUP SYNCHRONIZATION
==========================================================

[EXISTS] Group 'Dept-Engineering' is ready.
[EXISTS] Group 'Dept-IT' is ready.
[EXISTS] Group 'Dept-Finance' is ready.
[EXISTS] Group 'Dept-Sales' is ready.
[EXISTS] Group 'Type-Contractors' is ready.

Fetching directory users for group assignment...

[ASSIGNED] kbroflovski@southpark.local -> Dept-Finance
[ASSIGNED] kmccormick@southpark.local  -> Dept-IT
[ASSIGNED] kmccormick@southpark.local  -> Type-Contractors
[ASSIGNED] smarsh@southpark.local      -> Dept-Sales
[ASSIGNED] bstotch@southpark.local     -> Dept-IT
[ASSIGNED] ecartman@southpark.local    -> Dept-IT
[ASSIGNED] wtestaburger@southpark.local -> Dept-Engineering
[ASSIGNED] wtestaburger@southpark.local -> Type-Contractors

==========================================================
RBAC SYNCHRONIZATION COMPLETE
```

### Downstream SSO & Application Assignment
Directly assigning individual users to SaaS applications creates operational debt and access sprawl. Access was instead scoped at the group level:
* **Group-Based App Delivery:** Target applications (e.g., Bookmark / Internal Portal) are bound directly to the automated `Dept-IT` security group.
* **Zero-Touch Provisioning:** As users transition into the IT department via the HR feed, `Sync-OktaRBAC.ps1` places them into `Dept-IT`, automatically granting application Single Sign-On (SSO) downstream without manual admin intervention.

---

## 6. Privileged Access Governance & Granular RBAC Delegation

To enforce the **Principle of Least Privilege (PoLP)** and prevent administrative privilege creep, administrative rights are not granted via monolithic "Super Admin" roles. Instead, identities requiring elevated access are provisioned with granular, role-scoped administrative permissions tied to their functional responsibilities:

| Identity | Username | Delegated Administrative Role | Governance Scope & Security Function |
|---|---|---|---|
| **Eric Cartman** | `ecartman@southpark.local` | **Group Membership Administrator** | Scoped to manage group assignments without visibility or rights to modify directory-level policies or credential settings. |
| **Butters Stotch** | `bstotch@southpark.local` | **Help Desk Administrator** | Scoped to routine tier-1 support operations (e.g., password/MFA resets and user unlocking) without broad tenant configuration access. |
| **Kenny McCormick** | `kmccormick@southpark.local` | **Read-only Administrator** | Provides audit-level directory visibility for operational inspection while blocking any create, update, or delete actions against directory objects. |

### Architectural Takeaways:
* **Separation of Duties (SoD):** Granular role assignment prevents horizontal and vertical privilege escalation by ensuring team members only receive the permissions necessary for their direct workflows.
* **Privileged Identity Management (PIM):** Combined with the schema extension attribute `adminExpirationDate`, elevated roles are tagged for periodic access certification or automatic revocation, avoiding permanent standing privileges.

---

## 7. Automated Privilege Decay & Governance Enforcement

To mitigate permanent standing access and enforce administrative lease boundaries, `Revoke-OktaAdminAuthority.ps1` runs periodic audits against Okta directory assignments:

1. **Contract Expiration Checks:** Identifies identities where `contractEndDate <= Today` and invokes the Okta deactivation lifecycle endpoint (`/api/v1/users/{id}/lifecycle/deactivate`).
2. **Privileged Access Revocation:** Evaluates assigned admin leases against `adminExpirationDate`. When an administrative lease lapses, the engine enumerates assigned roles (`/api/v1/users/{id}/roles`) and sends an HTTP `DELETE` call to strip elevated authority while preserving the user's core identity.
