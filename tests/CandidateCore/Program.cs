using os_sr_cact;

static class Program
{
    static int passed;
    static readonly Guid Actor = Guid.Parse("00000000-0000-0000-0000-000000000001");
    static readonly Guid Candidate = Guid.Parse("00000000-0000-0000-0000-000000000002");
    static readonly DateTime Now = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
    static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL: " + name);
        passed++;
    }
    static void Reject(Action action, string code)
    {
        try { action(); throw new Exception("Expected rejection: " + code); }
        catch (OperationError error) { Check(error.Message == code, code); }
    }
    static Dictionary<string, object?> Input(string action = "RecordCall", Guid? correlation = null)
    {
        var input = new Dictionary<string, object?> { ["ActionType"] = action, ["CorrelationId"] = correlation ?? Guid.NewGuid() };
        if (action != "CreateCandidate") input["CandidateId"] = Candidate;
        if (action == "RecordCall") { input["ExpectedStatus"] = ActionRequest.NeedCall; input["CallOutcome"] = 100010000; input["ContactedAt"] = Now; }
        if (action == "CreateCandidate") { input["CandidateName"] = "Synthetic Candidate"; input["CandidateEmail"] = "synthetic@example.invalid"; }
        if (action == "UpdateCandidate") input["CandidateName"] = "Synthetic Replacement";
        return input;
    }
    static ActionRequest Request(Dictionary<string, object?> input) => new(Actor, input, Now);

    static void Main()
    {
        for (int outcome = 100010000; outcome <= 100010002; outcome++)
        {
            var input = Input(); input["CallOutcome"] = outcome;
            var store = new MemoryStore();
            var request = Request(input);
            var result = store.Atomic(request);
            Check(store.Calls == 1 && store.Histories == (outcome == 100010000 ? 1 : 0), "Exact call effects");
            Check(store.Status == (outcome == 100010000 ? ActionRequest.Answered : ActionRequest.NeedCall), "Call state");
            var replay = store.Atomic(request);
            Check(replay.Replay && replay.CallId == result.CallId && replay.HistoryId == result.HistoryId, "Persisted replay IDs");
            Check(store.Calls == 1 && store.Receipts.Count == 1, "Double-click no duplicate");
            input["Notes"] = "Changed intent";
            Reject(() => store.Atomic(Request(input)), "CORRELATION_CONFLICT");
        }
        var scheduling = Input("ProceedToScheduling"); scheduling["ExpectedStatus"] = ActionRequest.Answered;
        var queueStore = new MemoryStore { Status = ActionRequest.Answered };
        Check(queueStore.Atomic(Request(scheduling)).Current == ActionRequest.Waiting && queueStore.Histories == 1 && queueStore.Calls == 0, "Scheduling queue");
        foreach (var item in new[] {
            ("MarkRound1Scheduled", ActionRequest.Waiting, ActionRequest.Scheduled),
            ("RecordPass", ActionRequest.Scheduled, ActionRequest.Passed),
            ("RecordFail", ActionRequest.Scheduled, ActionRequest.Failed),
            ("RequestReschedule", ActionRequest.Scheduled, ActionRequest.NeedCall) })
            Check(CandidateOperation.Transition(item.Item1, item.Item2, null, true) == item.Item3, "Future transition contract");
        Reject(() => CandidateOperation.Transition("MarkRound1Scheduled", ActionRequest.Waiting, null), "SCHEDULER_DEPENDENCY_UNAVAILABLE");
        foreach (var action in new[] { "RecordPass", "RecordFail", "RequestReschedule" })
            Reject(() => CandidateOperation.Transition(action, ActionRequest.Scheduled, null), "RESULT_OR_CANCELLATION_DEPENDENCY_UNAVAILABLE");
        foreach (var status in new[] { ActionRequest.Passed, ActionRequest.Failed, ActionRequest.Waiting })
            Reject(() => CandidateOperation.Transition("RecordCall", status, 100010000), "INVALID_TRANSITION");
        var invalid = Input(); invalid["ExpectedStatus"] = ActionRequest.Answered;
        Reject(() => new MemoryStore().Atomic(Request(invalid)), "STALE_EXPECTED_STATUS");
        invalid = Input(); invalid["CallOutcome"] = -1;
        Reject(() => Request(invalid), "INVALID_OUTCOME");
        invalid = Input(); invalid["CorrelationId"] = Guid.Empty;
        Reject(() => Request(invalid), "INVALID_CORRELATION");
        invalid["CorrelationId"] = "not-a-guid";
        Reject(() => Request(invalid), "INVALID_CORRELATIONID");
        invalid = Input(); invalid.Remove("CandidateId");
        Reject(() => Request(invalid), "INVALID_CANDIDATE");
        invalid = Input("RequestReschedule"); invalid["ExpectedStatus"] = ActionRequest.Scheduled;
        Reject(() => Request(invalid), "REASON_REQUIRED");
        invalid = Input(); invalid["Actor"] = Guid.NewGuid();
        Reject(() => Request(invalid), "UNEXPECTED_INPUT");
        invalid = Input(); invalid["ContactedAt"] = Now.AddSeconds(1);
        Reject(() => Request(invalid), "INVALID_CONTACT_TIME");
        var updateStore = new MemoryStore();
        var update = Request(Input("UpdateCandidate"));
        var original = updateStore.Atomic(update);
        updateStore.Status = ActionRequest.Answered;
        updateStore.Version++;
        var updatedReplay = updateStore.Atomic(update);
        Check(updatedReplay.Replay && updatedReplay.Current == original.Current && updateStore.Updates == 1, "Replay after later edit returns original outcome");
        Check(updateStore.Calls == 0 && updateStore.Histories == 0, "Update never fabricates logs/history");
        var sameIdDifferentAction = Input("RecordCall", update.Correlation);
        Reject(() => updateStore.Atomic(Request(sameIdDifferentAction)), "CORRELATION_CONFLICT");
        foreach (int fail in new[] { 1, 2, 3, 4 })
        {
            var store = new MemoryStore { FailMutation = fail };
            Reject(() => store.Atomic(Request(Input())), "SYNTHETIC_MUTATION_FAILURE");
            Check(store.Calls == 0 && store.Histories == 0 && store.Status == ActionRequest.NeedCall && store.Receipts.Count == 0, "Host transaction rollback at each effect");
        }
        var auditStore = new MemoryStore { Audit = false };
        Reject(() => auditStore.Atomic(Request(Input())), "AUDIT_ACTIVATION_PENDING");
        Check(auditStore.Calls == 0, "Audit fail closed");
        var raceStore = new MemoryStore { StaleVersion = true };
        Reject(() => raceStore.Atomic(Request(Input())), "ROW_VERSION_CONFLICT");
        Check(raceStore.Calls == 0 && raceStore.Histories == 0, "Race no partial writes");
        var missing = new MemoryStore { CandidateExists = false };
        Reject(() => missing.Atomic(Request(Input())), "INVALID_CANDIDATE");
        var actorInput = Input();
        Check(Request(actorInput).Fingerprint != new ActionRequest(Guid.Parse("00000000-0000-0000-0000-000000000003"), actorInput, Now).Fingerprint, "Actor included in fingerprint");
        var ordered = Input("UpdateCandidate");
        var reversed = ordered.Reverse().ToDictionary(x => x.Key, x => x.Value);
        Check(Request(ordered).Fingerprint == Request(reversed).Fingerprint, "Canonical input order");
        reversed["CandidatePhone"] = null;
        Check(Request(ordered).Fingerprint != Request(reversed).Fingerprint, "Omitted and explicit null differ");
        var createStore = new MemoryStore();
        var create = Request(Input("CreateCandidate"));
        var created = createStore.Atomic(create);
        Check(created.Current == ActionRequest.NeedCall && createStore.Histories == 0, "Creation no fabricated history");
        Check(createStore.Atomic(create).Replay && createStore.Creates == 1, "Creation replay");
        Console.WriteLine($"PASS: {passed} synthetic Candidate operation assertions; in-memory host rollback simulation, no Dataverse calls.");
    }

    sealed class MemoryStore : IOperationStore
    {
        public int Status = ActionRequest.NeedCall, Calls, Histories, Updates, Creates, Version = 1, FailMutation, Mutation;
        public bool Audit = true, StaleVersion, CandidateExists = true;
        public Dictionary<Guid, Receipt> Receipts = new();
        void Mutate() { if (++Mutation == FailMutation) throw new OperationError("SYNTHETIC_MUTATION_FAILURE"); }
        public ActionResult Atomic(ActionRequest request)
        {
            var before = (Status, Calls, Histories, Updates, Creates, Version, Mutation, new Dictionary<Guid, Receipt>(Receipts));
            try { return CandidateOperation.Execute(request, this); }
            catch
            {
                (Status, Calls, Histories, Updates, Creates, Version, Mutation, Receipts) = before;
                throw;
            }
        }
        public void RequireTransactionAndAudit() { if (!Audit) throw new OperationError("AUDIT_ACTIVATION_PENDING"); }
        public Receipt? FindReceipt(Guid correlation) => Receipts.GetValueOrDefault(correlation);
        public CandidateState GetCandidate(Guid id)
        {
            if (!CandidateExists || id != Candidate) throw new OperationError("INVALID_CANDIDATE");
            return new CandidateState { Id = id, Status = Status, RowVersion = Version.ToString() };
        }
        public Guid CreateCandidate(ActionRequest request) { Mutate(); Creates++; return Candidate; }
        public void UpdateCandidate(ActionRequest request, CandidateState candidate, int status)
        {
            if (StaleVersion) throw new OperationError("ROW_VERSION_CONFLICT");
            Mutate(); Updates++; Status = status; Version++;
        }
        public Guid CreateCall(ActionRequest request, Guid candidate) { Mutate(); Calls++; return Guid.NewGuid(); }
        public Guid CreateHistory(ActionRequest request, Guid candidate, int previous, int current) { Mutate(); Histories++; return Guid.NewGuid(); }
        public void CreateReceipt(ActionRequest request, ActionResult result)
        {
            Mutate();
            Receipts.Add(request.Correlation, new Receipt { Actor = request.Actor, Action = request.Action,
                Fingerprint = request.Fingerprint, Version = "1", Result = result });
        }
    }
}
