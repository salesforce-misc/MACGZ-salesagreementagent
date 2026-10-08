/*
 * Copyright (c) 2026, Salesforce, Inc.
 * All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 * For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/Apache-2.0
 */

/**
 * Sales Agreement Agent — configuration.
 *
 * Reads the Sales_Agreement_Agent_Setting__mdt record named "Default" and
 * applies a safe fallback for every value, so the agent works even when the
 * record is missing or partly filled in. All org-specific behavior (which
 * opportunities qualify, record types, schedule shape, fields carried on clone)
 * lives in that record instead of the Apex.
 */
public with sharing class SaaSettings {

    public static final String START_NEXT_YEAR = 'Next_Year_Jan_1';
    public static final String START_NEXT_MONTH = 'Next_Month_1';
    public static final String START_TODAY = 'Today';

    private static SaaSettings cached;

    /** Opportunity record type DeveloperName; blank = any. */
    public String opportunityRecordType;
    /** Opportunity checkbox API name that must be true; blank = no rule. */
    public String opportunityEligibilityField;
    /** Sales Agreement record type DeveloperName for new agreements; blank = default. */
    public String agreementRecordType;
    /** Sales Agreement lookup to Opportunity; blank = no link. */
    public String agreementOpportunityField;
    public String startDateRule;
    public String scheduleFrequency;
    public Integer scheduleCount;
    public String agreementType;
    public String agreementNamePrefix;
    public List<String> cloneCarryFields;
    public String objectiveName;

    public static SaaSettings get() {
        if (cached == null) {
            cached = new SaaSettings(Sales_Agreement_Agent_Setting__mdt.getInstance('Default'));
        }
        return cached;
    }

    @TestVisible
    private static void reset() {
        cached = null;
    }

    @TestVisible
    private SaaSettings(Sales_Agreement_Agent_Setting__mdt rec) {
        opportunityRecordType = rec == null ? null : trimToNull(rec.Opportunity_Record_Type__c);
        opportunityEligibilityField = rec == null ? null : trimToNull(rec.Opportunity_Eligibility_Field__c);
        agreementRecordType = rec == null ? null : trimToNull(rec.Agreement_Record_Type__c);
        agreementOpportunityField = rec == null ? null : trimToNull(rec.Agreement_Opportunity_Field__c);
        startDateRule = orDefault(rec == null ? null : rec.Start_Date_Rule__c, START_NEXT_YEAR);
        scheduleFrequency = orDefault(rec == null ? null : rec.Schedule_Frequency__c, 'Monthly');
        scheduleCount = (rec == null || rec.Schedule_Count__c == null || rec.Schedule_Count__c < 1)
            ? 12 : rec.Schedule_Count__c.intValue();
        agreementType = orDefault(rec == null ? null : rec.Agreement_Type__c, 'Volume');
        agreementNamePrefix = orDefault(rec == null ? null : rec.Agreement_Name_Prefix__c, 'Sales Agreement');
        objectiveName = orDefault(rec == null ? null : rec.Objective_Name__c, 'Annual Pricing Work');
        cloneCarryFields = new List<String>();
        String csv = rec == null ? null : rec.Clone_Carry_Fields__c;
        if (String.isNotBlank(csv)) {
            for (String f : csv.split(',')) {
                if (String.isNotBlank(f)) { cloneCarryFields.add(f.trim()); }
            }
        }
    }

    /** Start date for a new or cloned agreement; an explicit date always wins. */
    public Date startDate(Date requested) {
        if (requested != null) { return requested; }
        Date today = Date.today();
        if (startDateRule == START_TODAY) { return today; }
        if (startDateRule == START_NEXT_MONTH) { return today.toStartOfMonth().addMonths(1); }
        return Date.newInstance(today.year() + 1, 1, 1);
    }

    /** End date covering the given number of periods at the configured frequency. */
    public static Date endDate(Date start, String frequency, Integer periods) {
        Integer monthsPerPeriod = frequency == 'Quarterly' ? 3 : (frequency == 'Yearly' ? 12 : 1);
        return start.addMonths(monthsPerPeriod * periods).addDays(-1);
    }

    public Id agreementRecordTypeId() {
        return recordTypeId(SalesAgreement.SObjectType, agreementRecordType);
    }

    public static Id recordTypeId(Schema.SObjectType objType, String developerName) {
        if (String.isBlank(developerName)) { return null; }
        Schema.RecordTypeInfo info = objType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }

    public static Boolean hasRecordTypes(Schema.SObjectType objType) {
        return objType.getDescribe().fields.getMap().containsKey('recordtypeid');
    }

    /** The field's describe, or null if it does not exist on the object. */
    public static Schema.DescribeFieldResult describeField(Schema.SObjectType objType, String fieldName) {
        if (String.isBlank(fieldName)) { return null; }
        Schema.SObjectField f = objType.getDescribe().fields.getMap().get(fieldName.toLowerCase());
        return f == null ? null : f.getDescribe();
    }

    private static String trimToNull(String s) {
        return String.isBlank(s) ? null : s.trim();
    }

    private static String orDefault(String s, String fallback) {
        return String.isBlank(s) ? fallback : s.trim();
    }
}
