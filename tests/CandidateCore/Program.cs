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
        {
            Reject(() => CandidateOperation.Transition(action, ActionRequest.Waiting, null), "INVALID_TRANSITION");
            Reject(() => CandidateOperation.Transition(action, ActionRequest.Scheduled, null), "RESULT_OR_CANCELLATION_DEPENDENCY_UNAVAILABLE");
        }
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
        var createWithNullCandidateId = Input("CreateCandidate");
        var createWithoutExpectedStatus = Request(createWithNullCandidateId);
        Check(!createWithoutExpectedStatus.ExpectedStatus.HasValue &&
            !createWithoutExpectedStatus.Values.ContainsKey("ExpectedStatus"),
            "CreateCandidate absent ExpectedStatus is omitted from normalized request");
        var createWithNullExpectedStatus = new Dictionary<string, object?>(createWithNullCandidateId)
        {
            ["ExpectedStatus"] = null
        };
        var nullExpectedCreate = Request(createWithNullExpectedStatus);
        Check(!nullExpectedCreate.ExpectedStatus.HasValue &&
            !nullExpectedCreate.Values.ContainsKey("ExpectedStatus") &&
            nullExpectedCreate.Fingerprint == createWithoutExpectedStatus.Fingerprint,
            "CreateCandidate null ExpectedStatus is accepted and canonicalized as absent");
        var createCorrelation = Guid.NewGuid();
        var createWithoutStatus = Request(Input("CreateCandidate", createCorrelation));
        foreach (var ignoredStatus in new object?[]
        {
            null, 0, ActionRequest.NeedCall, ActionRequest.Answered, 999, "100010000", new object()
        })
        {
            var inputWithIgnoredStatus = Input("CreateCandidate", createCorrelation);
            inputWithIgnoredStatus["ExpectedStatus"] = ignoredStatus;
            var ignoredStatusCreate = Request(inputWithIgnoredStatus);
            Check(!ignoredStatusCreate.ExpectedStatus.HasValue &&
                !ignoredStatusCreate.Values.ContainsKey("ExpectedStatus") &&
                ignoredStatusCreate.Fingerprint == createWithoutStatus.Fingerprint,
                "CreateCandidate ignores ExpectedStatus value and excludes it from the fingerprint");
        }
        var statusIndependentCreateStore = new MemoryStore();
        Check(!statusIndependentCreateStore.Atomic(createWithoutStatus).Replay &&
            statusIndependentCreateStore.Atomic(Request(new Dictionary<string, object?>(Input("CreateCandidate", createCorrelation))
            {
                ["ExpectedStatus"] = new object()
            })).Replay &&
            statusIndependentCreateStore.Creates == 1,
            "CreateCandidate replay identity is unchanged by arbitrary ExpectedStatus representations");
        var createOptionSetLike = new Dictionary<string, object?>(Input("CreateCandidate"));
        createOptionSetLike["ExpectedStatus"] = new StatusValue(ActionRequest.NeedCall);
        var ignoredWrappedStatus = Request(createOptionSetLike);
        Check(!ignoredWrappedStatus.ExpectedStatus.HasValue &&
            !ignoredWrappedStatus.Values.ContainsKey("ExpectedStatus"),
            "CreateCandidate ignores non-integer ExpectedStatus wrapper values");
        createWithNullCandidateId["CandidateId"] = null;
        Check(Request(createWithNullCandidateId).CandidateId == null, "Optional null CandidateId accepted on create");
        createWithNullCandidateId["CandidateId"] = Guid.Empty;
        Check(Request(createWithNullCandidateId).CandidateId == null, "Optional empty CandidateId accepted on create");
        createWithNullCandidateId["CandidateId"] = Candidate;
        Reject(() => Request(createWithNullCandidateId), "UNEXPECTED_INPUT");
        createWithNullCandidateId["CandidateId"] = "not-a-guid";
        Reject(() => Request(createWithNullCandidateId), "INVALID_CANDIDATEID");
        var missingCreateName = Input("CreateCandidate");
        missingCreateName.Remove("CandidateName");
        Reject(() => Request(missingCreateName), "CONTACT_REQUIRED");
        var missingCreateEmail = Input("CreateCandidate");
        missingCreateEmail.Remove("CandidateEmail");
        Reject(() => Request(missingCreateEmail), "CONTACT_REQUIRED");
        var invalidCreateStore = new MemoryStore();
        Reject(() => invalidCreateStore.Atomic(Request(missingCreateName)), "CONTACT_REQUIRED");
        Check(invalidCreateStore.Mutation == 0 && invalidCreateStore.Creates == 0 && invalidCreateStore.Receipts.Count == 0,
            "Invalid CreateCandidate input has no business mutation");
        invalid = Input(); invalid.Remove("CandidateId");
        Reject(() => Request(invalid), "INVALID_CANDIDATE");
        invalid = Input(); invalid.Remove("ExpectedStatus");
        Reject(() => Request(invalid), "EXPECTED_STATUS_REQUIRED");
        invalid = Input("UpdateCandidate"); invalid["ExpectedStatus"] = "100010000";
        Reject(() => Request(invalid), "INVALID_EXPECTED_STATUS");
        invalid = Input("UpdateCandidate"); invalid["ExpectedStatus"] = new StatusValue(ActionRequest.NeedCall);
        Reject(() => Request(invalid), "INVALID_EXPECTED_STATUS");
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
        var expectedUpdateInput = Input("UpdateCandidate");
        expectedUpdateInput["ExpectedStatus"] = ActionRequest.NeedCall;
        var expectedUpdateStore = new MemoryStore();
        var expectedUpdate = expectedUpdateStore.Atomic(Request(expectedUpdateInput));
        Check(expectedUpdate.Current == ActionRequest.NeedCall && expectedUpdateStore.Updates == 1,
            "UpdateCandidate accepts matching ExpectedStatus");
        var staleUpdateInput = Input("UpdateCandidate");
        staleUpdateInput["ExpectedStatus"] = ActionRequest.NeedCall;
        var staleUpdateStore = new MemoryStore { Status = ActionRequest.Answered };
        Reject(() => staleUpdateStore.Atomic(Request(staleUpdateInput)), "STALE_EXPECTED_STATUS");
        Check(staleUpdateStore.Updates == 0 && staleUpdateStore.Receipts.Count == 0,
            "Stale UpdateCandidate ExpectedStatus has no mutation");
        var sameIdDifferentAction = Input("RecordCall", update.Correlation);
        Reject(() => updateStore.Atomic(Request(sameIdDifferentAction)), "CORRELATION_CONFLICT");
        foreach (int fail in new[] { 1, 2, 3, 4 })
        {
            var store = new MemoryStore { FailMutation = fail };
            Reject(() => store.Atomic(Request(Input())), "SYNTHETIC_MUTATION_FAILURE");
            Check(store.Calls == 0 && store.Histories == 0 && store.Status == ActionRequest.NeedCall && store.Receipts.Count == 0, "Host transaction rollback at each effect");
        }
        var auditPendingStore = new MemoryStore { Audit = false };
        var auditPendingResult = auditPendingStore.Atomic(Request(Input()));
        Check(!auditPendingResult.Replay && auditPendingStore.Calls == 1 && auditPendingStore.Receipts.Count == 1,
            "Organization audit state is not a business runtime gate");
        var auditPendingCreateStore = new MemoryStore { Audit = false };
        var auditPendingCreate = auditPendingCreateStore.Atomic(Request(Input("CreateCandidate")));
        Check(auditPendingCreate.Current == ActionRequest.NeedCall && auditPendingCreateStore.Creates == 1 &&
            auditPendingCreateStore.Receipts.Count == 1 && auditPendingCreateStore.Histories == 0,
            "Organization audit inactive permits valid Candidate creation with receipt and no fabricated history");
        Check(auditPendingCreateStore.Status == ActionRequest.NeedCall,
            "CreateCandidate initial status is server-controlled Need Call Candidate");
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
        var vectorId = Guid.Parse("00000000-0000-0000-0000-000000000004");
        var vector = Input("UpdateCandidate", vectorId);
        Check(Request(vector).Fingerprint == "4e5eb0d4c3e770c2fd219dd2f3ddad71ca261af3a87220d1148cd9af8a46d0b5", "Update fingerprint golden vector");
        vector["CandidateName"] = "  Synthetic Replacement  ";
        Check(Request(vector).Fingerprint == "4e5eb0d4c3e770c2fd219dd2f3ddad71ca261af3a87220d1148cd9af8a46d0b5", "Trimmed equivalent request golden vector");
        vector["CandidatePhone"] = null;
        Check(Request(vector).Fingerprint == "c35231ed0a55b5c76c91f24e0db6c90fd086a4d94997f0279ceea8f11391ca81", "Explicit null fingerprint golden vector");
        vector["CandidatePhone"] = "";
        Check(Request(vector).Fingerprint != "c35231ed0a55b5c76c91f24e0db6c90fd086a4d94997f0279ceea8f11391ca81", "Empty string differs from explicit null");
        var callVector = Input("RecordCall", vectorId);
        Check(Request(callVector).Fingerprint == "6da0c75875c5e6fc97e34e59df7b0a64631b5874f8f75d4c922173d5b67ca4e2", "Call UTC and Choice fingerprint golden vector");
        var originalCulture = System.Globalization.CultureInfo.CurrentCulture;
        try
        {
            System.Globalization.CultureInfo.CurrentCulture = new System.Globalization.CultureInfo("vi-VN");
            Check(Request(callVector.Reverse().ToDictionary(x => x.Key, x => x.Value)).Fingerprint ==
                "6da0c75875c5e6fc97e34e59df7b0a64631b5874f8f75d4c922173d5b67ca4e2", "Culture and ordering preserve golden vector");
        }
        finally { System.Globalization.CultureInfo.CurrentCulture = originalCulture; }
        foreach (bool conflict in new[] { false, true })
        {
            var uniqueStore = new MemoryStore();
            var racingInput = Input("RecordCall", vectorId);
            racingInput["CallOutcome"] = 100010001;
            var accepted = uniqueStore.Atomic(Request(racingInput));
            var retained = uniqueStore.Receipts[vectorId];
            if (conflict) racingInput["Notes"] = "Different concurrent request";
            uniqueStore.HideReceiptOnce = true;
            Reject(() => uniqueStore.Atomic(Request(racingInput)), "RECEIPT_UNIQUENESS_CONFLICT");
            Check(uniqueStore.Calls == 1 && uniqueStore.Histories == 0 && uniqueStore.Updates == 0 &&
                uniqueStore.Status == ActionRequest.NeedCall && uniqueStore.Receipts.Count == 1 &&
                ReferenceEquals(uniqueStore.Receipts[vectorId], retained), "Unique insertion race rolls back loser and preserves accepted receipt");
            racingInput.Remove("Notes");
            Check(uniqueStore.Atomic(Request(racingInput)).CallId == accepted.CallId, "Accepted result survives duplicate insertion race");
        }
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
        public bool Audit, StaleVersion, CandidateExists = true, HideReceiptOnce;
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
        public void RequireTransaction() { }
        public Receipt? FindReceipt(Guid correlation)
        {
            // Model a losing transaction that read before the winning receipt committed.
            if (HideReceiptOnce) { HideReceiptOnce = false; return null; }
            return Receipts.GetValueOrDefault(correlation);
        }
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
            if (!Receipts.TryAdd(request.Correlation, new Receipt { Actor = request.Actor, Action = request.Action,
                Fingerprint = request.Fingerprint, Version = "1", Result = result }))
                throw new OperationError("RECEIPT_UNIQUENESS_CONFLICT");
        }
    }

    sealed class StatusValue
    {
        public StatusValue(int value) => Value = value;
        public int Value { get; }
    }
}
