# KeePass → Bitwarden Migration Plan

## Environment Context

- **Source:** Shared KeePass vault (single KDBX file, team-shared)
- **Target:** Bitwarden Enterprise (AKS-hosted), single shared org collection
- **Auth:** SSO + SCIM provisioning already enabled and verified
- **Permissions:** All team members have read/write access to the collection
- **Tooling:** PowerShell 7, Bitwarden CLI (`bw`), VS Code + GitHub Copilot Chat

---

## Prerequisites

- [ ] Bitwarden CLI installed and available in PATH
- [ ] `bw login` completed and `$env:BW_SESSION` set via `bw unlock --raw`
- [ ] KeePass vault exported to KeePass XML 2.x format (`File → Export → KeePass XML 2.x`)
- [ ] XML export stored on an encrypted volume with restricted access
- [ ] All team members can authenticate into Bitwarden and see the shared collection

---

## Tooling Overview

| File | Purpose | Contains Secrets? |
|---|---|---|
| `Export-KeePassManifest.ps1` | Sanitized structural manifest for Copilot analysis | No |
| `Export-RemediationChecklist.ps1` | Flags entries needing post-import manual work | No |
| `Convert-KeePassToBitwarden.ps1` | Transforms KeePass XML to Bitwarden import JSON | **Yes** |
| `Import-BitwardenVault.ps1` | Imports transformed JSON via BW CLI | **Yes** |

---

## Phase 1 — Vault Analysis & Design (No Secrets Involved)

### Step 1.1 — Generate Sanitized Manifest

Run `Export-KeePassManifest` against the KeePass XML export. This produces a
`vault-manifest.json` containing full group hierarchy, entry metadata, and
structural flags with **zero credential values**.

```powershell
Export-KeePassManifest -KeePassXmlPath '.\vault.xml' -OutputPath '.\vault-manifest.json'
```

### Step 1.2 — Generate Remediation Checklist

Run `Export-RemediationChecklist` to identify entries that will require manual
post-import work regardless of design decisions.

```powershell
Export-RemediationChecklist -KeePassXmlPath '.\vault.xml' -OutputPath '.\remediation.json'
```

### Step 1.3 — Copilot Design Session

Open `vault-manifest.json` and `remediation.json` in VS Code. Use GitHub Copilot
Chat to inform the following design decisions before touching the unsanitized XML.

**Suggested Copilot prompts:**

- *"Analyze this KeePass manifest. Does the group hierarchy add navigational value
  or is it shallow enough to flatten into a single Bitwarden collection?"*
- *"Are there naming patterns in the entry titles that suggest groups should be
  renamed or restructured during migration?"*
- *"Which entries are likely SecureNote candidates based on the manifest flags?"*
- *"Are there patterns in the custom field names that suggest special handling is
  needed in the transform step?"*
- *"Based on the remediation checklist summary, what should be prioritized for
  manual follow-up after import?"*

### Step 1.4 — Record Design Decisions

Document the outcomes of the Copilot session here before proceeding:

| Decision | Choice | Notes |
|---|---|---|
| Group hierarchy | Preserve / Flatten / Restructure | |
| Group rename rules | None / List rules below | |
| SecureNote promotion logic | Heuristic (no credentials) / Manual list | |
| Custom field handling | Default / Special cases below | |
| Entry cleanup (stale/duplicate) | Pre-import / Post-import / None | |

**Group rename rules** *(if any)*:

```
# Example:
# "IT" → "Infrastructure"
# "Dev" → "Development"
```

**Entries to exclude from import** *(stale/duplicate, if any)*:

```
# List by Title and GroupPath from manifest
```

---

## Phase 2 — Feature Gap Handling

The following KeePass features do not map cleanly to Bitwarden. The transform
function handles these automatically unless noted.

| KeePass Feature | Bitwarden Handling | Automated? |
|---|---|---|
| Single entry type | Heuristic SecureNote promotion (no credentials = SecureNote) | Yes |
| Custom fields | Mapped; protected fields detected by KeePass flag or name pattern | Yes |
| TOTP seeds (KeeOTP, Tray TOTP, native) | Normalized to Bitwarden Authenticator Key field | Yes |
| Binary attachments | Dropped from import; `[ATTACHMENT PENDING: filename]` appended to notes | Partial — re-upload is manual |
| Entry expiration dates | `[EXPIRES: date]` appended to notes | Yes |
| KeePass tags | `[TAGS: ...]` appended to notes | Yes |
| Password history | **Dropped entirely** — export separately if compliance requires | No |
| Auto-Type sequences | **Dropped entirely** — team behavior change | No |
| Custom icons | **Dropped** — Bitwarden uses favicon fetch | No |

### Password History Export (if required for compliance)

If historical passwords need to be retained for audit purposes, extract them
from the KeePass XML manually before migration:

```
KeePass → Entry → Show All History Entries → Copy/Export as needed
```

Store extracted history in a secure location outside of Bitwarden (e.g., encrypted
file, separate vault).

---

## Phase 3 — Transform & Import

> **Security note:** Steps in this phase involve unsanitized credential data.
> Run on a trusted machine, on an encrypted volume, with no screen sharing active.

### Step 3.1 — Transform KeePass XML to Bitwarden JSON

Apply design decisions from Phase 1 to `Convert-KeePassToBitwarden` if any
modifications were determined during the Copilot session, then run the transform.

```powershell
Convert-KeePassToBitwarden `
    -KeePassXmlPath '.\vault.xml' `
    -OutputPath     '.\vault-import.json'
```

`CollectionId` is optional here — `Import-BitwardenVault` resolves and injects
it automatically at import time.

### Step 3.2 — Authenticate to Bitwarden CLI

```powershell
$env:BW_SESSION = (bw unlock --raw)
```

### Step 3.3 — Resolve Org ID

```powershell
$orgId = (bw list organizations | ConvertFrom-Json)[0].id
Write-Host "Org ID: $orgId"
```

### Step 3.4 — Import (WhatIf first)

```powershell
# Dry run — confirm item count and collection resolution before committing
Import-BitwardenVault -JsonPath '.\vault-import.json' -OrganizationId $orgId -WhatIf

# Live import
Import-BitwardenVault -JsonPath '.\vault-import.json' -OrganizationId $orgId
```

---

## Phase 4 — Validation

Complete these checks before communicating cutover to the team.

- [ ] Item count in Bitwarden matches KeePass entry count
- [ ] Spot-check 10–15 entries across different groups for credential accuracy
- [ ] Folder/group hierarchy matches intended structure
- [ ] TOTP entries from remediation checklist are identifiable in Bitwarden
- [ ] Attachment-pending entries are identifiable via note markers
- [ ] All team members can authenticate and access the collection
- [ ] SecureNote candidates display correctly as Secure Notes

---

## Phase 5 — Post-Import Remediation

Work through `remediation.json` to complete manual tasks that automation cannot handle.

### TOTP Re-Wiring

For each entry in `remediation.json → TotpEntries`:

1. Open the item in Bitwarden
2. Confirm the Authenticator Key (TOTP) field is populated
3. Test TOTP generation in the Bitwarden client
4. If the field is empty (unusual plugin format), manually enter the seed from KeePass

### Attachment Re-Upload

For each entry in `remediation.json → AttachmentEntries`:

1. Locate the entry in KeePass by Title + GroupPath
2. Export the binary attachment from KeePass (`Right-click → Save Attached File`)
3. Open the corresponding item in Bitwarden
4. Upload the file as an attachment
5. Delete the `[ATTACHMENT PENDING: ...]` marker from the notes field

### SecureNote Type Verification

For each entry in `remediation.json → SecureNoteCandidates`:

1. Open the item in Bitwarden
2. Confirm it was correctly typed as Secure Note
3. If it landed as Login (no credentials but has a URL), convert manually

### Expired Entry Review

For each entry in `remediation.json → ExpiredEntries`:

1. Locate the item in Bitwarden (notes will contain `[EXPIRES: ...]` marker)
2. Determine if the credential is still valid and in use
3. Update, archive, or delete as appropriate

---

## Phase 6 — Cutover & Communication

- [ ] Set hard cutover date — communicate to team with adequate lead time
- [ ] Confirm all team members have Bitwarden client installed (browser extension and/or desktop)
- [ ] Brief team on behavior changes: no Auto-Type sequences, favicon-based icons
- [ ] Mark KeePass vault as read-only on cutover date (rename or restrict file access)
- [ ] Grace period: keep KeePass vault accessible (read-only) for N days post-cutover
- [ ] Collect gap reports from team during grace period and remediate

---

## Phase 7 — Cleanup

Complete after grace period with no reported gaps.

- [ ] Securely delete KeePass XML export (`Remove-Item '.\vault.xml' -Force`)
- [ ] Securely delete Bitwarden import JSON (`Remove-Item '.\vault-import.json' -Force`)
- [ ] Archive or securely delete the KDBX file — do not leave on a shared drive
- [ ] Remove any temporary storage locations used during migration
- [ ] Document migration completion date and item count for audit trail (CMMC artifact)
- [ ] Retain `vault-manifest.json` and `remediation.json` as non-sensitive migration artifacts if needed

---

## Quick Reference — End-to-End Commands

```powershell
# Phase 1 — Analysis (no secrets)
Export-KeePassManifest      -KeePassXmlPath '.\vault.xml' -OutputPath '.\vault-manifest.json'
Export-RemediationChecklist -KeePassXmlPath '.\vault.xml' -OutputPath '.\remediation.json'

# Phase 3 — Transform & Import (contains secrets)
Convert-KeePassToBitwarden  -KeePassXmlPath '.\vault.xml' -OutputPath '.\vault-import.json'
$env:BW_SESSION = (bw unlock --raw)
$orgId = (bw list organizations | ConvertFrom-Json)[0].id
Import-BitwardenVault -JsonPath '.\vault-import.json' -OrganizationId $orgId -WhatIf
Import-BitwardenVault -JsonPath '.\vault-import.json' -OrganizationId $orgId

# Cleanup
Remove-Item '.\vault.xml', '.\vault-import.json' -Force
```
