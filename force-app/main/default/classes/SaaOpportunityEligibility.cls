/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Sales Agreement Agent — the single eligibility rule for creating a Sales
 * Agreement from an opportunity. Both the read pre-check
 * (SaaCheckOpportunityEligibility) and the write path
 * (SaaCreateSalesAgreementFromOpp) use it, so they can never disagree.
 *
 * The rule comes from SaaSettings:
 *   - Opportunity Record Type: the opportunity must have this record type.
 *   - Opportunity Eligibility Field: this checkbox must be checked.
 * Either can be left blank, in which case that part of the rule is skipped.
 * A value that points at a record type or field the org doesn't have makes
 * every opportunity ineligible, with a message naming the bad setting.
 */
public with sharing class SaaOpportunityEligibility {

    public class EligibilityResult {
        public Boolean recordTypeOk = false;
        public Boolean criteriaFieldOk = false;
        public Boolean isEligible = false;
        public String message;
    }

    /** Opportunity fields the rule and the create path need. */
    public static List<String> queryFields() {
        List<String> fields = new List<String>{ 'Id', 'Name', 'AccountId', 'CloseDate', 'Pricebook2Id' };
        SaaSettings s = SaaSettings.get();
        if (String.isNotBlank(s.opportunityRecordType) && SaaSettings.hasRecordTypes(Opportunity.SObjectType)) {
            fields.add('RecordType.DeveloperName');
        }
        if (isCheckbox(s.opportunityEligibilityField)) {
            fields.add(s.opportunityEligibilityField);
        }
        return fields;
    }

    public static Map<Id, Opportunity> queryOpportunities(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) { return new Map<Id, Opportunity>(); }
        String soql = 'SELECT ' + String.join(queryFields(), ', ')
            + ' FROM Opportunity WHERE Id IN :oppIds';
        return new Map<Id, Opportunity>((List<Opportunity>) Database.queryWithBinds(
            soql, new Map<String, Object>{ 'oppIds' => oppIds }, AccessLevel.USER_MODE));
    }

    /** Evaluate an opportunity queried with queryFields(). A null opp is ineligible. */
    public static EligibilityResult evaluate(Opportunity opp) {
        EligibilityResult r = new EligibilityResult();
        if (opp == null) {
            r.message = 'No opportunity was provided to check eligibility.';
            return r;
        }
        SaaSettings s = SaaSettings.get();
        List<String> reasons = new List<String>();

        if (String.isBlank(s.opportunityRecordType)) {
            r.recordTypeOk = true;
        } else if (!SaaSettings.hasRecordTypes(Opportunity.SObjectType)
                || SaaSettings.recordTypeId(Opportunity.SObjectType, s.opportunityRecordType) == null) {
            reasons.add('the configured opportunity record type "' + s.opportunityRecordType
                + '" does not exist in this org (check the Sales Agreement Agent Setting)');
        } else {
            SObject rt = opp.getSObject('RecordType');
            String devName = rt == null ? null : (String) rt.get('DeveloperName');
            r.recordTypeOk = s.opportunityRecordType.equalsIgnoreCase(devName);
            if (!r.recordTypeOk) {
                reasons.add('it is not the ' + recordTypeLabel(s.opportunityRecordType) + ' record type');
            }
        }

        if (String.isBlank(s.opportunityEligibilityField)) {
            r.criteriaFieldOk = true;
        } else if (!isCheckbox(s.opportunityEligibilityField)) {
            reasons.add('the configured eligibility field "' + s.opportunityEligibilityField
                + '" is not a checkbox on Opportunity (check the Sales Agreement Agent Setting)');
        } else {
            r.criteriaFieldOk = opp.get(s.opportunityEligibilityField) == true;
            if (!r.criteriaFieldOk) {
                reasons.add(fieldLabel(s.opportunityEligibilityField) + ' is not checked');
            }
        }

        r.isEligible = r.recordTypeOk && r.criteriaFieldOk;
        r.message = r.isEligible
            ? 'Opportunity "' + opp.Name + '" is eligible for a sales agreement.'
            : 'Opportunity "' + opp.Name + '" is not eligible for a sales agreement because '
                + String.join(reasons, ' and ') + '.';
        return r;
    }

    private static Boolean isCheckbox(String fieldName) {
        Schema.DescribeFieldResult d = SaaSettings.describeField(Opportunity.SObjectType, fieldName);
        return d != null && d.getType() == Schema.DisplayType.BOOLEAN;
    }

    private static String fieldLabel(String fieldName) {
        return SaaSettings.describeField(Opportunity.SObjectType, fieldName).getLabel();
    }

    private static String recordTypeLabel(String developerName) {
        return Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get(developerName).getName();
    }
}
