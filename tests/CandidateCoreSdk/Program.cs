using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;
using System.ServiceModel;
using Microsoft.Crm.Sdk.Messages;
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
    private static readonly Guid SystemActor = Guid.NewGuid();
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
    private static EntityReference RegisterGuard(
        string messageName, string? entityName, bool active = true,
        string handlerType = "os_sr_cact.ProtectCandidateCore", bool packageBacked = true)
    {
        var package = new Entity("pluginpackage", Guid.NewGuid())
        {
            ["name"] = packageBacked ? "os_sr_cact_pkg" : "synthetic_other_pkg",
            ["uniquename"] = packageBacked ? "os_sr_cact_pkg" : "synthetic_other_pkg",
            ["version"] = "1.0.0"
        };
        var assembly = new Entity("pluginassembly", Guid.NewGuid())
        {
            ["name"] = "os_sr_cact", ["version"] = "1.0.0.0",
            ["packageid"] = package.ToEntityReference()
        };
        var type = new Entity("plugintype", Guid.NewGuid())
        {
            ["typename"] = handlerType, ["pluginassemblyid"] = assembly.ToEntityReference()
        };
        var message = new Entity("sdkmessage", Guid.NewGuid()) { ["name"] = messageName };
        var step = new Entity("sdkmessageprocessingstep", Guid.NewGuid())
        {
            ["statecode"] = new OptionSetValue(active ? 0 : 1),
            ["eventhandler"] = type.ToEntityReference(),
            ["sdkmessageid"] = message.ToEntityReference()
        };
        if (entityName != null)
        {
            var filter = new Entity("sdkmessagefilter", Guid.NewGuid())
            {
                ["primaryobjecttypecode"] = entityName,
                ["sdkmessageid"] = message.ToEntityReference()
            };
            step["sdkmessagefilterid"] = filter.ToEntityReference();
            Registrations.Add(filter.Id, filter);
        }
        foreach (var row in new[] { step, type, assembly, package, message }) Registrations.Add(row.Id, row);
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
    private static void ConfigureDevHost(Host host)
    {
        host.MainValues["MessageName"] = "os_sr_devcs";
        host.MainValues["PrimaryEntityName"] = null;
        host.MainValues["OrganizationId"] = Guid.Parse("0706072c-54ea-f011-872b-000d3ab60060");
        host.Input["CorrelationId"] = Guid.NewGuid().ToString("D");
    }
    private static void SetDevRecordCall(Host host, Guid candidateId, int expectedStatus, int outcome)
    {
        host.Input.Clear();
        host.Input["ActionType"] = "RecordCall";
        host.Input["CorrelationId"] = Guid.NewGuid().ToString("D");
        host.Input["CandidateId"] = candidateId.ToString("D");
        host.Input["ExpectedStatus"] = expectedStatus;
        host.Input["CallOutcome"] = outcome;
        host.Input["ContactedAt"] = DateTime.UtcNow.ToString("o");
        host.Input["Notes"] = "Synthetic SDK test";
    }
    private static void SetScheduleAction(Host host, string action, int expectedStatus)
    {
        host.Input.Clear();
        host.Input["ActionType"] = action;
        host.Input["CorrelationId"] = Guid.NewGuid();
        host.Input["CandidateId"] = Candidate;
        host.Input["ExpectedStatus"] = expectedStatus;
        if (action != "CancelRound1")
        {
            host.Input["InterviewerId"] = Guid.Parse("00000000-0000-0000-0000-000000000003");
            host.Input["LocationId"] = Guid.Parse("00000000-0000-0000-0000-000000000004");
            host.Input["StartAt"] = DateTime.UtcNow.AddDays(1);
            host.Input["EndAt"] = DateTime.UtcNow.AddDays(1).AddHours(1);
            host.Input["Notes"] = "Synthetic schedule";
        }
        if (action == "RequestReschedule" || action == "CancelRound1")
            host.Input["Reason"] = "Synthetic schedule change";
    }
    private static Entity ScheduleEntity(int status, int? result = ActionRequest.ResultPending)
    {
        var row = new Entity("os_sr_intv", Guid.NewGuid())
        {
            RowVersion = "17",
            ["os_sr_intv_cand"] = new EntityReference("os_sr_cand", Candidate),
            ["os_sr_intv_rnd"] = new OptionSetValue(ActionRequest.Round1),
            ["os_sr_intv_ta"] = new EntityReference("os_sr_ta", Guid.Parse("00000000-0000-0000-0000-000000000003")),
            ["os_sr_intv_loc"] = new EntityReference("os_sr_loc", Guid.Parse("00000000-0000-0000-0000-000000000004")),
            ["os_sr_intv_strt"] = DateTime.UtcNow.AddDays(1),
            ["os_sr_intv_end"] = DateTime.UtcNow.AddDays(1).AddHours(1),
            ["os_sr_intv_stat"] = new OptionSetValue(status)
        };
        if (result.HasValue) row["os_sr_intv_res"] = new OptionSetValue(result.Value);
        return row;
    }
    private static Dictionary<string, object?> Context(ParameterCollection input, ParameterCollection shared, ParameterCollection output)
    {
        return new Dictionary<string, object?>
        {
            ["MessageName"] = "os_sr_cact", ["Stage"] = 30, ["Mode"] = 0, ["IsInTransaction"] = true,
            ["Depth"] = 1, ["UserId"] = Actor, ["InitiatingUserId"] = Actor, ["OrganizationId"] = Organization,
            ["PrimaryEntityName"] = "none",
            ["InputParameters"] = input, ["OutputParameters"] = output, ["SharedVariables"] = shared,
            ["ParentContext"] = null, ["OwningExtension"] = RegisterImplementation()
        };
    }
    private static T Proxy<T>(Func<IMethodCallMessage, object?> call) => (T)new DynamicProxy(typeof(T), call).GetTransparentProxy();
    private static IPluginExecutionContext Execution(Dictionary<string, object?> values) =>
        Proxy<IPluginExecutionContext>(call => values[call.MethodName.Substring(4)]);

    private static void Main()
    {
        var devCreate = new Host(-1, createCandidate: true);
        ConfigureDevHost(devCreate);
        devCreate.Input["CandidateName"] = "Synthetic Candidate";
        Reject(() => new ApplyCandidateAction().Execute(devCreate),
            "DEV_SLICE_INPUT_REJECTED:SYNTHETIC_PROFILE");
        Check(devCreate.ServiceOperations.Count == 0 && devCreate.CreatedCandidates == 0,
            "DEV slice rejects non-prefixed candidate before any Dataverse operation");

        var devEmail = new Host(-1, createCandidate: true);
        ConfigureDevHost(devEmail);
        devEmail.Input["CandidateName"] = "[SYNTHETIC-E2E] Reserved email rejection";
        devEmail.Input["CandidateEmail"] = "synthetic@example.com";
        Reject(() => new ApplyCandidateAction().Execute(devEmail),
            "DEV_SLICE_INPUT_REJECTED:SYNTHETIC_PROFILE");
        Check(devEmail.ServiceOperations.Count == 0 && devEmail.CreatedCandidates == 0,
            "DEV slice rejects non-reserved email before any Dataverse operation");

        var devEnvironment = new Host(-1, createCandidate: true);
        ConfigureDevHost(devEnvironment);
        devEnvironment.MainValues["OrganizationId"] = Organization;
        Reject(() => new ApplyCandidateAction().Execute(devEnvironment), "DEV_SLICE_ENVIRONMENT_REJECTED");
        Check(devEnvironment.ServiceOperations.Count == 0,
            "DEV slice rejects a non-target organization before any Dataverse operation");

        var devWorkflow = new Host(-1, createCandidate: true);
        ConfigureDevHost(devWorkflow);
        devWorkflow.Input["CandidateName"] = "[SYNTHETIC-E2E] SDK visible workflow";
        devWorkflow.Input["CandidateEmail"] = "sdk-workflow@example.invalid";
        devWorkflow.Input["CandidatePhone"] = "555-0100";
        new ApplyCandidateAction().Execute(devWorkflow);
        Check((string)devWorkflow.Output["ResultCode"] == "Applied" &&
            (string)devWorkflow.Output["CandidateId"] == Candidate.ToString("D"),
            "DEV slice returns the created candidate reference");
        Check(devWorkflow.CreatedCandidates == 1 && devWorkflow.Calls == 0 &&
            devWorkflow.Histories == 0 && devWorkflow.Receipt == null &&
            !devWorkflow.ServiceOperations.Any(operation => operation.Contains("oprc")),
            "DEV candidate create writes no call, history, or receipt");
        Check(devWorkflow.CreatedCandidate!.GetAttributeValue<string>("os_sr_cand_nm") ==
                "[SYNTHETIC-E2E] SDK visible workflow" &&
            devWorkflow.CreatedCandidate.GetAttributeValue<OptionSetValue>("os_sr_cand_stat")?.Value == 100010000 &&
            devWorkflow.CreatedCandidate.GetAttributeValue<string>("os_sr_cand_cnum") == "CAND-00000001" &&
            devWorkflow.CreatedCandidate.GetAttributeValue<EntityReference>("ownerid")?.Id == Actor,
            "DEV candidate create sets the synthetic profile, initial status, generated number, and caller owner");

        SetDevRecordCall(devWorkflow, Candidate, 100010000, 100010001);
        new ApplyCandidateAction().Execute(devWorkflow);
        Check(devWorkflow.Calls == 1 && devWorkflow.Updates == 0 && devWorkflow.Histories == 0 &&
            devWorkflow.Status == 100010000 && devWorkflow.Receipt == null,
            "DEV No Answer creates a call without changing status or creating a receipt");
        var noAnswer = devWorkflow.CreatedCall!;
        Check(noAnswer.GetAttributeValue<OptionSetValue>("os_sr_call_out")?.Value == 100010001 &&
            noAnswer.GetAttributeValue<EntityReference>("os_sr_call_cand")?.Id == Candidate &&
            noAnswer.GetAttributeValue<DateTime>("os_sr_call_ctat") != default(DateTime) &&
            noAnswer.GetAttributeValue<EntityReference>("os_sr_call_ctby")?.Id == Actor,
            "DEV No Answer call uses the current Choice and required related fields");

        SetDevRecordCall(devWorkflow, Candidate, 100010000, 100010000);
        new ApplyCandidateAction().Execute(devWorkflow);
        Check(devWorkflow.Calls == 2 && devWorkflow.Updates == 1 &&
            devWorkflow.Histories == 1 && devWorkflow.Status == 100010001 &&
            devWorkflow.Receipt == null &&
            !devWorkflow.ServiceOperations.Any(operation => operation.Contains("oprc")),
            "DEV Answered creates a second call, updates Candidate, creates history, and never uses Receipts");
        Check(devWorkflow.CreatedHistory!.GetAttributeValue<OptionSetValue>("os_sr_csh_prevstat")?.Value == 100010000 &&
            devWorkflow.CreatedHistory.GetAttributeValue<OptionSetValue>("os_sr_csh_newstat")?.Value == 100010001 &&
            devWorkflow.CreatedHistory.GetAttributeValue<string>("os_sr_csh_cact") == "RecordCall",
            "DEV Answered history captures the status transition");
        Check(!devWorkflow.ServiceFactorySelections.Contains(null),
            "DEV-only direct-write slice cannot obtain the Candidate Core SYSTEM service");

        var devCreateFault = new Host(-1, createCandidate: true);
        ConfigureDevHost(devCreateFault);
        devCreateFault.Input["CandidateName"] = "[SYNTHETIC-E2E] SDK stage fault";
        devCreateFault.Input["CandidateEmail"] = "stage-fault@example.invalid";
        devCreateFault.FaultOnCreateTable = "os_sr_cand";
        Reject(() => new ApplyCandidateAction().Execute(devCreateFault),
            "DEV_SLICE_CANDIDATE_CREATE_FAILED:0x80040220");
        Check(!devCreateFault.TraceMessages.Any(message => message.Contains("SENSITIVE_SENTINEL")),
            "DEV stage diagnostics do not expose service exception payloads");

        var actionWriteMatrix = new Dictionary<string, string[]>
        {
            ["CreateCandidate"] = new[] { "CANDIDATE_CREATE", "RECEIPT_CREATE" },
            ["UpdateCandidate"] = new[] { "CANDIDATE_UPDATE", "RECEIPT_CREATE" },
            ["RecordCall"] = new[] { "CANDIDATE_UPDATE", "CALL_LOG_CREATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" },
            ["ProceedToScheduling"] = new[] { "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" },
            ["MarkRound1Scheduled"] = new[] { "INTERVIEW_SCHEDULE_CREATE", "INTERVIEW_SCHEDULE_UPDATE",
                "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" },
            ["RecordPass"] = new[] { "CANDIDATE_UPDATE", "INTERVIEW_SCHEDULE_UPDATE",
                "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" },
            ["RecordFail"] = new[] { "CANDIDATE_UPDATE", "INTERVIEW_SCHEDULE_UPDATE",
                "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" },
            ["RequestReschedule"] = new[] { "INTERVIEW_SCHEDULE_CREATE", "INTERVIEW_SCHEDULE_UPDATE",
                "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" },
            ["CancelRound1"] = new[] { "INTERVIEW_SCHEDULE_UPDATE",
                "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" }
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
            Check(CandidateOperation.MutationMatrix.TryGetValue(pair.Key, out var mutations) &&
                mutations.OrderBy(value => value, StringComparer.Ordinal).SequenceEqual(
                    pair.Value.OrderBy(value => value, StringComparer.Ordinal)),
                "Canonical engine mutation matrix: " + pair.Key);
            if (new[] { "CreateCandidate", "UpdateCandidate", "RecordCall", "ProceedToScheduling" }
                .Contains(pair.Key, StringComparer.Ordinal))
            {
                foreach (var write in protectedWrites)
                {
                    var target = new Entity(write.Table, Guid.NewGuid());
                    var parent = CreateTrustedParent(pair.Key, write.Message, target, 1, includeMarker: false);
                    if (pair.Value.Contains(write.Code))
                    {
                        ExecuteGuard(write.Message, target, parent);
                        Check(true, "Historical guard action/write allow: " + pair.Key + ":" + write.Code);
                    }
                    else RejectDirectGuard(write.Message, target, parent,
                        "DIRECT_WRITE_GUARD_REJECTED:" + write.Code + ":TRUSTED_PARENT:ACTIONTYPE_MISMATCH");
                    RejectDirectGuard(write.Message, target, null,
                        "DIRECT_WRITE_GUARD_REJECTED:" + write.Code + ":PARENT_CONTEXT");
                }
                foreach (var unsupported in new[] { ("Delete", "os_sr_cand"),
                    ("Upsert", "os_sr_oprc"), ("Update", "os_sr_call"), ("Update", "os_sr_csh") })
                {
                    var target = new Entity(unsupported.Item2, Guid.NewGuid());
                    RejectDirectGuard(unsupported.Item1, target,
                        CreateTrustedParent(pair.Key, unsupported.Item1, target, 1),
                        "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE");
                }
                var receiptUpdateTarget = new Entity("os_sr_oprc", Guid.NewGuid());
                RejectDirectGuard("Update", receiptUpdateTarget,
                    CreateTrustedParent(pair.Key, "Update", receiptUpdateTarget, 1),
                    "DIRECT_WRITE_GUARD_REJECTED:RECEIPT_UPDATE:TRUSTED_PARENT:ACTIONTYPE_MISMATCH");
            }
        }
        Check(!(CandidateOperation.MutationMatrix is Dictionary<string, IReadOnlyCollection<string>>) &&
            ((IList<string>)CandidateOperation.MutationMatrix["CreateCandidate"]).IsReadOnly,
            "The canonical write matrix cannot be changed by callers");
        var storageType = typeof(ApplyCandidateAction).Assembly.GetType("os_sr_cact.DataverseStore");
        Check(storageType != null && !storageType.IsPublic &&
            storageType.GetMethods(BindingFlags.Instance | BindingFlags.Public)
                .All(method => method.GetParameters().All(parameter =>
                    parameter.ParameterType != typeof(Entity) &&
                    parameter.ParameterType != typeof(string))),
            "Protected storage adapter is not public and exposes no arbitrary entity/table write surface");
        var unsupportedFault = CreateCandidateHost();
        unsupportedFault.FaultOnCreateTable = "os_sr_cand";
        unsupportedFault.FaultErrorCode = unchecked((int)0x80040265);
        unsupportedFault.FaultMessage = "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE";
        Reject(() => new ApplyCandidateAction().Execute(unsupportedFault),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:CANDIDATE_CREATE:0x80040265");
        var unknownWriteTarget = new Entity("os_sr_oprc", Guid.NewGuid());
        var unknownActionParent = CreateGuardParent("os_sr_cact",
            new ParameterCollection { ["ActionType"] = "SENSITIVE_SENTINEL " + Actor.ToString("D") },
            new ParameterCollection());
        RejectDirectGuard("Upsert", unknownWriteTarget, Execution(unknownActionParent),
            "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE");
        RejectDirectGuard("Update", unknownWriteTarget,
            CreateTrustedParent("CreateCandidate", "Update", unknownWriteTarget, 9),
            "DIRECT_WRITE_GUARD_REJECTED:RECEIPT_UPDATE:TRUSTED_PARENT:ANCESTOR_BOUND_EXCEEDED");
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
        Check(createWithoutOptionalGuids.ServiceFactorySelections.Contains(Actor) &&
            createWithoutOptionalGuids.ServiceFactorySelections.Contains(null) &&
            createWithoutOptionalGuids.CallerProtectedWriteAttempts == 0 &&
            !createWithoutOptionalGuids.CandidateNumberWasSupplied &&
            createWithoutOptionalGuids.ReceiptCreateTarget != null &&
            !createWithoutOptionalGuids.ReceiptCreateTarget.Contains("ownerid") &&
            createWithoutOptionalGuids.Receipt!.GetAttributeValue<EntityReference>("ownerid").Id == SystemActor &&
            createWithoutOptionalGuids.CreatedCandidate!.GetAttributeValue<EntityReference>("ownerid").Id == Actor &&
            createWithoutOptionalGuids.TraceMessages.All(message => !message.StartsWith("CC_GUARD_", StringComparison.Ordinal)),
            "Least-privilege caller creates Candidate and Receipt through SYSTEM; Candidate remains caller-owned and Receipt uses default SYSTEM ownership");
        var callerOwnedReceipt = new Entity("os_sr_oprc", Guid.NewGuid())
        {
            ["ownerid"] = new EntityReference("systemuser", Actor)
        };
        try
        {
            createWithoutOptionalGuids.ValidateReceiptOwner(callerOwnedReceipt);
            throw new Exception("Expected caller-owned Receipt rejection");
        }
        catch (FaultException<OrganizationServiceFault> error)
        {
            Check(error.Detail.ErrorCode == unchecked((int)0x80040299),
                "Explicitly assigning the no-Receipt-access caller reproduces TargetPrincipalLacksReadPrivilege");
        }
        new ApplyCandidateAction().Execute(createWithoutOptionalGuids);
        Check((string)createWithoutOptionalGuids.Output["ResultCode"] == "DuplicateReplay" &&
            createWithoutOptionalGuids.CreatedCandidates == 1 &&
            createWithoutOptionalGuids.Receipt != null &&
            createWithoutOptionalGuids.Receipt.GetAttributeValue<EntityReference>("ownerid").Id == SystemActor,
            "SYSTEM-owned Receipt replays without duplicate Candidate or Receipt effects");
        createWithoutOptionalGuids.MainValues["UserId"] = Guid.Parse("00000000-0000-0000-0000-000000000004");
        createWithoutOptionalGuids.MainValues["InitiatingUserId"] = Guid.Parse("00000000-0000-0000-0000-000000000004");
        Reject(() => new ApplyCandidateAction().Execute(createWithoutOptionalGuids),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:RECEIPT_READ:CORRELATION_CONFLICT");
        Check(createWithoutOptionalGuids.CreatedCandidates == 1 &&
            createWithoutOptionalGuids.ServiceOperations.Count(operation => operation == "Create:os_sr_oprc") == 1,
            "Actor-bound fingerprint rejects another caller replay without reading business data or changing the Receipt");
        createWithoutOptionalGuids.MainValues["UserId"] = Actor;
        createWithoutOptionalGuids.MainValues["InitiatingUserId"] = Actor;
        createWithoutOptionalGuids.Input["CandidateName"] = "Conflicting synthetic replay";
        Reject(() => new ApplyCandidateAction().Execute(createWithoutOptionalGuids),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:RECEIPT_READ:CORRELATION_CONFLICT");
        Check(createWithoutOptionalGuids.CreatedCandidates == 1 &&
            createWithoutOptionalGuids.ServiceOperations.Count(operation => operation == "Create:os_sr_oprc") == 1,
            "Conflicting Receipt replay is rejected without duplicate or mutable Receipt writes");
        Check(!createWithoutOptionalGuids.Shared.Contains(GetGuardIntentKey()) &&
            createWithoutOptionalGuids.Receipt!.Attributes.Keys.All(name => name != GetGuardIntentKey()) &&
            createWithoutOptionalGuids.Output.Keys.All(name => name != GetGuardIntentKey()) &&
            createWithoutOptionalGuids.MarkersAtProtectedWrites.Count == 0,
            "MVP operation does not create, persist, return, trace, or require the superseded marker");
        var packageApiParent = CreateCandidateHost();
        new ApplyCandidateAction().Execute(packageApiParent);
        Check(packageApiParent.CreatedCandidates == 1 && packageApiParent.Receipt != null &&
            packageApiParent.ServiceFactorySelections.Contains(null),
            "Candidate Core handler obtains its SYSTEM service after validating API context");
        var metadataIndependentApi = CreateCandidateHost();
        metadataIndependentApi.MainValues["OwningExtension"] = null;
        new ApplyCandidateAction().Execute(metadataIndependentApi);
        Check(metadataIndependentApi.CreatedCandidates == 1 && metadataIndependentApi.Receipt != null,
            "MVP authorization uses server-owned API execution context without runtime registration metadata reads");
        var candidateCreateFault = CreateCandidateHost();
        candidateCreateFault.FaultOnCreateTable = "os_sr_cand";
        candidateCreateFault.FaultMessage = "SENSITIVE_SENTINEL " + Actor.ToString("D");
        var candidateFaultMessage = Reject(() => new ApplyCandidateAction().Execute(candidateCreateFault),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:CANDIDATE_CREATE:0x80040220");
        Check(candidateCreateFault.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand" }) &&
            candidateCreateFault.Receipt == null,
            "Candidate Create fault terminates before Receipt Create");
        Check(candidateCreateFault.TraceMessages.Contains("CC_STAGE:CC_CREATE_CANDIDATE") &&
            candidateCreateFault.TraceMessages.Contains("CC_SERVICE_FAULT:CC_CREATE_CANDIDATE:0x80040220") &&
            !candidateCreateFault.TraceMessages.Any(message => message.Contains("SENSITIVE_SENTINEL")),
            "Candidate Create fault diagnostics contain stage and code only");
        var receiptReadFault = CreateCandidateHost();
        receiptReadFault.FaultOnRetrieveMultipleTable = "os_sr_oprc";
        receiptReadFault.FaultMessage = "SENSITIVE_SENTINEL " + Actor.ToString("D");
        var receiptReadMessage = Reject(() => new ApplyCandidateAction().Execute(receiptReadFault),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:RECEIPT_READ:0x80040220");
        Check(receiptReadFault.ServiceOperations.SequenceEqual(new[] { "RetrieveMultiple:os_sr_oprc" }) &&
            receiptReadFault.CreatedCandidates == 0 &&
            !receiptReadMessage.Contains("SENSITIVE_SENTINEL") &&
            !receiptReadMessage.Contains(Actor.ToString("D")),
            "Receipt lookup failures report only the safe stage and code");
        var candidateReadbackFault = CreateCandidateHost();
        new ApplyCandidateAction().Execute(candidateReadbackFault);
        candidateReadbackFault.FaultOnRetrieveTable = "os_sr_cand";
        candidateReadbackFault.FaultErrorCode = unchecked((int)0x80040222);
        var candidateReadbackMessage = Reject(
            () => new ApplyCandidateAction().Execute(candidateReadbackFault),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:CANDIDATE_READBACK:0x80040222");
        Check(candidateReadbackFault.CreatedCandidates == 1 &&
            candidateReadbackFault.Receipt != null &&
            !candidateReadbackMessage.Contains(Actor.ToString("D")),
            "Identical replay preserves one effect and classifies Candidate readback without exposing identity");
        var receiptCreateFault = CreateCandidateHost();
        receiptCreateFault.FaultOnCreateTable = "os_sr_oprc";
        receiptCreateFault.FaultErrorCode = unchecked((int)0x80040221);
        var receiptFaultMessage = Reject(() => new ApplyCandidateAction().Execute(receiptCreateFault),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:RECEIPT_CREATE:0x80040221");
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
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:CANDIDATE_CREATE:0x80040265");
        Check(legacyGuardFault.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand" }) &&
            !legacyGuardMessage.Contains("DIRECT_CANDIDATE_CORE_WRITE_BLOCKED"),
            "Dataverse privilege faults use sanitized platform rejection without guard-specific authorization");
        var tamperedCreate = CreateCandidateHost();
        tamperedCreate.TamperTarget = true;
        tamperedCreate.MainValues["MessageName"] = "unrelated_operation";
        var guardMessage = Reject(() => new ApplyCandidateAction().Execute(tamperedCreate),
            "UNSUPPORTED_EXECUTION_CONTEXT");
        Check(tamperedCreate.ServiceOperations.Count == 0,
            "Invalid server-owned Custom API context is rejected before business reads/writes");
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
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:CANDIDATE_CREATE:INVALID_OPERATION");
        Check(unknownFailure.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Create:os_sr_cand" }) &&
            !unknownFailureMessage.Contains("SENSITIVE_SENTINEL"),
            "Unknown service exception is categorized, sanitized, and terminates immediately");
        var invalidCreateInput = CreateCandidateHost();
        invalidCreateInput.Input["CandidateName"] = new string('x', 201);
        var invalidCreateMessage = Reject(
            () => new ApplyCandidateAction().Execute(invalidCreateInput),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:INPUT_VALIDATION:TEXT_TOO_LONG");
        Check(invalidCreateInput.ServiceOperations.Count == 0 &&
            !invalidCreateMessage.Contains(Actor.ToString("D")),
            "CreateCandidate input failures are safely classified before any storage access");
        Check(CandidateOperation.AllowsMutation("MarkRound1Scheduled", "INTERVIEW_SCHEDULE_CREATE") &&
            CandidateOperation.AllowsMutation("RecordPass", "INTERVIEW_SCHEDULE_UPDATE") &&
            CandidateOperation.AllowsMutation("RecordFail", "CANDIDATE_UPDATE") &&
            CandidateOperation.AllowsMutation("RequestReschedule", "INTERVIEW_SCHEDULE_CREATE") &&
            CandidateOperation.AllowsMutation("CancelRound1", "INTERVIEW_SCHEDULE_UPDATE") &&
            !CandidateOperation.MutationMatrix.Values.Any(mutations => mutations.Contains("RECEIPT_UPDATE")) &&
            !CandidateOperation.AllowsMutation("MarkRound1Scheduled", "UNLISTED_TABLE_WRITE") &&
            !CandidateOperation.AllowsMutation("RequestReschedule", "*"),
            "Action mutations allow only the canonical fixed matrix and never update append-only receipts");
        var invalidAction = CreateCandidateHost();
        invalidAction.Input["ActionType"] = "UnsupportedOperation";
        Reject(() => new ApplyCandidateAction().Execute(invalidAction), "INVALID_ACTION");
        Check(!invalidAction.ServiceFactorySelections.Contains(null) && invalidAction.ServiceOperations.Count == 0,
            "Unsupported ActionType is rejected before SYSTEM service creation or protected access");
        var invalidSchedule = new Host(-1) { Status = ActionRequest.Waiting };
        SetScheduleAction(invalidSchedule, "MarkRound1Scheduled", ActionRequest.Waiting);
        invalidSchedule.Input["EndAt"] = invalidSchedule.Input["StartAt"];
        invalidSchedule.MainValues = Context(invalidSchedule.Input, invalidSchedule.Shared, invalidSchedule.Output);
        invalidSchedule.MainContext = Execution(invalidSchedule.MainValues);
        Reject(() => new ApplyCandidateAction().Execute(invalidSchedule), "INVALID_SCHEDULE_TIME");
        Check(!invalidSchedule.ServiceFactorySelections.Contains(null) &&
            invalidSchedule.ServiceOperations.Count == 0,
            "Invalid schedule inputs are rejected before SYSTEM service creation");

        var inaccessibleCandidate = new Host(100010000);
        inaccessibleCandidate.CallerReadDeniedTables.Add("os_sr_cand");
        Reject(() => new ApplyCandidateAction().Execute(inaccessibleCandidate),
            "CALLER_READ_ACCESS_REQUIRED");
        Check(inaccessibleCandidate.CallerReadAccessChecks.SequenceEqual(new[] { "os_sr_cand" }) &&
            !inaccessibleCandidate.ServiceOperations.Contains("Retrieve:os_sr_cand") &&
            !inaccessibleCandidate.ServiceOperations.Any(operation => operation.StartsWith("Create:", StringComparison.Ordinal) ||
                operation.StartsWith("Execute:Update:", StringComparison.Ordinal)),
            "SYSTEM Candidate read is gated by the initiating caller's effective read access");

        var staleSchedule = new Host(-1) { Status = ActionRequest.Scheduled };
        SetScheduleAction(staleSchedule, "MarkRound1Scheduled", ActionRequest.Waiting);
        staleSchedule.MainValues = Context(staleSchedule.Input, staleSchedule.Shared, staleSchedule.Output);
        staleSchedule.MainContext = Execution(staleSchedule.MainValues);
        Reject(() => new ApplyCandidateAction().Execute(staleSchedule), "STALE_EXPECTED_STATUS");
        Check(staleSchedule.ServiceOperations.Contains("RetrieveMultiple:os_sr_oprc") &&
            staleSchedule.ServiceOperations.Contains("Retrieve:os_sr_cand") &&
            !staleSchedule.ServiceOperations.Any(operation => operation.StartsWith("Create:", StringComparison.Ordinal) ||
                operation.StartsWith("Execute:", StringComparison.Ordinal)) &&
            staleSchedule.ScheduleCreates == 0 && staleSchedule.ScheduleUpdates == 0,
            "Stale ExpectedStatus fails before any SYSTEM business write");
        var inaccessibleSchedule = new Host(100010000) { Status = ActionRequest.Scheduled };
        inaccessibleSchedule.Input["ActionType"] = "RecordPass";
        inaccessibleSchedule.Input["ExpectedStatus"] = ActionRequest.Scheduled;
        inaccessibleSchedule.Input["ResultNotes"] = "Synthetic result evidence";
        inaccessibleSchedule.Round1Schedule = ScheduleEntity(ActionRequest.ScheduleActive);
        inaccessibleSchedule.CallerReadDeniedTables.Add("os_sr_intv");
        inaccessibleSchedule.MainValues = Context(
            inaccessibleSchedule.Input, inaccessibleSchedule.Shared, inaccessibleSchedule.Output);
        inaccessibleSchedule.MainContext = Execution(inaccessibleSchedule.MainValues);
        Reject(() => new ApplyCandidateAction().Execute(inaccessibleSchedule),
            "CALLER_READ_ACCESS_REQUIRED");
        Check(inaccessibleSchedule.CallerReadAccessChecks.SequenceEqual(new[] { "os_sr_cand", "os_sr_intv" }) &&
            !inaccessibleSchedule.ServiceOperations.Contains("Retrieve:os_sr_intv") &&
            inaccessibleSchedule.ProtectedScheduleReadOrder.SequenceEqual(
                new[] { "ID_QUERY", "ACCESS_CHECK" }) &&
            !inaccessibleSchedule.ServiceOperations.Any(operation => operation.StartsWith("Create:", StringComparison.Ordinal) ||
                operation.StartsWith("Execute:Update:", StringComparison.Ordinal)),
            "SYSTEM checks initiating-caller access after an ID-only query and before retrieving Interview Schedule details");
        var inaccessibleReference = CreateCandidateHost();
        inaccessibleReference.Input["PositionId"] = Guid.NewGuid();
        inaccessibleReference.ReferenceReadFailureTable = "os_sr_pos";
        var referenceFailure = Reject(() => new ApplyCandidateAction().Execute(inaccessibleReference),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:REFERENCE_VALIDATION:0x80040220");
        Check(!inaccessibleReference.ServiceFactorySelections.Contains(null) &&
            !inaccessibleReference.ServiceOperations.Any(operation => operation.StartsWith("Create:", StringComparison.Ordinal)) &&
            !referenceFailure.Contains("SENSITIVE_SENTINEL") &&
            !referenceFailure.Contains("PositionId"),
            "Caller reference lookup faults expose only their safe stage and code before SYSTEM storage");
        var inactiveScheduleReference = new Host(-1) { Status = ActionRequest.Waiting };
        SetScheduleAction(inactiveScheduleReference, "MarkRound1Scheduled", ActionRequest.Waiting);
        inactiveScheduleReference.InactiveReferenceTable = "os_sr_ta";
        inactiveScheduleReference.MainValues = Context(
            inactiveScheduleReference.Input, inactiveScheduleReference.Shared, inactiveScheduleReference.Output);
        inactiveScheduleReference.MainContext = Execution(inactiveScheduleReference.MainValues);
        Reject(() => new ApplyCandidateAction().Execute(inactiveScheduleReference),
            "REFERENCE_NOT_AVAILABLE:InterviewerId");
        Check(!inactiveScheduleReference.ServiceFactorySelections.Contains(null) &&
            !inactiveScheduleReference.ServiceOperations.Any(operation => operation.StartsWith("Create:", StringComparison.Ordinal)) &&
            !inactiveScheduleReference.ServiceOperations.Any(operation => operation.StartsWith("Execute:", StringComparison.Ordinal)),
            "Inactive TA is rejected before SYSTEM service creation or business writes");
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
        foreach (string parameter in new[] { "PositionId", "CandidateSourceId", "AssignedTaId" })
        {
            foreach (object? absentEquivalent in new object?[] { null, Guid.Empty })
            {
                var host = CreateCandidateHost();
                host.Input[parameter] = absentEquivalent;
                new ApplyCandidateAction().Execute(host);
                string attribute = parameter switch
                {
                    "PositionId" => "os_sr_cand_pos",
                    "CandidateSourceId" => "os_sr_cand_csrc",
                    _ => "os_sr_cand_ta"
                };
                Check(host.CreatedCandidates == 1 && !host.CreatedCandidate!.Contains(attribute),
                    "SDK CreateCandidate normalizes " + parameter + " absent-equivalent to no lookup");
            }
            var validHost = CreateCandidateHost();
            var lookupId = Guid.NewGuid();
            validHost.Input[parameter] = lookupId;
            new ApplyCandidateAction().Execute(validHost);
            string validAttribute = parameter switch
            {
                "PositionId" => "os_sr_cand_pos",
                "CandidateSourceId" => "os_sr_cand_csrc",
                _ => "os_sr_cand_ta"
            };
            var reference = validHost.CreatedCandidate!.GetAttributeValue<EntityReference>(validAttribute);
            Check(reference != null && reference.Id == lookupId &&
                reference.LogicalName == (parameter switch
                {
                    "PositionId" => "os_sr_pos",
                    "CandidateSourceId" => "os_sr_csrc",
                    _ => "os_sr_ta"
                }),
                "SDK CreateCandidate preserves valid " + parameter + " reference");

            var invalidHost = CreateCandidateHost();
            invalidHost.Input[parameter] = "not-a-guid";
            Reject(() => new ApplyCandidateAction().Execute(invalidHost),
                "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:INPUT_VALIDATION:INVALID_GUID_PARAMETER");
            Check(invalidHost.CreatedCandidates == 0 && invalidHost.Receipt == null,
                "SDK invalid " + parameter + " rejected before any create");
        }
        var profileCreate = CreateCandidateHost();
        var profilePositionId = Guid.NewGuid();
        var profileSourceId = Guid.NewGuid();
        var profileTaId = Guid.NewGuid();
        profileCreate.Input["CandidateCvUrl"] = "https://careers.example.invalid/cv/123";
        profileCreate.Input["PositionId"] = profilePositionId;
        profileCreate.Input["CandidateSourceId"] = profileSourceId;
        profileCreate.Input["AssignedTaId"] = profileTaId;
        new ApplyCandidateAction().Execute(profileCreate);
        var createdProfile = profileCreate.CreatedCandidate!;
        Check(createdProfile.GetAttributeValue<string>("os_sr_cand_cvurl") ==
            "https://careers.example.invalid/cv/123" &&
            createdProfile.GetAttributeValue<EntityReference>("os_sr_cand_pos")?.Id == profilePositionId &&
            createdProfile.GetAttributeValue<EntityReference>("os_sr_cand_csrc")?.Id == profileSourceId &&
            createdProfile.GetAttributeValue<EntityReference>("os_sr_cand_ta")?.Id == profileTaId,
            "SDK CreateCandidate persists CV URL, Position, Candidate Source, and Assigned TA profile fields");
        foreach (string invalidCvUrl in new[]
        {
            "http://careers.example.invalid/cv",
            "https://user:password@careers.example.invalid/cv",
            "/candidate/cv"
        })
        {
            var invalidProfile = CreateCandidateHost();
            invalidProfile.Input["CandidateCvUrl"] = invalidCvUrl;
            Reject(() => new ApplyCandidateAction().Execute(invalidProfile),
                "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:INPUT_VALIDATION:INVALID_CV_URL");
            Check(invalidProfile.CreatedCandidates == 0 && invalidProfile.Receipt == null,
                "SDK invalid Candidate CV URL is rejected before any create");
        }
        var inactiveAssignedTa = CreateCandidateHost();
        inactiveAssignedTa.Input["AssignedTaId"] = Guid.NewGuid();
        inactiveAssignedTa.InactiveReferenceTable = "os_sr_ta";
        Reject(() => new ApplyCandidateAction().Execute(inactiveAssignedTa),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:REFERENCE_VALIDATION:REFERENCE_NOT_AVAILABLE");
        Check(inactiveAssignedTa.CreatedCandidates == 0 && inactiveAssignedTa.Receipt == null &&
            !inactiveAssignedTa.ServiceFactorySelections.Contains(null),
            "SDK inactive Assigned TA is rejected in caller context before SYSTEM storage");
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
                        "CC_STAGE:CC_READ_RECEIPT", "CC_STAGE:CC_CHECK_PROTECTED_READ_ACCESS",
                        "CC_STAGE:CC_READ_CANDIDATE", "CC_STAGE:CC_UPDATE_CANDIDATE",
                        "CC_STAGE:CC_CREATE_CALL_LOG", "CC_STAGE:CC_CREATE_STATUS_HISTORY", "CC_STAGE:CC_CREATE_RECEIPT"
                    }) && stageMarkers.Distinct(StringComparer.Ordinal).Count() == stageMarkers.Length,
                    "Each Answered transition service operation has a distinct safe stage marker");
            }
            Check(host.Calls == 1 && host.Histories == (outcome == 100010000 ? 1 : 0), "SDK exact call/history effects");
            Check(host.Updates == (outcome == 100010000 ? 1 : 0), "SDK non-answer log only");
            Check(host.ReceiptCreateTarget != null && !host.ReceiptCreateTarget.Contains("ownerid") &&
                host.Receipt != null && host.Receipt.GetAttributeValue<EntityReference>("ownerid").Id == SystemActor,
                "SDK Receipt creation omits caller ownership and uses SYSTEM default owner");
            Check(host.Receipt != null && host.Receipt.Attributes.Keys.All(name => !name.Contains("email") && !name.Contains("notes")), "SDK receipt minimization");
            new ApplyCandidateAction().Execute(host);
            Check((string)host.Output["ResultCode"] == "DuplicateReplay" && host.Calls == 1, "SDK persisted replay");
            Check(host.ServiceFactorySelections.Contains(Actor) &&
                host.ServiceFactorySelections.Contains(null) &&
                host.ServiceFactorySelections.All(id => id == Actor || id == null),
                "SDK uses caller reference validation and the contained SYSTEM storage service");
            Check(host.CandidateRequests.All(request => request.ConcurrencyBehavior == ConcurrencyBehavior.IfRowVersionMatches), "SDK conditional updates");
        }
        foreach (var resultAction in new[] { ("RecordPass", ActionRequest.ResultPass, ActionRequest.Passed),
            ("RecordFail", ActionRequest.ResultFail, ActionRequest.Failed) })
        {
            var resultHost = new Host(100010000) { Status = ActionRequest.Scheduled };
            resultHost.Input["ActionType"] = resultAction.Item1;
            resultHost.Input["ExpectedStatus"] = ActionRequest.Scheduled;
            resultHost.Input["ResultNotes"] = "Synthetic result evidence";
            resultHost.Round1Schedule = new Entity("os_sr_intv", Guid.NewGuid())
            {
                RowVersion = "17",
                ["os_sr_intv_cand"] = new EntityReference("os_sr_cand", Candidate),
                ["os_sr_intv_rnd"] = new OptionSetValue(ActionRequest.Round1),
                ["os_sr_intv_ta"] = new EntityReference("os_sr_ta", Guid.Parse("00000000-0000-0000-0000-000000000003")),
                ["os_sr_intv_loc"] = new EntityReference("os_sr_loc", Guid.Parse("00000000-0000-0000-0000-000000000004")),
                ["os_sr_intv_strt"] = DateTime.UtcNow.AddDays(1),
                ["os_sr_intv_end"] = DateTime.UtcNow.AddDays(1).AddHours(1),
                ["os_sr_intv_stat"] = new OptionSetValue(ActionRequest.ScheduleActive),
                ["os_sr_intv_res"] = new OptionSetValue(ActionRequest.ResultPending)
            };
            resultHost.MainValues = Context(resultHost.Input, resultHost.Shared, resultHost.Output);
            resultHost.MainContext = Execution(resultHost.MainValues);
            new ApplyCandidateAction().Execute(resultHost);
            Check(resultHost.Round1Schedule.GetAttributeValue<OptionSetValue>("os_sr_intv_res")?.Value == resultAction.Item2 &&
            resultHost.Round1Schedule.GetAttributeValue<string>("os_sr_intv_rnts") == "Synthetic result evidence" &&
            resultHost.ScheduleUpdates == 1 && resultHost.Status == resultAction.Item3,
            "SDK " + resultAction.Item1 + " persists result and terminal Candidate status");
            Check(resultHost.ScheduleRequests.Single().Target.RowVersion == "17" &&
            resultHost.ScheduleRequests.Single().ConcurrencyBehavior == ConcurrencyBehavior.IfRowVersionMatches &&
            resultHost.ScheduleRequests.Single().Target.GetAttributeValue<OptionSetValue>("os_sr_intv_res")?.Value == resultAction.Item2,
            "SDK " + resultAction.Item1 + " uses conditional SYSTEM update on the fixed Interview Schedule row");
            Check(resultHost.ServiceOperations.SequenceEqual(new[]
            { "RetrieveMultiple:os_sr_oprc", "Retrieve:os_sr_cand", "RetrieveMultiple:os_sr_intv",
                "Retrieve:os_sr_intv",
                "Execute:Update:os_sr_intv", "Execute:Update:os_sr_cand", "Create:os_sr_csh", "Create:os_sr_oprc" }) &&
            resultHost.ServiceFactorySelections.Contains(Actor) && resultHost.ServiceFactorySelections.Contains(null) &&
            resultHost.CallerReadAccessChecks.Contains("os_sr_cand") &&
            resultHost.CallerReadAccessChecks.Contains("os_sr_intv"),
            "SDK " + resultAction.Item1 + " checks caller read access and keeps protected storage in SYSTEM context");
            new ApplyCandidateAction().Execute(resultHost);
            Check((string)resultHost.Output["ResultCode"] == "DuplicateReplay" &&
            resultHost.ScheduleUpdates == 1 && resultHost.Histories == 1,
            "SDK " + resultAction.Item1 + " replay creates no duplicate result or history");
        }
        var scheduleHost = new Host(-1) { Status = ActionRequest.Waiting };
        SetScheduleAction(scheduleHost, "MarkRound1Scheduled", ActionRequest.Waiting);
        scheduleHost.MainValues = Context(scheduleHost.Input, scheduleHost.Shared, scheduleHost.Output);
        scheduleHost.MainContext = Execution(scheduleHost.MainValues);
        new ApplyCandidateAction().Execute(scheduleHost);
        Check(scheduleHost.ScheduleCreates == 1 && scheduleHost.ScheduleUpdates == 0 &&
            scheduleHost.Round1Schedule?.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value ==
                ActionRequest.ScheduleActive &&
            scheduleHost.Round1Schedule.GetAttributeValue<OptionSetValue>("os_sr_intv_res")?.Value ==
                ActionRequest.ResultPending &&
            scheduleHost.Status == ActionRequest.Scheduled && scheduleHost.Histories == 1 &&
            scheduleHost.Receipt != null,
            "SDK schedule creates and reads back Interview Schedule before Candidate, History, Receipt");
        Check(scheduleHost.ServiceOperations.SequenceEqual(new[]
            {
                "Retrieve:os_sr_ta", "Retrieve:os_sr_loc",
                "RetrieveMultiple:os_sr_oprc", "Retrieve:os_sr_cand",
                "RetrieveMultiple:os_sr_intv", "RetrieveMultiple:os_sr_intv",
                "Create:os_sr_intv", "Retrieve:os_sr_intv",
                "Execute:Update:os_sr_cand", "Create:os_sr_csh", "Create:os_sr_oprc"
            }) && scheduleHost.ServiceFactorySelections.Contains(null) &&
            scheduleHost.CallerReadAccessChecks.Contains("os_sr_cand") &&
            scheduleHost.CallerReadAccessChecks.Contains("os_sr_intv"),
            "SDK scheduling uses fixed SYSTEM storage with explicit caller read-access checks: " +
            string.Join(",", scheduleHost.ServiceOperations));
        Check(scheduleHost.Receipt!.GetAttributeValue<string>("os_sr_oprc_cact") == "MarkRound1Scheduled",
            "SDK schedule operation records idempotency Receipt");

        var confirmScheduleHost = new Host(-1) { Status = ActionRequest.Waiting };
        SetScheduleAction(confirmScheduleHost, "MarkRound1Scheduled", ActionRequest.Waiting);
        confirmScheduleHost.ProposedRound1Schedule = ScheduleEntity(ActionRequest.ScheduleProposed);
        confirmScheduleHost.MainValues = Context(confirmScheduleHost.Input, confirmScheduleHost.Shared, confirmScheduleHost.Output);
        confirmScheduleHost.MainContext = Execution(confirmScheduleHost.MainValues);
        new ApplyCandidateAction().Execute(confirmScheduleHost);
        Check(confirmScheduleHost.ScheduleCreates == 0 && confirmScheduleHost.ScheduleUpdates == 1 &&
            confirmScheduleHost.Round1Schedule?.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value ==
                ActionRequest.ScheduleActive &&
            confirmScheduleHost.ProposedRound1Schedule == null &&
            confirmScheduleHost.Status == ActionRequest.Scheduled,
            "SDK Schedule Round 1 promotes one persisted Proposed row without creating a duplicate");

        var rescheduleHost = new Host(-1) { Status = ActionRequest.Scheduled };
        SetScheduleAction(rescheduleHost, "RequestReschedule", ActionRequest.Scheduled);
        rescheduleHost.Round1Schedule = ScheduleEntity(ActionRequest.ScheduleActive);
        rescheduleHost.MainValues = Context(rescheduleHost.Input, rescheduleHost.Shared, rescheduleHost.Output);
        rescheduleHost.MainContext = Execution(rescheduleHost.MainValues);
        new ApplyCandidateAction().Execute(rescheduleHost);
        Check(rescheduleHost.ScheduleUpdates == 1 && rescheduleHost.ScheduleCreates == 1 &&
            rescheduleHost.Round1Schedule.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value ==
                ActionRequest.ScheduleSuperseded &&
            rescheduleHost.Round1Schedule.GetAttributeValue<string>("os_sr_intv_rsn") ==
                "Synthetic schedule change" &&
            rescheduleHost.Round1Schedule.Contains("os_sr_intv_chg") &&
            rescheduleHost.ProposedRound1Schedule?.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value ==
                ActionRequest.ScheduleProposed &&
            rescheduleHost.Status == ActionRequest.NeedCall && rescheduleHost.Histories == 1 &&
            rescheduleHost.Receipt != null,
            "SDK reschedule preserves superseded evidence, stores reason/time, creates Proposed replacement, then resets Candidate");

        var cancelHost = new Host(-1) { Status = ActionRequest.Scheduled };
        SetScheduleAction(cancelHost, "CancelRound1", ActionRequest.Scheduled);
        cancelHost.Round1Schedule = ScheduleEntity(ActionRequest.ScheduleActive);
        cancelHost.MainValues = Context(cancelHost.Input, cancelHost.Shared, cancelHost.Output);
        cancelHost.MainContext = Execution(cancelHost.MainValues);
        new ApplyCandidateAction().Execute(cancelHost);
        Check(cancelHost.ScheduleUpdates == 1 &&
            cancelHost.Round1Schedule.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value ==
                ActionRequest.ScheduleCancelled &&
            cancelHost.Round1Schedule.GetAttributeValue<string>("os_sr_intv_rsn") ==
                "Synthetic schedule change" && cancelHost.Round1Schedule.Contains("os_sr_intv_chg") &&
            cancelHost.Status == ActionRequest.NeedCall && cancelHost.Histories == 1 &&
            cancelHost.Receipt != null,
            "SDK cancel preserves schedule reason/time before Candidate reset, History, and Receipt");

        var auditPending = new Host(100010000) { OrganizationAuditEnabled = false };
        new ApplyCandidateAction().Execute(auditPending);
        Check(auditPending.Calls == 1 && auditPending.Updates == 1 && auditPending.Receipt != null,
            "SDK organization audit state does not block operation evidence");
        Check(auditPending.OrganizationReads == 0, "SDK does not query organization audit state");
        var validUpdate = new Host(100010000);
        validUpdate.Input["ActionType"] = "UpdateCandidate";
        validUpdate.Input["ProfileFieldMask"] =
            "CandidateName,CandidatePhone,PositionId,CandidateSourceId,CandidateCvUrl,AssignedTaId";
        validUpdate.Input["CandidateName"] = "Synthetic Replacement";
        var updatedPositionId = Guid.NewGuid();
        var updatedTaId = Guid.NewGuid();
        validUpdate.Input["CandidateCvUrl"] = "https://careers.example.invalid/cv/updated";
        validUpdate.Input["CandidatePhone"] = null;
        validUpdate.Input["PositionId"] = updatedPositionId;
        validUpdate.Input["CandidateSourceId"] = null;
        validUpdate.Input["AssignedTaId"] = updatedTaId;
        validUpdate.Input.Remove("CallOutcome");
        validUpdate.Input.Remove("ContactedAt");
        validUpdate.Input.Remove("ExpectedStatus");
        validUpdate.Input["ExpectedStatus"] = ActionRequest.NeedCall;
        new ApplyCandidateAction().Execute(validUpdate);
        Check(validUpdate.Updates == 1 && validUpdate.CandidateRequests.Count == 1,
            "SDK UpdateCandidate accepts matching ExpectedStatus");
        var profileUpdateTarget = validUpdate.CandidateRequests.Single().Target;
        Check(profileUpdateTarget.GetAttributeValue<string>("os_sr_cand_nm") == "Synthetic Replacement" &&
            profileUpdateTarget.GetAttributeValue<string>("os_sr_cand_cvurl") ==
                "https://careers.example.invalid/cv/updated" &&
            profileUpdateTarget.Contains("os_sr_cand_phn") &&
            profileUpdateTarget.GetAttributeValue<string>("os_sr_cand_phn") == null &&
            profileUpdateTarget.GetAttributeValue<EntityReference>("os_sr_cand_pos")?.Id == updatedPositionId &&
            profileUpdateTarget.Contains("os_sr_cand_csrc") &&
            profileUpdateTarget.GetAttributeValue<EntityReference>("os_sr_cand_csrc") == null &&
            profileUpdateTarget.GetAttributeValue<EntityReference>("os_sr_cand_ta")?.Id == updatedTaId &&
            validUpdate.Calls == 0 && validUpdate.Histories == 0,
            "SDK UpdateCandidate persists profile changes and explicit clears without workflow side effects");
        var minimalProfileUpdate = CreateProfileUpdateHost();
        var defaultedProfileUpdate = CreateProfileUpdateHost();
        defaultedProfileUpdate.Input["CorrelationId"] = minimalProfileUpdate.Input["CorrelationId"];
        minimalProfileUpdate.Input.Remove("CandidatePhone");
        minimalProfileUpdate.Input.Remove("CandidateCvUrl");
        foreach (var lookupName in new[] { "PositionId", "CandidateSourceId", "AssignedTaId" })
            minimalProfileUpdate.Input.Remove(lookupName);
        defaultedProfileUpdate.Input["CandidatePhone"] = null;
        defaultedProfileUpdate.Input["CandidateCvUrl"] = null;
        var profileLookups = new[]
        {
            (Parameter: "PositionId", Attribute: "os_sr_cand_pos"),
            (Parameter: "CandidateSourceId", Attribute: "os_sr_cand_csrc"),
            (Parameter: "AssignedTaId", Attribute: "os_sr_cand_ta")
        };
        foreach (var lookup in profileLookups)
            defaultedProfileUpdate.Input[lookup.Parameter] = Guid.Empty;
        new ApplyCandidateAction().Execute(minimalProfileUpdate);
        new ApplyCandidateAction().Execute(defaultedProfileUpdate);
        var defaultedTarget = defaultedProfileUpdate.CandidateRequests.Single().Target;
        Check(defaultedTarget.Attributes.Count == 1 &&
            defaultedTarget.GetAttributeValue<string>("os_sr_cand_nm") == "Synthetic Replacement" &&
            defaultedProfileUpdate.Updates == 1 && defaultedProfileUpdate.Calls == 0 &&
            defaultedProfileUpdate.Histories == 0 && defaultedProfileUpdate.Status == ActionRequest.NeedCall,
            "SDK unmasked null text and GUID defaults preserve unchanged optional fields and workflow state");
        Check(defaultedProfileUpdate.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash") ==
            minimalProfileUpdate.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash"),
            "SDK defaulted and omitted UpdateCandidate lookups have identical fingerprints");
        var nullDefaultedProfileUpdate = CreateProfileUpdateHost();
        nullDefaultedProfileUpdate.Input["CorrelationId"] = minimalProfileUpdate.Input["CorrelationId"];
        nullDefaultedProfileUpdate.Input["CandidatePhone"] = null;
        nullDefaultedProfileUpdate.Input["CandidateCvUrl"] = null;
        foreach (var lookup in profileLookups) nullDefaultedProfileUpdate.Input[lookup.Parameter] = null;
        new ApplyCandidateAction().Execute(nullDefaultedProfileUpdate);
        var nullDefaultedTarget = nullDefaultedProfileUpdate.CandidateRequests.Single().Target;
        Check(nullDefaultedTarget.Attributes.Count == 1 &&
            !nullDefaultedTarget.Contains("os_sr_cand_phn") &&
            !nullDefaultedTarget.Contains("os_sr_cand_cvurl") &&
            profileLookups.All(lookup => !nullDefaultedTarget.Contains(lookup.Attribute)) &&
            nullDefaultedProfileUpdate.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash") ==
                minimalProfileUpdate.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash"),
            "SDK unmasked null optional defaults preserve all optional profile fields");
        new ApplyCandidateAction().Execute(defaultedProfileUpdate);
        Check((string)defaultedProfileUpdate.Output["ResultCode"] == "DuplicateReplay" &&
            defaultedProfileUpdate.Updates == 1,
            "SDK transport-default profile replay performs no second Candidate update");
        var consoleProfileUpdate = CreateProfileUpdateHost();
        consoleProfileUpdate.Input["ProfileFieldMask"] = "CandidateEmail,CandidatePhone,CandidateCvUrl";
        consoleProfileUpdate.Input["CandidateEmail"] = "edited@example.invalid";
        consoleProfileUpdate.Input["CandidatePhone"] = "+15550101002";
        consoleProfileUpdate.Input["CandidateCvUrl"] = "https://careers.example.invalid/cv/updated";
        foreach (var lookup in profileLookups) consoleProfileUpdate.Input[lookup.Parameter] = Guid.Empty;
        new ApplyCandidateAction().Execute(consoleProfileUpdate);
        var consoleProfileTarget = consoleProfileUpdate.CandidateRequests.Single().Target;
        Check(consoleProfileTarget.Attributes.Count == 3 &&
            !consoleProfileTarget.Contains("os_sr_cand_nm") &&
            consoleProfileTarget.GetAttributeValue<string>("os_sr_cand_eml") == "edited@example.invalid" &&
            consoleProfileTarget.GetAttributeValue<string>("os_sr_cand_phn") == "+15550101002" &&
            consoleProfileTarget.GetAttributeValue<string>("os_sr_cand_cvurl") ==
                "https://careers.example.invalid/cv/updated" &&
            consoleProfileUpdate.Calls == 0 && consoleProfileUpdate.Histories == 0,
            "SDK matches the rejected Console edit payload shape without mutating its unchanged lookups");
        var unmaskedDefaultProfileUpdate = CreateProfileUpdateHost();
        unmaskedDefaultProfileUpdate.Input.Remove("ProfileFieldMask");
        unmaskedDefaultProfileUpdate.Input["CandidateName"] = null;
        unmaskedDefaultProfileUpdate.Input["CandidateEmail"] = "";
        unmaskedDefaultProfileUpdate.Input["CandidatePhone"] = "+15550101003";
        foreach (var lookup in profileLookups)
            unmaskedDefaultProfileUpdate.Input[lookup.Parameter] = Guid.Empty;
        Reject(() => new ApplyCandidateAction().Execute(unmaskedDefaultProfileUpdate), "PROFILE_FIELD_MASK_REQUIRED");
        Check(unmaskedDefaultProfileUpdate.Updates == 0 && unmaskedDefaultProfileUpdate.Receipt == null,
            "SDK rejects an UpdateCandidate request without a field mask before mutation");
        var maskedPhoneUpdate = CreateProfileUpdateHost();
        maskedPhoneUpdate.Input["ProfileFieldMask"] = "CandidatePhone";
        maskedPhoneUpdate.Input["CandidateName"] = null;
        maskedPhoneUpdate.Input["CandidateEmail"] = "";
        maskedPhoneUpdate.Input["CandidatePhone"] = "+15550101004";
        foreach (var lookup in profileLookups) maskedPhoneUpdate.Input[lookup.Parameter] = Guid.Empty;
        new ApplyCandidateAction().Execute(maskedPhoneUpdate);
        var maskedPhoneTarget = maskedPhoneUpdate.CandidateRequests.Single().Target;
        Check(maskedPhoneTarget.Attributes.Count == 1 &&
            maskedPhoneTarget.GetAttributeValue<string>("os_sr_cand_phn") == "+15550101004" &&
            maskedPhoneUpdate.Updates == 1 && maskedPhoneUpdate.Receipt != null,
            "SDK ProfileFieldMask applies a phone-only edit despite defaulted text and lookup parameters");
        var saturatedInputNames = new HashSet<string>(new[]
        {
            "ActionType", "CandidateId", "ExpectedStatus", "CorrelationId",
            "CandidateName", "CandidateEmail", "CandidatePhone", "CandidateCvUrl",
            "PositionId", "CandidateSourceId", "AssignedTaId", "ProfileFieldMask",
            "Reason", "CallOutcome", "ContactedAt", "Notes", "InterviewerId",
            "LocationId", "StartAt", "EndAt", "ResultNotes"
        }, StringComparer.Ordinal);
        var saturatedUnmaskedTextVariants = new[]
        {
            (Name: (object?)null, Email: (object?)"", Phone: "+15550101005",
                CvUrl: "https://careers.example.invalid/cv/saturated-null-name"),
            (Name: (object?)"", Email: (object?)null, Phone: "+15550101006",
                CvUrl: "https://careers.example.invalid/cv/saturated-null-email")
        };
        foreach (var variant in saturatedUnmaskedTextVariants)
        {
            var saturatedUpdate = CreateProfileUpdateHost();
            saturatedUpdate.Input["CandidateName"] = variant.Name;
            saturatedUpdate.Input["CandidateEmail"] = variant.Email;
            saturatedUpdate.Input["CandidatePhone"] = variant.Phone;
            saturatedUpdate.Input["CandidateCvUrl"] = variant.CvUrl;
            saturatedUpdate.Input["PositionId"] = Guid.Empty;
            saturatedUpdate.Input["CandidateSourceId"] = Guid.Empty;
            saturatedUpdate.Input["AssignedTaId"] = Guid.Empty;
            saturatedUpdate.Input["ProfileFieldMask"] = "CandidatePhone,CandidateCvUrl";
            saturatedUpdate.Input["Reason"] = null;
            saturatedUpdate.Input["CallOutcome"] = new OptionSetValue(0);
            saturatedUpdate.Input["ContactedAt"] = DateTime.MinValue;
            saturatedUpdate.Input["Notes"] = null;
            saturatedUpdate.Input["InterviewerId"] = Guid.Empty;
            saturatedUpdate.Input["LocationId"] = Guid.Empty;
            saturatedUpdate.Input["StartAt"] = DateTime.MinValue;
            saturatedUpdate.Input["EndAt"] = DateTime.MinValue;
            saturatedUpdate.Input["ResultNotes"] = null;
            Check(saturatedUpdate.Input.Count == 21 &&
                saturatedInputNames.SetEquals(saturatedUpdate.Input.Keys),
                "SDK saturated profile diagnostic uses the exact 21-input API shape");
            new ApplyCandidateAction().Execute(saturatedUpdate);
            var saturatedTarget = saturatedUpdate.CandidateRequests.Single().Target;
            Check(saturatedTarget.Attributes.Count == 2 &&
                !saturatedTarget.Contains("os_sr_cand_nm") &&
                !saturatedTarget.Contains("os_sr_cand_eml") &&
                !saturatedTarget.Contains("os_sr_cand_pos") &&
                !saturatedTarget.Contains("os_sr_cand_csrc") &&
                !saturatedTarget.Contains("os_sr_cand_ta") &&
                saturatedTarget.GetAttributeValue<string>("os_sr_cand_phn") == variant.Phone &&
                saturatedTarget.GetAttributeValue<string>("os_sr_cand_cvurl") == variant.CvUrl &&
                saturatedUpdate.Updates == 1 && saturatedUpdate.Receipt != null,
                "SDK saturated masked edit ignores unmasked null/empty text and defaulted lookup values");
            Check(saturatedUpdate.Status == ActionRequest.NeedCall &&
                saturatedUpdate.Calls == 0 && saturatedUpdate.Histories == 0,
                "SDK saturated profile-only edit preserves workflow status and history");
        }
        var legacySdkReplay = CreateProfileUpdateHost();
        var legacySdkRequest = new ActionRequest(Actor, legacySdkReplay.Input.ToDictionary(
            pair => pair.Key, pair => (object?)pair.Value, StringComparer.Ordinal), DateTime.UtcNow);
        var legacySdkReceipt = new Entity("os_sr_oprc", Guid.NewGuid())
        {
            ["os_sr_oprc_corid"] = ((Guid)legacySdkReplay.Input["CorrelationId"]).ToString("D"),
            ["os_sr_oprc_cact"] = "UpdateCandidate",
            ["os_sr_oprc_hash"] = legacySdkRequest.LegacyFingerprint,
            ["os_sr_oprc_ver"] = "1",
            ["os_sr_oprc_cand"] = new EntityReference("os_sr_cand", Candidate),
            ["os_sr_oprc_newstat"] = ActionRequest.NeedCall
        };
        legacySdkReplay.Receipt = legacySdkReceipt;
        new ApplyCandidateAction().Execute(legacySdkReplay);
        Check((string)legacySdkReplay.Output["ResultCode"] == "DuplicateReplay" &&
            legacySdkReplay.Updates == 0 && legacySdkReplay.Receipt == legacySdkReceipt &&
            legacySdkReceipt.GetAttributeValue<string>("os_sr_oprc_hash") == legacySdkRequest.LegacyFingerprint,
            "SDK replays a matching historical maskless receipt without updating Candidate or rewriting receipt");
        var legacyPhoneCvReplay = CreateProfileUpdateHost();
        legacyPhoneCvReplay.Input["ProfileFieldMask"] = "CandidatePhone,CandidateCvUrl";
        legacyPhoneCvReplay.Input.Remove("CandidateName");
        legacyPhoneCvReplay.Input["CandidatePhone"] = "+15550101011";
        legacyPhoneCvReplay.Input["CandidateCvUrl"] =
            "https://careers.example.invalid/cv/legacy";
        var legacyPhoneCvRequest = new ActionRequest(Actor, legacyPhoneCvReplay.Input.ToDictionary(
            pair => pair.Key, pair => (object?)pair.Value, StringComparer.Ordinal), DateTime.UtcNow);
        var legacyPhoneCvReceipt = new Entity("os_sr_oprc", Guid.NewGuid())
        {
            ["os_sr_oprc_corid"] =
                ((Guid)legacyPhoneCvReplay.Input["CorrelationId"]).ToString("D"),
            ["os_sr_oprc_cact"] = "UpdateCandidate",
            ["os_sr_oprc_hash"] = legacyPhoneCvRequest.LegacyFingerprint,
            ["os_sr_oprc_ver"] = "1",
            ["os_sr_oprc_cand"] = new EntityReference("os_sr_cand", Candidate),
            ["os_sr_oprc_newstat"] = ActionRequest.NeedCall
        };
        legacyPhoneCvReplay.Receipt = legacyPhoneCvReceipt;
        new ApplyCandidateAction().Execute(legacyPhoneCvReplay);
        Check((string)legacyPhoneCvReplay.Output["ResultCode"] == "DuplicateReplay" &&
            legacyPhoneCvReplay.Updates == 0 && legacyPhoneCvReplay.Receipt == legacyPhoneCvReceipt &&
            legacyPhoneCvReceipt.GetAttributeValue<string>("os_sr_oprc_hash") ==
                legacyPhoneCvRequest.LegacyFingerprint,
            "SDK replays a historical Phone/CV maskless receipt without Candidate update or receipt rewrite");
        var optionalProfileFields = new[]
        {
            (Parameter: "CandidatePhone", Attribute: "os_sr_cand_phn"),
            (Parameter: "CandidateCvUrl", Attribute: "os_sr_cand_cvurl"),
            (Parameter: "PositionId", Attribute: "os_sr_cand_pos"),
            (Parameter: "CandidateSourceId", Attribute: "os_sr_cand_csrc"),
            (Parameter: "AssignedTaId", Attribute: "os_sr_cand_ta")
        };
        foreach (var field in optionalProfileFields)
        {
            var clearProfile = CreateProfileUpdateHost();
            clearProfile.Input["CorrelationId"] = minimalProfileUpdate.Input["CorrelationId"];
            clearProfile.Input["ProfileFieldMask"] = field.Parameter;
            clearProfile.Input.Remove("CandidateName");
            clearProfile.Input.Remove("CandidateEmail");
            foreach (var other in profileLookups) clearProfile.Input[other.Parameter] = Guid.Empty;
            clearProfile.Input.Remove(field.Parameter);
            new ApplyCandidateAction().Execute(clearProfile);
            var clearTarget = clearProfile.CandidateRequests.Single().Target;
            Check(clearTarget.Attributes.Count == 1 && clearTarget.Contains(field.Attribute) &&
                clearTarget[field.Attribute] == null &&
                optionalProfileFields.Where(other => other.Parameter != field.Parameter)
                    .All(other => !clearTarget.Contains(other.Attribute)) &&
                clearProfile.Calls == 0 && clearProfile.Histories == 0,
                "SDK masked omission clears only " + field.Parameter + " without workflow side effects");
            var explicitNullInput = clearProfile.Input.ToDictionary(
                pair => pair.Key, pair => (object?)pair.Value, StringComparer.Ordinal);
            explicitNullInput[field.Parameter] = null;
            var explicitNullRequest = new ActionRequest(Actor, explicitNullInput, DateTime.UtcNow);
            Check(clearProfile.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash") ==
                explicitNullRequest.Fingerprint,
                "SDK omitted and explicit-null " + field.Parameter + " clears have identical fingerprints");
            if (field.Parameter == "PositionId" || field.Parameter == "CandidateSourceId" ||
                field.Parameter == "AssignedTaId")
            {
                var emptyGuidProfile = CreateProfileUpdateHost();
                emptyGuidProfile.Input["ProfileFieldMask"] = "CandidateName," + field.Parameter;
                emptyGuidProfile.Input[field.Parameter] = Guid.Empty;
                new ApplyCandidateAction().Execute(emptyGuidProfile);
                var emptyGuidTarget = emptyGuidProfile.CandidateRequests.Single().Target;
                Check(emptyGuidProfile.Updates == 1 && emptyGuidProfile.Receipt != null &&
                    emptyGuidTarget.Attributes.Count == 2 && emptyGuidTarget.Contains(field.Attribute) &&
                    emptyGuidTarget[field.Attribute] == null && emptyGuidTarget.Contains("os_sr_cand_nm"),
                    "SDK masked Guid.Empty clears " + field.Parameter + " alongside other masked fields");
            }
        }
        var liveShapedClear = CreateProfileUpdateHost();
        liveShapedClear.Input["ProfileFieldMask"] = "AssignedTaId";
        liveShapedClear.Input["CandidateName"] = null;
        liveShapedClear.Input["CandidateEmail"] = null;
        liveShapedClear.Input["CandidatePhone"] = null;
        liveShapedClear.Input["CandidateCvUrl"] = null;
        liveShapedClear.Input["PositionId"] = Guid.Empty;
        liveShapedClear.Input["CandidateSourceId"] = Guid.Empty;
        liveShapedClear.Input["AssignedTaId"] = Guid.Empty;
        liveShapedClear.Input["Reason"] = null;
        liveShapedClear.Input["CallOutcome"] = new OptionSetValue(0);
        liveShapedClear.Input["ContactedAt"] = DateTime.MinValue;
        liveShapedClear.Input["Notes"] = null;
        liveShapedClear.Input["InterviewerId"] = Guid.Empty;
        liveShapedClear.Input["LocationId"] = Guid.Empty;
        liveShapedClear.Input["StartAt"] = DateTime.MinValue;
        liveShapedClear.Input["EndAt"] = DateTime.MinValue;
        liveShapedClear.Input["ResultNotes"] = null;
        Check(liveShapedClear.Input.Count == 21 && saturatedInputNames.SetEquals(liveShapedClear.Input.Keys),
            "SDK live-shaped Assigned TA clear uses the exact 21-input API shape");
        new ApplyCandidateAction().Execute(liveShapedClear);
        var liveShapedTarget = liveShapedClear.CandidateRequests.Single().Target;
        Check(liveShapedTarget.Attributes.Count == 1 && liveShapedTarget.Contains("os_sr_cand_ta") &&
            liveShapedTarget["os_sr_cand_ta"] == null && !liveShapedTarget.Contains("ownerid") &&
            liveShapedClear.Updates == 1 && liveShapedClear.Receipt != null &&
            liveShapedClear.Receipt.GetAttributeValue<string>("os_sr_oprc_cact") == "UpdateCandidate" &&
            liveShapedClear.Status == ActionRequest.NeedCall && liveShapedClear.Calls == 0 &&
            liveShapedClear.Histories == 0 && liveShapedClear.ScheduleCreates == 0 &&
            liveShapedClear.ScheduleUpdates == 0,
            "SDK live-shaped masked Assigned TA Guid.Empty default clears only os_sr_cand_ta");
        foreach (var lookup in profileLookups)
        {
            string referenceTable = lookup.Parameter == "PositionId" ? "os_sr_pos" :
                lookup.Parameter == "CandidateSourceId" ? "os_sr_csrc" : "os_sr_ta";
            var clearCorrelation = Guid.NewGuid();
            var clearHashes = new List<string>();
            foreach (var representation in new[] { "omitted", "null", "empty" })
            {
                var maskedClear = CreateProfileUpdateHost();
                maskedClear.Input["CorrelationId"] = clearCorrelation;
                maskedClear.Input["ProfileFieldMask"] = lookup.Parameter;
                maskedClear.Input.Remove("CandidateName");
                foreach (var other in profileLookups) maskedClear.Input[other.Parameter] = Guid.Empty;
                if (representation == "omitted") maskedClear.Input.Remove(lookup.Parameter);
                else maskedClear.Input[lookup.Parameter] = representation == "null" ? null : (object)Guid.Empty;
                new ApplyCandidateAction().Execute(maskedClear);
                var maskedClearTarget = maskedClear.CandidateRequests.Single().Target;
                Check(maskedClearTarget.Attributes.Count == 1 && maskedClearTarget.Contains(lookup.Attribute) &&
                    maskedClearTarget[lookup.Attribute] == null && maskedClear.Updates == 1 &&
                    maskedClear.Receipt != null && maskedClear.Status == ActionRequest.NeedCall &&
                    maskedClear.Calls == 0 && maskedClear.Histories == 0 && maskedClear.ScheduleCreates == 0,
                    "SDK masked " + representation + " " + lookup.Parameter + " clears only " + lookup.Attribute);
                clearHashes.Add(maskedClear.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash"));
            }
            Check(clearHashes.Distinct(StringComparer.Ordinal).Count() == 1,
                "SDK omitted, null, and Guid.Empty masked " + lookup.Parameter + " clears share one fingerprint");
            var preserveHost = CreateProfileUpdateHost();
            preserveHost.Input["CorrelationId"] = clearCorrelation;
            preserveHost.Input[lookup.Parameter] = Guid.Empty;
            new ApplyCandidateAction().Execute(preserveHost);
            var preserveTarget = preserveHost.CandidateRequests.Single().Target;
            Check(!preserveTarget.Contains(lookup.Attribute) && preserveTarget.Attributes.Count == 1 &&
                preserveHost.Receipt!.GetAttributeValue<string>("os_sr_oprc_hash") != clearHashes[0],
                "SDK unmasked Guid.Empty " + lookup.Parameter + " preserves and differs from masked clear");
            var setId = Guid.NewGuid();
            var setHost = CreateProfileUpdateHost();
            setHost.Input["ProfileFieldMask"] = lookup.Parameter;
            setHost.Input.Remove("CandidateName");
            setHost.Input[lookup.Parameter] = setId;
            new ApplyCandidateAction().Execute(setHost);
            var setTarget = setHost.CandidateRequests.Single().Target;
            Check(setTarget.Attributes.Count == 1 &&
                setTarget.GetAttributeValue<EntityReference>(lookup.Attribute)?.Id == setId &&
                setHost.ServiceOperations.Contains("Retrieve:" + referenceTable),
                "SDK masked valid " + lookup.Parameter + " is validated in caller context and set");
            var inactiveSet = CreateProfileUpdateHost();
            inactiveSet.Input["ProfileFieldMask"] = lookup.Parameter;
            inactiveSet.Input.Remove("CandidateName");
            inactiveSet.Input[lookup.Parameter] = Guid.NewGuid();
            inactiveSet.InactiveReferenceTable = referenceTable;
            Reject(() => new ApplyCandidateAction().Execute(inactiveSet),
                "REFERENCE_NOT_AVAILABLE:" + lookup.Parameter);
            Check(inactiveSet.Updates == 0 && inactiveSet.Receipt == null,
                "SDK inactive masked " + lookup.Parameter + " remains rejected before mutation");
        }
        foreach (var lookup in profileLookups)
        {
            var malformedProfile = CreateProfileUpdateHost();
            malformedProfile.Input["ProfileFieldMask"] = "CandidateName," + lookup.Parameter;
            malformedProfile.Input[lookup.Parameter] = Guid.NewGuid().ToString("D");
            Reject(() => new ApplyCandidateAction().Execute(malformedProfile),
                "INVALID_GUID_PARAMETER:" + lookup.Parameter);
            Check(malformedProfile.Updates == 0 && malformedProfile.Receipt == null &&
                !malformedProfile.ServiceFactorySelections.Contains(null),
                "SDK malformed " + lookup.Parameter + " is rejected before SYSTEM storage");
        }
        var emptyDefaultedUpdate = CreateProfileUpdateHost();
        emptyDefaultedUpdate.Input.Remove("CandidateName");
        emptyDefaultedUpdate.Input.Remove("ProfileFieldMask");
        foreach (var lookup in profileLookups) emptyDefaultedUpdate.Input[lookup.Parameter] = Guid.Empty;
        Reject(() => new ApplyCandidateAction().Execute(emptyDefaultedUpdate), "PROFILE_FIELD_MASK_REQUIRED");
        Check(emptyDefaultedUpdate.Updates == 0 && emptyDefaultedUpdate.Receipt == null,
            "SDK GUID defaults cannot manufacture a profile mutation without a mask");
        foreach (string requiredGuid in new[] { "CandidateId", "CorrelationId" })
        {
            var invalidProfile = CreateProfileUpdateHost();
            invalidProfile.Input[requiredGuid] = Guid.Empty;
            Reject(() => new ApplyCandidateAction().Execute(invalidProfile),
                requiredGuid == "CandidateId" ? "INVALID_CANDIDATE" : "INVALID_CORRELATION");
            Check(invalidProfile.Updates == 0 && invalidProfile.Receipt == null,
                "SDK required " + requiredGuid + " is never normalized as an optional lookup");
        }
        var staleUpdate = new Host(100010000) { Status = ActionRequest.Answered };
        staleUpdate.Input["ActionType"] = "UpdateCandidate";
        staleUpdate.Input["ProfileFieldMask"] = "CandidateName";
        staleUpdate.Input["CandidateName"] = "Synthetic Replacement";
        staleUpdate.Input.Remove("CallOutcome");
        staleUpdate.Input.Remove("ContactedAt");
        foreach (var lookup in profileLookups) staleUpdate.Input[lookup.Parameter] = Guid.Empty;
        Reject(() => new ApplyCandidateAction().Execute(staleUpdate), "STALE_EXPECTED_STATUS");
        Check(staleUpdate.Updates == 0 && staleUpdate.Receipt == null &&
            !staleUpdate.ServiceOperations.Any(operation => operation.StartsWith("Create:", StringComparison.Ordinal) ||
                operation.StartsWith("Execute:", StringComparison.Ordinal)),
            "SDK UpdateCandidate validates stale ExpectedStatus before any SYSTEM write");
        foreach (string property in new[] { "IsInTransaction", "Depth", "UserId" })
        {
            var host = new Host(100010000);
            host.MainValues[property] = property == "IsInTransaction" ? (object)false : property == "Depth" ? 2 : (object)Guid.Empty;
            Reject(() => new ApplyCandidateAction().Execute(host), "UNSUPPORTED_EXECUTION_CONTEXT");
        }
        foreach (var kind in new[] { DateTimeKind.Unspecified, DateTimeKind.Local })
        {
            var nonUtcContact = new Host(100010000);
            nonUtcContact.Input["ContactedAt"] = DateTime.SpecifyKind(DateTime.UtcNow.AddMinutes(-1), kind);
            Reject(() => new ApplyCandidateAction().Execute(nonUtcContact), "INVALID_CONTACT_TIME");
            Check(nonUtcContact.ServiceOperations.Count == 0 && nonUtcContact.Receipt == null,
                "SDK adapter passes " + kind + " ContactedAt through unnormalized and rejects before any service call");
        }
        // The plugin reads DateTime.UtcNow after these values are captured, so +5 s is at or inside the boundary.
        foreach (var offset in new[] { TimeSpan.FromMinutes(-1), TimeSpan.Zero, TimeSpan.FromMilliseconds(160),
            ActionRequest.MaxRecordCallFutureClockSkew })
        {
            var acceptedContact = new Host(100010000);
            var submitted = DateTime.UtcNow + offset;
            acceptedContact.Input["ContactedAt"] = submitted;
            new ApplyCandidateAction().Execute(acceptedContact);
            Check((string)acceptedContact.Output["ResultCode"] == "Applied" &&
                acceptedContact.Calls == 1 && acceptedContact.Histories == 1 && acceptedContact.Receipt != null &&
                acceptedContact.Status == ActionRequest.Answered &&
                acceptedContact.CreatedCall!.GetAttributeValue<DateTime>("os_sr_call_ctat") == submitted,
                "SDK RecordCall accepts ContactedAt offset " + offset.Ticks + " ticks and persists it unchanged");
        }
        var futureContact = new Host(100010000);
        futureContact.Input["ContactedAt"] = DateTime.UtcNow.AddSeconds(30);
        Reject(() => new ApplyCandidateAction().Execute(futureContact), "INVALID_CONTACT_TIME");
        Check(futureContact.ServiceOperations.Count == 0 && futureContact.Receipt == null &&
            futureContact.Calls == 0 && futureContact.Histories == 0,
            "SDK RecordCall beyond the future clock-skew tolerance is rejected before any service call");
        var saturatedCall = new Host(100010000);
        var saturatedContact = DateTime.UtcNow.AddMilliseconds(160);
        saturatedCall.Input["ContactedAt"] = saturatedContact;
        saturatedCall.Input["Notes"] = null;
        saturatedCall.Input["CandidateName"] = null;
        saturatedCall.Input["CandidateEmail"] = "";
        saturatedCall.Input["CandidatePhone"] = null;
        saturatedCall.Input["CandidateCvUrl"] = "";
        saturatedCall.Input["PositionId"] = Guid.Empty;
        saturatedCall.Input["CandidateSourceId"] = Guid.Empty;
        saturatedCall.Input["AssignedTaId"] = Guid.Empty;
        saturatedCall.Input["ProfileFieldMask"] = null;
        saturatedCall.Input["Reason"] = null;
        saturatedCall.Input["InterviewerId"] = Guid.Empty;
        saturatedCall.Input["LocationId"] = Guid.Empty;
        saturatedCall.Input["StartAt"] = DateTime.MinValue;
        saturatedCall.Input["EndAt"] = DateTime.MinValue;
        saturatedCall.Input["ResultNotes"] = null;
        Check(saturatedCall.Input.Count == 21 && saturatedInputNames.SetEquals(saturatedCall.Input.Keys),
            "SDK saturated RecordCall uses the exact 21-input API shape");
        new ApplyCandidateAction().Execute(saturatedCall);
        Check((string)saturatedCall.Output["ResultCode"] == "Applied" && saturatedCall.Updates == 1 &&
            saturatedCall.CandidateRequests.Single().Target.Attributes.Keys.All(key => key == "os_sr_cand_stat" || key == "os_sr_cand_ver") &&
            saturatedCall.Calls == 1 && saturatedCall.Histories == 1 && saturatedCall.Receipt != null &&
            saturatedCall.CreatedCall!.GetAttributeValue<DateTime>("os_sr_call_ctat") == saturatedContact,
            "SDK saturated within-tolerance RecordCall ignores platform-default profile and schedule inputs");
        var replayCall = new Host(100010000) { Receipt = saturatedCall.Receipt, Status = ActionRequest.Answered };
        foreach (var parameter in saturatedCall.Input) replayCall.Input[parameter.Key] = parameter.Value;
        new ApplyCandidateAction().Execute(replayCall);
        Check((string)replayCall.Output["ResultCode"] == "DuplicateReplay" && replayCall.Calls == 0 &&
            replayCall.Histories == 0 && replayCall.Updates == 0 && replayCall.Receipt == saturatedCall.Receipt,
            "SDK same CorrelationId and same ContactedAt replays without new writes");
        var conflictCall = new Host(100010000) { Receipt = saturatedCall.Receipt, Status = ActionRequest.Answered };
        foreach (var parameter in saturatedCall.Input) conflictCall.Input[parameter.Key] = parameter.Value;
        conflictCall.Input["ContactedAt"] = saturatedContact.AddMilliseconds(-78);
        Reject(() => new ApplyCandidateAction().Execute(conflictCall), "CORRELATION_CONFLICT");
        Check(conflictCall.Calls == 0 && conflictCall.Histories == 0 && conflictCall.Updates == 0,
            "SDK same CorrelationId with different ContactedAt conflicts without new writes");
        var malicious = new Host(100010000);
        malicious.Input["Actor"] = Guid.NewGuid();
        Reject(() => new ApplyCandidateAction().Execute(malicious), "UNEXPECTED_INPUT:SDK_ADAPTER:OTHER");
        var unknownAction = new Host(100010000);
        unknownAction.Input["ActionType"] = "UnsupportedOperation";
        unknownAction.Input["Actor"] = Guid.NewGuid();
        Reject(() => new ApplyCandidateAction().Execute(unknownAction), "INVALID_ACTION");
        var inapplicableProfileMask = new Host(100010000, createCandidate: true);
        inapplicableProfileMask.Input["ProfileFieldMask"] = "CandidatePhone";
        Reject(() => new ApplyCandidateAction().Execute(inapplicableProfileMask),
            "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:INPUT_VALIDATION:PROFILE_FIELD_MASK_NOT_APPLICABLE");
        Check(inapplicableProfileMask.CreatedCandidates == 0 && inapplicableProfileMask.Receipt == null,
            "SDK rejects profile masks on CreateCandidate before storage");
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
        var createCandidateParent = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 1,
            includeMarker: false);
        var candidateCreateRegistration = RegisterGuard("Create", "os_sr_cand");
        ExecuteGuard("Create", candidateTarget, createCandidateParent, guardExtension: candidateCreateRegistration,
            includeTarget: false);
        Check(true, "Trusted CreateCandidate ancestor allows Candidate Create without Target or marker");
        var receiptForCreate = new Entity("os_sr_oprc", Guid.NewGuid());
        ExecuteGuard("Create", receiptForCreate,
            CreateTrustedParent("CreateCandidate", "Create", receiptForCreate, 1, includeMarker: false));
        Check(true, "Trusted CreateCandidate ancestor allows Receipt Create without marker");
        Reject(() => ExecuteGuard("Delete", candidateTarget, createCandidateParent),
            "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE");
        Reject(() => ExecuteGuard("Create", candidateTarget, createCandidateParent,
            contextMessage: "Update"),
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_UPDATE:TRUSTED_PARENT:ACTIONTYPE_MISMATCH");
        Reject(() => ExecuteGuard("Create", candidateTarget, createCandidateParent,
            contextEntity: "os_sr_call"),
            "DIRECT_WRITE_GUARD_REJECTED:CALL_LOG_CREATE:TRUSTED_PARENT:ACTIONTYPE_MISMATCH");

        var receiptUpdate = new Entity("os_sr_oprc", Guid.NewGuid());
        RejectDirectGuard("Update", receiptUpdate,
            CreateTrustedParent("CreateCandidate", "Update", receiptUpdate, 1),
            "DIRECT_WRITE_GUARD_REJECTED:RECEIPT_UPDATE:TRUSTED_PARENT:ACTIONTYPE_MISMATCH");

        var intentKey = GetGuardIntentKey();
        var validIntent = GetGuardIntent("Create", candidateTarget);
        foreach (var predicate in new[] { "API_MESSAGE_MISMATCH", "STAGE_MISMATCH", "MODE_MISMATCH",
            "TRANSACTION_MISMATCH", "DEPTH_MISMATCH", "USER_CONTEXT_MISMATCH", "INITIATING_USER_MISMATCH",
            "ACTIONTYPE_MISSING", "ACTIONTYPE_MISMATCH", "ANCESTOR_BOUND_EXCEEDED" })
        {
            var host = CreateCandidateHost();
            host.FaultOnCreateTable = "os_sr_cand";
            host.FaultErrorCode = unchecked((int)0x80040265);
            host.FaultMessage = "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:" + predicate;
            Reject(() => new ApplyCandidateAction().Execute(host),
                "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:CANDIDATE_CREATE:0x80040265");
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
        var noRegistrationParent = CreateGuardParent("os_sr_cact",
            new ParameterCollection { ["ActionType"] = "CreateCandidate" }, new ParameterCollection());
        noRegistrationParent["OwningExtension"] = null;
        ExecuteGuard("Create", candidateTarget, Execution(noRegistrationParent));
        Check(true, "Valid server-owned API context does not require OwningExtension metadata lookup");
        var unrelatedParent = CreateGuardParent("Update",
            new ParameterCollection { ["ActionType"] = "CreateCandidate" },
            new ParameterCollection { [intentKey] = validIntent });
        unrelatedParent["OwningExtension"] = new Entity("plugintype",
            Guid.Parse("00000000-0000-0000-0000-000000000202"));
        RejectDirectGuard("Create", candidateTarget, Execution(unrelatedParent),
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:API_MESSAGE_MISMATCH");

        var trustedParent = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 1);
        ExecuteGuard("Create", candidateTarget, trustedParent);
        Check(true, "Trusted Candidate Create is accepted without marker or registration cache");
        var trustedGrandparent = CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 2);
        ExecuteGuard("Create", candidateTarget, trustedGrandparent);
        Check(true, "Trusted Candidate Create marker two ancestors up is accepted");
        ExecuteGuard("Create", candidateTarget,
            CreateTrustedParent("CreateCandidate", "Create", candidateTarget, 8));
        Check(true, "Trusted ancestor at the traversal bound is accepted");

        var wrongMessageParent = CreateTrustedParent("CreateCandidate", "unrelated_operation",
            candidateTarget, 1);
        ExecuteGuard("Create", candidateTarget, wrongMessageParent);
        Check(true, "Action context, not mutation marker fingerprint, authorizes the write");
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
            "DIRECT_WRITE_GUARD_REJECTED:RECEIPT_UPDATE:TRUSTED_PARENT:ACTIONTYPE_MISMATCH");
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
                "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE");
            Reject(() => host.Guard("UpdateMultiple", new Entity(table, Candidate), host.MainContext),
                "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE");
        }
        var changed = new Host(100010000) { TamperTarget = true };
        changed.MainValues["MessageName"] = "unrelated_operation";
        Reject(() => new ApplyCandidateAction().Execute(changed),
            "UNSUPPORTED_EXECUTION_CONTEXT");
        Check(changed.ServiceOperations.Count == 0, "SDK invalid API context rejected before storage");
        foreach (string message in new[] { "Associate", "Disassociate" })
        {
            var values = Context(new ParameterCollection
            {
                ["Target"] = new EntityReference("systemuser", Actor),
                ["Relationship"] = new Relationship("OS_SR_USR_CSH_ACTR")
            }, new ParameterCollection(), new ParameterCollection());
            values["MessageName"] = message;
            values["OwningExtension"] = RegisterGuard(message, null);
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

    private static Host CreateProfileUpdateHost()
    {
        var host = new Host(ActionRequest.NeedCall);
        host.Input["ActionType"] = "UpdateCandidate";
        host.Input["ProfileFieldMask"] = "CandidateName";
        host.Input["CandidateName"] = "Synthetic Replacement";
        host.Input.Remove("CallOutcome");
        host.Input.Remove("ContactedAt");
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
        return "superseded-test-marker";
    }

    private static string GetGuardIntentKey()
    {
        return "superseded_test_marker";
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
        int? childDepth = null, EntityReference? guardExtension = null, bool includeTarget = true,
        bool omitOwningExtension = false, string? contextMessage = null, string? contextEntity = null)
    {
        var input = new ParameterCollection();
        if (includeTarget) input["Target"] = target;
        var child = Context(input,
            shared ?? new ParameterCollection(), new ParameterCollection());
        child["MessageName"] = contextMessage ?? message;
        child["Stage"] = 10;
        child["Depth"] = childDepth ?? (parent == null ? 1 : parent.Depth + 1);
        child["PrimaryEntityName"] = contextEntity ?? target.LogicalName;
        if (omitOwningExtension) child["OwningExtension"] = null;
        else child["OwningExtension"] = guardExtension ?? RegisterGuard(message, target.LogicalName);
        child["ParentContext"] = parent;
        new ProtectCandidateCore().Execute(new ContextProvider(Execution(child),
            Proxy<ITracingService>(call => null)));
    }

    private sealed class Host : IServiceProvider
    {
        public ParameterCollection Input = new ParameterCollection(), Output = new ParameterCollection(), Shared = new ParameterCollection();
        public Dictionary<string, object?> MainValues;
        public IPluginExecutionContext MainContext;
        public Entity? Receipt, ReceiptCreateTarget, CreatedCandidate, CreatedCall, CreatedHistory;
        public int Calls, Histories, Updates, ScheduleCreates, ScheduleUpdates, CreatedCandidates,
            OrganizationReads, CallerProtectedWriteAttempts, Status = 100010000;
        public bool OrganizationAuditEnabled = true, TamperTarget;
        public bool CandidateNumberWasSupplied;
        public List<Guid?> ServiceFactorySelections = new List<Guid?>();
        public List<string> CallerReadAccessChecks = new List<string>();
        public List<string> ProtectedScheduleReadOrder = new List<string>();
        public HashSet<string> CallerReadDeniedTables = new HashSet<string>(StringComparer.Ordinal);
        public List<UpdateRequest> CandidateRequests = new List<UpdateRequest>();
        public List<UpdateRequest> ScheduleRequests = new List<UpdateRequest>();
        public List<string> ServiceOperations = new List<string>();
        public List<string> TraceMessages = new List<string>();
        public List<string> MarkersAtProtectedWrites = new List<string>();
        public Entity? Round1Schedule;
        public Entity? ProposedRound1Schedule;
        public string? FaultOnCreateTable;
        public string? UnknownFailureOnCreateTable;
        public string? FaultOnRetrieveTable;
        public string? FaultOnRetrieveMultipleTable;
        public string? ReferenceReadFailureTable;
        public string? InactiveReferenceTable;
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
        public void ValidateReceiptOwner(Entity row)
        {
            var owner = row.GetAttributeValue<EntityReference>("ownerid");
            if (row.LogicalName == "os_sr_oprc" && owner?.LogicalName == "systemuser" && owner.Id == Actor)
                throw new FaultException<OrganizationServiceFault>(
                    new OrganizationServiceFault
                    {
                        ErrorCode = unchecked((int)0x80040299),
                        Message = "Target principal lacks Read privilege."
                    },
                    new FaultReason("Synthetic service fault"));
        }
        public object GetService(Type serviceType)
        {
            if (serviceType == typeof(IPluginExecutionContext)) return MainContext;
            if (serviceType == typeof(ITracingService)) return CreateTracingService();
            if (serviceType == typeof(IOrganizationServiceFactory))
                return Proxy<IOrganizationServiceFactory>(call =>
                {
                    var serviceUser = (Guid?)call.Args[0];
                    ServiceFactorySelections.Add(serviceUser);
                    return Proxy<IOrganizationService>(request => InvokeService(serviceUser, request));
                });
            throw new Exception("Unexpected service " + serviceType.Name);
        }
        public void Guard(string message, Entity target, IPluginExecutionContext? parent)
        {
            var child = Context(new ParameterCollection { ["Target"] = target }, new ParameterCollection(), new ParameterCollection());
            child["MessageName"] = message; child["Stage"] = 10; child["ParentContext"] = parent;
            child["Depth"] = parent == null ? 1 : parent.Depth + 1;
            child["PrimaryEntityName"] = target.LogicalName;
            child["OwningExtension"] = RegisterGuard(message, target.LogicalName);
            new ProtectCandidateCore().Execute(new ContextProvider(Execution(child), CreateTracingService()));
        }
        private object? InvokeService(Guid? serviceUser, IMethodCallMessage call)
        {
            if (call.MethodName == "Retrieve")
            {
                var table = (string)call.Args[0];
                var protectedTable = table == "os_sr_cand" || table == "os_sr_intv";
                var referenceTable = table == "os_sr_pos" || table == "os_sr_csrc" ||
                    table == "os_sr_ta" || table == "os_sr_loc";
                var devSlice = MainContext.MessageName == "os_sr_devcs";
                if ((protectedTable && serviceUser != (devSlice ? Actor : null)) ||
                    (referenceTable && serviceUser != Actor) ||
                    (table != "organization" && !protectedTable && !referenceTable))
                    throw new Exception("Unexpected read identity or table");
                ServiceOperations.Add("Retrieve:" + table);
                if (table == FaultOnRetrieveTable)
                    throw new FaultException<OrganizationServiceFault>(
                        new OrganizationServiceFault { ErrorCode = FaultErrorCode, Message = FaultMessage },
                        new FaultReason("Synthetic service fault"));
                if (table == "organization")
                {
                    OrganizationReads++;
                    return new Entity(table, Organization) { ["isauditenabled"] = OrganizationAuditEnabled };
                }
                if (table == "os_sr_cand")
                {
                    if (CreatedCandidate != null) return CreatedCandidate;
                    return new Entity(table, Candidate)
                    {
                        RowVersion = "1",
                        ["os_sr_cand_nm"] = "[SYNTHETIC-E2E] Existing SDK test candidate",
                        ["os_sr_cand_eml"] = "existing-sdk@example.invalid",
                        ["os_sr_cand_cnum"] = "CAND-00000001",
                        ["ownerid"] = new EntityReference("systemuser", Actor),
                        ["os_sr_cand_stat"] = new OptionSetValue(Status)
                    };
                }
                if (table == "os_sr_pos" || table == "os_sr_csrc")
                {
                    if (serviceUser != Actor) throw new Exception("Reference read escaped caller context");
                    if (table == ReferenceReadFailureTable)
                        throw new FaultException<OrganizationServiceFault>(
                            new OrganizationServiceFault { ErrorCode = unchecked((int)0x80040220), Message = "SENSITIVE_SENTINEL" },
                            new FaultReason("Synthetic reference access failure"));
                    return new Entity(table, (Guid)call.Args[1])
                    {
                        ["statecode"] = new OptionSetValue(table == InactiveReferenceTable ? 1 : 0)
                    };
                }
                if (table == "os_sr_ta" || table == "os_sr_loc")
                    return new Entity(table, (Guid)call.Args[1])
                    {
                        ["statecode"] = new OptionSetValue(table == InactiveReferenceTable ? 1 : 0)
                    };
                if (table == "os_sr_intv")
                {
                    ProtectedScheduleReadOrder.Add("DETAILS_READ");
                    if (Round1Schedule?.Id == (Guid)call.Args[1]) return Round1Schedule;
                    if (ProposedRound1Schedule?.Id == (Guid)call.Args[1]) return ProposedRound1Schedule;
                    throw new Exception("Unexpected Interview Schedule readback ID");
                }
                throw new Exception("Unexpected Retrieve");
            }
            if (call.MethodName == "RetrieveMultiple")
            {
                var query = (QueryExpression)call.Args[0];
                ServiceOperations.Add("RetrieveMultiple:" + query.EntityName);
                if (query.EntityName == FaultOnRetrieveMultipleTable)
                    throw new FaultException<OrganizationServiceFault>(
                        new OrganizationServiceFault { ErrorCode = FaultErrorCode, Message = FaultMessage },
                        new FaultReason("Synthetic service fault"));
                if (query.EntityName == "os_sr_oprc")
                    Check(serviceUser == null, "SDK SYSTEM service reads Operation Receipt");
                else if (query.EntityName == "os_sr_intv")
                    Check(serviceUser == null && query.TopCount == 2 &&
                        !query.ColumnSet.AllColumns && query.ColumnSet.Columns.Count == 0 &&
                        query.Criteria.Conditions.Any(condition => condition.AttributeName == "os_sr_intv_cand") &&
                        query.Criteria.Conditions.Any(condition => condition.AttributeName == "os_sr_intv_rnd"),
                        "SDK SYSTEM store queries at most two schedule IDs without loading schedule details");
                else
                    throw new Exception("Unexpected RetrieveMultiple identity or table");
                if (query.EntityName == "os_sr_intv")
                {
                    ProtectedScheduleReadOrder.Add("ID_QUERY");
                    bool proposed = query.Criteria.Conditions.Any(condition =>
                        condition.AttributeName == "os_sr_intv_stat" &&
                        condition.Values.Contains(ActionRequest.ScheduleProposed));
                    var schedule = proposed ? ProposedRound1Schedule : Round1Schedule;
                    return schedule == null ? new EntityCollection() :
                        new EntityCollection(new List<Entity> { new Entity("os_sr_intv", schedule.Id) });
                }
                return Receipt == null ? new EntityCollection() : new EntityCollection(new List<Entity> { Receipt });
            }
            if (call.MethodName == "Create")
            {
                var row = (Entity)call.Args[0];
                if (MainContext.MessageName == "os_sr_devcs")
                {
                    if (serviceUser != Actor) throw new Exception("DEV slice unexpectedly used SYSTEM");
                }
                else
                {
                    if (serviceUser != null)
                    {
                        CallerProtectedWriteAttempts++;
                        throw new Exception("Simulated least-privilege caller has no protected Create privilege");
                    }
                    if (!new[] { "os_sr_cand", "os_sr_call", "os_sr_csh", "os_sr_intv", "os_sr_oprc" }
                        .Contains(row.LogicalName))
                        throw new Exception("Candidate Core create used an unsupported storage target");
                }
                ServiceOperations.Add("Create:" + row.LogicalName);
                if (Shared.TryGetValue(GetGuardIntentKey(), out var marker) && marker is string markerValue)
                    MarkersAtProtectedWrites.Add(markerValue);
                if (row.Id == Guid.Empty)
                    row.Id = row.LogicalName == "os_sr_cand" ? Candidate : Guid.NewGuid();
                row[row.LogicalName + "id"] = row.Id;
                row.RowVersion = "1";
                if (TamperTarget) row["unexpected"] = "synthetic";
                if (row.LogicalName == FaultOnCreateTable)
                    throw new FaultException<OrganizationServiceFault>(
                        new OrganizationServiceFault { ErrorCode = FaultErrorCode, Message = FaultMessage },
                        new FaultReason("Synthetic service fault"));
                if (row.LogicalName == UnknownFailureOnCreateTable)
                    throw new InvalidOperationException("SENSITIVE_SENTINEL " + Actor.ToString("D"));
                if (row.LogicalName == "os_sr_call") { Calls++; CreatedCall = row; Check(row.GetAttributeValue<EntityReference>("os_sr_call_ctby").Id == Actor, "SDK Contacted By"); }
                else if (row.LogicalName == "os_sr_csh") { Histories++; CreatedHistory = row; Check(row.GetAttributeValue<EntityReference>("os_sr_csh_actr").Id == Actor, "SDK History Actor"); }
                else if (row.LogicalName == "os_sr_cand")
                {
                    CreatedCandidates++;
                    CreatedCandidate = row;
                    CandidateNumberWasSupplied = row.Contains("os_sr_cand_cnum");
                    row["os_sr_cand_cnum"] = "CAND-00000001";
                    Status = row.GetAttributeValue<OptionSetValue>("os_sr_cand_stat").Value;
                }
                else if (row.LogicalName == "os_sr_oprc")
                {
                    ReceiptCreateTarget = new Entity(row.LogicalName, row.Id);
                    foreach (var attribute in row.Attributes)
                        ReceiptCreateTarget[attribute.Key] = attribute.Value;
                    ValidateReceiptOwner(row);
                    if (!row.Contains("ownerid"))
                        row["ownerid"] = new EntityReference("systemuser", SystemActor);
                    Receipt = row;
                    Receipt["createdby"] = new EntityReference("systemuser", SystemActor);
                }
                else if (row.LogicalName == "os_sr_intv")
                {
                    if (row.GetAttributeValue<EntityReference>("os_sr_intv_cand")?.LogicalName != "os_sr_cand" ||
                        row.GetAttributeValue<EntityReference>("os_sr_intv_ta")?.LogicalName != "os_sr_ta" ||
                        row.GetAttributeValue<EntityReference>("os_sr_intv_loc")?.LogicalName != "os_sr_loc" ||
                        row.GetAttributeValue<OptionSetValue>("os_sr_intv_rnd")?.Value != ActionRequest.Round1)
                        throw new Exception("Interview Schedule create is outside its fixed schema boundary");
                    ScheduleCreates++;
                    if (row.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value == ActionRequest.ScheduleProposed)
                        ProposedRound1Schedule = row;
                    else
                        Round1Schedule = row;
                }
                else throw new Exception("Unexpected Create");
                return row.Id;
            }
            if (call.MethodName == "Update")
            {
                var target = (Entity)call.Args[0];
                if (MainContext.MessageName != "os_sr_devcs" || serviceUser != Actor)
                    throw new Exception("Unexpected caller-context update");
                ServiceOperations.Add("Update:" + target.LogicalName);
                if (target.LogicalName != "os_sr_cand") throw new Exception("Unexpected direct Update");
                Updates++;
                if (target.Contains("os_sr_cand_stat"))
                {
                    Status = target.GetAttributeValue<OptionSetValue>("os_sr_cand_stat").Value;
                    if (CreatedCandidate != null)
                        CreatedCandidate["os_sr_cand_stat"] = new OptionSetValue(Status);
                }
                return null;
            }
            if (call.MethodName == "Execute")
            {
                if (call.Args[0] is RetrievePrincipalAccessRequest accessRequest)
                {
                    if (serviceUser != null ||
                        accessRequest.Principal.Id != Actor ||
                        accessRequest.Target.LogicalName is not ("os_sr_cand" or "os_sr_intv"))
                        throw new Exception("Protected read access check escaped SYSTEM or caller identity boundary");
                    CallerReadAccessChecks.Add(accessRequest.Target.LogicalName);
                    if (accessRequest.Target.LogicalName == "os_sr_intv")
                        ProtectedScheduleReadOrder.Add("ACCESS_CHECK");
                    return new RetrievePrincipalAccessResponse
                    {
                        Results = new ParameterCollection
                        {
                            ["AccessRights"] = CallerReadDeniedTables.Contains(accessRequest.Target.LogicalName)
                                ? AccessRights.None : AccessRights.ReadAccess
                        }
                    };
                }

                var request = (UpdateRequest)call.Args[0];
                if (serviceUser != null || (request.Target.LogicalName != "os_sr_cand" &&
                    request.Target.LogicalName != "os_sr_intv"))
                    throw new Exception("Candidate Core update escaped its SYSTEM table boundary");
                ServiceOperations.Add("Execute:Update:" + request.Target.LogicalName);
                if (Shared.TryGetValue(GetGuardIntentKey(), out var marker) && marker is string markerValue)
                    MarkersAtProtectedWrites.Add(markerValue);
                if (TamperTarget) request.Target["unexpected"] = "synthetic";
                if (request.Target.LogicalName == "os_sr_intv")
                {
                    var existingSchedule = Round1Schedule?.Id == request.Target.Id
                        ? Round1Schedule : ProposedRound1Schedule;
                    if (existingSchedule == null || request.Target.Id != existingSchedule.Id ||
                        request.Target.RowVersion != existingSchedule.RowVersion ||
                        request.ConcurrencyBehavior != ConcurrencyBehavior.IfRowVersionMatches)
                        throw new Exception("Interview Schedule update escaped its fixed row/concurrency boundary");
                    ScheduleRequests.Add(request); ScheduleUpdates++;
                    foreach (var attribute in request.Target.Attributes)
                        existingSchedule[attribute.Key] = attribute.Value;
                    existingSchedule.RowVersion = (int.Parse(existingSchedule.RowVersion) + 1).ToString();
                    if (request.Target.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value ==
                        ActionRequest.ScheduleActive && ProposedRound1Schedule?.Id == existingSchedule.Id)
                    {
                        ProposedRound1Schedule = null;
                        Round1Schedule = existingSchedule;
                    }
                    return new UpdateResponse();
                }
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
