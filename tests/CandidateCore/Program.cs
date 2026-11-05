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
        if (action == "MarkRound1Scheduled" || action == "RequestReschedule")
        {
            input["ExpectedStatus"] = action == "MarkRound1Scheduled" ? ActionRequest.Waiting : ActionRequest.Scheduled;
            input["InterviewerId"] = Guid.Parse("00000000-0000-0000-0000-000000000003");
            input["LocationId"] = Guid.Parse("00000000-0000-0000-0000-000000000004");
            input["StartAt"] = Now.AddDays(1);
            input["EndAt"] = Now.AddDays(1).AddHours(1);
        }
        if (action == "RecordPass" || action == "RecordFail" || action == "CancelRound1")
            input["ExpectedStatus"] = ActionRequest.Scheduled;
        if (action == "RequestReschedule" || action == "CancelRound1") input["Reason"] = "Synthetic reason";
        if (action == "CreateCandidate") { input["CandidateName"] = "Synthetic Candidate"; input["CandidateEmail"] = "synthetic@example.invalid"; }
        if (action == "UpdateCandidate")
        {
            input["ProfileFieldMask"] = "CandidateName";
            input["CandidateName"] = "Synthetic Replacement";
        }
        return input;
    }
    static ActionRequest Request(Dictionary<string, object?> input) => new(Actor, input, Now);

    static void Main()
    {
        foreach (var scenario in new[]
        {
            ("CreateCandidate", ActionRequest.NeedCall, -1, "RECEIPT_READ,CANDIDATE_CREATE,RECEIPT_CREATE"),
            ("UpdateCandidate", ActionRequest.NeedCall, -1, "RECEIPT_READ,CANDIDATE_READ,CANDIDATE_UPDATE,RECEIPT_CREATE"),
            ("RecordCall", ActionRequest.NeedCall, 100010001, "RECEIPT_READ,CANDIDATE_READ,CALL_LOG_CREATE,RECEIPT_CREATE"),
            ("RecordCall", ActionRequest.NeedCall, 100010002, "RECEIPT_READ,CANDIDATE_READ,CALL_LOG_CREATE,RECEIPT_CREATE"),
            ("RecordCall", ActionRequest.NeedCall, 100010000, "RECEIPT_READ,CANDIDATE_READ,CANDIDATE_UPDATE,CALL_LOG_CREATE,STATUS_HISTORY_CREATE,RECEIPT_CREATE"),
            ("ProceedToScheduling", ActionRequest.Answered, -1, "RECEIPT_READ,CANDIDATE_READ,CANDIDATE_UPDATE,STATUS_HISTORY_CREATE,RECEIPT_CREATE")
        })
        {
            var input = Input(scenario.Item1);
            if (scenario.Item1 != "CreateCandidate") input["ExpectedStatus"] = scenario.Item2;
            if (scenario.Item3 >= 0) input["CallOutcome"] = scenario.Item3;
            var request = Request(input);
            var store = new MemoryStore { Status = scenario.Item2 };
            store.Atomic(request);
            Check(string.Join(",", store.Events) == scenario.Item4, "Canonical engine read/write order: " + scenario.Item1);
            store.Atomic(request);
            Check(string.Join(",", store.Events) == "RECEIPT_READ,CANDIDATE_READ" && store.Receipts.Count == 1,
                "Canonical identical replay reads without receipt mutation");
            Reject(() => store.Atomic(new ActionRequest(Guid.NewGuid(), input, Now)), "CORRELATION_CONFLICT");
            Check(string.Join(",", store.Events) == "RECEIPT_READ" && store.Receipts.Count == 1,
                "Canonical conflicting replay leaves receipt unchanged");
        }
        var scheduleInput = Input("MarkRound1Scheduled");
        var scheduleStore = new MemoryStore { Status = ActionRequest.Waiting };
        var scheduled = scheduleStore.Atomic(Request(scheduleInput));
        Check(scheduled.Current == ActionRequest.Scheduled &&
            scheduleStore.ActiveSchedule?.Status == ActionRequest.ScheduleActive &&
            scheduleStore.Histories == 1 && scheduleStore.Receipts.Count == 1,
            "Round 1 schedule is durable before Candidate transition");
        Check(string.Join(",", scheduleStore.Events) ==
            "RECEIPT_READ,CANDIDATE_READ,ACTIVE_SCHEDULE_READ,PROPOSED_SCHEDULE_READ,INTERVIEW_SCHEDULE_CREATE,INTERVIEW_SCHEDULE_READBACK,CANDIDATE_UPDATE,STATUS_HISTORY_CREATE,RECEIPT_CREATE",
            "Round 1 scheduling confirms persistence before Candidate, History, and Receipt");
        var scheduleCreateCount = scheduleStore.ScheduleCreates;
        var scheduleReplay = scheduleStore.Atomic(Request(scheduleInput));
        Check(scheduleReplay.Replay && scheduleStore.ScheduleCreates == scheduleCreateCount &&
            scheduleStore.Histories == 1 && scheduleStore.Receipts.Count == 1,
            "Round 1 identical replay creates no duplicate schedule");
        scheduleInput["Notes"] = "Conflicting schedule request";
        Reject(() => scheduleStore.Atomic(Request(scheduleInput)), "CORRELATION_CONFLICT");

        var proposedStore = new MemoryStore { Status = ActionRequest.Waiting };
        proposedStore.SeedProposedSchedule();
        var confirmProposed = proposedStore.Atomic(Request(Input("MarkRound1Scheduled")));
        Check(confirmProposed.Current == ActionRequest.Scheduled &&
            proposedStore.ActiveSchedule?.Status == ActionRequest.ScheduleActive &&
            proposedStore.ProposedSchedule == null && proposedStore.ScheduleCreates == 0 &&
            proposedStore.ScheduleUpdates == 1,
            "Round 1 scheduling explicitly confirms an existing Proposed row without duplication");

        foreach (var action in new[] { "RecordPass", "RecordFail" })
        {
            var input = Input(action);
            var store = new MemoryStore { Status = ActionRequest.Scheduled };
            store.SeedActiveSchedule();
            var result = store.Atomic(Request(input));
            var expected = action == "RecordPass" ? ActionRequest.Passed : ActionRequest.Failed;
            Check(result.Current == expected && store.ActiveSchedule?.Result ==
                (action == "RecordPass" ? ActionRequest.ResultPass : ActionRequest.ResultFail) &&
                store.Histories == 1, action + " updates schedule before terminal Candidate state");
            Check(store.Events.IndexOf("INTERVIEW_SCHEDULE_UPDATE") < store.Events.IndexOf("CANDIDATE_UPDATE"),
                action + " persists result before Candidate transition");
            Check(string.Join(",", store.Events) ==
                "RECEIPT_READ,CANDIDATE_READ,ACTIVE_SCHEDULE_READ,INTERVIEW_SCHEDULE_UPDATE,CANDIDATE_UPDATE,STATUS_HISTORY_CREATE,RECEIPT_CREATE",
                action + " mutation order is schedule, Candidate, History, Receipt");
            var updates = store.ScheduleUpdates;
            var replay = store.Atomic(Request(input));
            Check(replay.Replay && replay.Current == expected && store.ScheduleUpdates == updates &&
                store.Histories == 1 && store.Receipts.Count == 1,
                action + " replay creates no duplicate result or history");
            input["ResultNotes"] = "Conflicting replay";
            Reject(() => store.Atomic(Request(input)), "CORRELATION_CONFLICT");
        }

        var rescheduleInput = Input("RequestReschedule");
        var rescheduleStore = new MemoryStore { Status = ActionRequest.Scheduled };
        var replacedSchedule = rescheduleStore.SeedActiveSchedule();
        var rescheduled = rescheduleStore.Atomic(Request(rescheduleInput));
        Check(rescheduled.Current == ActionRequest.NeedCall &&
            replacedSchedule.Status == ActionRequest.ScheduleSuperseded &&
            rescheduleStore.ProposedSchedule?.Status == ActionRequest.ScheduleProposed &&
            rescheduleStore.ActiveSchedule == null && rescheduleStore.Histories == 1 &&
            rescheduleStore.Receipts.Count == 1,
            "Reschedule preserves old schedule, creates Proposed replacement, and returns Candidate to Need Call");
        Check(string.Join(",", rescheduleStore.Events) ==
            "RECEIPT_READ,CANDIDATE_READ,ACTIVE_SCHEDULE_READ,PROPOSED_SCHEDULE_READ,INTERVIEW_SCHEDULE_UPDATE,INTERVIEW_SCHEDULE_READBACK,INTERVIEW_SCHEDULE_CREATE,INTERVIEW_SCHEDULE_READBACK,CANDIDATE_UPDATE,STATUS_HISTORY_CREATE,RECEIPT_CREATE",
            "Reschedule persists old and replacement schedule evidence before Candidate, History, and Receipt");
        var rescheduleUpdates = rescheduleStore.ScheduleUpdates;
        var rescheduleCreates = rescheduleStore.ScheduleCreates;
        Check(rescheduleStore.Atomic(Request(rescheduleInput)).Replay &&
            rescheduleStore.ScheduleUpdates == rescheduleUpdates &&
            rescheduleStore.ScheduleCreates == rescheduleCreates,
            "Reschedule identical replay creates no duplicate effects");
        rescheduleInput["Reason"] = "Conflicting replay";
        Reject(() => rescheduleStore.Atomic(Request(rescheduleInput)), "CORRELATION_CONFLICT");

        var cancelInput = Input("CancelRound1");
        var cancelStore = new MemoryStore { Status = ActionRequest.Scheduled };
        var cancelledSchedule = cancelStore.SeedActiveSchedule();
        var cancelled = cancelStore.Atomic(Request(cancelInput));
        Check(cancelled.Current == ActionRequest.NeedCall &&
            cancelledSchedule.Status == ActionRequest.ScheduleCancelled &&
            cancelStore.ActiveSchedule == null && cancelStore.Histories == 1 &&
            cancelStore.Receipts.Count == 1,
            "Cancel preserves cancelled schedule and returns Candidate to Need Call");
        Check(string.Join(",", cancelStore.Events) ==
            "RECEIPT_READ,CANDIDATE_READ,ACTIVE_SCHEDULE_READ,PROPOSED_SCHEDULE_READ,INTERVIEW_SCHEDULE_UPDATE,INTERVIEW_SCHEDULE_READBACK,CANDIDATE_UPDATE,STATUS_HISTORY_CREATE,RECEIPT_CREATE",
            "Cancel persists schedule evidence before Candidate, History, and Receipt");

        foreach (var action in new[] { "RequestReschedule", "CancelRound1" })
        {
            var missingSchedule = new MemoryStore { Status = ActionRequest.Scheduled };
            Reject(() => missingSchedule.Atomic(Request(Input(action))), "ACTIVE_SCHEDULE_REQUIRED");
            Check(missingSchedule.ScheduleUpdates == 0 && missingSchedule.ScheduleCreates == 0 &&
                missingSchedule.Updates == 0 && missingSchedule.Histories == 0,
                action + " requires active schedule evidence before mutation");

            var terminalSchedule = new MemoryStore { Status = ActionRequest.Scheduled };
            terminalSchedule.SeedActiveSchedule(ActionRequest.ResultFail);
            Reject(() => terminalSchedule.Atomic(Request(Input(action))),
                "SCHEDULE_RESULT_ALREADY_RECORDED");
            Check(terminalSchedule.ScheduleUpdates == 0 && terminalSchedule.ScheduleCreates == 0 &&
                terminalSchedule.Updates == 0 && terminalSchedule.Histories == 0,
                action + " rejects terminal schedule evidence before mutation");

            var ambiguousSchedules = new MemoryStore { Status = ActionRequest.Scheduled };
            ambiguousSchedules.SeedActiveSchedule();
            ambiguousSchedules.SeedProposedSchedule();
            Reject(() => ambiguousSchedules.Atomic(Request(Input(action))),
                "SCHEDULE_STATE_AMBIGUOUS");
            Check(ambiguousSchedules.ScheduleUpdates == 0 && ambiguousSchedules.ScheduleCreates == 0 &&
                ambiguousSchedules.Updates == 0 && ambiguousSchedules.Histories == 0,
                action + " rejects competing active/proposed evidence before mutation");
        }

        var completedScheduleStore = new MemoryStore { Status = ActionRequest.Scheduled };
        completedScheduleStore.SeedActiveSchedule(ActionRequest.ResultPass);
        Reject(() => completedScheduleStore.Atomic(Request(Input("RecordFail"))),
            "SCHEDULE_RESULT_ALREADY_RECORDED");
        Check(completedScheduleStore.ScheduleUpdates == 0 && completedScheduleStore.Histories == 0 &&
            completedScheduleStore.Status == ActionRequest.Scheduled,
            "Completed result schedule cannot receive a second result");
        var noScheduleStore = new MemoryStore { Status = ActionRequest.Scheduled };
        Reject(() => noScheduleStore.Atomic(Request(Input("RecordPass"))), "ACTIVE_SCHEDULE_REQUIRED");
        Check(noScheduleStore.ScheduleUpdates == 0 && noScheduleStore.Updates == 0 &&
            noScheduleStore.Histories == 0 && noScheduleStore.Receipts.Count == 0,
            "Result operation requires active Round 1 schedule evidence");
        var ambiguousScheduleStore = new MemoryStore { Status = ActionRequest.Scheduled, AmbiguousActiveSchedule = true };
        Reject(() => ambiguousScheduleStore.Atomic(Request(Input("RecordPass"))), "ACTIVE_SCHEDULE_REQUIRED");
        Check(ambiguousScheduleStore.ScheduleUpdates == 0 && ambiguousScheduleStore.Updates == 0,
            "Ambiguous active schedules fail closed before mutation");
        var invalid = Input("MarkRound1Scheduled"); invalid["StartAt"] = DateTime.SpecifyKind(Now, DateTimeKind.Local);
        Reject(() => Request(invalid), "INVALID_SCHEDULE_TIME");
        invalid = Input("CancelRound1"); invalid.Remove("Reason");
        Reject(() => Request(invalid), "REASON_REQUIRED");
        invalid = Input("MarkRound1Scheduled"); invalid["StartAt"] = Now.AddMinutes(-1);
        Reject(() => Request(invalid), "INVALID_SCHEDULE_TIME");
        invalid = Input("MarkRound1Scheduled"); invalid["EndAt"] = Now.AddDays(2);
        Reject(() => Request(invalid), "INVALID_SCHEDULE_TIME");
        invalid = Input("MarkRound1Scheduled"); invalid["ActionType"] = "UnsupportedOperation";
        Reject(() => Request(invalid), "INVALID_ACTION");
        invalid = Input("RecordCall"); invalid["EntityName"] = "account";
        Reject(() => Request(invalid), "UNEXPECTED_INPUT:ACTION_REQUEST:OTHER");
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
        Check(CandidateOperation.Transition("MarkRound1Scheduled", ActionRequest.Waiting, null) == ActionRequest.Scheduled,
            "Schedule transition requires a durable Round 1 evidence operation");
        foreach (var action in new[] { "RecordPass", "RecordFail", "RequestReschedule", "CancelRound1" })
        {
            Reject(() => CandidateOperation.Transition(action, ActionRequest.Waiting, null), "INVALID_TRANSITION");
            if (action == "RecordPass" || action == "RecordFail")
                Reject(() => CandidateOperation.Transition(action, ActionRequest.Scheduled, null), "RESULT_EVIDENCE_REQUIRED");
            else
                Check(CandidateOperation.Transition(action, ActionRequest.Scheduled, null) == ActionRequest.NeedCall,
                    action + " returns Candidate to Need Call Candidate");
        }
        foreach (var status in new[] { ActionRequest.Passed, ActionRequest.Failed, ActionRequest.Waiting })
            Reject(() => CandidateOperation.Transition("RecordCall", status, 100010000), "INVALID_TRANSITION");
        invalid = Input(); invalid["ExpectedStatus"] = ActionRequest.Answered;
        Reject(() => new MemoryStore().Atomic(Request(invalid)), "STALE_EXPECTED_STATUS");
        invalid = Input("MarkRound1Scheduled");
        Reject(() => new MemoryStore { Status = ActionRequest.Answered }.Atomic(Request(invalid)),
            "STALE_EXPECTED_STATUS");
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
        var createWithoutCandidateId = Request(Input("CreateCandidate", createCorrelation));
        Check(Request(new Dictionary<string, object?>(Input("CreateCandidate", createCorrelation))
        {
            ["CandidateId"] = null
        }).Fingerprint == createWithoutCandidateId.Fingerprint &&
            Request(new Dictionary<string, object?>(Input("CreateCandidate", createCorrelation))
            {
                ["CandidateId"] = Guid.Empty
            }).Fingerprint == createWithoutCandidateId.Fingerprint,
            "CreateCandidate absent, null, and empty CandidateId normalize identically");
        createWithNullCandidateId["CandidateId"] = Candidate;
        Reject(() => Request(createWithNullCandidateId), "UNEXPECTED_INPUT:ACTION_REQUEST:CandidateId");
        createWithNullCandidateId["CandidateId"] = "not-a-guid";
        Reject(() => Request(createWithNullCandidateId), "INVALID_CANDIDATEID");
        var createLookupCorrelation = Guid.NewGuid();
        var createWithoutLookups = Request(Input("CreateCandidate", createLookupCorrelation));
        foreach (string parameter in new[] { "PositionId", "CandidateSourceId", "AssignedTaId" })
        {
            foreach (object? emptyValue in new object?[] { null, Guid.Empty })
            {
                var inputWithEmptyLookup = Input("CreateCandidate", createLookupCorrelation);
                inputWithEmptyLookup[parameter] = emptyValue;
                var emptyLookup = Request(inputWithEmptyLookup);
                Check(!emptyLookup.Values.ContainsKey(parameter) &&
                    emptyLookup.Fingerprint == createWithoutLookups.Fingerprint,
                    "CreateCandidate optional " + parameter + " empty forms normalize to omission");
            }
            var validId = Guid.NewGuid();
            var inputWithLookup = Input("CreateCandidate", createLookupCorrelation);
            inputWithLookup[parameter] = validId;
            Check((Guid)Request(inputWithLookup).Values[parameter]! == validId,
                "CreateCandidate valid " + parameter + " is preserved");
            inputWithLookup[parameter] = "not-a-guid";
            Reject(() => Request(inputWithLookup), "INVALID_GUID_PARAMETER:" + parameter);
        }
        var updateWithNullLookup = Input("UpdateCandidate");
        updateWithNullLookup["ProfileFieldMask"] = "CandidateName,PositionId";
        updateWithNullLookup["PositionId"] = null;
        Check(Request(updateWithNullLookup).Values.ContainsKey("PositionId") &&
            Request(updateWithNullLookup).Values["PositionId"] == null,
            "UpdateCandidate explicit null lookup remains a clear operation");
        updateWithNullLookup["PositionId"] = Guid.Empty;
        Check(Request(updateWithNullLookup).Values.ContainsKey("PositionId") &&
            Request(updateWithNullLookup).Values["PositionId"] == null,
            "UpdateCandidate masked Guid.Empty lookup normalizes to a clear operation");
        updateWithNullLookup["PositionId"] = "not-a-guid";
        Reject(() => Request(updateWithNullLookup), "INVALID_GUID_PARAMETER:PositionId");
        foreach (string parameter in new[] { "PositionId", "CandidateSourceId", "AssignedTaId" })
        {
            var lookupClearCorrelation = Guid.NewGuid();
            var clearFingerprints = new List<string>();
            foreach (string representation in new[] { "omitted", "null", "empty" })
            {
                var maskedClearInput = Input("UpdateCandidate", lookupClearCorrelation);
                maskedClearInput["ProfileFieldMask"] = parameter;
                maskedClearInput.Remove("CandidateName");
                maskedClearInput.Remove("CandidateEmail");
                if (representation == "omitted") maskedClearInput.Remove(parameter);
                else maskedClearInput[parameter] = representation == "null" ? null : (object)Guid.Empty;
                var maskedClearRequest = Request(maskedClearInput);
                Check(maskedClearRequest.Values.ContainsKey(parameter) &&
                    maskedClearRequest.Values[parameter] == null &&
                    maskedClearRequest.ProfilePatch[parameter].IsSelected &&
                    maskedClearRequest.ProfilePatch[parameter].Value == null,
                    "UpdateCandidate masked " + representation + " " + parameter + " normalizes to clear");
                clearFingerprints.Add(maskedClearRequest.Fingerprint);
            }
            Check(clearFingerprints.Distinct(StringComparer.Ordinal).Count() == 1,
                "UpdateCandidate omitted, null, and Guid.Empty masked " + parameter + " share one fingerprint");
            var unmaskedEmptyInput = Input("UpdateCandidate", lookupClearCorrelation);
            unmaskedEmptyInput[parameter] = Guid.Empty;
            var unmaskedEmptyRequest = Request(unmaskedEmptyInput);
            Check(!unmaskedEmptyRequest.Values.ContainsKey(parameter) &&
                !unmaskedEmptyRequest.ProfilePatch[parameter].IsSelected &&
                unmaskedEmptyRequest.Fingerprint != clearFingerprints[0],
                "UpdateCandidate unmasked Guid.Empty " + parameter + " preserves and differs from masked clear");
            foreach (object malformed in new object[] { "not-a-guid", Guid.NewGuid().ToString("D"), 0, new object() })
            {
                var malformedInput = Input("UpdateCandidate");
                malformedInput["ProfileFieldMask"] = parameter;
                malformedInput.Remove("CandidateName");
                malformedInput.Remove("CandidateEmail");
                malformedInput[parameter] = malformed;
                Reject(() => Request(malformedInput), "INVALID_GUID_PARAMETER:" + parameter);
            }
        }
        updateWithNullLookup = Input("UpdateCandidate");
        updateWithNullLookup["ProfileFieldMask"] = "CandidateName,AssignedTaId";
        updateWithNullLookup["AssignedTaId"] = null;
        Check(Request(updateWithNullLookup).Values.ContainsKey("AssignedTaId") &&
            Request(updateWithNullLookup).Values["AssignedTaId"] == null,
            "UpdateCandidate explicit null AssignedTaId remains a clear operation");
        var missingProfileMask = Input("UpdateCandidate");
        missingProfileMask.Remove("ProfileFieldMask");
        Reject(() => Request(missingProfileMask), "PROFILE_FIELD_MASK_REQUIRED");
        foreach (var invalidMask in new object?[]
        {
            "", " ", "CandidateName,", "CandidateName, CandidatePhone",
            "CandidateName,CandidateName", "Name", new object()
        })
        {
            var invalidMaskInput = Input("UpdateCandidate");
            invalidMaskInput["ProfileFieldMask"] = invalidMask;
            Reject(() => Request(invalidMaskInput), "INVALID_PROFILE_FIELD_MASK");
        }
        var canonicalMaskInput = Input("UpdateCandidate");
        canonicalMaskInput["ProfileFieldMask"] = "AssignedTaId,CandidatePhone,CandidateName";
        canonicalMaskInput["CandidatePhone"] = "+15550101001";
        canonicalMaskInput["AssignedTaId"] = Guid.NewGuid();
        var canonicalMaskRequest = Request(canonicalMaskInput);
        Check(string.Equals((string?)canonicalMaskRequest.Values["ProfileFieldMask"],
            "CandidateName,CandidatePhone,AssignedTaId", StringComparison.Ordinal) &&
            Request(new Dictionary<string, object?>(canonicalMaskInput)
            {
                ["ProfileFieldMask"] = "CandidateName,CandidatePhone,AssignedTaId"
            }).Fingerprint == canonicalMaskRequest.Fingerprint,
            "UpdateCandidate mask whitelist is canonicalized before fingerprinting");
        var unmaskedDefaults = Input("UpdateCandidate");
        unmaskedDefaults["CandidateEmail"] = new object();
        unmaskedDefaults["CandidatePhone"] = Guid.Empty;
        var ignoredUnmaskedDefaults = Request(unmaskedDefaults);
        Check(!ignoredUnmaskedDefaults.Values.ContainsKey("CandidateEmail") &&
            !ignoredUnmaskedDefaults.Values.ContainsKey("CandidatePhone") &&
            !ignoredUnmaskedDefaults.ProfilePatch["CandidatePhone"].IsSelected &&
            ignoredUnmaskedDefaults.ProfilePatch["CandidatePhone"].IsSupplied,
            "UpdateCandidate ignores malformed and empty values outside the field mask");
        var missingOptionalValue = Input("UpdateCandidate");
        missingOptionalValue["ProfileFieldMask"] = "CandidatePhone";
        missingOptionalValue.Remove("CandidateName");
        missingOptionalValue.Remove("CandidateEmail");
        missingOptionalValue.Remove("CandidatePhone");
        var omittedOptionalRequest = Request(missingOptionalValue);
        Check(omittedOptionalRequest.ProfilePatch["CandidatePhone"].IsSelected &&
            !omittedOptionalRequest.ProfilePatch["CandidatePhone"].IsSupplied &&
            omittedOptionalRequest.ProfilePatch["CandidatePhone"].Value == null &&
            omittedOptionalRequest.Values.ContainsKey("CandidatePhone") &&
            omittedOptionalRequest.Values["CandidatePhone"] == null &&
            !omittedOptionalRequest.Values.ContainsKey("CandidateName") &&
            !omittedOptionalRequest.Values.ContainsKey("CandidateEmail"),
            "Masked omitted optional field is an explicit clear while unmasked required fields are preserved");
        var explicitNullOptional = new Dictionary<string, object?>(missingOptionalValue)
        {
            ["CandidatePhone"] = null
        };
        var explicitNullRequest = Request(explicitNullOptional);
        Check(explicitNullRequest.ProfilePatch["CandidatePhone"].IsSelected &&
            explicitNullRequest.ProfilePatch["CandidatePhone"].IsSupplied &&
            explicitNullRequest.ProfilePatch["CandidatePhone"].Value == null &&
            explicitNullRequest.Fingerprint == omittedOptionalRequest.Fingerprint,
            "Masked omission and explicit null have the same clear intent and fingerprint");
        var emptyOptional = new Dictionary<string, object?>(missingOptionalValue)
        {
            ["CandidatePhone"] = "   "
        };
        Check(Request(emptyOptional).Fingerprint == omittedOptionalRequest.Fingerprint,
            "Masked blank optional text normalizes to the same clear fingerprint");
        var omittedCvUrl = Input("UpdateCandidate");
        omittedCvUrl["ProfileFieldMask"] = "CandidateCvUrl";
        omittedCvUrl.Remove("CandidateName");
        omittedCvUrl.Remove("CandidateEmail");
        omittedCvUrl.Remove("CandidateCvUrl");
        var blankCvUrl = new Dictionary<string, object?>(omittedCvUrl)
        {
            ["CandidateCvUrl"] = " "
        };
        Check(Request(blankCvUrl).Fingerprint == Request(omittedCvUrl).Fingerprint,
            "Masked blank CV URL normalizes to the omitted-field clear fingerprint");
        var missingMaskedName = Input("UpdateCandidate");
        missingMaskedName["ProfileFieldMask"] = "CandidateName";
        missingMaskedName.Remove("CandidateName");
        Reject(() => Request(missingMaskedName), "REQUIRED_TEXT");
        var blankMaskedEmail = Input("UpdateCandidate");
        blankMaskedEmail["ProfileFieldMask"] = "CandidateEmail";
        blankMaskedEmail["CandidateEmail"] = "  ";
        Reject(() => Request(blankMaskedEmail), "REQUIRED_TEXT");
        var inapplicableMask = Input("CreateCandidate");
        inapplicableMask["ProfileFieldMask"] = "CandidatePhone";
        Reject(() => Request(inapplicableMask), "PROFILE_FIELD_MASK_NOT_APPLICABLE");
        foreach (string invalidCvUrl in new[]
        {
            "http://careers.example.invalid/cv",
            "https://user:password@careers.example.invalid/cv",
            "/candidate/cv"
        })
        {
            var invalidCvInput = Input("CreateCandidate");
            invalidCvInput["CandidateCvUrl"] = invalidCvUrl;
            Reject(() => Request(invalidCvInput), "INVALID_CV_URL");
        }
        var overlongCvInput = Input("CreateCandidate");
        overlongCvInput["CandidateCvUrl"] = "https://careers.example.invalid/" + new string('a', 2000);
        Reject(() => Request(overlongCvInput), "TEXT_TOO_LONG");
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
        invalid.Remove("Reason");
        Reject(() => Request(invalid), "REASON_REQUIRED");
        invalid = Input(); invalid["Actor"] = Guid.NewGuid();
        Reject(() => Request(invalid), "UNEXPECTED_INPUT:ACTION_REQUEST:OTHER");
        invalid = Input(); invalid["ContactedAt"] = Now.AddSeconds(1);
        Reject(() => Request(invalid), "INVALID_CONTACT_TIME");
        // Live RecordCall skew: ContactedAt was +160 ms after handler start and +82 ms after handler end.
        invalid = Input(); invalid["ContactedAt"] = Now.AddMilliseconds(160);
        Reject(() => Request(invalid), "INVALID_CONTACT_TIME");
        invalid = Input(); invalid["ContactedAt"] = Now.AddMilliseconds(82);
        Reject(() => Request(invalid), "INVALID_CONTACT_TIME");
        invalid = Input(); invalid["ContactedAt"] = Now.AddTicks(1);
        Reject(() => Request(invalid), "INVALID_CONTACT_TIME");
        Check(Request(Input()).Values["ContactedAt"] is DateTime equalContact && equalContact == Now &&
            equalContact.Kind == DateTimeKind.Utc, "ContactedAt equal to server UTC time is accepted unchanged");
        invalid = Input(); invalid["ContactedAt"] = DateTime.SpecifyKind(Now.AddMinutes(-1), DateTimeKind.Unspecified);
        Reject(() => Request(invalid), "INVALID_CONTACT_TIME");
        invalid = Input(); invalid["ContactedAt"] = DateTime.SpecifyKind(Now.AddMinutes(-1), DateTimeKind.Local);
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
        ordered["ProfileFieldMask"] = "CandidateName,CandidatePhone";
        ordered["CandidatePhone"] = "+15550101000";
        var reversed = ordered.Reverse().ToDictionary(x => x.Key, x => x.Value);
        Check(Request(ordered).Fingerprint == Request(reversed).Fingerprint, "Canonical input order");
        reversed["CandidatePhone"] = null;
        Check(Request(ordered).Fingerprint != Request(reversed).Fingerprint,
            "Setting an optional field differs from clearing it");
        var omittedPhone = new Dictionary<string, object?>(ordered);
        omittedPhone.Remove("CandidatePhone");
        Check(Request(omittedPhone).Fingerprint == Request(reversed).Fingerprint,
            "Masked omission and explicit null clear fingerprints match");
        var preservedPhone = Input("UpdateCandidate");
        preservedPhone["CandidatePhone"] = "+15550101000";
        Check(Request(preservedPhone).Fingerprint != Request(omittedPhone).Fingerprint,
            "Unmasked preservation differs from masked omission clear");
        var vectorId = Guid.Parse("00000000-0000-0000-0000-000000000004");
        var vector = Input("UpdateCandidate", vectorId);
        Check(Request(vector).Fingerprint == "8fd2f364aa2547776970aae88501e24893f5cbd20cace81005d73381a4988ccc",
            "Update fingerprint golden vector: " + Request(vector).Fingerprint);
        vector["CandidateName"] = "  Synthetic Replacement  ";
        Check(Request(vector).Fingerprint == "8fd2f364aa2547776970aae88501e24893f5cbd20cace81005d73381a4988ccc",
            "Trimmed equivalent request golden vector: " + Request(vector).Fingerprint);
        vector["ProfileFieldMask"] = "CandidateName,CandidatePhone";
        vector["CandidatePhone"] = null;
        Check(Request(vector).Fingerprint == "1f7e4c1efdc6dca185bb479c5002f59e9407f5786ae2dc779e2b10c819ab1887",
            "Explicit null fingerprint golden vector: " + Request(vector).Fingerprint);
        vector["CandidatePhone"] = "";
        Check(Request(vector).Fingerprint == "1f7e4c1efdc6dca185bb479c5002f59e9407f5786ae2dc779e2b10c819ab1887",
            "Empty string normalizes to the explicit-null clear fingerprint");
        var legacyReceiptInput = Input("UpdateCandidate", Guid.NewGuid());
        var legacyReceiptRequest = Request(legacyReceiptInput);
        var legacyReceipt = new Receipt
        {
            Action = "UpdateCandidate",
            Fingerprint = legacyReceiptRequest.LegacyFingerprint,
            Version = "1",
            Result = new ActionResult
            {
                CandidateId = Candidate,
                Previous = ActionRequest.NeedCall,
                Current = ActionRequest.NeedCall
            }
        };
        var legacyReceiptStore = new MemoryStore();
        legacyReceiptStore.Receipts[legacyReceiptInput["CorrelationId"] is Guid legacyCorrelation
            ? legacyCorrelation : throw new Exception("Expected correlation")] = legacyReceipt;
        var legacyReplay = legacyReceiptStore.Atomic(legacyReceiptRequest);
        Check(legacyReplay.Replay && legacyReceiptStore.Updates == 0 &&
            legacyReceipt.Fingerprint == legacyReceiptRequest.LegacyFingerprint &&
            legacyReceiptStore.Events.SequenceEqual(new[] { "RECEIPT_READ", "CANDIDATE_READ" }),
            "Maskless UpdateCandidate receipt replays through legacy fingerprint without rewriting receipt");
        var changedLegacyRequestInput = Input("UpdateCandidate", legacyReceiptRequest.Correlation);
        changedLegacyRequestInput["ProfileFieldMask"] = "CandidateName,CandidatePhone";
        changedLegacyRequestInput["CandidatePhone"] = null;
        Reject(() => legacyReceiptStore.Atomic(Request(changedLegacyRequestInput)), "CORRELATION_CONFLICT");
        var phoneCvReceiptInput = Input("UpdateCandidate", Guid.NewGuid());
        phoneCvReceiptInput["ProfileFieldMask"] = "CandidatePhone,CandidateCvUrl";
        phoneCvReceiptInput.Remove("CandidateName");
        phoneCvReceiptInput["CandidatePhone"] = "+15550101011";
        phoneCvReceiptInput["CandidateCvUrl"] = "https://careers.example.invalid/cv/legacy";
        var phoneCvReceiptRequest = Request(phoneCvReceiptInput);
        var phoneCvReceipt = new Receipt
        {
            Action = "UpdateCandidate",
            Fingerprint = phoneCvReceiptRequest.LegacyFingerprint,
            Version = "1",
            Result = new ActionResult
            {
                CandidateId = Candidate,
                Previous = ActionRequest.NeedCall,
                Current = ActionRequest.NeedCall
            }
        };
        var phoneCvReceiptStore = new MemoryStore();
        phoneCvReceiptStore.Receipts[phoneCvReceiptRequest.Correlation] = phoneCvReceipt;
        var phoneCvReplay = phoneCvReceiptStore.Atomic(phoneCvReceiptRequest);
        Check(phoneCvReplay.Replay && phoneCvReceiptStore.Updates == 0 &&
            phoneCvReceipt.Fingerprint == phoneCvReceiptRequest.LegacyFingerprint,
            "Historical Phone/CV maskless receipt replays without rewriting or updating Candidate");
        var preserveReceiptInput = Input("UpdateCandidate", Guid.NewGuid());
        var preserveReceiptRequest = Request(preserveReceiptInput);
        var clearSameCorrelationInput = new Dictionary<string, object?>(preserveReceiptInput)
        {
            ["ProfileFieldMask"] = "CandidateName,AssignedTaId"
        };
        clearSameCorrelationInput.Remove("AssignedTaId");
        var preserveReceiptStore = new MemoryStore();
        preserveReceiptStore.Receipts[preserveReceiptRequest.Correlation] = new Receipt
        {
            Action = "UpdateCandidate",
            Fingerprint = preserveReceiptRequest.LegacyFingerprint,
            Version = "1",
            Result = new ActionResult
            {
                CandidateId = Candidate,
                Previous = ActionRequest.NeedCall,
                Current = ActionRequest.NeedCall
            }
        };
        Reject(() => preserveReceiptStore.Atomic(Request(clearSameCorrelationInput)), "CORRELATION_CONFLICT");
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
        public int Status = ActionRequest.NeedCall, Calls, Histories, Updates, Creates,
            ScheduleCreates, ScheduleUpdates, Version = 1, FailMutation, Mutation;
        public bool Audit, StaleVersion, CandidateExists = true, HideReceiptOnce, AmbiguousActiveSchedule;
        public Dictionary<Guid, Receipt> Receipts = new();
        public InterviewScheduleState? ActiveSchedule;
        public InterviewScheduleState? ProposedSchedule;
        public List<InterviewScheduleState> HistoricalSchedules = new();
        public List<string> Events = new();
        void Mutate() { if (++Mutation == FailMutation) throw new OperationError("SYNTHETIC_MUTATION_FAILURE"); }
        public ActionResult Atomic(ActionRequest request)
        {
            Events.Clear();
            var before = (Status, Calls, Histories, Updates, Creates, ScheduleCreates, ScheduleUpdates, Version, Mutation,
                new Dictionary<Guid, Receipt>(Receipts),
                ActiveSchedule == null ? null : Copy(ActiveSchedule),
                ProposedSchedule == null ? null : Copy(ProposedSchedule),
                HistoricalSchedules.Select(Copy).ToList());
            try { return CandidateOperation.Execute(request, this); }
            catch
            {
                (Status, Calls, Histories, Updates, Creates, ScheduleCreates, ScheduleUpdates, Version, Mutation,
                    Receipts, ActiveSchedule, ProposedSchedule, HistoricalSchedules) = before;
                throw;
            }
        }
        static InterviewScheduleState Copy(InterviewScheduleState value) => new()
        {
            Id = value.Id, CandidateId = value.CandidateId,
            InterviewerId = value.InterviewerId, LocationId = value.LocationId,
            StartAt = value.StartAt, EndAt = value.EndAt, Notes = value.Notes,
            Reason = value.Reason, ChangedAt = value.ChangedAt,
            Status = value.Status, Result = value.Result, RowVersion = value.RowVersion
        };
        public InterviewScheduleState SeedActiveSchedule(int? result = ActionRequest.ResultPending)
        {
            var schedule = new InterviewScheduleState
            {
                Id = Guid.NewGuid(), CandidateId = Candidate,
                InterviewerId = Guid.Parse("00000000-0000-0000-0000-000000000003"),
                LocationId = Guid.Parse("00000000-0000-0000-0000-000000000004"),
                StartAt = Now.AddDays(1), EndAt = Now.AddDays(1).AddHours(1),
                Status = ActionRequest.ScheduleActive,
                Result = result, RowVersion = "1"
            };
            ActiveSchedule = schedule;
            return schedule;
        }
        public InterviewScheduleState SeedProposedSchedule()
        {
            var schedule = new InterviewScheduleState
            {
                Id = Guid.NewGuid(), CandidateId = Candidate,
                InterviewerId = Guid.Parse("00000000-0000-0000-0000-000000000003"),
                LocationId = Guid.Parse("00000000-0000-0000-0000-000000000004"),
                StartAt = Now.AddDays(1), EndAt = Now.AddDays(1).AddHours(1),
                Status = ActionRequest.ScheduleProposed,
                Result = ActionRequest.ResultPending, RowVersion = "1"
            };
            ProposedSchedule = schedule;
            return schedule;
        }
        public void RequireTransaction() { }
        public Receipt? FindReceipt(Guid correlation)
        {
            Events.Add("RECEIPT_READ");
            // Model a losing transaction that read before the winning receipt committed.
            if (HideReceiptOnce) { HideReceiptOnce = false; return null; }
            return Receipts.GetValueOrDefault(correlation);
        }
        public CandidateState GetCandidate(Guid id)
        {
            Events.Add("CANDIDATE_READ");
            if (!CandidateExists || id != Candidate) throw new OperationError("INVALID_CANDIDATE");
            return new CandidateState { Id = id, Status = Status, RowVersion = Version.ToString() };
        }
        public Guid CreateCandidate(ActionRequest request) { Events.Add("CANDIDATE_CREATE"); Mutate(); Creates++; return Candidate; }
        public void UpdateCandidate(ActionRequest request, CandidateState candidate, int status)
        {
            Events.Add("CANDIDATE_UPDATE");
            if (StaleVersion) throw new OperationError("ROW_VERSION_CONFLICT");
            Mutate(); Updates++; Status = status; Version++;
        }
        public Guid CreateCall(ActionRequest request, Guid candidate) { Events.Add("CALL_LOG_CREATE"); Mutate(); Calls++; return Guid.NewGuid(); }
        public Guid CreateHistory(ActionRequest request, Guid candidate, int previous, int current) { Events.Add("STATUS_HISTORY_CREATE"); Mutate(); Histories++; return Guid.NewGuid(); }
        public InterviewScheduleState? GetCurrentRound1Schedule(Guid candidateId)
        {
            Events.Add("ACTIVE_SCHEDULE_READ");
            if (AmbiguousActiveSchedule) throw new OperationError("ACTIVE_SCHEDULE_REQUIRED");
            return ActiveSchedule == null ? null : Copy(ActiveSchedule);
        }
        public InterviewScheduleState? GetProposedRound1Schedule(Guid candidateId)
        {
            Events.Add("PROPOSED_SCHEDULE_READ");
            return ProposedSchedule == null ? null : Copy(ProposedSchedule);
        }
        public InterviewScheduleState CreateRound1Schedule(
            ActionRequest request, Guid candidateId, int scheduleStatus)
        {
            Events.Add("INTERVIEW_SCHEDULE_CREATE"); Mutate(); ScheduleCreates++;
            var schedule = new InterviewScheduleState
            {
                Id = Guid.NewGuid(), CandidateId = candidateId,
                InterviewerId = (Guid)request.Values["InterviewerId"]!,
                LocationId = (Guid)request.Values["LocationId"]!,
                StartAt = (DateTime)request.Values["StartAt"]!,
                EndAt = (DateTime)request.Values["EndAt"]!,
                Notes = request.Values.TryGetValue("Notes", out var notes) ? (string?)notes ?? "" : "",
                Status = scheduleStatus, Result = ActionRequest.ResultPending,
                RowVersion = "1"
            };
            if (scheduleStatus == ActionRequest.ScheduleActive) ActiveSchedule = schedule;
            else ProposedSchedule = schedule;
            Events.Add("INTERVIEW_SCHEDULE_READBACK");
            return Copy(schedule);
        }
        public InterviewScheduleState UpdateRound1Schedule(
            ActionRequest request, InterviewScheduleState schedule, int scheduleStatus)
        {
            Events.Add("INTERVIEW_SCHEDULE_UPDATE"); Mutate(); ScheduleUpdates++;
            InterviewScheduleState? target;
            if (ProposedSchedule?.Id == schedule.Id) target = ProposedSchedule;
            else if (ActiveSchedule?.Id == schedule.Id) target = ActiveSchedule;
            else throw new OperationError("ACTIVE_SCHEDULE_REQUIRED");

            if (request.Action == "MarkRound1Scheduled")
            {
                target.Status = scheduleStatus;
                target.InterviewerId = (Guid)request.Values["InterviewerId"]!;
                target.LocationId = (Guid)request.Values["LocationId"]!;
                target.StartAt = (DateTime)request.Values["StartAt"]!;
                target.EndAt = (DateTime)request.Values["EndAt"]!;
                if (request.Values.TryGetValue("Notes", out var notes))
                    target.Notes = (string?)notes ?? "";
                ProposedSchedule = null;
                ActiveSchedule = target;
            }
            else
            {
                target.Status = scheduleStatus;
                target.Reason = (string)request.Values["Reason"]!;
                target.ChangedAt = Now;
                HistoricalSchedules.Add(target);
                ActiveSchedule = null;
            }
            Events.Add("INTERVIEW_SCHEDULE_READBACK");
            return Copy(target);
        }
        public void RecordRound1Result(ActionRequest request, InterviewScheduleState schedule, int result)
        {
            if (string.IsNullOrEmpty(schedule.RowVersion)) throw new OperationError("ROW_VERSION_UNAVAILABLE");
            Events.Add("INTERVIEW_SCHEDULE_UPDATE"); Mutate(); ScheduleUpdates++;
            if (ActiveSchedule == null || ActiveSchedule.Id != schedule.Id)
                throw new OperationError("ACTIVE_SCHEDULE_REQUIRED");
            ActiveSchedule.Result = result;
        }
        public void CreateReceipt(ActionRequest request, ActionResult result)
        {
            Events.Add("RECEIPT_CREATE");
            Mutate();
            if (!Receipts.TryAdd(request.Correlation, new Receipt { Action = request.Action,
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
