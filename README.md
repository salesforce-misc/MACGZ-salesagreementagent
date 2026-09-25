# Sales Agreement Agent

An Agentforce employee agent for account executives who run the annual pricing cycle on **Manufacturing Cloud Sales Agreements**. The AE describes what they're doing in plain language, and the agent routes it to one of eight capabilities:

| # | Capability | What the agent does | Type |
|---|---|---|---|
| 1 | Start pricing work | Finds the account and logs an Account Plan Objective | Apex |
| 2 | Create the agreement | Checks the opportunity is eligible, then creates a Draft Sales Agreement with its products | Apex |
| 3 | Clone forward | Clones the current agreement into the next period, keeping lines and prices | Apex |
| 4 | Apply the increase | Previews, then applies, an approved % across every product and period | Apex |
| 5 | Prepare the conversation | Coaches the AE through a pricing-conversation strategy | Instructions |
| 6 | Practice | Role-plays the customer, then gives feedback | Instructions |
| 7 | Price list & signature | Shares the agreement link and walks through Generate Document, then Send For Signature | Instructions |
| 8 | Track & close out | Summarizes planned vs. actual, then closes the objective and its tasks | Apex |

The agent never claims a record was created or changed unless the action returned a real record Id. Every write is confirmed with the AE first.

**One-pager:** https://github.com/salesforce-misc/MACGZ-salesagreementagent/blob/main/docs/index.html

---

## Prerequisites

- A Salesforce org with **Manufacturing Cloud** (Sales Agreements, Account Plans) and **Agentforce** enabled. Einstein generative AI must be on.
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) v2 with the agent commands (`sf agent --help`).
- Users of the agent need the Manufacturing Cloud Sales Agreement permission set/license. They also need create/edit access to Sales Agreement, Sales Agreement Product, Account Plan Objective and Task.

## Install

```bash
git clone https://github.com/salesforce-misc/MACGZ-salesagreementagent.git
cd salesagreementagent
sf org login web --alias my-mfg-org

# 1. Deploy the Apex, settings, permission set and agent bundle, running the tests
sf project deploy start -x manifest/package.xml -o my-mfg-org -l RunSpecifiedTests \
  --tests SaaSalesAgreementActionsTest --tests SaaApplyPriceIncreaseTest \
  --tests SaaSummarizeSalesAgreementTest --tests SaaAccountPlanObjectiveTest \
  --tests SaaGroundAndLogTest

# 2. Publish and activate the agent
sf agent publish authoring-bundle --api-name Sales_Agreement_Agent -o my-mfg-org
sf agent activate --api-name Sales_Agreement_Agent -o my-mfg-org

# 3. Deploy the agent-access permission set (needs the published agent)
sf project deploy start -d post-publish -o my-mfg-org

# 4. Give users access
sf org assign permset -n Sales_Agreement_Agent_User -n Sales_Agreement_Agent_Access -o my-mfg-org
```

Then open any record in Lightning, open the Agentforce panel, pick **Sales Agreement Agent**, and say *"I'm starting pricing work for Acme."*

To try the agent from the CLI before rolling it out:

```bash
sf agent preview start -n Sales_Agreement_Agent -o my-mfg-org
```

## Configure it for your org

Every org-specific rule lives in one Custom Metadata record: **Setup → Custom Metadata Types → Sales Agreement Agent Setting → Manage Records → Default**. There's no need to edit the Apex.

| Setting | Default | Use it to… |
|---|---|---|
| Opportunity Record Type | *(blank = any)* | Allow agreements only from one opportunity record type (DeveloperName) |
| Opportunity Eligibility Field | *(blank = none)* | Require an opportunity checkbox, e.g. `Multi_Year_Commitment__c` |
| Agreement Record Type | *(blank = user default)* | Set the Sales Agreement record type for new agreements (DeveloperName) |
| Agreement Opportunity Field | *(blank = none)* | Link new agreements back to the opportunity through your lookup field |
| Start Date Rule | January 1 of next year | Start agreements on Jan 1 next year, the first of next month, or today |
| Schedule Frequency / Count | Monthly / 12 | Change the schedule shape of new agreements |
| Agreement Type | Volume | Use Revenue, or your own value |
| Agreement Name Prefix | Sales Agreement | Default names become *"Prefix 2027 — Opportunity Name"* |
| Clone Carry Fields | *(blank)* | Comma-separated extra fields to copy on clone, e.g. `Description, Terms__c` |
| Objective Name | Annual Pricing Work | Default Account Plan Objective name |

A setting that names a record type or field your org doesn't have makes the eligibility check fail with a message naming that setting. It never lets an opportunity through silently.

See [docs/SETUP.md](docs/SETUP.md) for the full setup guide: where each action is used, how to change the price-list and signature steps, and troubleshooting.

## What's in the repo

```
force-app/main/default/
  aiAuthoringBundles/Sales_Agreement_Agent/   Agent Script: router + 7 subagents
  classes/Saa*.cls                            11 invocable actions/helpers + 6 test classes
  objects/Sales_Agreement_Agent_Setting__mdt/ Configuration type (11 fields)
  customMetadata/                             The Default settings record
  permissionsets/Sales_Agreement_Agent_User   Apex class + settings access
post-publish/permissionsets/                  Agent access (deploy after publishing)
manifest/package.xml                          Everything in force-app
docs/SETUP.md                                 Setup, customization and troubleshooting
```

## Repurposing it

- **Rename the agent:** change `developer_name` and `agent_label` in `Sales_Agreement_Agent.agent`. Update `agentName` in the post-publish permission set and the manifest to match.
- **Change the wording:** each subagent's `instructions` block is plain language. The conversation planner and practice simulation are instruction-only, so they're the easiest to tailor to your sales motion.
- **Add a capability:** write an `@InvocableMethod` class that returns `isSuccess` and `message`. Declare it under a subagent's `actions:` with `target: "apex://YourClass"`, and add a routing line to `agent_router`.
- **Validate after edits:** `sf agent validate authoring-bundle --api-name Sales_Agreement_Agent -o my-mfg-org`.

## Tests

Six test classes cover every Apex class above 85% using only standard objects and fields. If your org adds **required custom fields or validation rules** on Sales Agreement, Opportunity or Account, the tests will hit them. So will the agent's create action, which reports the error rather than failing silently. Either give those fields defaults (for example with a before-save flow), or extend `SaaTestDataFactory` to set them.
