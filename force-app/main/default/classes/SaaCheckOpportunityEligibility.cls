/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Sales Agreement Agent — read-only pre-check: can this opportunity become a
 * sales agreement?
 *
 * Wire with: target: "apex://SaaCheckOpportunityEligibility"
 *
 * Lets the agent explain eligibility before it tries to create the agreement.
 * The rule itself lives in SaaOpportunityEligibility.
 */
public with sharing class SaaCheckOpportunityEligibility {

    @InvocableMethod(
        label='SAA Check Opportunity Eligibility'
        description='Checks whether an opportunity is eligible for a Sales Agreement, using the rule in the Sales Agreement Agent Setting. Read-only.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        Map<Id, Opportunity> oppById = new Map<Id, Opportunity>();
        try {
            Set<Id> oppIds = new Set<Id>();
            for (Request req : requests) {
                if (String.isNotBlank(req.opportunityId)) { oppIds.add((Id) req.opportunityId); }
            }
            oppById = SaaOpportunityEligibility.queryOpportunities(oppIds);
        } catch (Exception ex) {
            for (Request req : requests) {
                Result r = new Result();
                r.message = 'Error checking eligibility: ' + ex.getMessage();
                results.add(r);
            }
            return results;
        }

        for (Request req : requests) {
            Result r = new Result();
            Opportunity opp = String.isNotBlank(req.opportunityId)
                ? oppById.get((Id) req.opportunityId) : null;
            if (opp == null) {
                r.message = 'Opportunity not found or not accessible: ' + req.opportunityId;
            } else {
                SaaOpportunityEligibility.EligibilityResult e = SaaOpportunityEligibility.evaluate(opp);
                r.recordTypeOk = e.recordTypeOk;
                r.criteriaFieldOk = e.criteriaFieldOk;
                r.isEligible = e.isEligible;
                r.message = e.message;
            }
            results.add(r);
        }
        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Opportunity Id'
            description='Id of the opportunity to check for Sales Agreement eligibility.'
            required=true
        )
        public String opportunityId;
    }

    public class Result {
        @InvocableVariable(label='Record Type OK' description='Whether the opportunity has the configured record type (true when none is configured).')
        public Boolean recordTypeOk = false;

        @InvocableVariable(label='Criteria Field OK' description='Whether the configured eligibility checkbox is checked (true when none is configured).')
        public Boolean criteriaFieldOk = false;

        @InvocableVariable(label='Is Eligible' description='Whether the opportunity is eligible for a Sales Agreement.')
        public Boolean isEligible = false;

        @InvocableVariable(label='Message' description='Human-readable eligibility explanation for the agent to relay.')
        public String message;
    }
}
