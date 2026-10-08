/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Tests for SaaGroundAccount (resolve by Id, related Id or name; brief content)
 * and SaaLogActivity (objective, plan and account targets; guards).
 */
@IsTest
private class SaaGroundAndLogTest {

    private static SaaGroundAccount.Result ground(String recordId, String accountName) {
        SaaGroundAccount.Request req = new SaaGroundAccount.Request();
        req.recordId = recordId;
        req.accountName = accountName;
        return SaaGroundAccount.execute(new List<SaaGroundAccount.Request>{ req })[0];
    }

    private static SaaLogActivity.Result logActivity(String accountId, String planId, String objectiveId, String subject) {
        SaaLogActivity.Request req = new SaaLogActivity.Request();
        req.recordId = accountId;
        req.accountPlanId = planId;
        req.primaryObjectiveId = objectiveId;
        req.subject = subject;
        req.callNote = 'Note';
        return SaaLogActivity.execute(new List<SaaLogActivity.Request>{ req })[0];
    }

    @IsTest
    static void ground_byNameAndRelatedIds() {
        Account a = SaaTestDataFactory.makeAccount('Saa Ground Industries');
        AccountPlan plan = new AccountPlan(Name = 'Saa Ground Plan', AccountId = a.Id);
        insert plan;
        AccountPlanObjective obj = new AccountPlanObjective(Name = 'Saa Ground Objective', AccountPlanId = plan.Id);
        insert obj;
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Ground Opp');
        SalesAgreement sa = SaaTestDataFactory.makeSalesAgreement(a, 'Saa Ground SA');
        Contact c = new Contact(LastName = 'Saa Ground', AccountId = a.Id);
        insert c;

        Test.startTest();
        SaaGroundAccount.Result byName = ground(null, 'Saa Ground Industries');
        SaaGroundAccount.Result byFuzzyName = ground(null, 'Ground Indus');
        List<SaaGroundAccount.Result> byIds = new List<SaaGroundAccount.Result>();
        for (Id recId : new List<Id>{ a.Id, o.Id, sa.Id, plan.Id, obj.Id, c.Id }) {
            byIds.add(ground(recId, null));
        }
        Test.stopTest();

        System.assert(byName.success, byName.message);
        System.assertEquals(String.valueOf(a.Id), byName.resolvedAccountId);
        System.assertEquals(1, byName.planCount);
        System.assertEquals(1, byName.salesAgreementCount);
        System.assert(byName.contextSummary.contains('PLAN_ID=' + plan.Id), byName.contextSummary);
        System.assert(byName.contextSummary.contains('OBJECTIVE_ID=' + obj.Id), byName.contextSummary);
        System.assert(byName.contextSummary.contains('OPPORTUNITY_ID=' + o.Id), byName.contextSummary);
        System.assert(byName.contextSummary.contains('SALES_AGREEMENT_ID=' + sa.Id), byName.contextSummary);
        System.assertEquals(String.valueOf(a.Id), byFuzzyName.resolvedAccountId);
        for (SaaGroundAccount.Result r : byIds) {
            System.assertEquals(String.valueOf(a.Id), r.resolvedAccountId, r.message);
        }
    }

    @IsTest
    static void ground_emptyAccountAndMisses() {
        Account a = SaaTestDataFactory.makeAccount('Saa Empty Account');
        Task t = new Task(Subject = 'Unrelated', WhatId = a.Id);
        insert t;

        Test.startTest();
        SaaGroundAccount.Result empty = ground(a.Id, null);
        SaaGroundAccount.Result none = ground(null, 'No Such Account Saa');
        SaaGroundAccount.Result blank = ground(null, null);
        SaaGroundAccount.Result unsupported = ground(t.Id, null);
        SaaGroundAccount.Result malformed = ground('not-an-id', null);
        Test.stopTest();

        System.assert(empty.success);
        System.assertEquals(0, empty.planCount);
        System.assert(empty.contextSummary.contains('An account plan is needed'), empty.contextSummary);
        System.assert(!none.success);
        System.assert(!blank.success);
        System.assert(!unsupported.success);
        System.assert(malformed.message.startsWith('Error looking up the account'), malformed.message);
    }

    @IsTest
    static void log_targetsObjectivePlanOrAccount() {
        Account a = SaaTestDataFactory.makeAccount('Saa Log Account');
        AccountPlan plan = new AccountPlan(Name = 'Saa Log Plan', AccountId = a.Id);
        insert plan;
        AccountPlanObjective obj = new AccountPlanObjective(Name = 'Saa Log Objective', AccountPlanId = plan.Id);
        insert obj;

        Test.startTest();
        SaaLogActivity.Result onObjective = logActivity(a.Id, plan.Id, obj.Id, 'Pricing kickoff');
        SaaLogActivity.Result onPlan = logActivity(a.Id, plan.Id, null, null);
        SaaLogActivity.Result onAccount = logActivity(a.Id, null, null, 'Account note');
        Test.stopTest();

        System.assert(onObjective.success, onObjective.message);
        System.assertEquals(obj.Id, [SELECT WhatId FROM Task WHERE Id = :onObjective.activityId].WhatId);
        System.assert(onPlan.success, onPlan.message);
        Task planTask = [SELECT WhatId, Subject, Status FROM Task WHERE Id = :onPlan.activityId];
        System.assertEquals(plan.Id, planTask.WhatId);
        System.assertEquals('Pricing work update', planTask.Subject);
        System.assertEquals('Completed', planTask.Status);
        System.assert(onAccount.success, onAccount.message);
        System.assertEquals(a.Id, [SELECT WhatId FROM Task WHERE Id = :onAccount.activityId].WhatId);
    }

    @IsTest
    static void log_guards() {
        Account a = SaaTestDataFactory.makeAccount('Saa Log Account');
        Test.startTest();
        SaaLogActivity.Result noTarget = logActivity(null, null, null, 'Nothing');
        SaaLogActivity.Result malformed = logActivity('not-an-id', null, null, 'Bad');
        SaaLogActivity.Result badTarget = logActivity(Test.getStandardPricebookId(), null, null, 'Pricebook');
        Test.stopTest();

        System.assert(!noTarget.success);
        System.assert(noTarget.message.contains('I need an account'), noTarget.message);
        System.assert(!malformed.success);
        System.assert(malformed.message.startsWith('The activity was not logged'), malformed.message);
        System.assert(!badTarget.success, 'a price book cannot own a task');
        System.assert(badTarget.message.startsWith('The activity was not logged'), badTarget.message);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :a.Id]);
    }
}
