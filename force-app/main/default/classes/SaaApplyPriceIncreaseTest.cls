/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Tests for SaaApplyPriceIncrease: input guards, empty agreement,
 * preview (no commit), and commit for Increase / Decrease / Replace in both
 * percentage and absolute modes.
 */
@IsTest
private class SaaApplyPriceIncreaseTest {

    @TestSetup
    static void setup() {
        Account a = SaaTestDataFactory.makeAccount('Saa Increase Account');
        SalesAgreement sa = SaaTestDataFactory.makeSalesAgreement(a, 'Saa Increase SA');
        SaaTestDataFactory.addProducts(sa, new List<Decimal>{ 1000, 2000 });
        SaaTestDataFactory.makeSalesAgreement(a, 'Saa Empty SA');
    }

    private static Id saId(String name) {
        return [SELECT Id FROM SalesAgreement WHERE Name = :name LIMIT 1].Id;
    }

    private static SaaApplyPriceIncrease.Result run(
        String salesAgreementId, Double pct, Boolean preview, String operation, String valueType
    ) {
        SaaApplyPriceIncrease.Request req = new SaaApplyPriceIncrease.Request();
        req.salesAgreementId = salesAgreementId;
        req.percentage = pct;
        req.preview = preview;
        req.operation = operation;
        req.numericValueType = valueType;
        return SaaApplyPriceIncrease.execute(new List<SaaApplyPriceIncrease.Request>{ req })[0];
    }

    private static Map<Id, Decimal> pricesBySchedule(Id agreementId) {
        Map<Id, Decimal> m = new Map<Id, Decimal>();
        for (SalesAgreementProductSchedule s : [
            SELECT Id, SalesPrice FROM SalesAgreementProductSchedule
            WHERE SalesAgreementProduct.SalesAgreementId = :agreementId
        ]) {
            m.put(s.Id, s.SalesPrice == null ? 0 : s.SalesPrice);
        }
        return m;
    }

    @IsTest
    static void guards_rejectMissingInputs() {
        Test.startTest();
        SaaApplyPriceIncrease.Result noId = run(null, 4, true, null, null);
        SaaApplyPriceIncrease.Result noPct = run(saId('Saa Increase SA'), null, true, null, null);
        SaaApplyPriceIncrease.Result negPct = run(saId('Saa Increase SA'), -1, true, null, null);
        SaaApplyPriceIncrease.Result empty = run(saId('Saa Empty SA'), 4, true, null, null);
        SaaApplyPriceIncrease.Result bad = run('not-an-id', 4, true, null, null);
        Test.stopTest();

        System.assertEquals(false, noId.isSuccess);
        System.assert(noId.message.contains('sales agreement id is required'));
        System.assertEquals(false, noPct.isSuccess);
        System.assertEquals(false, negPct.isSuccess);
        System.assert(negPct.message.contains('percentage'));
        System.assertEquals(false, empty.isSuccess);
        System.assert(empty.message.contains('No product schedules'));
        System.assertEquals(false, bad.isSuccess);
        System.assert(bad.message.startsWith('Error applying the price increase'), bad.message);
    }

    @IsTest
    static void preview_reportsScopeWithoutCommitting() {
        Id sa = saId('Saa Increase SA');
        Map<Id, Decimal> before = pricesBySchedule(sa);

        Test.startTest();
        SaaApplyPriceIncrease.Result r = run(sa, 4, true, null, null);
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals(false, r.committed);
        System.assertEquals(2, r.productCount);
        System.assert(r.periodCount > 0);
        System.assert(r.message.startsWith('Preview'), r.message);
        System.assertEquals(before, pricesBySchedule(sa), 'preview must not change prices');
    }

    @IsTest
    static void commit_increaseByPercent() {
        Id sa = saId('Saa Increase SA');
        Map<Id, Decimal> before = pricesBySchedule(sa);

        Test.startTest();
        SaaApplyPriceIncrease.Result r = run(sa, 4, false, null, null);
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals(true, r.committed);
        Map<Id, Decimal> after = pricesBySchedule(sa);
        for (Id sid : before.keySet()) {
            System.assertEquals((before.get(sid) * 1.04).setScale(2), after.get(sid));
        }
    }

    @IsTest
    static void commit_decreaseAbsolute_floorsAtZero() {
        Id sa = saId('Saa Increase SA');

        Test.startTest();
        SaaApplyPriceIncrease.Result r = run(sa, 5000, false, 'Decrease By', 'absolute');
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assert(!r.message.contains('%'), r.message);
        for (Decimal p : pricesBySchedule(sa).values()) {
            System.assertEquals(0, p, 'price must not go below zero');
        }
    }

    @IsTest
    static void commit_decreaseByPercent_andReplace() {
        Id sa = saId('Saa Increase SA');
        Map<Id, Decimal> before = pricesBySchedule(sa);

        Test.startTest();
        SaaApplyPriceIncrease.Result dec = run(sa, 10, false, 'Decrease By', null);
        Map<Id, Decimal> afterDec = pricesBySchedule(sa);
        SaaApplyPriceIncrease.Result rep = run(sa, 1500, false, 'Replace With', 'absolute');
        SaaApplyPriceIncrease.Result inc = run(sa, 50, false, 'Increase By', 'absolute');
        Test.stopTest();

        System.assert(dec.isSuccess, dec.message);
        for (Id sid : before.keySet()) {
            System.assertEquals((before.get(sid) * 0.9).setScale(2), afterDec.get(sid));
        }
        System.assert(rep.isSuccess, rep.message);
        System.assert(inc.isSuccess, inc.message);
        for (Decimal p : pricesBySchedule(sa).values()) {
            System.assertEquals(1550, p);
        }
    }
}
