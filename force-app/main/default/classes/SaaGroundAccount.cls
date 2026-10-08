/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Sales Agreement Agent — resolve an account and return the records the agent
 * needs to work on it (read-only).
 *
 * Wire with: target: "apex://SaaGroundAccount"
 *
 * Accepts an Account Id, a related record Id (Opportunity, Sales Agreement,
 * Account Plan, Account Plan Objective, Contact) or an account name. Returns a
 * plain-text brief with the account's plans and objectives, open opportunities
 * and sales agreements, each with its record Id, so the agent can pass real Ids
 * to the next action instead of guessing.
 */
public with sharing class SaaGroundAccount {

    private static final Integer MAX_ROWS = 10;

    @InvocableMethod(
        label='SAA Ground Account'
        description='Resolves an account by Id, related record Id or name, and returns its account plans and objectives, open opportunities and sales agreements with their Ids. Read-only.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.success = false;
            try {
                Id accountId = resolveAccountId(req);
                if (accountId == null) {
                    r.message = 'I could not find that account. Give me the exact account name or open the record and try again.';
                    results.add(r);
                    continue;
                }
                List<Account> accts = [SELECT Id, Name FROM Account WHERE Id = :accountId WITH USER_MODE LIMIT 1];
                if (accts.isEmpty()) {
                    r.message = 'That account could not be found or you do not have access to it.';
                    results.add(r);
                    continue;
                }
                r.resolvedAccountId = accts[0].Id;
                r.accountName = accts[0].Name;
                r.contextSummary = buildSummary(accts[0], r);
                r.success = true;
                r.message = 'Found account ' + accts[0].Name + '.';
            } catch (Exception e) {
                r.message = 'Error looking up the account: ' + e.getMessage();
            }
            results.add(r);
        }
        return results;
    }

    @TestVisible
    private static Id resolveAccountId(Request req) {
        if (String.isNotBlank(req.recordId)) {
            Id recId = (Id) req.recordId.trim();
            Schema.SObjectType t = recId.getSObjectType();
            if (t == Account.SObjectType) { return recId; }
            if (t == Opportunity.SObjectType) {
                for (Opportunity o : [SELECT AccountId FROM Opportunity WHERE Id = :recId WITH USER_MODE]) { return o.AccountId; }
            } else if (t == SalesAgreement.SObjectType) {
                for (SalesAgreement s : [SELECT AccountId FROM SalesAgreement WHERE Id = :recId WITH USER_MODE]) { return s.AccountId; }
            } else if (t == AccountPlan.SObjectType) {
                for (AccountPlan p : [SELECT AccountId FROM AccountPlan WHERE Id = :recId WITH USER_MODE]) { return p.AccountId; }
            } else if (t == AccountPlanObjective.SObjectType) {
                for (AccountPlanObjective o : [SELECT AccountPlan.AccountId FROM AccountPlanObjective WHERE Id = :recId WITH USER_MODE]) {
                    return o.AccountPlan.AccountId;
                }
            } else if (t == Contact.SObjectType) {
                for (Contact c : [SELECT AccountId FROM Contact WHERE Id = :recId WITH USER_MODE]) { return c.AccountId; }
            }
            return null;
        }
        if (String.isNotBlank(req.accountName)) {
            String name = req.accountName.trim();
            List<Account> exact = [SELECT Id FROM Account WHERE Name = :name WITH USER_MODE LIMIT 1];
            if (!exact.isEmpty()) { return exact[0].Id; }
            String pattern = '%' + name + '%';
            List<Account> fuzzy = [
                SELECT Id FROM Account WHERE Name LIKE :pattern
                WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 1
            ];
            if (!fuzzy.isEmpty()) { return fuzzy[0].Id; }
        }
        return null;
    }

    private static String buildSummary(Account acct, Result r) {
        List<String> lines = new List<String>{ 'ACCOUNT: ' + acct.Name + ' | ACCOUNT_ID=' + acct.Id, '' };

        List<AccountPlan> plans = [
            SELECT Id, Name,
                   (SELECT Id, Name, Status FROM AccountPlanObjectives ORDER BY CreatedDate DESC LIMIT :MAX_ROWS)
            FROM AccountPlan
            WHERE AccountId = :acct.Id
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_ROWS
        ];
        r.planCount = plans.size();
        lines.add('ACCOUNT PLANS & OBJECTIVES (newest first):');
        if (plans.isEmpty()) { lines.add('  None. An account plan is needed before an objective can be logged.'); }
        for (AccountPlan p : plans) {
            lines.add('  PLAN "' + p.Name + '" | PLAN_ID=' + p.Id);
            for (AccountPlanObjective o : p.AccountPlanObjectives) {
                lines.add('     OBJECTIVE "' + o.Name + '" | OBJECTIVE_ID=' + o.Id
                    + ' | Status=' + (o.Status == null ? 'n/a' : o.Status));
            }
        }

        lines.add('');
        lines.add('OPEN OPPORTUNITIES:');
        List<Opportunity> opps = [
            SELECT Id, Name, StageName, CloseDate FROM Opportunity
            WHERE AccountId = :acct.Id AND IsClosed = false
            WITH USER_MODE ORDER BY CloseDate DESC LIMIT :MAX_ROWS
        ];
        if (opps.isEmpty()) { lines.add('  None.'); }
        for (Opportunity o : opps) {
            lines.add('  "' + o.Name + '" | OPPORTUNITY_ID=' + o.Id + ' | Stage=' + o.StageName
                + ' | Close ' + String.valueOf(o.CloseDate));
        }

        lines.add('');
        lines.add('SALES AGREEMENTS (newest start first):');
        List<SalesAgreement> sas = [
            SELECT Id, Name, Status, StartDate, EndDate FROM SalesAgreement
            WHERE AccountId = :acct.Id
            WITH USER_MODE ORDER BY StartDate DESC NULLS LAST LIMIT :MAX_ROWS
        ];
        r.salesAgreementCount = sas.size();
        if (sas.isEmpty()) { lines.add('  None.'); }
        for (SalesAgreement s : sas) {
            lines.add('  "' + s.Name + '" | SALES_AGREEMENT_ID=' + s.Id + ' | Status=' + s.Status
                + ' | ' + String.valueOf(s.StartDate) + ' to ' + String.valueOf(s.EndDate));
        }
        return String.join(lines, '\n');
    }

    public class Request {
        @InvocableVariable(
            label='Record Id'
            description='Account Id, or an Opportunity, Sales Agreement, Account Plan, Account Plan Objective or Contact Id that belongs to the account.'
            required=false
        )
        public String recordId;

        @InvocableVariable(
            label='Account Name'
            description='Account name to look up when no Id is known.'
            required=false
        )
        public String accountName;
    }

    public class Result {
        @InvocableVariable(label='Success' description='Whether the account was found.')
        public Boolean success;

        @InvocableVariable(label='Resolved Account Id' description='Id of the account that was found.')
        public String resolvedAccountId;

        @InvocableVariable(label='Account Name' description='Name of the account that was found.')
        public String accountName;

        @InvocableVariable(label='Plan Count' description='Number of account plans returned.')
        public Integer planCount;

        @InvocableVariable(label='Sales Agreement Count' description='Number of sales agreements returned.')
        public Integer salesAgreementCount;

        @InvocableVariable(label='Context Summary' description='Plain-text brief with the account plans, objectives, open opportunities and sales agreements, with record Ids. Use only these Ids.')
        public String contextSummary;

        @InvocableVariable(label='Message' description='Human-readable result for the agent to relay.')
        public String message;
    }
}
