/**
 * Tests for the Sales Agreement Agent create and clone actions and their
 * configuration: SaaSettings, SaaOpportunityEligibility,
 * SaaCheckOpportunityEligibility, SaaCreateSalesAgreementFromOpp and
 * SaaCloneSalesAgreement.
 *
 * Each test sets the settings it relies on, so the results don't depend on how
 * the Default setting record is configured in the org.
 */
@IsTest
private class SaaSalesAgreementActionsTest {

    private static SaaSettings openRule() {
        SaaSettings s = SaaSettings.get();
        s.opportunityRecordType = null;
        s.opportunityEligibilityField = null;
        s.agreementRecordType = null;
        s.agreementOpportunityField = null;
        s.startDateRule = SaaSettings.START_NEXT_YEAR;
        s.scheduleFrequency = 'Monthly';
        s.scheduleCount = 12;
        s.agreementType = 'Volume';
        s.agreementNamePrefix = 'Sales Agreement';
        s.cloneCarryFields = new List<String>();
        return s;
    }

    private static Opportunity queried(Id oppId) {
        return SaaOpportunityEligibility.queryOpportunities(new Set<Id>{ oppId }).get(oppId);
    }

    private static SaaCreateSalesAgreementFromOpp.Result create(SaaCreateSalesAgreementFromOpp.Request req) {
        return SaaCreateSalesAgreementFromOpp.execute(new List<SaaCreateSalesAgreementFromOpp.Request>{ req })[0];
    }

    private static SaaCreateSalesAgreementFromOpp.Request createReq(Id oppId) {
        SaaCreateSalesAgreementFromOpp.Request req = new SaaCreateSalesAgreementFromOpp.Request();
        req.opportunityId = oppId;
        return req;
    }

    private static Date nextJan1() {
        return Date.newInstance(Date.today().year() + 1, 1, 1);
    }

    // ── Settings ────────────────────────────────────────────────────────────

    @IsTest
    static void settings_defaultsWhenRecordMissing() {
        SaaSettings s = new SaaSettings(null);
        System.assertEquals(null, s.opportunityRecordType);
        System.assertEquals(null, s.opportunityEligibilityField);
        System.assertEquals(SaaSettings.START_NEXT_YEAR, s.startDateRule);
        System.assertEquals('Monthly', s.scheduleFrequency);
        System.assertEquals(12, s.scheduleCount);
        System.assertEquals('Volume', s.agreementType);
        System.assertEquals('Sales Agreement', s.agreementNamePrefix);
        System.assertEquals('Annual Pricing Work', s.objectiveName);
        System.assert(s.cloneCarryFields.isEmpty());
        System.assertEquals(null, s.agreementRecordTypeId());
    }

    @IsTest
    static void settings_readsRecordValues() {
        Sales_Agreement_Agent_Setting__mdt rec = (Sales_Agreement_Agent_Setting__mdt) JSON.deserialize(
            '{"Opportunity_Record_Type__c":" Big_Deal ","Opportunity_Eligibility_Field__c":"IsPrivate",'
            + '"Agreement_Record_Type__c":"No_Such_RT","Agreement_Opportunity_Field__c":"Opportunity__c",'
            + '"Start_Date_Rule__c":"Today","Schedule_Frequency__c":"Quarterly","Schedule_Count__c":4,'
            + '"Agreement_Type__c":"Revenue","Agreement_Name_Prefix__c":"Supply Deal",'
            + '"Clone_Carry_Fields__c":"Description, ContactId,,","Objective_Name__c":"FY Pricing"}',
            Sales_Agreement_Agent_Setting__mdt.class);
        SaaSettings s = new SaaSettings(rec);
        System.assertEquals('Big_Deal', s.opportunityRecordType);
        System.assertEquals('IsPrivate', s.opportunityEligibilityField);
        System.assertEquals('Opportunity__c', s.agreementOpportunityField);
        System.assertEquals('Quarterly', s.scheduleFrequency);
        System.assertEquals(4, s.scheduleCount);
        System.assertEquals('Revenue', s.agreementType);
        System.assertEquals('Supply Deal', s.agreementNamePrefix);
        System.assertEquals('FY Pricing', s.objectiveName);
        System.assertEquals(new List<String>{ 'Description', 'ContactId' }, s.cloneCarryFields);
        System.assertEquals(null, s.agreementRecordTypeId(), 'unknown record type resolves to null');
        System.assertEquals(Date.today(), s.startDate(null));
    }

    @IsTest
    static void settings_startAndEndDates() {
        SaaSettings s = new SaaSettings(null);
        Date explicitDate = Date.newInstance(2030, 5, 1);
        System.assertEquals(explicitDate, s.startDate(explicitDate));
        System.assertEquals(nextJan1(), s.startDate(null));
        s.startDateRule = SaaSettings.START_NEXT_MONTH;
        System.assertEquals(Date.today().toStartOfMonth().addMonths(1), s.startDate(null));

        Date start = Date.newInstance(2030, 1, 1);
        System.assertEquals(Date.newInstance(2030, 12, 31), SaaSettings.endDate(start, 'Monthly', 12));
        System.assertEquals(Date.newInstance(2030, 12, 31), SaaSettings.endDate(start, 'Quarterly', 4));
        System.assertEquals(Date.newInstance(2031, 12, 31), SaaSettings.endDate(start, 'Yearly', 2));

        System.assertEquals(SaaSettings.get(), SaaSettings.get(), 'settings are cached');
        SaaSettings.reset();
        System.assertNotEquals(null, SaaSettings.get());
        System.assertEquals(null, SaaSettings.describeField(Opportunity.SObjectType, 'Not_A_Field__c'));
        System.assertEquals(null, SaaSettings.describeField(Opportunity.SObjectType, null));
    }

    // ── Eligibility ─────────────────────────────────────────────────────────

    @IsTest
    static void eligibility_openRuleAcceptsAnyOpportunity() {
        openRule();
        Account a = SaaTestDataFactory.makeAccount('Saa Eligibility Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Open Opp');

        SaaOpportunityEligibility.EligibilityResult r = SaaOpportunityEligibility.evaluate(queried(o.Id));
        System.assert(r.isEligible, r.message);
        System.assert(r.recordTypeOk && r.criteriaFieldOk);

        SaaOpportunityEligibility.EligibilityResult none = SaaOpportunityEligibility.evaluate(null);
        System.assert(!none.isEligible);
    }

    @IsTest
    static void eligibility_checkboxRule() {
        SaaSettings s = openRule();
        s.opportunityEligibilityField = 'IsPrivate';
        Account a = SaaTestDataFactory.makeAccount('Saa Eligibility Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Unchecked Opp');

        SaaOpportunityEligibility.EligibilityResult r = SaaOpportunityEligibility.evaluate(queried(o.Id));
        System.assert(!r.isEligible, r.message);
        System.assert(!r.criteriaFieldOk);
        System.assert(r.message.contains('is not checked'), r.message);
    }

    @IsTest
    static void eligibility_misconfiguredSettingsFailClosed() {
        SaaSettings s = openRule();
        s.opportunityEligibilityField = 'Name';
        s.opportunityRecordType = 'No_Such_Record_Type_Saa';
        Account a = SaaTestDataFactory.makeAccount('Saa Eligibility Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Misconfigured Opp');

        SaaOpportunityEligibility.EligibilityResult r = SaaOpportunityEligibility.evaluate(queried(o.Id));
        System.assert(!r.isEligible);
        System.assert(r.message.contains('No_Such_Record_Type_Saa'), r.message);
        System.assert(r.message.contains('is not a checkbox'), r.message);
    }

    @IsTest
    static void eligibility_recordTypeRule() {
        List<RecordType> rts = [
            SELECT DeveloperName FROM RecordType
            WHERE SobjectType = 'Opportunity' AND IsActive = true LIMIT 2
        ];
        if (rts.size() < 2) { return; }
        SaaSettings s = openRule();
        Account a = SaaTestDataFactory.makeAccount('Saa Eligibility Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa RT Opp');

        s.opportunityRecordType = rts[0].DeveloperName;
        Boolean first = SaaOpportunityEligibility.evaluate(queried(o.Id)).isEligible;
        s.opportunityRecordType = rts[1].DeveloperName;
        Boolean second = SaaOpportunityEligibility.evaluate(queried(o.Id)).isEligible;
        System.assert(!(first && second), 'an opportunity has only one record type');
    }

    @IsTest
    static void checkEligibility_action() {
        SaaSettings s = openRule();
        s.opportunityEligibilityField = 'IsPrivate';
        Account a = SaaTestDataFactory.makeAccount('Saa Check Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Check Opp');

        SaaCheckOpportunityEligibility.Request good = new SaaCheckOpportunityEligibility.Request();
        good.opportunityId = o.Id;
        SaaCheckOpportunityEligibility.Request blank = new SaaCheckOpportunityEligibility.Request();

        Test.startTest();
        List<SaaCheckOpportunityEligibility.Result> res = SaaCheckOpportunityEligibility.execute(
            new List<SaaCheckOpportunityEligibility.Request>{ good, blank });
        SaaCheckOpportunityEligibility.Request bad = new SaaCheckOpportunityEligibility.Request();
        bad.opportunityId = 'not-an-id';
        List<SaaCheckOpportunityEligibility.Result> badRes = SaaCheckOpportunityEligibility.execute(
            new List<SaaCheckOpportunityEligibility.Request>{ bad });
        Test.stopTest();

        System.assert(!res[0].isEligible);
        System.assert(res[0].recordTypeOk);
        System.assert(!res[0].criteriaFieldOk);
        System.assert(res[1].message.startsWith('Opportunity not found'), res[1].message);
        System.assert(badRes[0].message.startsWith('Error checking eligibility'), badRes[0].message);
    }

    // ── Create from opportunity ─────────────────────────────────────────────

    @IsTest
    static void create_withProducts_mergesSharedPricebookEntries() {
        SaaSettings s = openRule();
        s.agreementOpportunityField = 'Description';
        Account a = SaaTestDataFactory.makeAccount('Saa Create Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Create Opp');
        PricebookEntry shared = SaaTestDataFactory.makeStandardPbe('Saa Shared Product', 1000);
        PricebookEntry single = SaaTestDataFactory.makeStandardPbe('Saa Single Product', 500);
        insert new List<OpportunityLineItem>{
            new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = shared.Id, Quantity = 5, UnitPrice = 1000),
            new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = shared.Id, Quantity = 7, UnitPrice = 1100),
            new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = single.Id, Quantity = 3, UnitPrice = 500)
        };

        Test.startTest();
        SaaCreateSalesAgreementFromOpp.Result r = create(createReq(o.Id));
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals(2, r.productCount, r.message);
        System.assertEquals('Sales Agreement ' + nextJan1().year() + ' — Saa Create Opp', r.salesAgreementName);
        SalesAgreement sa = [
            SELECT StartDate, EndDate, ScheduleCount, ScheduleFrequency, Status, Description,
                   (SELECT PricebookEntryId, InitialPlannedQuantity, SalesPrice FROM SalesAgreementProducts)
            FROM SalesAgreement WHERE Id = :r.salesAgreementId
        ];
        System.assertEquals(nextJan1(), sa.StartDate);
        System.assertEquals(nextJan1().addMonths(12).addDays(-1), sa.EndDate);
        System.assertEquals(12, sa.ScheduleCount);
        System.assertEquals('Draft', sa.Status);
        System.assertEquals(String.valueOf(o.Id), sa.Description, 'opportunity link field is populated');
        for (SalesAgreementProduct sap : sa.SalesAgreementProducts) {
            if (sap.PricebookEntryId == shared.Id) {
                System.assertEquals(12, sap.InitialPlannedQuantity);
                System.assertEquals(1100, sap.SalesPrice);
            }
        }
    }

    @IsTest
    static void create_explicitValuesAndQuarterlySchedule() {
        SaaSettings s = openRule();
        s.startDateRule = SaaSettings.START_NEXT_MONTH;
        s.scheduleFrequency = 'Quarterly';
        s.scheduleCount = 4;
        s.agreementRecordType = 'No_Such_RT_Saa';
        Account a = SaaTestDataFactory.makeAccount('Saa Create Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Quarterly Opp');

        SaaCreateSalesAgreementFromOpp.Request req = createReq(o.Id);
        req.agreementName = 'Saa Named Agreement';
        Test.startTest();
        SaaCreateSalesAgreementFromOpp.Result r = create(req);
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals('Saa Named Agreement', r.salesAgreementName);
        System.assertEquals(0, r.productCount);
        SalesAgreement sa = [SELECT StartDate, EndDate, ScheduleFrequency, ScheduleCount FROM SalesAgreement WHERE Id = :r.salesAgreementId];
        Date start = Date.today().toStartOfMonth().addMonths(1);
        System.assertEquals(start, sa.StartDate);
        System.assertEquals('Quarterly', sa.ScheduleFrequency);
        System.assertEquals(4, sa.ScheduleCount);
        System.assertEquals(start.addMonths(12).addDays(-1), sa.EndDate);
    }

    @IsTest
    static void create_ineligibleOpportunity_failsClosed() {
        SaaSettings s = openRule();
        s.opportunityEligibilityField = 'IsPrivate';
        Account a = SaaTestDataFactory.makeAccount('Saa Create Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Ineligible Opp');

        Test.startTest();
        SaaCreateSalesAgreementFromOpp.Result r = create(createReq(o.Id));
        Test.stopTest();

        System.assertEquals(false, r.isSuccess);
        System.assertEquals(null, r.salesAgreementId);
        System.assert(r.message.contains('not eligible'), r.message);
        System.assertEquals(0, [SELECT COUNT() FROM SalesAgreement]);
    }

    @IsTest
    static void create_guards() {
        openRule();
        Opportunity noAccount = new Opportunity(
            Name = 'Saa No Account Opp', StageName = 'Prospecting', CloseDate = Date.today().addMonths(1)
        );
        insert noAccount;
        SaaCreateSalesAgreementFromOpp.Request blank = new SaaCreateSalesAgreementFromOpp.Request();

        Test.startTest();
        List<SaaCreateSalesAgreementFromOpp.Result> res = SaaCreateSalesAgreementFromOpp.execute(
            new List<SaaCreateSalesAgreementFromOpp.Request>{ blank, createReq(noAccount.Id) });
        SaaCreateSalesAgreementFromOpp.Result bad = create(createReq(null));
        SaaCreateSalesAgreementFromOpp.Request malformed = new SaaCreateSalesAgreementFromOpp.Request();
        malformed.opportunityId = 'not-an-id';
        SaaCreateSalesAgreementFromOpp.Result badId = create(malformed);
        Test.stopTest();

        System.assert(res[0].message.startsWith('Opportunity not found'), res[0].message);
        System.assert(res[1].message.contains('has no account'), res[1].message);
        System.assertEquals(false, bad.isSuccess);
        System.assert(badId.message.startsWith('Error preparing sales agreement'), badId.message);
        System.assertEquals(0, [SELECT COUNT() FROM SalesAgreement]);
    }

    @IsTest
    static void create_insertFailure_isReported() {
        SaaSettings s = openRule();
        s.scheduleCount = 5000;
        Account a = SaaTestDataFactory.makeAccount('Saa Create Account');
        Opportunity o = SaaTestDataFactory.makeOpportunity(a.Id, 'Saa Failing Opp');

        Test.startTest();
        SaaCreateSalesAgreementFromOpp.Result r = create(createReq(o.Id));
        Test.stopTest();

        if (r.isSuccess) {
            System.assertNotEquals(null, r.salesAgreementId);
        } else {
            System.assertEquals(null, r.salesAgreementId);
            System.assert(r.message.startsWith('Could not create the sales agreement'), r.message);
        }
    }

    // ── Clone ───────────────────────────────────────────────────────────────

    @IsTest
    static void clone_copiesLinesAndCarryFields() {
        SaaSettings s = openRule();
        s.cloneCarryFields = new List<String>{ 'Description', 'Name', 'Not_A_Field__c' };
        Account a = SaaTestDataFactory.makeAccount('Saa Clone Account');
        Integer year = Date.today().year();
        SalesAgreement src = SaaTestDataFactory.makeSalesAgreement(
            a, 'Saa Supply ' + year, Date.newInstance(year, 1, 1));
        src.Description = 'Carry me forward';
        update src;
        SaaTestDataFactory.addProducts(src, new List<Decimal>{ 1000, 2000 });

        SaaCloneSalesAgreement.Request req = new SaaCloneSalesAgreement.Request();
        req.sourceSalesAgreementId = src.Id;
        Test.startTest();
        SaaCloneSalesAgreement.Result r = SaaCloneSalesAgreement.execute(
            new List<SaaCloneSalesAgreement.Request>{ req })[0];
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals(2, r.productCount, r.message);
        System.assertEquals('Saa Supply ' + (year + 1), r.salesAgreementName);
        SalesAgreement cloned = [
            SELECT StartDate, Description, Status, AccountId FROM SalesAgreement WHERE Id = :r.salesAgreementId
        ];
        System.assertEquals(nextJan1(), cloned.StartDate);
        System.assertEquals('Carry me forward', cloned.Description);
        System.assertEquals('Draft', cloned.Status);
        System.assertEquals(a.Id, cloned.AccountId);
    }

    @IsTest
    static void clone_guards() {
        openRule();
        SaaCloneSalesAgreement.Request blank = new SaaCloneSalesAgreement.Request();
        SaaCloneSalesAgreement.Request malformed = new SaaCloneSalesAgreement.Request();
        malformed.sourceSalesAgreementId = 'not-an-id';

        Test.startTest();
        SaaCloneSalesAgreement.Result missing = SaaCloneSalesAgreement.execute(
            new List<SaaCloneSalesAgreement.Request>{ blank })[0];
        SaaCloneSalesAgreement.Result bad = SaaCloneSalesAgreement.execute(
            new List<SaaCloneSalesAgreement.Request>{ malformed })[0];
        Test.stopTest();

        System.assertEquals(false, missing.isSuccess);
        System.assert(missing.message.startsWith('Source sales agreement not found'), missing.message);
        System.assert(bad.message.startsWith('Error preparing the clone'), bad.message);
    }

    @IsTest
    static void clone_nameAndFieldHelpers() {
        SaaSettings s = openRule();
        SalesAgreement noYear = new SalesAgreement(Name = 'Acme Supply', StartDate = Date.newInstance(2026, 1, 1));
        System.assertEquals('Acme Supply 2027', SaaCloneSalesAgreement.rollName(noYear, Date.newInstance(2027, 1, 1)));
        SalesAgreement blankName = new SalesAgreement();
        System.assertEquals('2027', SaaCloneSalesAgreement.rollName(blankName, Date.newInstance(2027, 1, 1)));

        s.cloneCarryFields = new List<String>{ 'description', 'Description', 'StartDate', 'TotalAgreementAmount' };
        System.assertEquals(new List<String>{ 'Description' }, SaaCloneSalesAgreement.carryFields(s));
    }
}
