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
        var audit = new Host(100010000) { Audit = false };
        Reject(() => new ApplyCandidateAction().Execute(audit), "AUDIT_ACTIVATION_PENDING");
        Check(audit.Calls == 0 && audit.Updates == 0 && audit.Receipt == null, "SDK audit gate before mutation");
        foreach (string property in new[] { "IsInTransaction", "Depth", "UserId" })
        {
            var host = new Host(100010000);
            host.MainValues[property] = property == "IsInTransaction" ? (object)false : property == "Depth" ? 2 : (object)Guid.Empty;
            Reject(() => new ApplyCandidateAction().Execute(host), "UNSUPPORTED_EXECUTION_CONTEXT");
        }
        var malicious = new Host(100010000);
        malicious.Input["Actor"] = Guid.NewGuid();
        Reject(() => new ApplyCandidateAction().Execute(malicious), "UNEXPECTED_INPUT");
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

    private sealed class Host : IServiceProvider
    {
        public ParameterCollection Input = new ParameterCollection(), Output = new ParameterCollection(), Shared = new ParameterCollection();
        public Dictionary<string, object?> MainValues;
        public IPluginExecutionContext MainContext;
        public Entity? Receipt;
        public int Calls, Histories, Updates, Status = 100010000;
        public bool Audit = true, TamperTarget;
        public List<Guid?> CallerFactorySelections = new List<Guid?>();
        public List<UpdateRequest> CandidateRequests = new List<UpdateRequest>();
        public Host(int outcome)
        {
            Input["ActionType"] = "RecordCall"; Input["CorrelationId"] = Guid.NewGuid(); Input["CandidateId"] = Candidate;
            Input["ExpectedStatus"] = 100010000; Input["CallOutcome"] = outcome; Input["ContactedAt"] = DateTime.UtcNow.AddMinutes(-1);
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
                if (table == "organization") return new Entity(table, Organization) { ["isauditenabled"] = Audit };
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
