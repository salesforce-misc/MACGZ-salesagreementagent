/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Sales Agreement Agent — create next period's Sales Agreement by cloning the
 * customer's current agreement forward.
 *
 * Wire with: target: "apex://SaaCloneSalesAgreement"
 *
 * Copies the source agreement's shape (record type, schedule, agreement and
 * product level, price book) plus any extra fields listed in Clone Carry Fields
 * on the Sales Agreement Agent Setting, and copies the product lines. Prices
 * carry over unchanged; the user applies the new increase afterward. The start
 * date follows the configured Start Date Rule, and the name rolls the source's
 * year forward (e.g. "Acme 2026" -> "Acme 2027").
 *
 * This is a plain field-copy clone. It does not set RenewedFromAgreementId,
 * because that triggers Manufacturing Cloud renewal validation (renew only
 * within 60 days of the end date), which would block an early clone.
 *
 * Runs in the logged-in user's context (USER_MODE) and fails closed.
 */
public with sharing class SaaCloneSalesAgreement {

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id', 'Name', 'AccountId', 'ScheduleFrequency', 'ScheduleCount',
        'AgreementType', 'ProductLevel', 'StartDate', 'PricebookId'
    };

    @InvocableMethod(
        label='SAA Clone Sales Agreement'
        description='Clones a Sales Agreement forward into a new one for the next period, copying its product lines at current prices and any configured carry-forward fields.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        SaaSettings settings = SaaSettings.get();
        List<String> carryFields = carryFields(settings);

        Map<Id, SalesAgreement> sourceById;
        Map<Id, List<SalesAgreementProduct>> productsBySa = new Map<Id, List<SalesAgreementProduct>>();
        try {
            Set<Id> sourceIds = new Set<Id>();
            for (Request req : requests) {
                if (String.isNotBlank(req.sourceSalesAgreementId)) { sourceIds.add((Id) req.sourceSalesAgreementId); }
            }
            List<String> fields = new List<String>(BASE_FIELDS);
            if (SaaSettings.hasRecordTypes(SalesAgreement.SObjectType)) { fields.add('RecordTypeId'); }
            fields.addAll(carryFields);
            sourceById = new Map<Id, SalesAgreement>((List<SalesAgreement>) Database.queryWithBinds(
                'SELECT ' + String.join(fields, ', ') + ' FROM SalesAgreement WHERE Id IN :sourceIds',
                new Map<String, Object>{ 'sourceIds' => sourceIds }, AccessLevel.USER_MODE));

            for (SalesAgreementProduct sap : [
                SELECT Id, SalesAgreementId, Name, DisplayName, PricebookEntryId, ProductCategoryId,
                       InitialPlannedQuantity, InitialPlannedQtyValue, InitialPlannedAmount,
                       SalesPrice, IsQuantityInDecimals
                FROM SalesAgreementProduct
                WHERE SalesAgreementId IN :sourceIds
                WITH USER_MODE
            ]) {
                if (!productsBySa.containsKey(sap.SalesAgreementId)) {
                    productsBySa.put(sap.SalesAgreementId, new List<SalesAgreementProduct>());
                }
                productsBySa.get(sap.SalesAgreementId).add(sap);
            }
        } catch (Exception e) {
            for (Request req : requests) {
                results.add(failure('Error preparing the clone: ' + e.getMessage()));
            }
            return results;
        }

        List<SalesAgreement> toInsert = new List<SalesAgreement>();
        List<Result> pending = new List<Result>();
        List<Id> pendingSourceIds = new List<Id>();

        for (Request req : requests) {
            SalesAgreement src = String.isNotBlank(req.sourceSalesAgreementId)
                ? sourceById.get((Id) req.sourceSalesAgreementId) : null;
            if (src == null) {
                results.add(failure('Source sales agreement not found or not accessible: ' + req.sourceSalesAgreementId));
                continue;
            }

            Date startDate = settings.startDate(req.startDate);
            Integer periods = src.ScheduleCount != null ? src.ScheduleCount : settings.scheduleCount;
            String frequency = String.isNotBlank(src.ScheduleFrequency) ? src.ScheduleFrequency : settings.scheduleFrequency;

            SalesAgreement clone = new SalesAgreement();
            clone.Name = String.isNotBlank(req.agreementName)
                ? req.agreementName.left(255)
                : rollName(src, startDate).left(255);
            clone.AccountId = src.AccountId;
            for (String f : carryFields) { clone.put(f, src.get(f)); }
            if (src.getPopulatedFieldsAsMap().containsKey('RecordTypeId') && src.get('RecordTypeId') != null) {
                clone.put('RecordTypeId', src.get('RecordTypeId'));
            }
            clone.StartDate = startDate;
            clone.EndDate = SaaSettings.endDate(startDate, frequency, periods);
            clone.ScheduleFrequency = frequency;
            clone.ScheduleCount = periods;
            clone.AgreementType = String.isNotBlank(src.AgreementType) ? src.AgreementType : settings.agreementType;
            clone.ProductLevel = String.isNotBlank(src.ProductLevel) ? src.ProductLevel : 'Product';
            clone.Status = 'Draft';
            if (src.PricebookId != null) { clone.PricebookId = src.PricebookId; }

            Result r = new Result();
            r.isSuccess = true;
            toInsert.add(clone);
            pending.add(r);
            pendingSourceIds.add(src.Id);
            results.add(r);
        }

        if (toInsert.isEmpty()) { return results; }

        List<Database.SaveResult> saSrs = Database.insert(toInsert, false, AccessLevel.USER_MODE);

        // Manufacturing Cloud allows one SalesAgreementProduct per pricebook entry,
        // so source lines that share an entry are merged into one line.
        List<SalesAgreementProduct> newProducts = new List<SalesAgreementProduct>();
        List<Id> productSaIds = new List<Id>();
        for (Integer i = 0; i < saSrs.size(); i++) {
            Result r = pending.get(i);
            Database.SaveResult sr = saSrs.get(i);
            if (!sr.isSuccess()) {
                r.isSuccess = false;
                r.message = 'Could not clone the sales agreement: '
                    + (sr.getErrors().isEmpty() ? 'unknown error' : sr.getErrors()[0].getMessage());
                continue;
            }
            r.salesAgreementId = sr.getId();
            r.salesAgreementName = toInsert.get(i).Name;

            List<SalesAgreementProduct> srcLines = productsBySa.get(pendingSourceIds.get(i));
            if (srcLines == null) { continue; }
            Map<Id, SalesAgreementProduct> byPbe = new Map<Id, SalesAgreementProduct>();
            for (SalesAgreementProduct srcSap : srcLines) {
                if (srcSap.PricebookEntryId == null) { continue; }
                SalesAgreementProduct sap = byPbe.get(srcSap.PricebookEntryId);
                if (sap == null) {
                    sap = new SalesAgreementProduct(
                        SalesAgreementId = sr.getId(),
                        Name = srcSap.Name,
                        DisplayName = srcSap.DisplayName,
                        PricebookEntryId = srcSap.PricebookEntryId,
                        ProductCategoryId = srcSap.ProductCategoryId,
                        SalesPrice = srcSap.SalesPrice,
                        IsQuantityInDecimals = srcSap.IsQuantityInDecimals,
                        InitialPlannedQuantity = 0,
                        InitialPlannedQtyValue = 0,
                        InitialPlannedAmount = 0
                    );
                    byPbe.put(srcSap.PricebookEntryId, sap);
                }
                if (srcSap.InitialPlannedQuantity != null) { sap.InitialPlannedQuantity += srcSap.InitialPlannedQuantity; }
                if (srcSap.InitialPlannedQtyValue != null) { sap.InitialPlannedQtyValue += srcSap.InitialPlannedQtyValue; }
                if (srcSap.InitialPlannedAmount != null) { sap.InitialPlannedAmount += srcSap.InitialPlannedAmount; }
            }
            for (SalesAgreementProduct sap : byPbe.values()) {
                newProducts.add(sap);
                productSaIds.add(sr.getId());
            }
        }

        Map<Id, Integer> productCountBySa = new Map<Id, Integer>();
        if (!newProducts.isEmpty()) {
            List<Database.SaveResult> pSrs = Database.insert(newProducts, false, AccessLevel.USER_MODE);
            for (Integer j = 0; j < pSrs.size(); j++) {
                if (!pSrs.get(j).isSuccess()) { continue; }
                Id saId = productSaIds.get(j);
                productCountBySa.put(saId, (productCountBySa.containsKey(saId) ? productCountBySa.get(saId) : 0) + 1);
            }
        }

        for (Result r : pending) {
            if (!r.isSuccess) { continue; }
            Id saId = r.salesAgreementId;
            Integer cnt = productCountBySa.containsKey(saId) ? productCountBySa.get(saId) : 0;
            r.productCount = cnt;
            r.message = 'Cloned into "' + r.salesAgreementName + '" with ' + cnt
                + ' product line(s) carried forward at the current prices. Apply the new price increase before sharing the price list.';
        }
        return results;
    }

    /** Configured carry-forward fields that exist, are createable, and aren't already copied. */
    @TestVisible
    private static List<String> carryFields(SaaSettings settings) {
        Set<String> skip = new Set<String>();
        for (String f : BASE_FIELDS) { skip.add(f.toLowerCase()); }
        skip.addAll(new Set<String>{ 'recordtypeid', 'enddate', 'status', 'renewedfromagreementid', 'renewedtoagreementid', 'clonedfromagreementid' });
        List<String> out = new List<String>();
        for (String f : settings.cloneCarryFields) {
            Schema.DescribeFieldResult d = SaaSettings.describeField(SalesAgreement.SObjectType, f);
            if (d == null || !d.isCreateable() || skip.contains(d.getName().toLowerCase())) { continue; }
            skip.add(d.getName().toLowerCase());
            out.add(d.getName());
        }
        return out;
    }

    /** Replaces the source's start year in its name with the new year, or appends the new year. */
    @TestVisible
    private static String rollName(SalesAgreement src, Date newStart) {
        String name = src.Name == null ? '' : src.Name;
        String newYear = String.valueOf(newStart.year());
        if (src.StartDate != null && name.contains(String.valueOf(src.StartDate.year()))) {
            return name.replace(String.valueOf(src.StartDate.year()), newYear);
        }
        return String.isBlank(name) ? newYear : name + ' ' + newYear;
    }

    private static Result failure(String message) {
        Result r = new Result();
        r.isSuccess = false;
        r.message = message;
        return r;
    }

    public class Request {
        @InvocableVariable(
            label='Source Sales Agreement Id'
            description='Id of the current sales agreement to clone forward.'
            required=true
        )
        public String sourceSalesAgreementId;

        @InvocableVariable(
            label='Agreement Name'
            description='Optional name for the new agreement (defaults to the source name with its year rolled forward).'
            required=false
        )
        public String agreementName;

        @InvocableVariable(
            label='Start Date'
            description='Optional start date (defaults to the Start Date Rule in the Sales Agreement Agent Setting).'
            required=false
        )
        public Date startDate;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the clone was created.')
        public Boolean isSuccess;

        @InvocableVariable(label='Sales Agreement Id' description='Id of the newly cloned sales agreement.')
        public String salesAgreementId;

        @InvocableVariable(label='Sales Agreement Name' description='Name of the newly cloned sales agreement.')
        public String salesAgreementName;

        @InvocableVariable(label='Product Count' description='Number of product lines carried forward.')
        public Integer productCount;

        @InvocableVariable(label='Message' description='Human-readable result for the agent to relay.')
        public String message;
    }
}
