/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Sales Agreement Agent — apply the approved percentage increase
 * across all products on a Sales Agreement.
 *
 * Wire with: target: "apex://SaaApplyPriceIncrease"
 *
 * Thin wrapper over the standard Manufacturing Cloud "Sales Agreement Mass
 * Update" invocable action (massUpdateSalesAgreement). The AE just supplies the
 * agreement and the percentage; this class resolves ALL of the agreement's
 * product schedule IDs and periods so the update applies across every product,
 * then invokes the standard action. Supports a preview mode that reports the
 * scope (products / periods) without committing.
 *
 * Runs in the AE's context; the standard action performs the update
 * asynchronously.
 */
public with sharing class SaaApplyPriceIncrease {

    @InvocableMethod(
        label='SAA Apply Price Increase'
        description='Applies an approved percentage price increase across all products on a Sales Agreement. Use preview=true first to see the scope, then preview=false to commit.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            try {
                if (String.isBlank(req.salesAgreementId)) {
                    r.isSuccess = false;
                    r.message = 'A sales agreement id is required.';
                    results.add(r);
                    continue;
                }
                if (req.percentage == null || req.percentage < 0) {
                    r.isSuccess = false;
                    r.message = 'A percentage value (0 or greater) is required.';
                    results.add(r);
                    continue;
                }
                Id saId = (Id) req.salesAgreementId;

                // Load all of this agreement's product schedules (SalesPrice is
                // the field the approved percentage adjusts).
                List<SalesAgreementProductSchedule> schedules = [
                    SELECT Id, SalesAgreementProductId, StartDate, SalesPrice
                    FROM SalesAgreementProductSchedule
                    WHERE SalesAgreementProduct.SalesAgreementId = :saId
                    WITH USER_MODE
                    LIMIT 5000
                ];

                Set<Id> productIds = new Set<Id>();
                Set<Date> periodSet = new Set<Date>();
                for (SalesAgreementProductSchedule s : schedules) {
                    if (s.SalesAgreementProductId != null) { productIds.add(s.SalesAgreementProductId); }
                    if (s.StartDate != null) { periodSet.add(s.StartDate); }
                }

                if (schedules.isEmpty()) {
                    r.isSuccess = false;
                    r.message = 'No product schedules were found on this agreement to update.';
                    results.add(r);
                    continue;
                }

                r.productCount = productIds.size();
                r.periodCount = periodSet.size();

                String operation = String.isNotBlank(req.operation) ? req.operation : 'Increase By';
                String valueType = String.isNotBlank(req.numericValueType) ? req.numericValueType : 'percentage';
                Boolean isPct = valueType != 'absolute';

                if (req.preview == true) {
                    r.isSuccess = true;
                    r.committed = false;
                    r.message = 'Preview: this will ' + operation + ' the sales price by '
                        + req.percentage + (isPct ? '%' : '')
                        + ' across ' + productIds.size() + ' product(s) over '
                        + periodSet.size() + ' period(s). Confirm to apply.';
                    results.add(r);
                    continue;
                }

                // COMMIT: compute the new SalesPrice per schedule and update.
                // (The standard massUpdateSalesAgreement action is a Manufacturing
                // Cloud industry action that is not Apex-invocable; its only effect
                // on these schedules is updating SalesPrice, so we apply it directly.)
                Decimal value = Decimal.valueOf(String.valueOf(req.percentage));
                List<SalesAgreementProductSchedule> toUpdate = new List<SalesAgreementProductSchedule>();
                for (SalesAgreementProductSchedule s : schedules) {
                    Decimal current = s.SalesPrice == null ? 0 : s.SalesPrice;
                    Decimal updated = current;
                    if (operation == 'Replace With') {
                        updated = value;
                    } else if (operation == 'Decrease By') {
                        updated = isPct ? current - (current * value / 100) : current - value;
                    } else { // Increase By (default)
                        updated = isPct ? current + (current * value / 100) : current + value;
                    }
                    if (updated < 0) { updated = 0; }
                    // Build a minimal record (Id + SalesPrice only) so USER_MODE
                    // only checks update access on the field we actually change.
                    toUpdate.add(new SalesAgreementProductSchedule(
                        Id = s.Id,
                        SalesPrice = updated.setScale(2)
                    ));
                }

                List<Database.SaveResult> srs = Database.update(toUpdate, false, AccessLevel.USER_MODE);
                Integer updatedCount = 0;
                String firstErr = null;
                for (Database.SaveResult sr : srs) {
                    if (sr.isSuccess()) {
                        updatedCount++;
                    } else if (firstErr == null && !sr.getErrors().isEmpty()) {
                        firstErr = sr.getErrors()[0].getMessage();
                    }
                }

                if (updatedCount > 0) {
                    r.isSuccess = true;
                    r.committed = true;
                    r.message = 'Applied a ' + req.percentage + (isPct ? '%' : '') + ' '
                        + operation + ' to the sales price across ' + productIds.size()
                        + ' product(s) over ' + periodSet.size() + ' period(s) ('
                        + updatedCount + ' schedule rows updated).';
                } else {
                    r.isSuccess = false;
                    r.committed = false;
                    r.message = 'The price update could not be applied: '
                        + (firstErr != null ? firstErr : 'no rows were updated') + '.';
                }
            } catch (Exception e) {
                r.isSuccess = false;
                r.message = 'Error applying the price increase: ' + e.getMessage();
            }
            results.add(r);
        }
        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Sales Agreement Id'
            description='Id of the sales agreement to update.'
            required=true
        )
        public String salesAgreementId;

        @InvocableVariable(
            label='Percentage'
            description='The percentage to apply (e.g. 4 for a 4% increase).'
            required=true
        )
        public Double percentage;

        @InvocableVariable(
            label='Preview'
            description='If true, report the scope without committing. If false, apply the update.'
            required=false
        )
        public Boolean preview;

        @InvocableVariable(
            label='Operation'
            description='Increase By, Decrease By, or Replace With. Defaults to Increase By.'
            required=false
        )
        public String operation;

        @InvocableVariable(
            label='Field To Update'
            description='Product schedule field to update. Defaults to SalesPrice.'
            required=false
        )
        public String fieldToUpdate;

        @InvocableVariable(
            label='Numeric Value Type'
            description='percentage or absolute. Defaults to percentage.'
            required=false
        )
        public String numericValueType;

        @InvocableVariable(
            label='Adjustment Note'
            description='Optional note explaining the adjustment.'
            required=false
        )
        public String adjustmentNote;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the operation succeeded.')
        public Boolean isSuccess;

        @InvocableVariable(label='Committed' description='True if the update was applied; false for preview.')
        public Boolean committed;

        @InvocableVariable(label='Product Count' description='Number of products in scope.')
        public Integer productCount;

        @InvocableVariable(label='Period Count' description='Number of periods in scope.')
        public Integer periodCount;

        @InvocableVariable(label='Message' description='Human-readable result for the agent to relay.')
        public String message;
    }
}
