/**
 * Sales Agreement Agent — log the start of pricing work as an Account Plan
 * Objective on the customer's account plan.
 *
 * Wire with: target: "apex://SaaCreateAccountPlanObjective"
 *
 * Creates an AccountPlanObjective under the supplied Account Plan. If no
 * accountPlanId is provided but an accountId is, the newest Account Plan for
 * that account is used. The default name comes from Objective Name on the
 * Sales Agreement Agent Setting. Runs in the logged-in user's context
 * (USER_MODE) so their own sharing and CRUD apply.
 */
public with sharing class SaaCreateAccountPlanObjective {

    @InvocableMethod(
        label='SAA Create Account Plan Objective'
        description='Creates an Account Plan Objective to log the start of pricing work for a customer. Provide the Account Plan Id (preferred) or an Account Id, plus an objective name.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Resolve account plans for any requests that gave an accountId instead.
        Set<Id> accountIds = new Set<Id>();
        for (Request req : requests) {
            if (String.isBlank(req.accountPlanId) && String.isNotBlank(req.accountId)) {
                accountIds.add((Id) req.accountId);
            }
        }
        Map<Id, Id> newestPlanByAccount = new Map<Id, Id>();
        if (!accountIds.isEmpty()) {
            for (AccountPlan p : [
                SELECT Id, AccountId
                FROM AccountPlan
                WHERE AccountId IN :accountIds
                WITH USER_MODE
                ORDER BY CreatedDate DESC
            ]) {
                if (!newestPlanByAccount.containsKey(p.AccountId)) {
                    newestPlanByAccount.put(p.AccountId, p.Id);
                }
            }
        }

        List<AccountPlanObjective> toInsert = new List<AccountPlanObjective>();
        List<Result> pending = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            try {
                Id planId = String.isNotBlank(req.accountPlanId)
                    ? (Id) req.accountPlanId
                    : (String.isNotBlank(req.accountId) ? newestPlanByAccount.get((Id) req.accountId) : null);
                if (planId == null) {
                    r.isSuccess = false;
                    r.message = 'Could not determine an Account Plan. Provide an Account Plan Id, or an Account Id that has an existing account plan.';
                    results.add(r);
                    continue;
                }
                AccountPlanObjective obj = new AccountPlanObjective();
                obj.AccountPlanId = planId;
                obj.Name = String.isNotBlank(req.objectiveName)
                    ? req.objectiveName.left(255)
                    : SaaSettings.get().objectiveName.left(255);
                obj.Description = String.isNotBlank(req.description)
                    ? req.description
                    : 'Pricing work started for this account.';
                obj.Status = 'Yellow'; // RAG health: in progress
                Date start = Date.today();
                obj.StartDate = start;
                obj.EndDate = start.addMonths(12).addDays(-1);
                obj.ObjectiveOwnerId = UserInfo.getUserId();
                toInsert.add(obj);
                r.isSuccess = true; // provisional; finalized after DML
                pending.add(r);
                results.add(r);
            } catch (Exception e) {
                r.isSuccess = false;
                r.message = 'Error preparing objective: ' + e.getMessage();
                results.add(r);
            }
        }

        if (!toInsert.isEmpty()) {
            List<Database.SaveResult> srs = Database.insert(toInsert, false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < srs.size(); i++) {
                Result r = pending.get(i);
                Database.SaveResult sr = srs.get(i);
                if (sr.isSuccess()) {
                    r.objectiveId = sr.getId();
                    r.accountPlanId = toInsert.get(i).AccountPlanId;
                    r.message = 'Logged pricing work as Account Plan Objective "' + toInsert.get(i).Name + '".';
                } else {
                    r.isSuccess = false;
                    r.message = 'Could not create objective: ' + (sr.getErrors().isEmpty() ? 'unknown error' : sr.getErrors()[0].getMessage());
                }
            }
        }
        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Account Plan Id'
            description='Id of the Account Plan to attach the objective to (preferred).'
            required=false
        )
        public String accountPlanId;

        @InvocableVariable(
            label='Account Id'
            description='Id of the Account; used to find the newest account plan if no Account Plan Id is given.'
            required=false
        )
        public String accountId;

        @InvocableVariable(
            label='Objective Name'
            description='Short name for the objective (defaults to the Objective Name in the Sales Agreement Agent Setting).'
            required=false
        )
        public String objectiveName;

        @InvocableVariable(
            label='Description'
            description='Optional longer description of the objective.'
            required=false
        )
        public String description;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the objective was created.')
        public Boolean isSuccess;

        @InvocableVariable(label='Objective Id' description='Id of the created Account Plan Objective.')
        public String objectiveId;

        @InvocableVariable(label='Account Plan Id' description='Id of the Account Plan the objective was attached to.')
        public String accountPlanId;

        @InvocableVariable(label='Message' description='Human-readable result for the agent to relay.')
        public String message;
    }
}
