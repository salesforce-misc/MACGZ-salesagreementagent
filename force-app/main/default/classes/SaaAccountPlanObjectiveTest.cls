/**
 * Tests for the Sales Agreement Agent objective actions:
 *   - SaaCreateAccountPlanObjective (by plan id, by account id, no plan, DML failure)
 *   - SaaCloseAccountPlanObjective (close with open tasks, not found)
 */
@IsTest
private class SaaAccountPlanObjectiveTest {

    private static AccountPlan makePlan(Account a) {
        AccountPlan p = new AccountPlan(Name = 'Saa Test Plan', AccountId = a.Id);
        insert p;
        return p;
    }

    private static SaaCreateAccountPlanObjective.Result create(SaaCreateAccountPlanObjective.Request req) {
        return SaaCreateAccountPlanObjective.execute(
            new List<SaaCreateAccountPlanObjective.Request>{ req })[0];
    }

    @IsTest
    static void create_withAccountPlanId() {
        Account a = SaaTestDataFactory.makeAccount('Saa Plan Account');
        AccountPlan plan = makePlan(a);

        SaaCreateAccountPlanObjective.Request req = new SaaCreateAccountPlanObjective.Request();
        req.accountPlanId = plan.Id;
        req.objectiveName = 'Pricing 2027';
        req.description = 'Custom description';

        Test.startTest();
        SaaCreateAccountPlanObjective.Result r = create(req);
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        AccountPlanObjective obj = [
            SELECT Name, Description, Status, AccountPlanId, EndDate, StartDate
            FROM AccountPlanObjective WHERE Id = :r.objectiveId
        ];
        System.assertEquals('Pricing 2027', obj.Name);
        System.assertEquals('Custom description', obj.Description);
        System.assertEquals('Yellow', obj.Status);
        System.assertEquals(plan.Id, obj.AccountPlanId);
        System.assertEquals(obj.StartDate.addMonths(12).addDays(-1), obj.EndDate);
        System.assert(r.message.contains('Pricing 2027'));
    }

    @IsTest
    static void create_withAccountId_usesNewestPlanAndDefaults() {
        Account a = SaaTestDataFactory.makeAccount('Saa Plan Account');
        AccountPlan plan = makePlan(a);

        SaaCreateAccountPlanObjective.Request req = new SaaCreateAccountPlanObjective.Request();
        req.accountId = a.Id;

        Test.startTest();
        SaaCreateAccountPlanObjective.Result r = create(req);
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals(plan.Id, r.accountPlanId);
        AccountPlanObjective obj = [SELECT Name, Description FROM AccountPlanObjective WHERE Id = :r.objectiveId];
        System.assertEquals(SaaSettings.get().objectiveName, obj.Name);
        System.assert(obj.Description.contains('Pricing work started'));
    }

    @IsTest
    static void create_noPlan_fails() {
        Account a = SaaTestDataFactory.makeAccount('Saa No Plan Account');

        SaaCreateAccountPlanObjective.Request byAccount = new SaaCreateAccountPlanObjective.Request();
        byAccount.accountId = a.Id;
        SaaCreateAccountPlanObjective.Request empty = new SaaCreateAccountPlanObjective.Request();

        Test.startTest();
        List<SaaCreateAccountPlanObjective.Result> res = SaaCreateAccountPlanObjective.execute(
            new List<SaaCreateAccountPlanObjective.Request>{ byAccount, empty });
        Test.stopTest();

        for (SaaCreateAccountPlanObjective.Result r : res) {
            System.assertEquals(false, r.isSuccess);
            System.assertEquals(null, r.objectiveId);
            System.assert(r.message.contains('Could not determine an Account Plan'));
        }
        System.assertEquals(0, [SELECT COUNT() FROM AccountPlanObjective]);
    }

    @IsTest
    static void create_invalidPlanId_reportsDmlFailure() {
        Account a = SaaTestDataFactory.makeAccount('Saa Bad Plan Account');

        SaaCreateAccountPlanObjective.Request req = new SaaCreateAccountPlanObjective.Request();
        req.accountPlanId = a.Id; // an Account Id is not a valid AccountPlanId

        Test.startTest();
        SaaCreateAccountPlanObjective.Result r = create(req);
        Test.stopTest();

        System.assertEquals(false, r.isSuccess);
        System.assertEquals(null, r.objectiveId);
        System.assert(r.message.startsWith('Could not create objective'), r.message);
    }

    @IsTest
    static void create_malformedPlanId_reportsError() {
        SaaCreateAccountPlanObjective.Request req = new SaaCreateAccountPlanObjective.Request();
        req.accountPlanId = 'not-an-id';

        Test.startTest();
        SaaCreateAccountPlanObjective.Result r = create(req);
        Test.stopTest();

        System.assertEquals(false, r.isSuccess);
        System.assert(r.message.startsWith('Error preparing objective'), r.message);
    }

    @IsTest
    static void close_completesOpenTasks() {
        Account a = SaaTestDataFactory.makeAccount('Saa Close Account');
        AccountPlan plan = makePlan(a);
        AccountPlanObjective obj = new AccountPlanObjective(
            Name = 'Pricing Work', AccountPlanId = plan.Id, Status = 'Yellow',
            StartDate = Date.today().addMonths(-1), EndDate = Date.today().addMonths(11)
        );
        insert obj;
        insert new List<Task>{
            new Task(Subject = 'Send price list', WhatId = obj.Id, Status = 'Not Started'),
            new Task(Subject = 'Confirm volumes', WhatId = obj.Id, Status = 'Not Started')
        };

        SaaCloseAccountPlanObjective.Request req = new SaaCloseAccountPlanObjective.Request();
        req.objectiveId = obj.Id;

        Test.startTest();
        SaaCloseAccountPlanObjective.Result r = SaaCloseAccountPlanObjective.execute(
            new List<SaaCloseAccountPlanObjective.Request>{ req })[0];
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals(2, r.tasksCompleted);
        System.assert(r.message.contains('completed 2 open task(s)'), r.message);
        AccountPlanObjective closed = [SELECT Status, EndDate FROM AccountPlanObjective WHERE Id = :obj.Id];
        System.assertEquals('Green', closed.Status);
        System.assertEquals(Date.today(), closed.EndDate);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :obj.Id AND IsClosed = false]);
    }

    @IsTest
    static void close_withoutTasks_andNotFound() {
        Account a = SaaTestDataFactory.makeAccount('Saa Close Account');
        AccountPlan plan = makePlan(a);
        AccountPlanObjective obj = new AccountPlanObjective(Name = 'Pricing Work', AccountPlanId = plan.Id);
        insert obj;

        SaaCloseAccountPlanObjective.Request ok = new SaaCloseAccountPlanObjective.Request();
        ok.objectiveId = obj.Id;
        SaaCloseAccountPlanObjective.Request missing = new SaaCloseAccountPlanObjective.Request();

        Test.startTest();
        List<SaaCloseAccountPlanObjective.Result> res = SaaCloseAccountPlanObjective.execute(
            new List<SaaCloseAccountPlanObjective.Request>{ ok, missing });
        Test.stopTest();

        System.assert(res[0].isSuccess, res[0].message);
        System.assertEquals(0, res[0].tasksCompleted);
        System.assert(!res[0].message.contains('task'), res[0].message);
        System.assertEquals(false, res[1].isSuccess);
        System.assert(res[1].message.startsWith('Objective not found'));
    }
}
