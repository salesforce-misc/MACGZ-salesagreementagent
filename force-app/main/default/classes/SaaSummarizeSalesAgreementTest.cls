/**
 * Tests for SaaSummarizeSalesAgreement: guards, not found, an agreement with no
 * products, and planned-vs-actual deviations across products.
 */
@IsTest
private class SaaSummarizeSalesAgreementTest {

    private static SaaSummarizeSalesAgreement.Result run(String salesAgreementId) {
        SaaSummarizeSalesAgreement.Request req = new SaaSummarizeSalesAgreement.Request();
        req.salesAgreementId = salesAgreementId;
        return SaaSummarizeSalesAgreement.execute(new List<SaaSummarizeSalesAgreement.Request>{ req })[0];
    }

    @IsTest
    static void summarize_reportsDeviations() {
        Account a = SaaTestDataFactory.makeAccount('Saa Summary Account');
        SalesAgreement sa = SaaTestDataFactory.makeSalesAgreement(a, 'Saa Summary SA');
        List<SalesAgreementProduct> saps = SaaTestDataFactory.addProducts(sa, new List<Decimal>{ 1000, 2000, 3000 });

        // A Draft agreement has no actuals (Manufacturing Cloud blocks editing
        // ActualQuantity until activation), so deviations come from planned
        // quantity: product 1 far from plan, product 2 slightly, product 3 on plan.
        List<SalesAgreementProductSchedule> updates = new List<SalesAgreementProductSchedule>();
        for (SalesAgreementProductSchedule s : [
            SELECT Id, SalesAgreementProductId
            FROM SalesAgreementProductSchedule
            WHERE SalesAgreementProduct.SalesAgreementId = :sa.Id
        ]) {
            Integer planned = s.SalesAgreementProductId == saps[0].Id ? 5
                : (s.SalesAgreementProductId == saps[1].Id ? 1 : 0);
            updates.add(new SalesAgreementProductSchedule(Id = s.Id, PlannedQuantity = planned));
        }
        update updates;

        Test.startTest();
        SaaSummarizeSalesAgreement.Result r = run(sa.Id);
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals(3, r.productCount);
        System.assertEquals(-100, r.overallDeviationPct);
        System.assert(r.totalPlannedQuantity > 0);
        System.assert(r.summary.contains('Saa Summary SA'), r.summary);
        System.assert(r.summary.contains('Saa Summary Account'), r.summary);
        System.assert(r.summary.contains('Largest deviations'), r.summary);
        System.assert(r.summary.contains('Saa Test Product 1'), r.summary);
        System.assert(r.summary.contains('Saa Test Product 2'), r.summary);
        System.assert(!r.summary.contains('Saa Test Product 3'), 'on-plan product is not a deviation: ' + r.summary);
        System.assertEquals(r.summary, r.message);
    }

    @IsTest
    static void summarize_noProducts() {
        Account a = SaaTestDataFactory.makeAccount('Saa Summary Account');
        SalesAgreement sa = SaaTestDataFactory.makeSalesAgreement(a, 'Saa Empty Summary SA');

        Test.startTest();
        SaaSummarizeSalesAgreement.Result r = run(sa.Id);
        Test.stopTest();

        System.assert(r.isSuccess, r.message);
        System.assertEquals(0, r.productCount);
        System.assertEquals(0, r.overallDeviationPct);
        System.assert(!r.summary.contains('Largest deviations'), r.summary);
    }

    @IsTest
    static void summarize_guards() {
        Account a = SaaTestDataFactory.makeAccount('Saa Summary Account');

        Test.startTest();
        SaaSummarizeSalesAgreement.Result noId = run(null);
        SaaSummarizeSalesAgreement.Result notFound = run(a.Id);
        SaaSummarizeSalesAgreement.Result bad = run('not-an-id');
        Test.stopTest();

        System.assertEquals(false, noId.isSuccess);
        System.assert(noId.message.contains('required'));
        System.assertEquals(false, notFound.isSuccess);
        System.assert(notFound.message.startsWith('Sales agreement not found'));
        System.assertEquals(false, bad.isSuccess);
        System.assert(bad.message.startsWith('Could not summarize'), bad.message);
    }
}
