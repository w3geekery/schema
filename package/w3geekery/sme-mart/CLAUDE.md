# CLAUDE.md - SME Mart Schema Package

> **Parent:** See repo-root `CLAUDE.md` for general schema authoring patterns, validation, and deployment.

## Overview

AuditgraphDB schema for **SME Mart** — W3Geekery's marketplace for Subject Matter Experts. Defines entity classes, fields, enums, and links for the engagement lifecycle: RFP creation, bids, reviews, notes, documents, and service offerings.

**Package:** `@zerobias-org/schema-w3geekery-sme-mart`
**Catalog:** `w3geekery.sme-mart.schema`
**PR:** https://github.com/zerobias-org/schema/pull/3
**Branch:** `feat/w3geekery-sme-mart-schema`

## Entity Model

```
Engagement (extends Object)
  |-- bids --> Bid[]
  |-- reviews --> Review[]
  |-- notes --> Note[]
  |-- documents --> SmeMartDocument[]
  |
  Bid (extends Object) --> engagement
  Review (extends Object) --> engagement
  Note (extends Object) --> engagement, folder
  NoteFolder (extends Object) --> parent/children (self-ref), notes
  SmeMartDocument (extends File) --> engagement
  ServiceOffering (extends Object) -- standalone catalog listing
```

## Classes (7)

| Class | Base | Purpose |
|-------|------|---------|
| `Engagement` | Object | Buyer RFP / engagement — full lifecycle from draft to completed |
| `Bid` | Object | Vendor response/bid to an RFP |
| `Review` | Object | Post-engagement provider rating |
| `ServiceOffering` | Object | Provider catalog listing |
| `Note` | Object | Rich-text engagement note |
| `NoteFolder` | Object | Hierarchical folder for notes |
| `SmeMartDocument` | File | Uploaded procurement document (extends platform File) |

## Enums

| Enum | Values |
|------|--------|
| `engagement.status` | DRAFT, OPEN, IN_PROGRESS, COMPLETED, CANCELLED |
| `engagement.budgetType` | FIXED, HOURLY, RETAINER, NEGOTIABLE, NOT_SPECIFIED |
| `document.documentType` | SECURITY_REQUIREMENTS, SOW, BUDGET, LEGAL_TERMS, COMPLIANCE, FUNCTIONAL_SPEC, EVALUATION, PRIVACY, FEDERAL_PROVISIONS, OTHER |
| `bid.status` | DRAFT, PENDING, ACCEPTED, REJECTED, WITHDRAWN |
| `bidResponse.complianceStatus` | MET, PARTIALLY_MET, NOT_MET, NOT_APPLICABLE, PLANNED |
| `review.status` | PENDING_APPROVAL, APPROVED, REJECTED |
| `serviceOffering.pricingType` | FIXED, HOURLY, SUBSCRIPTION, CUSTOM |

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `Engagement` not `WorkRequest` | Aligns with UI/Brian terminology. GQL queries read as `query { Engagement { ... } }` |
| `SmeMartDocument` not `Document` | Avoids collision with platform `Document` type |
| Extends `Object` (not `Element`) | Element = formal document parts (laws, standards). Wrong for marketplace entities |
| `open` status (not `published`) | Matches Neon DB, UI language, and Plan 032. "Open" = accepting bids |
| `File` base for documents | Platform File provides fileVersionId, size, mimeType, downloadUrl |
| RFP requirements = ZB Tasks | After wizard publish, requirements become real ZB Tasks with child_of links. No separate GQL entity needed |
| Wizard state in `wizardData` | JSON blob on Engagement for draft persistence. Cleared on publish |
| `Bid` not `Proposal` | Brian directive (2026-03-06): "Proposal" removed from vocabulary. Vendor response = **Bid** |

## RFP Wizard Fields (Plan 032)

The Engagement class includes fields specifically for the RFP creation wizard:

- `budgetType` — pricing model (fixed/hourly/retainer/negotiable)
- `responseDeadline` — vendor bid deadline
- `questionsDeadline` — vendor questions deadline
- `confidentialityRequirements` — NDA/data handling text
- `evaluationCriteria` — JSON: weighted scoring per domain (SECURITY, COMPLIANCE, etc.)
- `wizardStep` — last completed step (0-4) for draft resumption
- `wizardData` — full wizard state JSON blob

## Document Types (from CDPH RFP Analysis)

Derived from analyzing the California CDPH HBEDS RFP (17 documents, ~200 requirements):

| documentType | Source Documents |
|-------------|-----------------|
| security_requirements | Exhibit F (ISO/SR1 v5.5) |
| sow | Exhibit A (Statement of Work) |
| budget | Exhibit B, Attachment 1 (Cost Workbook) |
| legal_terms | Exhibit C, D, G (IP, Insurance, Release) |
| compliance | General compliance documentation |
| functional_spec | Exhibit A1, A2 (CDC/NHSN specs, data elements) |
| evaluation | Attachments 3, 4 (Bidder qualifications, experience) |
| privacy | Exhibit E (Information Privacy) |
| federal_provisions | Exhibit B1 (Federal fund provisions) |
| other | Catch-all |

## Task Type Domains (Global ZB Tags)

RFP requirements decompose into 6 typed domains (global ZB platform tags, not schema entities):

| Domain | Tag Name | Example Source |
|--------|----------|---------------|
| Security | SECURITY | Exhibit F — access controls, encryption, pen testing |
| Compliance | COMPLIANCE | Exhibit E, B1 — HIPAA, regulatory, privacy |
| Legal | LEGAL | Exhibit C, D — IP, insurance, subcontractors |
| Functional | FUNCTIONAL | Exhibit A — system requirements, dashboards, onboarding |
| Financial | FINANCIAL | Exhibit B — pricing, invoicing, budget |
| Evaluation | EVALUATION | Attachments 3, 4 — bidder qualifications, references |

## Development

```bash
# Validate YAML schema (always run after changes)
cd package/w3geekery/sme-mart
npm run verify:yaml

# Full verification (YAML + dataloader against scratch DB)
npm run verify

# Rebuild scratch DB baseline (after platform updates)
npm run update-db
```

## Deployment

Schema merges to `dev`/`qa`/`main` in `zerobias-org/schema` trigger automatic dataloader import into the corresponding environment's AuditgraphDB. After merge, verify via GraphQL introspection that new types/fields appear.

## Related

- **SME Mart Angular app:** `~/Projects/w3geekery/zerobias-org-forks/app/package/w3geekery/sme-mart/`
- **GQL schema howto:** `app/.claude/notes/zb-graphql-custom-schema-howto.md`
- **CDPH RFP analysis:** `app/.claude/notes/cdph-rfp-analysis.md`
- **Migration plan:** `app/.claude/plans/local/034-gql-schema-migration.md`
- **RFP wizard plan:** `app/.claude/plans/local/032-rfp-creation-wizard.md`
- **Scratch DB setup:** Uses `npx @zerobias-org/util-content-dev-schema` (Supabase PG17, port 15432, database content_dev)
