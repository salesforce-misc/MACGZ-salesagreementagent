/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Shared test data for the Sales Agreement Agent tests: accounts, standard
 * pricebook entries, opportunities, and Draft sales agreements with product
 * lines and monthly schedules. Uses only standard fields.
 */
@IsTest
public class SaaTestDataFactory {

    public static Account makeAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    public static PricebookEntry makeStandardPbe(String productName, Decimal price) {
        Product2 p = new Product2(Name = productName, IsActive = true);
        insert p;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(), Product2Id = p.Id,
            UnitPrice = price, IsActive = true
        );
        insert pbe;
        return pbe;
    }

    public static Opportunity makeOpportunity(Id accountId, String name) {
        Opportunity o = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(1),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert o;
        return o;
    }

    /** Draft agreement for the account starting on the given date, no product lines. */
    public static SalesAgreement makeSalesAgreement(Account a, String name, Date startDate) {
        SalesAgreement sa = new SalesAgreement(
            Name = name,
            AccountId = a.Id,
            PricebookId = Test.getStandardPricebookId(),
            StartDate = startDate,
            EndDate = startDate.addMonths(12).addDays(-1),
            ScheduleFrequency = 'Monthly',
            ScheduleCount = 12,
            AgreementType = 'Volume',
            ProductLevel = 'Product',
            Status = 'Draft'
        );
        insert sa;
        return sa;
    }

    public static SalesAgreement makeSalesAgreement(Account a, String name) {
        return makeSalesAgreement(a, name, Date.today().toStartOfMonth());
    }

    /**
     * Adds one product line per price, each with its own pricebook entry, and
     * makes sure every line has monthly schedules (Manufacturing Cloud normally
     * generates them; they are created here if it didn't).
     */
    public static List<SalesAgreementProduct> addProducts(SalesAgreement sa, List<Decimal> prices) {
        List<SalesAgreementProduct> saps = new List<SalesAgreementProduct>();
        Integer i = 0;
        for (Decimal price : prices) {
            i++;
            PricebookEntry pbe = makeStandardPbe('Saa Test Product ' + i, price);
            saps.add(new SalesAgreementProduct(
                SalesAgreementId = sa.Id, Name = 'Saa Test Product ' + i,
                DisplayName = 'Saa Test Product ' + i, PricebookEntryId = pbe.Id,
                InitialPlannedQuantity = 12, SalesPrice = price
            ));
        }
        insert saps;

        Set<Id> withSchedules = new Set<Id>();
        for (SalesAgreementProductSchedule s : [
            SELECT SalesAgreementProductId FROM SalesAgreementProductSchedule
            WHERE SalesAgreementProduct.SalesAgreementId = :sa.Id
        ]) {
            withSchedules.add(s.SalesAgreementProductId);
        }
        SalesAgreement header = [SELECT StartDate FROM SalesAgreement WHERE Id = :sa.Id];
        List<SalesAgreementProductSchedule> missing = new List<SalesAgreementProductSchedule>();
        for (SalesAgreementProduct sap : saps) {
            if (withSchedules.contains(sap.Id)) { continue; }
            for (Integer m = 0; m < 12; m++) {
                Date s = header.StartDate.addMonths(m);
                missing.add(new SalesAgreementProductSchedule(
                    Name = 'Period ' + (m + 1), SalesAgreementProductId = sap.Id,
                    StartDate = s, EndDate = s.addMonths(1).addDays(-1),
                    PlannedQuantity = 1, SalesPrice = sap.SalesPrice
                ));
            }
        }
        if (!missing.isEmpty()) { insert missing; }
        return saps;
    }
}
