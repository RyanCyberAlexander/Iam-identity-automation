# Iam-identity-automation
Automated Joiner-Mover-Leaver (JML) identity lifecycle and access governance engine using PowerShell.

## 1. Identity Data Modeling & HR Source of Truth

To simulate an enterprise identity lifecycle engine (Joiner-Mover-Leaver), I designed a synthetic HRIS dataset generated via a locally hosted LLM endpoint to model real-world employee and contractor lifecycles for automated provisioning into Okta.

The schema accounts for core enterprise attributes, contract expiration boundaries, privileged flags, and deliberate edge cases to test automation error-handling:

| EmployeeID | FirstName | LastName   | WorkEmail                   | Department  | JobTitle                 | EmploymentType | StartDate  | EndDate    | IsAdmin | PrivilegeDuration | ManagerEmail               |
|------------|-----------|------------|-----------------------------|-------------|--------------------------|----------------|------------|------------|---------|-------------------|----------------------------|
| 1001       | Stan      | Marsh      | smarsh@southpark.local      | Sales       | Account Rep              | FTE            | 2025-09-01 |            | FALSE   |                   | rmarsh@southpark.local     |
| 1002       | Kyle      | Broflovski | kbroflovski@southpark.local | Finance     | Staff Accountant         | FTE            | 2025-09-01 |            | FALSE   |                   | gbroflovski@southpark.local|
| 1003       | Eric      | Cartman    | ecartman@southpark.local    | IT          | Lead Systems Admin       | FTE            | 2024-01-15 |            | TRUE    |                   | rmarsh@southpark.local     |
| 1004       | Kenny     | McCormick  | kmccormick@southpark.local  | IT          | Temp Systems Admin       | Contractor     | 2025-07-01 | 2026-12-31 | TRUE    | 30                | ecartman@southpark.local   |
| 1005       | Butters   | Stotch     | bstotch@southpark.local     | IT          | Junior DevOps Engineer   | FTE            | 2025-09-01 |            | TRUE    |                   | ecartman@southpark.local   |
| 1006       | Wendy     | Testaburger| wtestaburger@southpark.local| Engineering | Full Stack Engineer      | Contractor     | 2025-08-01 | 2026-12-31 | FALSE   |                   | ecartman@southpark.local   |
| 1007       | Tolkien   | Black      | tblack@southpark.local      | Marketing   | Media Consultant         | Contractor     | 2025-01-10 | 2026-08-31 | FALSE   |                   | rmarsh@southpark.local     |
| 1008       | Clyde     | Donovan    | cdonovan@southpark.local    | Support     | Customer Support Rep     | Contractor     | 2025-03-01 | 2026-05-01 | FALSE   |                   | rmarsh@southpark.local     |
| 1009       | Randy     | Marsh      | rmarsh@southpark.local      | Operations  | Operations Director      | FTE            | 2023-05-15 |            | FALSE   |                   | executive@southpark.local  |
| 1010       | Towelie   | Dryer      | invalid-email-placeholder   | Facilities  | Towel Consultant         | Contractor     | 2025-09-01 | 2026-09-15 | FALSE   |                   | rmarsh@southpark.local     |

### Schema & Governance Logic
* **JML Lifecycle Tracking (`StartDate` / `EndDate`):** Enables time-based automated provisioning for new hires and scheduled deprovisioning/account suspension for fixed-term contractors.
* **Privilege & Least Privilege Flags (`IsAdmin`, `PrivilegeDuration`):** Distinguishes between standard business users and elevated access candidates. Includes temporary privilege duration logic for time-bound contractor access reviews.
* **Manager Hierarchy (`ManagerEmail`):** Maps reporting lines required for automated access request routing, approval chains, and periodic access certifications.
* **Intentional Data Quality Edge Cases:** Includes deliberate malformed data (e.g., `invalid-email-placeholder` on ID 1010) and expired contractor dates (e.g., ID 1008) to test script input validation, error handling, and security quarantine workflows.
