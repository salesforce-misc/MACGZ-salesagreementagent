# Open-source dependency report

Repository: [salesforce-misc/MACGZ-salesagreementagent](https://github.com/salesforce-misc/MACGZ-salesagreementagent)

Google Sheet: [MACGZ-salesagreementagent open-source dependencies](https://docs.google.com/spreadsheets/d/1lK-eyKGXJOlyUm6plc3VBa-Hdg6HXbTc6E0FRXPvLbo/edit)

## Summary

Sales Agreement Agent is an Agentforce employee agent for Manufacturing Cloud sales agreements. The repository is published under Apache-2.0 (`LICENSE.txt`). This inventory follows the [Calculating Open-Source Dependencies](https://docs.google.com/document/d/1LJy_3dQqW4wfLhaX5sYBg2-NXkzxfQa2VtDALMOQ68k/edit) guide.

No third-party packages are declared. There is no `package.json`, `pom.xml`, `requirements.txt`, `go.mod`, `composer.lock`, or vendored third-party source. Nothing under a copyleft license (GPL-3.0 or AGPL) was found. No third-party code is redistributed in a build artifact.

Salesforce platform, Manufacturing Cloud, Agentforce, and the Salesforce CLI are prerequisites the customer or developer already licenses. They are listed as excluded prerequisites, not as redistributed dependencies.

Embedded Salesforce Sans and Avant Garde for Salesforce font files were removed from `docs/index.html`. Those fonts are proprietary Monotype faces licensed to Salesforce and are not covered by Apache-2.0.

## Inventory

The same rows are in [dependency-report.csv](dependency-report.csv) and in the Google Sheet.

| package_name | spdx_license | graph_position | redistributed |
| --- | --- | --- | --- |
| salesforce-misc/MACGZ-salesagreementagent | Apache-2.0 | project | yes |
| No third-party packages | NONE | direct | no |
| Salesforce platform | proprietary | excluded-prerequisite | no |
| Manufacturing Cloud | proprietary | excluded-prerequisite | no |
| Agentforce | proprietary | excluded-prerequisite | no |
| Salesforce CLI | proprietary | excluded-prerequisite | no |
| Salesforce Sans (removed) | proprietary | excluded-prerequisite | no |
| Avant Garde For Salesforce (removed) | proprietary | excluded-prerequisite | no |

## Approvals

VP approval, Legal approval, and OSPO approval via the OSS Request Portal (https://oss-request2.sfdc.sh/) are required before publishing.
