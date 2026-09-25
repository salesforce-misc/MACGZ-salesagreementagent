# Sales Agreement Agent — setup guide

This guide goes beyond the [README](../README.md) install steps. It covers what each piece does, which settings to change for your org, and how to troubleshoot.

## 1. How the agent is organized

The agent is an Agentforce Employee Agent written in Agent Script (`force-app/main/default/aiAuthoringBundles/Sales_Agreement_Agent/Sales_Agreement_Agent.agent`). A router reads what the AE says and hands off to one of seven subagents:

| Subagent | Actions it calls | Writes data? |
|---|---|---|
| `objective_management` | `SaaGroundAccount`, `SaaCreateAccountPlanObjective`, `SaaLogActivity`, `SaaCloseAccountPlanObjective` | Yes, after confirmation |
| `create_sales_agreement` | `SaaCheckOpportunityEligibility`, `SaaCreateSalesAgreementFromOpp`, `SaaCloneSalesAgreement` | Yes, after confirmation |
| `bulk_update` | `SaaApplyPriceIncrease` (preview first, then commit) | Yes, after confirmation |
| `agreement_management` | `SaaSummarizeSalesAgreement` | No |
| `generate_and_sign` | none (shares the record link and explains the steps) | No |
| `conversation_planner` | none (coaching) | No |
| `practice_simulation` | none (role-play) | No |

Writes are gated in the script, not just in the instructions. For example, `create_agreement` is only available once the `sa_create_confirmed` variable is true and no agreement has been created yet in this session. `apply_increase` is only available after `bulk_commit_confirmed`.

All Apex runs in **user mode**, so each AE's own sharing, object and field access apply. Every action returns `isSuccess` (or `success`) and a plain-language `message` that the agent relays.

## 2. Settings reference

Edit **Setup → Custom Metadata Types → Sales Agreement Agent Setting → Manage Records → Default**. The Apex reads it through `SaaSettings`; any blank value falls back to the default shown.

### Which opportunities can become an agreement

`SaaOpportunityEligibility` holds the rule. The read-only pre-check and the create action both use it, so they always agree.

- **Opportunity Record Type**: the DeveloperName, e.g. `Industrial_OEM`. Blank allows any record type.
- **Opportunity Eligibility Field**: the API name of an Opportunity **checkbox**, e.g. `Multi_Year_Commitment__c`. Blank means no checkbox rule.

If a value names something your org doesn't have, or the field isn't a checkbox, every opportunity is reported as ineligible, and the message names the setting to fix.

### How new agreements are shaped

| Setting | Applies to | Notes |
|---|---|---|
| Start Date Rule | create + clone | `Next_Year_Jan_1` suits an autumn pricing cycle for next year. |
| Schedule Frequency | create | `Monthly`, `Quarterly` or `Yearly`. Clones keep the source's frequency. |
| Schedule Count | create | Clones keep the source's count. |
| Agreement Type | create | Clones keep the source's type. |
| Agreement Record Type | create | Clones keep the source's record type. |
| Agreement Name Prefix | create | Clones roll the year in the source name forward instead ("Acme 2026" becomes "Acme 2027"). |
| Agreement Opportunity Field | create | Your Sales Agreement lookup to Opportunity, if you have one. Manufacturing Cloud has no standard one. |
| Clone Carry Fields | clone | Extra fields to copy, e.g. `Description, ContactId, Terms__c`. Fields that don't exist or can't be set are skipped. |

New and cloned agreements are always created as **Draft** with product level **Product**. Opportunity lines, and source agreement lines, that share a price book entry are merged into one Sales Agreement Product, because Manufacturing Cloud allows only one per entry.

The clone deliberately does **not** set `RenewedFromAgreementId`. That field triggers Manufacturing Cloud's renewal window validation (renew only within 60 days of the end date), which would block cloning early in the cycle.

## 3. Price list and signature steps

The `generate_and_sign` subagent doesn't generate or send documents. It shares the relative link `/lightning/r/SalesAgreement/<id>/view` and walks the AE through two buttons on the record: **Generate Document**, then **Send For Signature**.

If your Sales Agreement page uses different actions, for example a Document Generation OmniScript, DocuSign or Adobe Acrobat Sign, edit steps 2–4 in that subagent's instructions to match your button labels and any fields to check first. Then validate and republish:

```bash
sf agent validate authoring-bundle --api-name Sales_Agreement_Agent -o my-mfg-org
sf agent publish authoring-bundle --api-name Sales_Agreement_Agent -o my-mfg-org
sf agent activate --api-name Sales_Agreement_Agent -o my-mfg-org
```

Publishing creates a new agent version. Activate it to make it live.

## 4. Access checklist

| Who | Needs |
|---|---|
| Agent users (AEs) | `Sales_Agreement_Agent_User`, `Sales_Agreement_Agent_Access`, the Manufacturing Cloud Sales Agreements permission set, and CRUD on Sales Agreement, Sales Agreement Product, Sales Agreement Product Schedule, Account Plan, Account Plan Objective, Opportunity and Task |
| Admin who installs | Modify All Data or Customize Application + Author Apex, and Manage AI Agents |

## 5. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "…is not eligible… the configured opportunity record type "X" does not exist" | Setting points to the wrong DeveloperName | Fix **Opportunity Record Type**, or clear it |
| "Could not create the sales agreement: Required fields are missing: [Field__c]" | Your org requires a custom field on Sales Agreement | Default it with a before-save flow, or add it to **Clone Carry Fields** for clones |
| Tests fail on insert with REQUIRED_FIELD_MISSING or FIELD_CUSTOM_VALIDATION_EXCEPTION | Org-specific required fields or validation rules | Extend `SaaTestDataFactory` to populate them |
| Agent created 0 product lines | The opportunity has no products, or lines lack a price book entry | Add products to the opportunity; the agreement uses the opportunity's price book |
| Preview shows "No product schedules" | The agreement has no product lines yet | Add lines, or clone from an agreement that has them |
| The agreement link opens a "page not found" | The AE is in a different org/community URL | The link is relative on purpose; open it from the same Lightning session |
| Agent isn't in the Agentforce panel | Access permission set missing or agent not active | Assign `Sales_Agreement_Agent_Access`; run `sf agent activate` |

## 6. Uninstall

Deactivate the agent in **Setup → Agentforce Agents**. Then remove the metadata with a destructive-changes deploy listing the components in `manifest/package.xml` and `post-publish/`.
