/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Sales Agreement Agent — Jobs 7/8 (summarize side): summarize a Sales
 * Agreement's performance, including planned-vs-actual quantity deviation across
 * its products.
 *
 * Wire with: target: "apex://SaaSummarizeSalesAgreement"
 *
 * Computes the summary directly from the agreement's product schedules
 * (PlannedQuantity vs ActualQuantity) so the agent gets clean, groundable values.
 * Highlights the products with the largest deviations.
 */
public with sharing class SaaSummarizeSalesAgreement {

    @InvocableMethod(
        label='SAA Summarize Sales Agreement'
        description='Summarizes sales agreement performance and planned-vs-actual deviations, highlighting the products needing attention.'
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
                Id saId = (Id) req.salesAgreementId;

                List<SalesAgreement> sas = [
                    SELECT Id, Name, Status, StartDate, EndDate, ScheduleFrequency,
                           ScheduleCount, TotalAgreementAmount, Account.Name
                    FROM SalesAgreement WHERE Id = :saId WITH USER_MODE LIMIT 1
                ];
                if (sas.isEmpty()) {
                    r.isSuccess = false;
                    r.message = 'Sales agreement not found or not accessible: ' + req.salesAgreementId;
                    results.add(r);
                    continue;
                }
                SalesAgreement sa = sas[0];

                // Aggregate planned/actual by product.
                Map<Id, Decimal> plannedByProduct = new Map<Id, Decimal>();
                Map<Id, Decimal> actualByProduct = new Map<Id, Decimal>();
                Map<Id, String> nameByProduct = new Map<Id, String>();
                Decimal totalPlanned = 0, totalActual = 0;

                for (AggregateResult ar : [
                    SELECT SalesAgreementProductId pid,
                           SUM(PlannedQuantity) planned, SUM(ActualQuantity) actual
                    FROM SalesAgreementProductSchedule
                    WHERE SalesAgreementProduct.SalesAgreementId = :saId
                    WITH USER_MODE
                    GROUP BY SalesAgreementProductId
                ]) {
                    Id pid = (Id) ar.get('pid');
                    Decimal pl = (Decimal) (ar.get('planned') == null ? 0 : ar.get('planned'));
                    Decimal ac = (Decimal) (ar.get('actual') == null ? 0 : ar.get('actual'));
                    plannedByProduct.put(pid, pl);
                    actualByProduct.put(pid, ac);
                    totalPlanned += pl;
                    totalActual += ac;
                }

                if (!plannedByProduct.isEmpty()) {
                    for (SalesAgreementProduct p : [
                        SELECT Id, Name, DisplayName FROM SalesAgreementProduct
                        WHERE Id IN :plannedByProduct.keySet() WITH USER_MODE
                    ]) {
                        nameByProduct.put(p.Id, String.isNotBlank(p.DisplayName) ? p.DisplayName : p.Name);
                    }
                }

                r.productCount = plannedByProduct.size();
                r.totalPlannedQuantity = totalPlanned;
                r.totalActualQuantity = totalActual;
                Decimal dev = totalPlanned == 0 ? 0 : ((totalActual - totalPlanned) / totalPlanned * 100).setScale(1);
                r.overallDeviationPct = dev;

                // Find the largest absolute deviations.
                List<String> topDeviations = new List<String>();
                List<Id> pids = new List<Id>(plannedByProduct.keySet());
                // simple selection of up to 3 largest |actual-planned|
                for (Integer k = 0; k < 3 && !pids.isEmpty(); k++) {
                    Id worst = null; Decimal worstAbs = -1;
                    for (Id pid : pids) {
                        Decimal diff = Math.abs(actualByProduct.get(pid) - plannedByProduct.get(pid));
                        if (diff > worstAbs) { worstAbs = diff; worst = pid; }
                    }
                    if (worst == null) { break; }
                    pids.remove(pids.indexOf(worst));
                    Decimal pl = plannedByProduct.get(worst);
                    Decimal ac = actualByProduct.get(worst);
                    if (pl == ac) { continue; }
                    topDeviations.add(nameByProduct.get(worst) + ' (planned ' + pl + ', actual ' + ac + ')');
                }

                r.isSuccess = true;
                String summary = 'Sales agreement "' + sa.Name + '" for '
                    + (sa.Account != null ? sa.Account.Name : 'the account')
                    + ' — status ' + sa.Status + ', ' + sa.ScheduleFrequency + ' x ' + sa.ScheduleCount
                    + '. ' + r.productCount + ' products; planned quantity ' + totalPlanned
                    + ', actual ' + totalActual + ' (' + dev + '% deviation).';
                if (!topDeviations.isEmpty()) {
                    summary += ' Largest deviations: ' + String.join(topDeviations, '; ') + '.';
                }
                r.summary = summary;
                r.message = summary;
            } catch (Exception e) {
                r.isSuccess = false;
                r.message = 'Could not summarize the agreement: ' + e.getMessage();
            }
            results.add(r);
        }
        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Sales Agreement Id'
            description='Id of the sales agreement to summarize.'
            required=true
        )
        public String salesAgreementId;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the summary was produced.')
        public Boolean isSuccess;

        @InvocableVariable(label='Summary' description='Human-readable performance summary.')
        public String summary;

        @InvocableVariable(label='Product Count' description='Number of products on the agreement.')
        public Integer productCount;

        @InvocableVariable(label='Total Planned Quantity' description='Sum of planned quantity.')
        public Decimal totalPlannedQuantity;

        @InvocableVariable(label='Total Actual Quantity' description='Sum of actual quantity.')
        public Decimal totalActualQuantity;

        @InvocableVariable(label='Overall Deviation Pct' description='Overall actual-vs-planned deviation percentage.')
        public Decimal overallDeviationPct;

        @InvocableVariable(label='Message' description='Human-readable result for the agent to relay.')
        public String message;
    }
}
