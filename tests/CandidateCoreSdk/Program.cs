using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;
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

    private static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL: " + name);
        passed++;
    }
    private static void Reject(Action action, string code)
    {
        try { action(); throw new Exception("Expected rejection: " + code); }
        catch (InvalidPluginExecutionException error) { Check(error.Message == code, code); }
    }
    private static Dictionary<string, object?> Context(ParameterCollection input, ParameterCollection shared, ParameterCollection output)
    {
        return new Dictionary<string, object?>
        {
            ["MessageName"] = "os_sr_cact", ["Stage"] = 30, ["Mode"] = 0, ["IsInTransaction"] = true,
            ["Depth"] = 1, ["UserId"] = Actor, ["InitiatingUserId"] = Actor, ["OrganizationId"] = Organization,
            ["InputParameters"] = input, ["OutputParameters"] = output, ["SharedVariables"] = shared
        };
    }
    private static T Proxy<T>(Func<IMethodCallMessage, object?> call) => (T)new DynamicProxy(typeof(T), call).GetTransparentProxy();
    private static IPluginExecutionContext Execution(Dictionary<string, object?> values) =>
        Proxy<IPluginExecutionContext>(call => values[call.MethodName.Substring(4)]);

    private static void Main()
    {
        var createWithoutOptionalGuids = CreateCandidateHost();
        new ApplyCandidateAction().Execute(createWithoutOptionalGuids);
        Check(createWithoutOptionalGuids.CreatedCandidates == 1 &&
            !createWithoutOptionalGuids.CreatedCandidate!.Contains("os_sr_cand_pos") &&
            !createWithoutOptionalGuids.CreatedCandidate.Contains("os_sr_cand_csrc") &&
            (int)createWithoutOptionalGuids.Output["CurrentStatus"] == ActionRequest.NeedCall &&
            createWithoutOptionalGuids.Calls == 0 && createWithoutOptionalGuids.Histories == 0 &&
            createWithoutOptionalGuids.Receipt != null,
            "SDK CreateCandidate omits optional GUIDs and uses server-controlled initial status");
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
        var direct = new Host(100010000);
        Reject(() => direct.Guard("Create", new Entity("os_sr_csh", Guid.NewGuid()), null), "DIRECT_CANDIDATE_CORE_WRITE_BLOCKED");
        foreach (string table in new[] { "os_sr_cand", "os_sr_call", "os_sr_csh", "os_sr_oprc" })
        {
            var host = new Host(100010000);
            Reject(() => host.Guard("Delete", new Entity(table, Candidate), host.MainContext), "DIRECT_CANDIDATE_CORE_WRITE_BLOCKED");
            Reject(() => host.Guard("UpdateMultiple", new Entity(table, Candidate), host.MainContext), "DIRECT_CANDIDATE_CORE_WRITE_BLOCKED");
        }
        var changed = new Host(100010000) { TamperTarget = true };
        Reject(() => new ApplyCandidateAction().Execute(changed), "DIRECT_CANDIDATE_CORE_WRITE_BLOCKED");
        Check(changed.Calls == 0, "SDK tampered target rejected before storage");
        foreach (string message in new[] { "Associate", "Disassociate" })
        {
            var values = Context(new ParameterCollection
            {
                ["Target"] = new EntityReference("systemuser", Actor),
                ["Relationship"] = new Relationship("OS_SR_USR_CSH_ACTR")
            }, new ParameterCollection(), new ParameterCollection());
            values["MessageName"] = message;
            Reject(() => new ProtectCandidateCore().Execute(new ContextProvider(Execution(values))), "DIRECT_CANDIDATE_CORE_WRITE_BLOCKED");
            values["InputParameters"] = new ParameterCollection
            {
                ["Target"] = new EntityReference("account", Guid.NewGuid()),
                ["Relationship"] = new Relationship("synthetic_unrelated_relationship")
            };
            new ProtectCandidateCore().Execute(new ContextProvider(Execution(values)));
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
            if (serviceType == typeof(ITracingService)) return Proxy<ITracingService>(call => null);
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
            child["PrimaryEntityName"] = target.LogicalName;
            new ProtectCandidateCore().Execute(new ContextProvider(Execution(child)));
        }
        private object? InvokeService(IMethodCallMessage call)
        {
            if (call.MethodName == "Retrieve")
            {
                var table = (string)call.Args[0];
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
                Check(((QueryExpression)call.Args[0]).EntityName == "os_sr_oprc", "SDK query receipt only");
                return Receipt == null ? new EntityCollection() : new EntityCollection(new List<Entity> { Receipt });
            }
            if (call.MethodName == "Create")
            {
                var row = (Entity)call.Args[0];
                row[row.LogicalName + "id"] = row.Id;
                if (TamperTarget) row["unexpected"] = "synthetic";
                Guard("Create", row, MainContext);
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
                if (TamperTarget) request.Target["unexpected"] = "synthetic";
                Guard("Update", request.Target, MainContext);
                CandidateRequests.Add(request); Updates++;
                if (request.Target.Contains("os_sr_cand_stat")) Status = request.Target.GetAttributeValue<OptionSetValue>("os_sr_cand_stat").Value;
                return new UpdateResponse();
            }
            throw new Exception("Unexpected service method " + call.MethodName);
        }
    }
    private sealed class ContextProvider : IServiceProvider
    {
        private readonly IPluginExecutionContext context;
        public ContextProvider(IPluginExecutionContext context) { this.context = context; }
        public object GetService(Type type) => type == typeof(IPluginExecutionContext) ? context : throw new Exception("Unexpected service");
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
