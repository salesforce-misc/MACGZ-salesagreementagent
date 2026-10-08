# Draft email — do not send

To: OSS Legal
Subject: Open-source dependency review for salesforce-misc/MACGZ-salesagreementagent

Sales Agreement Agent is an Agentforce employee agent that helps account executives run the annual pricing cycle on Manufacturing Cloud sales agreements. Customers deploy the Salesforce source into an org that already has Manufacturing Cloud and Agentforce. The repository is https://github.com/salesforce-misc/MACGZ-salesagreementagent.

License types found:

- Apache-2.0 for this repository (`LICENSE.txt`)
- No third-party package licenses. There is no npm, Maven, Python, Go, or Composer manifest, and no vendored third-party source.
- Proprietary Salesforce platform products (Salesforce platform, Manufacturing Cloud, Agentforce, Salesforce CLI) are prerequisites the consumer already licenses. They are not redistributed.
- Proprietary Monotype fonts (Salesforce Sans and Avant Garde for Salesforce) were embedded in `docs/index.html` and have been removed. They are not redistributed.

We are not redistributing any third-party dependency in a build artifact. The published artifact is this source repository under Apache-2.0.

Spreadsheet: https://docs.google.com/spreadsheets/d/1lK-eyKGXJOlyUm6plc3VBa-Hdg6HXbTc6E0FRXPvLbo/edit

CSV in the repository: `docs/open-source/dependency-report.csv`
