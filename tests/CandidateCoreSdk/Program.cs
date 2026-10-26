using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;
using System.ServiceModel;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Query;
using os_sr_cact;

internal static class Program
{
    private static int passed;
    private static readonly Guid Actor = Guid.Parse("00000000-0000-0000-0000-000000000001");
    private static readonly Guid Candidate = Guid.Parse("00000000-0000-0000-0000-000000000002");
    private static readonly Guid Organization = Guid.Parse("00000000-0000-0000-0000-000000000003");
    private static readonly Dictionary<Guid, Entity> Registrations = new Dictionary<Guid, Entity>();
    private static int registrationReads;
    private static EntityReference RegisterImplementation()
    {
        var package = new Entity("pluginpackage", Guid.NewGuid())
        {
            ["name"] = "os_sr_cact_pkg", ["uniquename"] = "os_sr_cact_pkg", ["version"] = "1.0.0"
        };
        var assembly = new Entity("pluginassembly", Guid.NewGuid())
        {
            ["name"] = "os_sr_cact", ["version"] = "1.0.0.0", ["packageid"] = package.ToEntityReference()
        };
        var type = new Entity("plugintype", Guid.NewGuid())
        {
            ["typename"] = "os_sr_cact.ApplyCandidateAction", ["pluginassemblyid"] = assembly.ToEntityReference()
        };
        var step = new Entity("sdkmessageprocessingstep", Guid.NewGuid()) { ["eventhandler"] = type.ToEntityReference() };
        foreach (var row in new[] { step, type, assembly, package }) Registrations.Add(row.Id, row);
        return step.ToEntityReference();
    }
    private static IOrganizationServiceFactory RegistrationFactory() => Proxy<IOrganizationServiceFactory>(call =>
    {
        if ((Guid?)call.Args[0] != Actor) throw new Exception("Registration reads elevated identity");
        return Proxy<IOrganizationService>(request =>
        {
            if (request.MethodName != "Retrieve") throw new Exception("Unexpected registration write/read");
            registrationReads++;
            if (!Registrations.TryGetValue((Guid)request.Args[1], out var row))
                throw new FaultException<OrganizationServiceFault>(new OrganizationServiceFault { Message = "SENSITIVE_SENTINEL" });
            if (row.LogicalName != (string)request.Args[0]) throw new Exception("Registration logical type mismatch");
            return row;
        });
    });

    private static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL: " + name);
        passed++;
    }
    private static string Reject(Action action, string code)
    {
        try { action(); throw new Exception("Expected rejection: " + code); }
        catch (InvalidPluginExecutionException error)
        {
            Check(error.Message == code, "Expected " + code + ", received " + error.Message);
            return error.Message;
        }
    }
    private static Dictionary<string, object?> Context(ParameterCollection input, ParameterCollection shared, ParameterCollection output)
    {
        return new Dictionary<string, object?>
        {
            ["MessageName"] = "os_sr_cact", ["Stage"] = 30, ["Mode"] = 0, ["IsInTransaction"] = true,
            ["Depth"] = 1, ["UserId"] = Actor, ["InitiatingUserId"] = Actor, ["OrganizationId"] = Organization,
            ["InputParameters"] = input, ["OutputParameters"] = output, ["SharedVariables"] = shared,
            ["ParentContext"] = null, ["OwningExtension"] = RegisterImplementation()
        };
    }
    private static T Proxy<T>(Func<IMethodCallMessage, object?> call) => (T)new DynamicProxy(typeof(T), call).GetTransparentProxy();
    private static IPluginExecutionContext Execution(Dictionary<string, object?> values) =>
        Proxy<IPluginExecutionContext>(call => values[call.MethodName.Substring(4)]);

    private static void Main()
    {
        var actionWriteMatrix = new Dictionary<string, string[]>
        {
            ["CreateCandidate"] = new[] { "CANDIDATE_CREATE", "RECEIPT_CREATE" },
            ["UpdateCandidate"] = new[] { "CANDIDATE_UPDATE", "RECEIPT_CREATE" },
            ["RecordCall"] = new[] { "CANDIDATE_UPDATE", "CALL_LOG_CREATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" },
            ["ProceedToScheduling"] = new[] { "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" },
            ["MarkRound1Scheduled"] = Array.Empty<string>(),
            ["RecordPass"] = Array.Empty<string>(),
            ["RecordFail"] = Array.Empty<string>(),
            ["RequestReschedule"] = Array.Empty<string>()
        };
        var protectedWrites = new[]
        {
            (Message: "Create", Table: "os_sr_cand", Code: "CANDIDATE_CREATE"),
            (Message: "Update", Table: "os_sr_cand", Code: "CANDIDATE_UPDATE"),
            (Message: "Create", Table: "os_sr_call", Code: "CALL_LOG_CREATE"),
            (Message: "Create", Table: "os_sr_csh", Code: "STATUS_HISTORY_CREATE"),
            (Message: "Create", Table: "os_sr_oprc", Code: "RECEIPT_CREATE")
        };
        foreach (var pair in actionWriteMatrix)
        {
            foreach (var write in protectedWrites)
            {
                var target = new Entity(write.Table, Guid.NewGuid());
                var parent = CreateTrustedParent(pair.Key, write.Message, target, 1, includeMarker: false);
                if (pair.Value.Contains(write.Code))
                {
                    ExecuteGuard(write.Message, target, parent);
                    Check(true, "Canonical action/write allow: " + pair.Key + ":" + write.Code);
                }
                else RejectDirectGuard(write.Message, target, parent,
                    "DIRECT_WRITE_GUARD_REJECTED:" + write.Code + ":TRUSTED_PARENT:ACTIONTYPE_MISMATCH");
                RejectDirectGuard(write.Message, target, null,
                    "DIRECT_WRITE_GUARD_REJECTED:" + write.Code + ":PARENT_CONTEXT");
            }
            var actionIndex = Array.IndexOf(actionWriteMatrix.Keys.ToArray(), pair.Key);
            var actionCode = new[] { "CREATE_CANDIDATE", "UPDATE_CANDIDATE", "RECORD_CALL",
                "PROCEED_TO_SCHEDULING", "MARK_ROUND1_SCHEDULED", "RECORD_PASS", "RECORD_FAIL", "REQUEST_RESCHEDULE" }[actionIndex];
            foreach (var unsupported in new[] { ("Update", "os_sr_oprc", "RECEIPT_UPDATE"),
                ("Delete", "os_sr_cand", "OTHER_PROTECTED_WRITE"),
                ("Upsert", "os_sr_oprc", "OTHER_PROTECTED_WRITE"),
                ("Update", "os_sr_call", "OTHER_PROTECTED_WRITE"),
                ("Update", "os_sr_csh", "OTHER_PROTECTED_WRITE") })
            {
                var target = new Entity(unsupported.Item2, Guid.NewGuid());
                RejectDirectGuard(unsupported.Item1, target,
                    CreateTrustedParent(pair.Key, unsupported.Item1, target, 1),
                    "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:" + actionCode + ":" + unsupported.Item3);
            }
        }
        var unsupportedFault = CreateCandidateHost();
        unsupportedFault.FaultOnCreateTable = "os_sr_cand";
        unsupportedFault.FaultErrorCode = unchecked((int)0x80040265);
        unsupportedFault.FaultMessage = "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:CREATE_CANDIDATE:OTHER_PROTECTED_WRITE";
        Reject(() => new ApplyCandidateAction().Execute(unsupportedFault),
            unsupportedFault.FaultMessage + ":CC_CREATE_CANDIDATE:0x80040265");
        var unknownWriteTarget = new Entity("os_sr_oprc", Guid.NewGuid());
        var unknownActionParent = CreateGuardParent("os_sr_cact",
            new ParameterCollection { ["ActionType"] = "SENSITIVE_SENTINEL " + Actor.ToString("D") },
            new ParameterCollection());
        RejectDirectGuard("Upsert", unknownWriteTarget, Execution(unknownActionParent),
            "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:UNKNOWN_ACTION:OTHER_PROTECTED_WRITE");
        RejectDirectGuard("Update", unknownWriteTarget,
            CreateTrustedParent("CreateCandidate", "Update", unknownWriteTarget, 9),
            "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:UNKNOWN_ACTION:RECEIPT_UPDATE");
        var createWithoutOptionalGuids = CreateCandidateHost();
        new ApplyCandidateAction().Execute(createWithoutOptionalGuids);
        Check(createWithoutOptionalGuids.CreatedCandidates == 1 &&
            !createWithoutOptionalGuids.CreatedCandidate!.Contains("os_sr_cand_pos") &&
            !createWithoutOptionalGuids.CreatedCandidate.Contains("os_sr_cand_csrc") &&
            (int)createWithoutOptionalGuids.Output["CurrentStatus"] == ActionRequest.NeedCall &&
            createWithoutOptionalGuids.Calls == 0 && createWithoutOptionalGuids.Histories == 0 &&
            createWithoutOptionalGuids.Receipt != null,
            "SDK CreateCandidate omits optional GUIDs and uses server-controlled initial status");
        Check(createWithoutOptionalGuids.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand", "Create:os_sr_oprc" }) &&
            createWithoutOptionalGuids.TraceMessages.Where(message => message.StartsWith("CC_STAGE:", StringComparison.Ordinal))
                .SequenceEqual(new[] { "CC_STAGE:CC_READ_RECEIPT", "CC_STAGE:CC_CREATE_CANDIDATE", "CC_STAGE:CC_CREATE_RECEIPT" }),
            "SDK CreateCandidate service-operation sequence and stage markers are exact");
        Check(createWithoutOptionalGuids.TraceMessages.Contains("CC_GUARD_ALLOWED:CANDIDATE_CREATE") &&
            createWithoutOptionalGuids.TraceMessages.Contains("CC_GUARD_ALLOWED:RECEIPT_CREATE"),
            "Approved package-backed Custom API parent context satisfies Candidate and Receipt guard rules");
        Check(!createWithoutOptionalGuids.Shared.Contains(GetGuardIntentKey()) &&
            createWithoutOptionalGuids.Receipt!.Attributes.Keys.All(name => name != GetGuardIntentKey()) &&
            createWithoutOptionalGuids.Output.Keys.All(name => name != GetGuardIntentKey()) &&
            !createWithoutOptionalGuids.TraceMessages.Any(message => message.Contains(GetGuardIntentKey())) &&
            createWithoutOptionalGuids.MarkersAtProtectedWrites.Count == 2 &&
            createWithoutOptionalGuids.MarkersAtProtectedWrites.All(marker => marker.Length == 64) &&
            createWithoutOptionalGuids.MarkersAtProtectedWrites.All(marker =>
                !createWithoutOptionalGuids.TraceMessages.Any(message => message.Contains(marker)) &&
                !createWithoutOptionalGuids.Receipt.Attributes.Values.OfType<string>().Contains(marker) &&
                !createWithoutOptionalGuids.Output.Values.OfType<string>().Contains(marker)),
            "Private mutation marker is removed and never persisted, returned, or traced");
        Check(createWithoutOptionalGuids.TraceMessages.Contains("CC_GUARD_TRUSTED_PARENT_FOUND:ANCESTOR_HOPS:1"),
            "Trusted parent trace contains only the safe ancestor-hop category");
        var packageApiParent = CreateCandidateHost();
        new ApplyCandidateAction().Execute(packageApiParent);
        Check(packageApiParent.CreatedCandidates == 1 && packageApiParent.Receipt != null &&
            packageApiParent.TraceMessages.Contains("CC_GUARD_ALLOWED:CANDIDATE_CREATE"),
            "Package-backed ApplyCandidateAction server registration is accepted");
        var legacyApiParent = CreateCandidateHost();
        var legacyStep = Registrations[((EntityReference)legacyApiParent.MainValues["OwningExtension"]!).Id];
        var legacyType = Registrations[legacyStep.GetAttributeValue<EntityReference>("eventhandler").Id];
        Registrations[legacyType.GetAttributeValue<EntityReference>("pluginassemblyid").Id].Attributes.Remove("packageid");
        Reject(() => new ApplyCandidateAction().Execute(legacyApiParent),
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:PACKAGE_MISMATCH:CC_CREATE_CANDIDATE");
        Check(legacyApiParent.CreatedCandidates == 0, "Legacy handler requires matching guard rollback");
        var candidateCreateFault = CreateCandidateHost();
        candidateCreateFault.FaultOnCreateTable = "os_sr_cand";
        candidateCreateFault.FaultMessage = "SENSITIVE_SENTINEL " + Actor.ToString("D");
        var candidateFaultMessage = Reject(() => new ApplyCandidateAction().Execute(candidateCreateFault),
            "DATAVERSE_OPERATION_REJECTED:CC_CREATE_CANDIDATE:0x80040220");
        Check(candidateCreateFault.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand" }) &&
            candidateCreateFault.Receipt == null,
            "Candidate Create fault terminates before Receipt Create");
        Check(candidateCreateFault.TraceMessages.Contains("CC_STAGE:CC_CREATE_CANDIDATE") &&
            candidateCreateFault.TraceMessages.Contains("CC_SERVICE_FAULT:CC_CREATE_CANDIDATE:0x80040220") &&
            !candidateCreateFault.TraceMessages.Any(message => message.Contains("SENSITIVE_SENTINEL")),
            "Candidate Create fault diagnostics contain stage and code only");
        var receiptCreateFault = CreateCandidateHost();
        receiptCreateFault.FaultOnCreateTable = "os_sr_oprc";
        receiptCreateFault.FaultErrorCode = unchecked((int)0x80040221);
        var receiptFaultMessage = Reject(() => new ApplyCandidateAction().Execute(receiptCreateFault),
            "DATAVERSE_OPERATION_REJECTED:CC_CREATE_RECEIPT:0x80040221");
        Check(receiptCreateFault.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand", "Create:os_sr_oprc" }),
            "Receipt Create fault terminates after the failing final service operation");
        Check(receiptCreateFault.TraceMessages.Contains("CC_STAGE:CC_CREATE_RECEIPT") &&
            receiptCreateFault.TraceMessages.Contains("CC_SERVICE_FAULT:CC_CREATE_RECEIPT:0x80040221"),
            "Receipt Create fault reports its distinct safe stage and code");
        var legacyGuardFault = CreateCandidateHost();
        legacyGuardFault.FaultOnCreateTable = "os_sr_cand";
        legacyGuardFault.FaultErrorCode = unchecked((int)0x80040265);
        legacyGuardFault.FaultMessage = "DIRECT_CANDIDATE_CORE_WRITE_BLOCKED";
        var legacyGuardMessage = Reject(() => new ApplyCandidateAction().Execute(legacyGuardFault),
            "DIRECT_WRITE_GUARD_REJECTED:LEGACY_GENERIC_GUARD:CC_CREATE_CANDIDATE:0x80040265");
        Check(legacyGuardFault.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand" }) &&
            !legacyGuardMessage.Contains("DIRECT_CANDIDATE_CORE_WRITE_BLOCKED"),
            "Legacy guard fault is classified by safe category without exposing its raw message");
        var tamperedCreate = CreateCandidateHost();
        tamperedCreate.TamperTarget = true;
        tamperedCreate.MainValues["OwningExtension"] = null;
        var guardMessage = Reject(() => new ApplyCandidateAction().Execute(tamperedCreate),
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:OWNING_EXTENSION_MISSING:CC_CREATE_CANDIDATE");
        Check(tamperedCreate.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand" }) &&
            tamperedCreate.TraceMessages.Contains("CC_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:OWNING_EXTENSION_MISSING"),
            "Guard registration rejection is categorized and stops before Receipt Create");
        Check(!candidateFaultMessage.Contains("SENSITIVE_SENTINEL") &&
            !candidateFaultMessage.Contains(Actor.ToString("D")) &&
            !receiptFaultMessage.Contains("SENSITIVE_SENTINEL") &&
            !legacyGuardMessage.Contains("SENSITIVE_SENTINEL") &&
            !guardMessage.Contains("SENSITIVE_SENTINEL") &&
            !guardMessage.Contains(Actor.ToString("D")),
            "Returned service-fault diagnostics exclude message content and IDs");
        var unknownFailure = CreateCandidateHost();
        unknownFailure.UnknownFailureOnCreateTable = "os_sr_cand";
        var unknownFailureMessage = Reject(() => new ApplyCandidateAction().Execute(unknownFailure),
            "CANDIDATE_CORE_FAILURE:CC_CREATE_CANDIDATE:INVALID_OPERATION");
        Check(unknownFailure.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand" }) &&
            !unknownFailureMessage.Contains("SENSITIVE_SENTINEL"),
            "Unknown service exception is categorized, sanitized, and terminates immediately");
        var minimalCreate = CreateCandidateHost();
        minimalCreate.Input.Remove("ExpectedStatus");
        minimalCreate.Input["CandidatePhone"] = "5550100";
        var saturatedCreate = CreateCandidateHost();
        saturatedCreate.Input["CorrelationId"] = minimalCreate.Input["CorrelationId"];
        saturatedCreate.Input["CandidateId"] = Guid.NewGuid();
        saturatedCreate.Input["ExpectedStatus"] = new OptionSetValue(0);
        saturatedCreate.Input["CandidatePhone"] = "5550100";
        saturatedCreate.Input["PositionId"] = Guid.Empty;
        saturatedCreate.Input["CandidateSourceId"] = Guid.Empty;
        saturatedCreate.Input["CallOutcome"] = new OptionSetValue(0);
        saturatedCreate.Input["ContactedAt"] = DateTime.MinValue;
        saturatedCreate.Input["Notes"] = null;
        saturatedCreate.Input["Reason"] = string.Empty;
        Check(minimalCreate.Input.Count == 5 && saturatedCreate.Input.Count == 13,
            "SDK CreateCandidate minimal and saturated parameter sets have expected shapes");
        new ApplyCandidateAction().Execute(minimalCreate);
        new ApplyCandidateAction().Execute(saturatedCreate);
        Check(minimalCreate.CreatedCandidates == 1 && saturatedCreate.CreatedCandidates == 1 &&
            saturatedCreate.CreatedCandidate!.GetAttributeValue<string>("os_sr_cand_phn") == "5550100" &&
            !saturatedCreate.CreatedCandidate.Contains("os_sr_cand_pos") &&
            !saturatedCreate.CreatedCandidate.Contains("os_sr_cand_csrc"),
            "SDK CreateCandidate projects applicable profile inputs and ignores non-applicable defaults");
        Check(minimalCreate.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash") ==
            saturatedCreate.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash"),
            "SDK saturated CreateCandidate fingerprint equals its minimal applicable-input fingerprint");
        foreach (string parameter in new[] { "PositionId", "CandidateSourceId" })
        {
            foreach (object? absentEquivalent in new object?[] { null, Guid.Empty })
            {
                var host = CreateCandidateHost();
                host.Input[parameter] = absentEquivalent;
                new ApplyCandidateAction().Execute(host);
                string attribute = parameter == "PositionId" ? "os_sr_cand_pos" : "os_sr_cand_csrc";
                Check(host.CreatedCandidates == 1 && !host.CreatedCandidate!.Contains(attribute),
                    "SDK CreateCandidate normalizes " + parameter + " absent-equivalent to no lookup");
            }
            var validHost = CreateCandidateHost();
            var lookupId = Guid.NewGuid();
            validHost.Input[parameter] = lookupId;
            new ApplyCandidateAction().Execute(validHost);
            string validAttribute = parameter == "PositionId" ? "os_sr_cand_pos" : "os_sr_cand_csrc";
            var reference = validHost.CreatedCandidate!.GetAttributeValue<EntityReference>(validAttribute);
            Check(reference != null && reference.Id == lookupId &&
                reference.LogicalName == (parameter == "PositionId" ? "os_sr_pos" : "os_sr_csrc"),
                "SDK CreateCandidate preserves valid " + parameter + " reference");

            var invalidHost = CreateCandidateHost();
            invalidHost.Input[parameter] = "not-a-guid";
            Reject(() => new ApplyCandidateAction().Execute(invalidHost), "INVALID_GUID_PARAMETER:" + parameter);
            Check(invalidHost.CreatedCandidates == 0 && invalidHost.Receipt == null,
                "SDK invalid " + parameter + " rejected before any create");
        }
        var createWithNullCandidateId = CreateCandidateHost();
        createWithNullCandidateId.Input["CandidateId"] = null;
        new ApplyCandidateAction().Execute(createWithNullCandidateId);
        Check(createWithNullCandidateId.CreatedCandidates == 1, "SDK CreateCandidate accepts null CandidateId");
        var createWithEmptyCandidateId = CreateCandidateHost();
        createWithEmptyCandidateId.Input["CandidateId"] = Guid.Empty;
        new ApplyCandidateAction().Execute(createWithEmptyCandidateId);
        Check(createWithEmptyCandidateId.CreatedCandidates == 1, "SDK CreateCandidate accepts empty CandidateId");
        var malformedCandidateId = CreateCandidateHost();
        malformedCandidateId.Input["CandidateId"] = "not-a-guid";
        new ApplyCandidateAction().Execute(malformedCandidateId);
        Check(malformedCandidateId.CreatedCandidates == 1,
            "SDK CreateCandidate does not parse its non-applicable CandidateId input");

        var createInput = new Dictionary<string, object?>
        {
            ["ActionType"] = "CreateCandidate",
            ["CorrelationId"] = Guid.NewGuid(),
            ["CandidateName"] = "Synthetic Candidate",
            ["CandidateEmail"] = "synthetic@example.invalid",
            ["ExpectedStatus"] = new OptionSetValue(100010000)
        };
        var createRequest = new ActionRequest(Actor, createInput, DateTime.UtcNow);
        Check(!createRequest.ExpectedStatus.HasValue &&
            !createRequest.Values.ContainsKey("ExpectedStatus"),
            "CreateCandidate ignores SDK OptionSetValue ExpectedStatus representation");
        foreach (int outcome in new[] { 100010000, 100010001, 100010002 })
        {
            var host = new Host(outcome);
            new ApplyCandidateAction().Execute(host);
            if (outcome == 100010000)
            {
                var stageMarkers = host.TraceMessages.Where(message => message.StartsWith("CC_STAGE:", StringComparison.Ordinal)).ToArray();
                Check(stageMarkers.SequenceEqual(new[]
                    {
                        "CC_STAGE:CC_READ_RECEIPT", "CC_STAGE:CC_READ_CANDIDATE", "CC_STAGE:CC_UPDATE_CANDIDATE",
                        "CC_STAGE:CC_CREATE_CALL_LOG", "CC_STAGE:CC_CREATE_STATUS_HISTORY", "CC_STAGE:CC_CREATE_RECEIPT"
                    }) && stageMarkers.Distinct(StringComparer.Ordinal).Count() == stageMarkers.Length,
                    "Each Answered transition service operation has a distinct safe stage marker");
            }
            Check(host.Calls == 1 && host.Histories == (outcome == 100010000 ? 1 : 0), "SDK exact call/history effects");
            Check(host.Updates == (outcome == 100010000 ? 1 : 0), "SDK non-answer log only");
            Check(host.Receipt != null && host.Receipt.GetAttributeValue<EntityReference>("ownerid").Id == Actor, "SDK receipt caller owner");
            Check(host.Receipt != null && host.Receipt.Attributes.Keys.All(name => !name.Contains("email") && !name.Contains("notes")), "SDK receipt minimization");
            new ApplyCandidateAction().Execute(host);
            Check((string)host.Output["ResultCode"] == "DuplicateReplay" && host.Calls == 1, "SDK persisted replay");
            Check(host.CallerFactorySelections.All(id => id == Actor), "SDK no service elevation");
            Check(host.CandidateRequests.All(request => request.ConcurrencyBehavior == ConcurrencyBehavior.IfRowVersionMatches), "SDK conditional updates");
        }
        var auditPending = new Host(100010000) { OrganizationAuditEnabled = false };
        new ApplyCandidateAction().Execute(auditPending);
        Check(auditPending.Calls == 1 && auditPending.Updates == 1 && auditPending.Receipt != null,
            "SDK organization audit state does not block operation evidence");
        Check(auditPending.OrganizationReads == 0, "SDK does not query organization audit state");
        var validUpdate = new Host(100010000);
        validUpdate.Input["ActionType"] = "UpdateCandidate";
        validUpdate.Input["CandidateName"] = "Synthetic Replacement";
        validUpdate.Input.Remove("CallOutcome");
        validUpdate.Input.Remove("ContactedAt");
        validUpdate.Input.Remove("ExpectedStatus");
        validUpdate.Input["ExpectedStatus"] = ActionRequest.NeedCall;
        new ApplyCandidateAction().Execute(validUpdate);
        Check(validUpdate.Updates == 1 && validUpdate.CandidateRequests.Count == 1,
            "SDK UpdateCandidate accepts matching ExpectedStatus");
        var staleUpdate = new Host(100010000) { Status = ActionRequest.Answered };
        staleUpdate.Input["ActionType"] = "UpdateCandidate";
        staleUpdate.Input["CandidateName"] = "Synthetic Replacement";
        staleUpdate.Input.Remove("CallOutcome");
        staleUpdate.Input.Remove("ContactedAt");
        Reject(() => new ApplyCandidateAction().Execute(staleUpdate), "STALE_EXPECTED_STATUS");
        Check(staleUpdate.Updates == 0 && staleUpdate.Receipt == null,
            "SDK UpdateCandidate rejects stale ExpectedStatus without mutation");
        foreach (string property in new[] { "IsInTransaction", "Depth", "UserId" })
        {
            var host = new Host(100010000);
            host.MainValues[property] = property == "IsInTransaction" ? (object)false : property == "Depth" ? 2 : (object)Guid.Empty;
            Reject(() => new ApplyCandidateAction().Execute(host), "UNSUPPORTED_EXECUTION_CONTEXT");
        }
        var malicious = new Host(100010000);
        malicious.Input["Actor"] = Guid.NewGuid();
        Reject(() => new ApplyCandidateAction().Execute(malicious), "UNEXPECTED_INPUT:SDK_ADAPTER:OTHER");
        var unknownAction = new Host(100010000);
        unknownAction.Input["ActionType"] = "UnsupportedOperation";
        unknownAction.Input["Actor"] = Guid.NewGuid();
        Reject(() => new ApplyCandidateAction().Execute(unknownAction), "INVALID_ACTION");
        foreach (var directWrite in new[]
        {
            (Message: "Create", Table: "os_sr_cand", Category: "CANDIDATE_CREATE"),
            (Message: "Update", Table: "os_sr_cand", Category: "CANDIDATE_UPDATE"),
            (Message: "Create", Table: "os_sr_call", Category: "CALL_LOG_CREATE"),
            (Message: "Create", Table: "os_sr_csh", Category: "STATUS_HISTORY_CREATE"),
            (Message: "Create", Table: "os_sr_oprc", Category: "RECEIPT_CREATE")
        })
        {
            RejectDirectGuard(directWrite.Message, new Entity(directWrite.Table, Guid.NewGuid()), null,
                "DIRECT_WRITE_GUARD_REJECTED:" + directWrite.Category + ":PARENT_CONTEXT");
        }
        var candidateTarget = new Entity("os_sr_cand", Guid.NewGuid())
        {
            ["os_sr_cand_stat"] = new OptionSetValue(ActionRequest.NeedCall)
        };
        foreach (var predicate in new[] { "API_MESSAGE_MISMATCH", "STAGE_MISMATCH", "MODE_MISMATCH",
            "TRANSACTION_MISMATCH", "DEPTH_MISMATCH", "USER_CONTEXT_MISMATCH", "INITIATING_USER_MISMATCH",
            "ACTIONTYPE_MISSING", "ACTIONTYPE_MISMATCH", "MARKER_MISSING", "MARKER_TYPE_MISMATCH",
            "MARKER_FINGERPRINT_MISMATCH", "ANCESTOR_BOUND_EXCEEDED", "OWNING_EXTENSION_MISSING",
            "OWNING_EXTENSION_TYPE_MISMATCH", "HANDLER_TYPE_MISMATCH", "ASSEMBLY_MISMATCH",
            "PACKAGE_MISMATCH", "REGISTRATION_READ_FAILED" })
        {
            var host = CreateCandidateHost();
            host.FaultOnCreateTable = "os_sr_cand";
            host.FaultErrorCode = unchecked((int)0x80040265);
            host.FaultMessage = "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:" + predicate;
            Reject(() => new ApplyCandidateAction().Execute(host),
                host.FaultMessage + ":CC_CREATE_CANDIDATE:0x80040265");
        }
        var intentKey = GetGuardIntentKey();
        var validIntent = GetGuardIntent("Create", candidateTarget);
        foreach (var failure in new[] { "OWNING_EXTENSION_MISSING", "OWNING_EXTENSION_TYPE_MISMATCH",
            "HANDLER_TYPE_MISMATCH", "ASSEMBLY_MISMATCH", "PACKAGE_MISMATCH", "REGISTRATION_READ_FAILED" })
        {
            var values = CreateGuardParent("os_sr_cact",
                new ParameterCollection { ["ActionType"] = "CreateCandidate" }, new ParameterCollection());
            var extension = (EntityReference)values["OwningExtension"]!;
            var step = Registrations[extension.Id];
            var type = Registrations[step.GetAttributeValue<EntityReference>("eventhandler").Id];
            var assembly = Registrations[type.GetAttributeValue<EntityReference>("pluginassemblyid").Id];
            if (failure == "OWNING_EXTENSION_MISSING") values["OwningExtension"] = null;
            if (failure == "OWNING_EXTENSION_TYPE_MISMATCH")
                values["OwningExtension"] = new EntityReference("plugintype", extension.Id);
            if (failure == "HANDLER_TYPE_MISMATCH") type["typename"] = "synthetic.UnrelatedPlugin";
            if (failure == "ASSEMBLY_MISMATCH") assembly["name"] = "synthetic_legacy";
            if (failure == "PACKAGE_MISMATCH") assembly.Attributes.Remove("packageid");
            if (failure == "REGISTRATION_READ_FAILED") Registrations.Remove(extension.Id);
            RejectDirectGuard("Create", candidateTarget, Execution(values),
                "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:" + failure);
            // Negative decisions are not cached: correcting the server fixture must take effect immediately.
            if (failure == "HANDLER_TYPE_MISMATCH")
            {
                type["typename"] = "os_sr_cact.ApplyCandidateAction";
                ExecuteGuard("Create", candidateTarget, Execution(values));
                Check(true, "Negative registration result is not cached");
            }
        }
        foreach (var mutation in new (string Property, object Value, string Predicate)[]
        {
            ("MessageName", "unrelated_api", "API_MESSAGE_MISMATCH"),
            ("Stage", 20, "STAGE_MISMATCH"),
            ("Mode", 1, "MODE_MISMATCH"),
            ("IsInTransaction", false, "TRANSACTION_MISMATCH"),
            ("Depth", 0, "DEPTH_MISMATCH"),
            ("Depth", 2, "DEPTH_MISMATCH"),
            ("UserId", Guid.NewGuid(), "USER_CONTEXT_MISMATCH"),
            ("InitiatingUserId", Guid.NewGuid(), "INITIATING_USER_MISMATCH"),
            ("InputParameters", new ParameterCollection(), "ACTIONTYPE_MISSING"),
            ("InputParameters", new ParameterCollection { ["ActionType"] = "UnsupportedOperation" }, "ACTIONTYPE_MISMATCH"),
            ("InputParameters", new ParameterCollection { ["ActionType"] = 42 }, "ACTIONTYPE_MISMATCH")
        })
        {
            var values = CreateGuardParent("os_sr_cact",
                new ParameterCollection { ["ActionType"] = "CreateCandidate" },
                new ParameterCollection { [intentKey] = validIntent });
            values[mutation.Property] = mutation.Value;
            Reject(() => ExecuteGuard("Create", candidateTarget, Execution(values), childDepth: 2),
                "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:" + mutation.Predicate);
        }
        var unrelatedParent = CreateGuardParent("Update",
            new ParameterCollection { ["ActionType"] = "CreateCandidate" },
            new ParameterCollection { [intentKey] = validIntent });
        unrelatedParent["OwningExtension"] = new Entity("plugintype",
            Guid.Parse("00000000-0000-0000-0000-000000000202"));
        RejectDirectGuard("Create", candidateTarget, Execution(unrelatedParent),
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:API_MESSAGE_MISMATCH");

        var trustedParent = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 1);
        ExecuteGuard("Create", candidateTarget, trustedParent);
        Check(true, "Trusted Candidate Create marker one ancestor up is accepted");
        var reads = registrationReads;
        ExecuteGuard("Create", candidateTarget, trustedParent);
        Check(registrationReads == reads, "Positive registration cache avoids repeated reads");
        var cacheField = typeof(ProtectCandidateCore).GetField("RegistrationCache", BindingFlags.Static | BindingFlags.NonPublic)!;
        var cache = (Dictionary<Tuple<Guid, Guid, Guid>, DateTime>)cacheField.GetValue(null)!;
        cache[Tuple.Create(Organization, Actor, trustedParent.OwningExtension.Id)] = DateTime.UtcNow.AddSeconds(-1);
        ExecuteGuard("Create", candidateTarget, trustedParent);
        Check(registrationReads == reads + 4, "Expired positive cache revalidates all four registration records");
        var trustedGrandparent = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 2);
        ExecuteGuard("Create", candidateTarget, trustedGrandparent);
        Check(true, "Trusted Candidate Create marker two ancestors up is accepted");
        ExecuteGuard("Create", candidateTarget,
            CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 8));
        Check(true, "Trusted ancestor at the traversal bound is accepted");

        var wrongMessageParent = CreateTrustedParent("CreateCandidate", "unrelated_operation",
            candidateTarget, 1);
        ExecuteGuard("Create", candidateTarget, wrongMessageParent);
        Check(true, "Historical marker fingerprint is not authorization");
        var missingMarkerParent = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 1,
            includeMarker: false);
        ExecuteGuard("Create", candidateTarget, missingMarkerParent);
        Check(true, "Live depth one parent depth two child with missing marker is accepted");
        var wrongMarkerParent = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 1,
            markerValue: "not-the-current-target-intent");
        ExecuteGuard("Create", candidateTarget, wrongMarkerParent);
        Check(true, "Wrong marker value cannot change verified ancestor trust");
        var malformedMarkerParent = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 1,
            markerValue: new byte[] { 1, 2, 3 });
        ExecuteGuard("Create", candidateTarget, malformedMarkerParent);
        Check(true, "Malformed non-authoritative marker cannot change verified ancestor trust");
        var actionMismatchParent = CreateTrustedParent("RecordCall", "Create", candidateTarget, 1);
        RejectDirectGuard("Create", candidateTarget, actionMismatchParent,
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:ACTIONTYPE_MISMATCH");

        var externalTag = new ParameterCollection { ["tag"] = validIntent };
        RejectDirectGuard("Create", candidateTarget, null,
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:PARENT_CONTEXT", externalTag);
        var injectedPrivateKey = new ParameterCollection { [intentKey] = validIntent };
        RejectDirectGuard("Create", candidateTarget, null,
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:PARENT_CONTEXT", injectedPrivateKey);
        var tagWithUntrustedParent = new ParameterCollection { ["tag"] = validIntent };
        RejectDirectGuard("Create", candidateTarget, Execution(unrelatedParent),
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:API_MESSAGE_MISMATCH", tagWithUntrustedParent);

        var receiptTarget = new Entity("os_sr_oprc", Guid.NewGuid());
        ExecuteGuard("Create", receiptTarget, CreateTrustedParent("CreateCandidate", "Create", receiptTarget, 1));
        Check(true, "Operation Receipt child write is accepted only under a trusted CreateCandidate");
        RejectDirectGuard("Update", receiptTarget, CreateTrustedParent("CreateCandidate", "Update", receiptTarget, 1),
            "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:CREATE_CANDIDATE:RECEIPT_UPDATE");
        Check(true, "Operation Receipts remain append-only; no receipt update path is introduced");
        var callTarget = new Entity("os_sr_call", Guid.NewGuid());
        ExecuteGuard("Create", callTarget, CreateTrustedParent("RecordCall", "Create", callTarget, 1));
        Check(true, "Call Log child write is accepted only under a trusted RecordCall");
        var historyTarget = new Entity("os_sr_csh", Guid.NewGuid());
        ExecuteGuard("Create", historyTarget, CreateTrustedParent("ProceedToScheduling", "Create", historyTarget, 2));
        Check(true, "Status History child write is accepted under a trusted scheduling transition");
        var answerUpdate = new Entity("os_sr_cand", Guid.NewGuid());
        ExecuteGuard("Update", answerUpdate, CreateTrustedParent("RecordCall", "Update", answerUpdate, 1));
        Check(true, "Candidate Answered update is accepted only under a trusted RecordCall");

        var excessiveChain = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 9);
        RejectDirectGuard("Create", candidateTarget, excessiveChain,
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:ANCESTOR_BOUND_EXCEEDED");
        Check(GetMaximumParentContexts() == 8,
            "ParentContext traversal is bounded at eight contexts and fails closed beyond the bound");

        foreach (string table in new[] { "os_sr_cand", "os_sr_call", "os_sr_csh", "os_sr_oprc" })
        {
            var host = new Host(100010000);
            Reject(() => host.Guard("Delete", new Entity(table, Candidate), host.MainContext),
                "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:RECORD_CALL:OTHER_PROTECTED_WRITE");
            Reject(() => host.Guard("UpdateMultiple", new Entity(table, Candidate), host.MainContext),
                "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:RECORD_CALL:OTHER_PROTECTED_WRITE");
        }
        var changed = new Host(100010000) { TamperTarget = true };
        changed.MainValues["OwningExtension"] = null;
        Reject(() => new ApplyCandidateAction().Execute(changed),
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_UPDATE:TRUSTED_PARENT:OWNING_EXTENSION_MISSING:CC_UPDATE_CANDIDATE");
        Check(changed.Calls == 0, "SDK unverified parent rejected before storage");
        foreach (string message in new[] { "Associate", "Disassociate" })
        {
            var values = Context(new ParameterCollection
            {
                ["Target"] = new EntityReference("systemuser", Actor),
                ["Relationship"] = new Relationship("OS_SR_USR_CSH_ACTR")
            }, new ParameterCollection(), new ParameterCollection());
            values["MessageName"] = message;
            Reject(() => new ProtectCandidateCore().Execute(new ContextProvider(Execution(values), Proxy<ITracingService>(call => null))),
                "DIRECT_WRITE_GUARD_REJECTED:ASSOCIATION_PROJECT_RELATIONSHIP");
            values["InputParameters"] = new ParameterCollection
            {
                ["Target"] = new EntityReference("account", Guid.NewGuid()),
                ["Relationship"] = new Relationship("synthetic_unrelated_relationship")
            };
            new ProtectCandidateCore().Execute(new ContextProvider(Execution(values), Proxy<ITracingService>(call => null)));
            Check(true, "Unrelated association is no-op");
        }
        Console.WriteLine("PASS: " + passed + " offline SDK adapter/guard assertions; dynamic synthetic SDK contexts and service, no authentication/network.");
    }

    private static Host CreateCandidateHost()
    {
        var host = new Host(100010000, true);
        host.Input["ExpectedStatus"] = new OptionSetValue(ActionRequest.NeedCall);
        return host;
    }

    private static Dictionary<string, object?> CreateGuardParent(
        string message, ParameterCollection input, ParameterCollection shared, int depth = 1)
    {
        var values = Context(input, shared, new ParameterCollection());
        values["MessageName"] = message;
        values["Depth"] = depth;
        return values;
    }

    private static IPluginExecutionContext CreateTrustedParent(
        string action, string markerMessage, Entity target, int hops,
        bool includeMarker = true, object? markerValue = null)
    {
        var shared = new ParameterCollection();
        if (includeMarker)
            shared[GetGuardIntentKey()] = markerValue ?? GetGuardIntent(markerMessage, target);
        var root = CreateGuardParent("os_sr_cact", new ParameterCollection { ["ActionType"] = action }, shared);
        IPluginExecutionContext parent = Execution(root);
        for (int depth = 2; depth <= hops; depth++)
        {
            var intermediate = CreateGuardParent("Create", new ParameterCollection(), new ParameterCollection(), depth);
            intermediate["ParentContext"] = parent;
            parent = Execution(intermediate);
        }
        return parent;
    }

    private static string GetGuardIntent(string message, Entity target)
    {
        var method = typeof(ProtectCandidateCore).GetMethod("Intent", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new Exception("Guard intent method is unavailable.");
        return (string)(method.Invoke(null, new object[] { message, target })
            ?? throw new Exception("Guard intent method returned no value."));
    }

    private static string GetGuardIntentKey()
    {
        var field = typeof(ProtectCandidateCore).GetField("IntentKey", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new Exception("Guard intent key is unavailable.");
        return (string)(field.GetValue(null) ?? throw new Exception("Guard intent key is empty."));
    }

    private static int GetMaximumParentContexts()
    {
        var field = typeof(ProtectCandidateCore).GetField("MaximumParentContexts",
            BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new Exception("ParentContext search bound is unavailable.");
        return (int)(field.GetRawConstantValue() ?? throw new Exception("ParentContext search bound is empty."));
    }

    private static void RejectDirectGuard(
        string message, Entity target, IPluginExecutionContext? parent, string expected,
        ParameterCollection? shared = null)
    {
        Reject(() => ExecuteGuard(message, target, parent, shared), expected);
    }

    private static void ExecuteGuard(
        string message, Entity target, IPluginExecutionContext? parent, ParameterCollection? shared = null,
        int? childDepth = null)
    {
        var child = Context(new ParameterCollection { ["Target"] = target },
            shared ?? new ParameterCollection(), new ParameterCollection());
        child["MessageName"] = message;
        child["Stage"] = 10;
        child["Depth"] = childDepth ?? (parent == null ? 1 : parent.Depth + 1);
        child["PrimaryEntityName"] = target.LogicalName;
        child["OwningExtension"] = new Entity("plugintype", Guid.Parse("00000000-0000-0000-0000-000000000201"));
        child["ParentContext"] = parent;
        new ProtectCandidateCore().Execute(new ContextProvider(Execution(child),
            Proxy<ITracingService>(call => null)));
    }

    private sealed class Host : IServiceProvider
    {
        public ParameterCollection Input = new ParameterCollection(), Output = new ParameterCollection(), Shared = new ParameterCollection();
        public Dictionary<string, object?> MainValues;
        public IPluginExecutionContext MainContext;
        public Entity? Receipt, CreatedCandidate;
        public int Calls, Histories, Updates, CreatedCandidates, OrganizationReads, Status = 100010000;
        public bool OrganizationAuditEnabled = true, TamperTarget;
        public List<Guid?> CallerFactorySelections = new List<Guid?>();
        public List<UpdateRequest> CandidateRequests = new List<UpdateRequest>();
        public List<string> ServiceOperations = new List<string>();
        public List<string> TraceMessages = new List<string>();
        public List<string> MarkersAtProtectedWrites = new List<string>();
        public string? FaultOnCreateTable;
        public string? UnknownFailureOnCreateTable;
        public string FaultMessage = "Synthetic service failure.";
        public int FaultErrorCode = unchecked((int)0x80040220);
        public Host(int outcome, bool createCandidate = false)
        {
            Input["ActionType"] = createCandidate ? "CreateCandidate" : "RecordCall";
            Input["CorrelationId"] = Guid.NewGuid();
            if (createCandidate)
            {
                Input["CandidateName"] = "Synthetic Candidate";
                Input["CandidateEmail"] = "synthetic@example.invalid";
            }
            else
            {
                Input["CandidateId"] = Candidate;
                Input["ExpectedStatus"] = 100010000;
                Input["CallOutcome"] = outcome;
                Input["ContactedAt"] = DateTime.UtcNow.AddMinutes(-1);
            }
            MainValues = Context(Input, Shared, Output);
            MainContext = Execution(MainValues);
        }
        public object GetService(Type serviceType)
        {
            if (serviceType == typeof(IPluginExecutionContext)) return MainContext;
            if (serviceType == typeof(ITracingService)) return CreateTracingService();
            if (serviceType == typeof(IOrganizationServiceFactory))
                return Proxy<IOrganizationServiceFactory>(call =>
                {
                    CallerFactorySelections.Add((Guid?)call.Args[0]);
                    return Proxy<IOrganizationService>(InvokeService);
                });
            throw new Exception("Unexpected service " + serviceType.Name);
        }
        public void Guard(string message, Entity target, IPluginExecutionContext? parent)
        {
            var child = Context(new ParameterCollection { ["Target"] = target }, new ParameterCollection(), new ParameterCollection());
            child["MessageName"] = message; child["Stage"] = 10; child["ParentContext"] = parent;
            child["Depth"] = parent == null ? 1 : parent.Depth + 1;
            child["PrimaryEntityName"] = target.LogicalName;
            child["OwningExtension"] = new Entity("plugintype", Guid.Parse("00000000-0000-0000-0000-000000000201"));
            new ProtectCandidateCore().Execute(new ContextProvider(Execution(child), CreateTracingService()));
        }
        private object? InvokeService(IMethodCallMessage call)
        {
            if (call.MethodName == "Retrieve")
            {
                var table = (string)call.Args[0];
                ServiceOperations.Add("Retrieve:" + table);
                if (table == "organization")
                {
                    OrganizationReads++;
                    return new Entity(table, Organization) { ["isauditenabled"] = OrganizationAuditEnabled };
                }
                if (table == "os_sr_cand") return new Entity(table, Candidate) { RowVersion = "1", ["os_sr_cand_stat"] = new OptionSetValue(Status) };
                throw new Exception("Unexpected Retrieve");
            }
            if (call.MethodName == "RetrieveMultiple")
            {
                ServiceOperations.Add("RetrieveMultiple:" + ((QueryExpression)call.Args[0]).EntityName);
                Check(((QueryExpression)call.Args[0]).EntityName == "os_sr_oprc", "SDK query receipt only");
                return Receipt == null ? new EntityCollection() : new EntityCollection(new List<Entity> { Receipt });
            }
            if (call.MethodName == "Create")
            {
                var row = (Entity)call.Args[0];
                ServiceOperations.Add("Create:" + row.LogicalName);
                if (Shared.TryGetValue(GetGuardIntentKey(), out var marker) && marker is string markerValue)
                    MarkersAtProtectedWrites.Add(markerValue);
                row[row.LogicalName + "id"] = row.Id;
                if (TamperTarget) row["unexpected"] = "synthetic";
                Guard("Create", row, MainContext);
                if (row.LogicalName == FaultOnCreateTable)
                    throw new FaultException<OrganizationServiceFault>(
                        new OrganizationServiceFault { ErrorCode = FaultErrorCode, Message = FaultMessage },
                        new FaultReason("Synthetic service fault"));
                if (row.LogicalName == UnknownFailureOnCreateTable)
                    throw new InvalidOperationException("SENSITIVE_SENTINEL " + Actor.ToString("D"));
                if (row.LogicalName == "os_sr_call") { Calls++; Check(row.GetAttributeValue<EntityReference>("os_sr_call_ctby").Id == Actor, "SDK Contacted By"); }
                else if (row.LogicalName == "os_sr_csh") { Histories++; Check(row.GetAttributeValue<EntityReference>("os_sr_csh_actr").Id == Actor, "SDK History Actor"); }
                else if (row.LogicalName == "os_sr_cand") { CreatedCandidates++; CreatedCandidate = row; }
                else if (row.LogicalName == "os_sr_oprc") { Receipt = row; Receipt["createdby"] = new EntityReference("systemuser", Actor); }
                else throw new Exception("Unexpected Create");
                return row.Id;
            }
            if (call.MethodName == "Execute")
            {
                var request = (UpdateRequest)call.Args[0];
                ServiceOperations.Add("Execute:Update:" + request.Target.LogicalName);
                if (Shared.TryGetValue(GetGuardIntentKey(), out var marker) && marker is string markerValue)
                    MarkersAtProtectedWrites.Add(markerValue);
                if (TamperTarget) request.Target["unexpected"] = "synthetic";
                Guard("Update", request.Target, MainContext);
                CandidateRequests.Add(request); Updates++;
                if (request.Target.Contains("os_sr_cand_stat")) Status = request.Target.GetAttributeValue<OptionSetValue>("os_sr_cand_stat").Value;
                return new UpdateResponse();
            }
            throw new Exception("Unexpected service method " + call.MethodName);
        }

        private ITracingService CreateTracingService() => Proxy<ITracingService>(call =>
        {
            if (call.MethodName == "Trace")
            {
                var format = (string)call.Args[0];
                var arguments = call.Args.Length > 1 && call.Args[1] is object[] values
                    ? values
                    : call.Args.Skip(1).ToArray();
                TraceMessages.Add(string.Format(System.Globalization.CultureInfo.InvariantCulture, format, arguments));
            }
            return null;
        });
    }
    private sealed class ContextProvider : IServiceProvider
    {
        private readonly IPluginExecutionContext context;
        private readonly ITracingService trace;
        public ContextProvider(IPluginExecutionContext context, ITracingService trace)
        {
            this.context = context;
            this.trace = trace;
        }
        public object GetService(Type type) => type == typeof(IPluginExecutionContext) ? context :
            type == typeof(ITracingService) ? trace :
            type == typeof(IOrganizationServiceFactory) ? RegistrationFactory() : throw new Exception("Unexpected service");
    }
    private sealed class DynamicProxy : RealProxy
    {
        private readonly Func<IMethodCallMessage, object?> invoke;
        public DynamicProxy(Type type, Func<IMethodCallMessage, object?> invoke) : base(type) { this.invoke = invoke; }
        public override IMessage Invoke(IMessage msg)
        {
            var call = (IMethodCallMessage)msg;
            try { return new ReturnMessage(invoke(call), null, 0, call.LogicalCallContext, call); }
            catch (Exception error) { return new ReturnMessage(error, call); }
        }
    }
}
