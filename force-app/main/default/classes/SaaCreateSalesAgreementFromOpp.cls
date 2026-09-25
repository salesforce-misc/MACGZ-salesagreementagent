/**
 * Sales Agreement Agent — create a Sales Agreement from an opportunity and add
 * a SalesAgreementProduct line for each product on the opportunity.
 *
 * Wire with: target: "apex://SaaCreateSalesAgreementFromOpp"
 *
 * The schedule shape (start date rule, frequency, period count, agreement type),
 * record type, name prefix and the optional link back to the opportunity come
 * from SaaSettings. The opportunity must pass SaaOpportunityEligibility first
 * (fail closed).
 *
 * Runs in the logged-in user's context (USER_MODE); the user needs Manufacturing
 * Cloud Sales Agreement access for the inserts to succeed.
 */
public with sharing class SaaCreateSalesAgreementFromOpp {

    @InvocableMethod(
        label='SAA Create Sales Agreement From Opportunity'
        description='Creates a Sales Agreement from an eligible opportunity using the Sales Agreement Agent Setting defaults, and adds a product line for each opportunity product.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        SaaSettings settings = SaaSettings.get();

        Set<Id> oppIds = new Set<Id>();
        Map<Id, Opportunity> oppById;
        try {
            for (Request req : requests) {
                if (String.isNotBlank(req.opportunityId)) { oppIds.add((Id) req.opportunityId); }
            }
            oppById = SaaOpportunityEligibility.queryOpportunities(oppIds);
        } catch (Exception e) {
            for (Request req : requests) {
                results.add(failure('Error preparing sales agreement: ' + e.getMessage()));
            }
            return results;
        }

        Map<Id, List<OpportunityLineItem>> olisByOpp = new Map<Id, List<OpportunityLineItem>>();
        if (!oppById.isEmpty()) {
            Set<Id> foundIds = oppById.keySet();
            for (OpportunityLineItem oli : [
                SELECT Id, OpportunityId, Product2.Name, PricebookEntryId, Quantity, UnitPrice, Name
                FROM OpportunityLineItem
                WHERE OpportunityId IN :foundIds
                WITH USER_MODE
            ]) {
                if (!olisByOpp.containsKey(oli.OpportunityId)) {
                    olisByOpp.put(oli.OpportunityId, new List<OpportunityLineItem>());
                }
                olisByOpp.get(oli.OpportunityId).add(oli);
            }
        }

        Id agreementRtId = settings.agreementRecordTypeId();
        Schema.DescribeFieldResult oppLinkField =
            SaaSettings.describeField(SalesAgreement.SObjectType, settings.agreementOpportunityField);
        if (oppLinkField != null && !oppLinkField.isCreateable()) { oppLinkField = null; }

        List<SalesAgreement> toInsert = new List<SalesAgreement>();
        List<Result> pending = new List<Result>();
        List<Id> pendingOppIds = new List<Id>();

        for (Request req : requests) {
            Opportunity opp = String.isNotBlank(req.opportunityId)
                ? oppById.get((Id) req.opportunityId) : null;
            if (opp == null) {
                results.add(failure('Opportunity not found or not accessible: ' + req.opportunityId));
                continue;
            }
            if (opp.AccountId == null) {
                results.add(failure('The opportunity has no account, so a sales agreement cannot be created.'));
                continue;
            }
            SaaOpportunityEligibility.EligibilityResult elig = SaaOpportunityEligibility.evaluate(opp);
            if (!elig.isEligible) {
                results.add(failure(elig.message));
                continue;
            }

            Date startDate = settings.startDate(req.startDate);
            Integer periods = req.scheduleCount != null && req.scheduleCount > 0
                ? req.scheduleCount : settings.scheduleCount;

            SalesAgreement sa = new SalesAgreement();
            sa.Name = String.isNotBlank(req.agreementName)
                ? req.agreementName.left(255)
                : (settings.agreementNamePrefix + ' ' + startDate.year() + ' — ' + opp.Name).left(255);
            sa.AccountId = opp.AccountId;
            if (agreementRtId != null) { sa.put('RecordTypeId', agreementRtId); }
            if (oppLinkField != null) { sa.put(oppLinkField.getName(), opp.Id); }
            sa.StartDate = startDate;
            sa.EndDate = SaaSettings.endDate(startDate, settings.scheduleFrequency, periods);
            sa.ScheduleFrequency = settings.scheduleFrequency;
            sa.ScheduleCount = periods;
            sa.AgreementType = settings.agreementType;
            sa.ProductLevel = 'Product';
            sa.Status = 'Draft';
            if (opp.Pricebook2Id != null) { sa.PricebookId = opp.Pricebook2Id; }

            Result r = new Result();
            r.isSuccess = true;
            toInsert.add(sa);
            pending.add(r);
            pendingOppIds.add(opp.Id);
            results.add(r);
        }

        if (toInsert.isEmpty()) { return results; }

        List<Database.SaveResult> saSrs = Database.insert(toInsert, false, AccessLevel.USER_MODE);

        // Manufacturing Cloud allows one SalesAgreementProduct per pricebook entry,
        // so opportunity lines that share an entry are merged into one line.
        List<SalesAgreementProduct> products = new List<SalesAgreementProduct>();
        List<Id> productSaIds = new List<Id>();
        for (Integer i = 0; i < saSrs.size(); i++) {
            Result r = pending.get(i);
            Database.SaveResult sr = saSrs.get(i);
            if (!sr.isSuccess()) {
                r.isSuccess = false;
                r.message = 'Could not create the sales agreement: '
                    + (sr.getErrors().isEmpty() ? 'unknown error' : sr.getErrors()[0].getMessage());
                continue;
            }
            r.salesAgreementId = sr.getId();
            r.salesAgreementName = toInsert.get(i).Name;

            List<OpportunityLineItem> olis = olisByOpp.get(pendingOppIds.get(i));
            if (olis == null) { continue; }
            Map<Id, SalesAgreementProduct> byPbe = new Map<Id, SalesAgreementProduct>();
            for (OpportunityLineItem oli : olis) {
                if (oli.PricebookEntryId == null) { continue; }
                SalesAgreementProduct sap = byPbe.get(oli.PricebookEntryId);
                if (sap == null) {
                    String prodName = oli.Product2 != null && oli.Product2.Name != null
                        ? oli.Product2.Name : (oli.Name != null ? oli.Name : 'Product');
                    sap = new SalesAgreementProduct(
                        SalesAgreementId = sr.getId(),
                        Name = prodName.left(255),
                        DisplayName = prodName,
                        PricebookEntryId = oli.PricebookEntryId,
                        InitialPlannedQtyValue = 0,
                        SalesPrice = oli.UnitPrice
                    );
                    byPbe.put(oli.PricebookEntryId, sap);
                }
                if (oli.Quantity != null) { sap.InitialPlannedQtyValue += oli.Quantity; }
                if (oli.UnitPrice != null && (sap.SalesPrice == null || oli.UnitPrice > sap.SalesPrice)) {
                    sap.SalesPrice = oli.UnitPrice;
                }
            }
            for (SalesAgreementProduct sap : byPbe.values()) {
                sap.InitialPlannedQuantity = sap.InitialPlannedQtyValue.intValue();
                products.add(sap);
                productSaIds.add(sr.getId());
            }
        }

        Map<Id, Integer> productCountBySa = countInserted(products, productSaIds);

        for (Integer i = 0; i < pending.size(); i++) {
            Result r = pending.get(i);
            if (!r.isSuccess) { continue; }
            Id saId = r.salesAgreementId;
            Integer cnt = productCountBySa.containsKey(saId) ? productCountBySa.get(saId) : 0;
            r.productCount = cnt;
            r.message = 'Created sales agreement "' + r.salesAgreementName + '" ('
                + toInsert.get(i).ScheduleFrequency + ', ' + toInsert.get(i).ScheduleCount
                + ' periods, starting ' + String.valueOf(toInsert.get(i).StartDate)
                + ') with ' + cnt + ' product line(s).';
        }
        return results;
    }

    private static Map<Id, Integer> countInserted(List<SalesAgreementProduct> products, List<Id> saIds) {
        Map<Id, Integer> countBySa = new Map<Id, Integer>();
        if (products.isEmpty()) { return countBySa; }
        List<Database.SaveResult> srs = Database.insert(products, false, AccessLevel.USER_MODE);
        for (Integer j = 0; j < srs.size(); j++) {
            if (!srs.get(j).isSuccess()) { continue; }
            Id saId = saIds.get(j);
            countBySa.put(saId, (countBySa.containsKey(saId) ? countBySa.get(saId) : 0) + 1);
        }
        return countBySa;
    }

    private static Result failure(String message) {
        Result r = new Result();
        r.isSuccess = false;
        r.message = message;
        return r;
    }

    public class Request {
        @InvocableVariable(
            label='Opportunity Id'
            description='Id of the opportunity to create the sales agreement from.'
            required=true
        )
        public String opportunityId;

        @InvocableVariable(
            label='Agreement Name'
            description='Optional name for the sales agreement (defaults to "<prefix> <start year> — <opportunity>").'
            required=false
        )
        public String agreementName;

        @InvocableVariable(
            label='Start Date'
            description='Optional start date (defaults to the Start Date Rule in the Sales Agreement Agent Setting).'
            required=false
        )
        public Date startDate;

        @InvocableVariable(
            label='Schedule Count'
            description='Optional number of periods (defaults to the Schedule Count in the Sales Agreement Agent Setting).'
            required=false
        )
        public Integer scheduleCount;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the sales agreement was created.')
        public Boolean isSuccess;

        @InvocableVariable(label='Sales Agreement Id' description='Id of the created sales agreement.')
        public String salesAgreementId;

        @InvocableVariable(label='Sales Agreement Name' description='Name of the created sales agreement.')
        public String salesAgreementName;

        @InvocableVariable(label='Product Count' description='Number of product lines added.')
        public Integer productCount;

        @InvocableVariable(label='Message' description='Human-readable result for the agent to relay.')
        public String message;
    }
}
