/**
 * Sales Agreement Agent — close out the pricing-work Account Plan Objective
 * and complete the AE's open tasks related to it.
 *
 * Wire with: target: "apex://SaaCloseAccountPlanObjective"
 *
 * AccountPlanObjective has no dedicated "closed"/"completed" field — Status is a
 * RAG health value (Red/Yellow/Green). "Closing out" is therefore modeled as:
 * set Status = 'Green' (objective achieved) and EndDate = today, and mark any
 * open Tasks linked to the objective (WhatId) as Completed. Runs USER_MODE.
 */
public with sharing class SaaCloseAccountPlanObjective {

    @InvocableMethod(
        label='SAA Close Account Plan Objective'
        description='Closes out an Account Plan Objective (sets it to Green / achieved with an end date of today) and completes any open tasks linked to it. Provide the Objective Id.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        Set<Id> objectiveIds = new Set<Id>();
        for (Request req : requests) {
            if (String.isNotBlank(req.objectiveId)) {
                objectiveIds.add((Id) req.objectiveId);
            }
        }

        // Load the objectives.
        Map<Id, AccountPlanObjective> objById = new Map<Id, AccountPlanObjective>();
        if (!objectiveIds.isEmpty()) {
            objById = new Map<Id, AccountPlanObjective>([
                SELECT Id, Name, Status, EndDate
                FROM AccountPlanObjective
                WHERE Id IN :objectiveIds
                WITH USER_MODE
            ]);
        }

        // Find open tasks linked to those objectives (WhatId).
        Map<Id, List<Task>> openTasksByObjective = new Map<Id, List<Task>>();
        if (!objectiveIds.isEmpty()) {
            for (Task t : [
                SELECT Id, WhatId, Status
                FROM Task
                WHERE WhatId IN :objectiveIds AND IsClosed = false
                WITH USER_MODE
            ]) {
                if (!openTasksByObjective.containsKey(t.WhatId)) {
                    openTasksByObjective.put(t.WhatId, new List<Task>());
                }
                openTasksByObjective.get(t.WhatId).add(t);
            }
        }

        List<AccountPlanObjective> objUpdates = new List<AccountPlanObjective>();
        List<Task> taskUpdates = new List<Task>();
        Map<Id, Integer> taskCountByObjective = new Map<Id, Integer>();

        for (Request req : requests) {
            Result r = new Result();
            Id objId = String.isNotBlank(req.objectiveId) ? (Id) req.objectiveId : null;
            AccountPlanObjective obj = objId != null ? objById.get(objId) : null;
            if (obj == null) {
                r.isSuccess = false;
                r.message = 'Objective not found or not accessible: ' + req.objectiveId;
                results.add(r);
                continue;
            }
            obj.Status = 'Green';
            obj.EndDate = Date.today();
            objUpdates.add(obj);

            Integer cnt = 0;
            if (openTasksByObjective.containsKey(objId)) {
                for (Task t : openTasksByObjective.get(objId)) {
                    t.Status = 'Completed';
                    taskUpdates.add(t);
                    cnt++;
                }
            }
            taskCountByObjective.put(objId, cnt);

            r.isSuccess = true;
            r.objectiveId = objId;
            r.tasksCompleted = cnt;
            r.message = 'Closed out objective "' + obj.Name + '" (marked achieved, end date today)'
                + (cnt > 0 ? ' and completed ' + cnt + ' open task(s).' : '.');
            results.add(r);
        }

        if (!objUpdates.isEmpty()) {
            Database.update(objUpdates, false, AccessLevel.USER_MODE);
        }
        if (!taskUpdates.isEmpty()) {
            Database.update(taskUpdates, false, AccessLevel.USER_MODE);
        }
        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Objective Id'
            description='Id of the Account Plan Objective to close out.'
            required=true
        )
        public String objectiveId;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the objective was closed out.')
        public Boolean isSuccess;

        @InvocableVariable(label='Objective Id' description='Id of the closed objective.')
        public String objectiveId;

        @InvocableVariable(label='Tasks Completed' description='Number of open tasks that were completed.')
        public Integer tasksCompleted;

        @InvocableVariable(label='Message' description='Human-readable result for the agent to relay.')
        public String message;
    }
}
