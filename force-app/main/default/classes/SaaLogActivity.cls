/**
 * Sales Agreement Agent — log a completed activity (Task).
 *
 * Wire with: target: "apex://SaaLogActivity"
 *
 * Creates a completed Task dated today. It is related to the objective when one
 * is given, so SaaCloseAccountPlanObjective finds it later; otherwise to the
 * account plan, otherwise to the account.
 */
public with sharing class SaaLogActivity {

    @InvocableMethod(
        label='SAA Log Activity'
        description='Logs a completed activity (Task) against an Account Plan Objective, Account Plan or Account. Confirm the subject and note with the user first.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<Task> toInsert = new List<Task>();
        List<Result> pending = new List<Result>();

        for (Request req : requests) {
            Result r = new Result();
            r.success = false;
            try {
                Id whatId = firstId(new List<String>{ req.primaryObjectiveId, req.accountPlanId, req.recordId });
                if (whatId == null) {
                    r.message = 'I need an account, account plan or objective to log the activity against.';
                    results.add(r);
                    continue;
                }
                toInsert.add(new Task(
                    Subject = String.isNotBlank(req.subject) ? req.subject.left(255) : 'Pricing work update',
                    Description = req.callNote,
                    WhatId = whatId,
                    ActivityDate = Date.today(),
                    Status = 'Completed',
                    OwnerId = UserInfo.getUserId()
                ));
                pending.add(r);
            } catch (Exception e) {
                r.message = 'The activity was not logged: ' + e.getMessage();
            }
            results.add(r);
        }

        if (toInsert.isEmpty()) { return results; }
        List<Database.SaveResult> srs = Database.insert(toInsert, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < srs.size(); i++) {
            Result r = pending.get(i);
            if (srs.get(i).isSuccess()) {
                r.success = true;
                r.activityId = srs.get(i).getId();
                r.message = 'Logged the activity "' + toInsert.get(i).Subject + '".';
            } else {
                r.message = 'The activity was not logged: '
                    + (srs.get(i).getErrors().isEmpty() ? 'unknown error' : srs.get(i).getErrors()[0].getMessage());
            }
        }
        return results;
    }

    private static Id firstId(List<String> candidates) {
        for (String c : candidates) {
            if (String.isNotBlank(c)) { return (Id) c.trim(); }
        }
        return null;
    }

    public class Request {
        @InvocableVariable(label='Account Id' description='Account Id to log the activity against when no plan or objective is given.' required=false)
        public String recordId;

        @InvocableVariable(label='Subject' description='Short subject for the activity.' required=false)
        public String subject;

        @InvocableVariable(label='Note' description='Note describing the activity.' required=false)
        public String callNote;

        @InvocableVariable(label='Account Plan Id' description='Account Plan Id to relate the activity to.' required=false)
        public String accountPlanId;

        @InvocableVariable(label='Objective Id' description='Account Plan Objective Id to relate the activity to (preferred).' required=false)
        public String primaryObjectiveId;
    }

    public class Result {
        @InvocableVariable(label='Success' description='Whether the activity was logged.')
        public Boolean success;

        @InvocableVariable(label='Activity Id' description='Id of the logged Task.')
        public String activityId;

        @InvocableVariable(label='Message' description='Human-readable result for the agent to relay.')
        public String message;
    }
}
