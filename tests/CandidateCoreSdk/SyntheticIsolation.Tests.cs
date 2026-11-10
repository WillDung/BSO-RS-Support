using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.Remoting.Messaging;
using Microsoft.Crm.Sdk.Messages;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Query;
using os_sr_cact;

internal static partial class Program
{
    private static readonly Guid DevOrganization = (Guid)typeof(ApplyCandidateAction).Assembly
        .GetType("os_sr_cact.DevCandidateSlice")!.GetField("DevelopmentOrganizationId",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!.GetValue(null)!;
    private static readonly Guid Scope = Guid.Parse("10000000-0000-4000-8000-000000000001");
    private static readonly Guid Reference = Guid.Parse("20000000-0000-4000-8000-000000000001");
    private static string IsolationXml => "<syntheticIsolation organizationId=\"" + DevOrganization +
        "\" environmentId=\"" + Organization + "\" actorId=\"" + Actor + "\" scopeId=\"" + Scope +
        "\" expiresUtc=\"" + DateTime.UtcNow.AddHours(1).ToString("yyyy-MM-ddTHH:mm:ssZ") +
        "\" positionId=\"" + Reference + "\" sourceId=\"" + Reference + "\" taId=\"" + Reference +
        "\" locationId=\"" + Reference + "\" />";

    private static void TestSyntheticIsolation()
    {
        var before = passed;
        var policy = SyntheticIsolation.Parse(IsolationXml);
        policy.ValidateContext(DevOrganization, Actor, DateTime.UtcNow);
        Check(policy.ScopeId == Scope && policy.CandidateEmail.EndsWith(".invalid"), "Server derives exact marker identity");
        RejectPolicy(() => policy.ValidateContext(Organization, Actor, DateTime.UtcNow), "SYNTHETIC_ORGANIZATION_REJECTED");
        RejectPolicy(() => policy.ValidateContext(DevOrganization, Guid.NewGuid(), DateTime.UtcNow), "SYNTHETIC_ACTOR_REJECTED");
        RejectPolicy(() => policy.ValidateContext(DevOrganization, Actor, policy.ExpiresUtc), "SYNTHETIC_SCOPE_EXPIRED");
        RejectPolicy(() => SyntheticIsolation.Parse(IsolationXml.Replace("scopeId=", "forged=")),
            "SYNTHETIC_CONFIGURATION_INVALID");
        RejectPolicy(() => SyntheticIsolation.Parse(IsolationXml.Replace(Scope.ToString(), "forged")),
            "SYNTHETIC_CONFIGURATION_INVALID");
        var unscopedDefault = CreateCandidateHost();
        unscopedDefault.Input["SyntheticScopeId"] = Guid.Empty;
        new ApplyCandidateAction().Execute(unscopedDefault);
        Check((string)unscopedDefault.Output["ResultCode"] == "Applied",
            "New optional Guid transport default preserves the ordinary unscoped API");

        var host = new IsolationHost();
        host.Invoke(SyntheticIsolation.VerifyAction);
        Check((string)host.Output["ResultCode"] == "SyntheticIsolationVerified" &&
            ((string)host.Output["IsolationContract"]).Contains("\"calendarEnabled\":false") && host.Writes == 0,
            "Verifier performs zero storage mutations and forbids Calendar");
        host.MissingConfiguration = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CONFIGURATION_MISSING");
        host.MissingConfiguration = false;
        var step = host.Steps[0];
        host.Steps.RemoveAt(0);
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_GUARD_COVERAGE_MISSING");
        host.Steps.Add(step);
        host.Steps.Add(step);
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_GUARD_COVERAGE_MISSING");
        host.Steps.RemoveAt(host.Steps.Count - 1);
        host.TdsEnabled = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_TDS_NOT_DISABLED");
        host.TdsEnabled = false;
        host.SearchEnabled = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_SEARCH_NOT_DISABLED");
        host.SearchEnabled = false;
        host.ChangeTrackingEnabled = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CHANGE_TRACKING_NOT_DISABLED");
        host.ChangeTrackingEnabled = false;
        host.BypassPrivilege = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        host.BypassPrivilege = false;

        var candidate = new Entity("os_sr_cand", Scope)
        {
            ["os_sr_cand_nm"] = policy.CandidateName, ["os_sr_cand_eml"] = policy.CandidateEmail,
            ["ownerid"] = new EntityReference("systemuser", Actor)
        };
        policy.ValidateRow(candidate);
        foreach (var bad in new[]
        {
            new KeyValuePair<string, object>("os_sr_cand_nm", "[SYNTHETIC-E2E] forged"),
            new KeyValuePair<string, object>("os_sr_cand_eml", "synthetic@example.com"),
            new KeyValuePair<string, object>("ownerid", new EntityReference("systemuser", Guid.NewGuid())),
            new KeyValuePair<string, object>("os_sr_cand_ta", new EntityReference("os_sr_ta", Guid.NewGuid()))
        })
        {
            var copy = Clone(candidate);
            copy[bad.Key] = bad.Value;
            RejectPolicy(() => policy.ValidateRow(copy), bad.Key == "os_sr_cand_ta" ?
                "SYNTHETIC_REFERENCE_REJECTED" : "SYNTHETIC_PROFILE_REJECTED");
        }
        foreach (var table in new[] { "os_sr_call", "os_sr_csh", "os_sr_intv", "os_sr_oprc" })
            RejectPolicy(() => policy.ValidateRow(new Entity(table, Guid.NewGuid())
            {
                [table + "_cand"] = new EntityReference("os_sr_cand", Guid.NewGuid())
            }), "SYNTHETIC_CANDIDATE_REJECTED");
        host.ReferenceRows["os_sr_ta"]["statecode"] = new OptionSetValue(1);
        RejectPolicy(() => policy.ValidateReferences(host.Service), "SYNTHETIC_REFERENCE_REJECTED");
        host.ReferenceRows["os_sr_ta"]["statecode"] = new OptionSetValue(0);

        foreach (var table in SyntheticIsolation.Tables)
        {
            var expression = new QueryExpression(table);
            expression.Criteria.FilterOperator = LogicalOperator.Or;
            expression.Criteria.AddCondition(table + "id", ConditionOperator.NotNull);
            policy.ScopeQuery(expression);
            Check(expression.Criteria.FilterOperator == LogicalOperator.And &&
                expression.Criteria.Filters.Count == 2, "Existing OR cannot broaden " + table);
        }
        var join = new QueryExpression("os_sr_cand");
        join.AddLink("account", "os_sr_candid", "accountid");
        RejectPolicy(() => policy.ScopeQuery(join), "SYNTHETIC_QUERY_REJECTED");
        var fetch = new FetchExpression("<fetch><entity name='os_sr_call'><attribute name='os_sr_callid'/>" +
            "<filter type='or'><condition attribute='os_sr_callid' operator='not-null'/></filter></entity></fetch>");
        policy.ScopeQuery(fetch);
        Check(fetch.Query.Contains("link-entity") && fetch.Query.Contains(policy.CandidateEmail),
            "Fetch joins exact parent identity, not just a foreign-key marker");
        RejectPolicy(() => policy.ScopeQuery(new FetchExpression("<fetch aggregate='true'><entity name='os_sr_cand'/></fetch>")),
            "SYNTHETIC_QUERY_REJECTED");
        RejectPolicy(() => policy.ScopeQuery(new QueryByAttribute("os_sr_cand")), "SYNTHETIC_QUERY_REJECTED");
        var crossRoot = new QueryExpression("account");
        crossRoot.AddLink("OS_SR_CAND", "accountid", "os_sr_candid");
        Reject(() => host.ReadProbe(crossRoot), "SYNTHETIC_CROSS_ROOT_QUERY_REJECTED");
        Reject(() => host.ReadProbe(new FetchExpression(
            "<fetch><entity name='account'><link-entity name='OS_SR_CAND' from='os_sr_candid' to='accountid'/></entity></fetch>")),
            "SYNTHETIC_CROSS_ROOT_QUERY_REJECTED");
        Reject(() => host.ReadProbe(new QueryExpression("account"), new Entity("account", Guid.NewGuid())
        {
            ["regardingobjectid"] = new EntityReference("os_sr_cand", Guid.NewGuid())
        }), "SYNTHETIC_EXPANSION_REJECTED");
        var expanded = new Entity("account", Guid.NewGuid());
        expanded.RelatedEntities[new Relationship("synthetic_relation")] =
            new EntityCollection(new List<Entity> { Clone(candidate) });
        Reject(() => host.ReadProbe(new QueryExpression("account"), expanded), "SYNTHETIC_EXPANSION_REJECTED");
        var nested = new Entity("account", Guid.NewGuid());
        nested.RelatedEntities[new Relationship("synthetic_relation")] =
            new EntityCollection(new List<Entity> { new Entity("contact", Guid.NewGuid())
            {
                ["regardingobjectid"] = new EntityReference("os_sr_cand", Guid.NewGuid())
            } });
        Reject(() => host.ReadProbe(new QueryExpression("account"), nested), "SYNTHETIC_EXPANSION_REJECTED");

        foreach (var message in SyntheticIsolation.WriteMessages)
        {
            host.Input.Clear();
            var target = Clone(candidate);
            Reject(() => host.Direct(message, target), "SYNTHETIC_DIRECT_WRITE_REJECTED");
        }
        foreach (var table in SyntheticIsolation.Tables)
            foreach (var message in new[] { "Create", "Update" })
                Reject(() => host.Direct(message, new Entity(table, Guid.NewGuid())), "SYNTHETIC_DIRECT_WRITE_REJECTED");
        foreach (var message in new[] { "Associate", "Disassociate" })
            Reject(() => host.Direct(message, Clone(candidate)), "SYNTHETIC_DIRECT_WRITE_REJECTED");
        Check(host.Writes == 0, "Direct/bulk/upsert/state/relationship bypass attempts write nothing");

        host.Create();
        var createCorrelation = (Guid)host.Input["CorrelationId"];
        Check(host.Writes == 2 && host.Rows.Count == 2 && host.Rows.ContainsKey(Scope),
            "Scoped Create executes existing Candidate and durable Receipt engine");
        host.InvokeAgain();
        Check((string)host.Output["ResultCode"] == "DuplicateReplay" && host.Writes == 2,
            "Duplicate scoped Create writes no second row");
        host.Input["CandidateName"] = "[SYNTHETIC-E2E] forged";
        RejectContains(() => host.InvokeAgain(), "SYNTHETIC_PROFILE_REJECTED");
        Check(host.Writes == 2, "Forged identity cannot replay a valid receipt");
        host.Input["CandidateName"] = policy.CandidateName;
        host.Input.Remove("SyntheticScopeId");
        RejectContains(() => host.InvokeAgain(), "SYNTHETIC_SCOPE_REQUIRED");
        host.Input["SyntheticScopeId"] = Scope;
        host.Input["CorrelationId"] = createCorrelation;

        host.Call();
        var writes = host.Writes;
        Check(host.Rows.Values.Count(row => row.LogicalName == "os_sr_call") == 1 &&
            host.Rows.Values.Count(row => row.LogicalName == "os_sr_csh") == 1,
            "RecordCall preserves atomic same-Candidate Call/History evidence");
        host.InvokeAgain();
        Check(host.Writes == writes && (string)host.Output["ResultCode"] == "DuplicateReplay",
            "Duplicate call preserves receipt idempotency");
        host.Input["CandidateId"] = Guid.NewGuid();
        Reject(() => host.InvokeAgain(), "SYNTHETIC_CANDIDATE_REJECTED");
        Check(host.Writes == writes, "Real Candidate request rejects before mutation");
        host.Input["CandidateId"] = Scope;
        host.Input["AssignedTaId"] = Guid.NewGuid();
        host.Input["ProfileFieldMask"] = "AssignedTaId";
        host.Input["ActionType"] = "UpdateCandidate";
        Reject(() => host.InvokeAgain(), "SYNTHETIC_REFERENCE_REJECTED");
        host.Input.Clear();
        host.Invoke("ProceedToScheduling", ActionRequest.Answered);
        host.Input["InterviewerId"] = Guid.NewGuid();
        host.Input["LocationId"] = Reference;
        host.Input["StartAt"] = DateTime.UtcNow.AddDays(1);
        host.Input["EndAt"] = DateTime.UtcNow.AddDays(1).AddHours(1);
        host.Input["ActionType"] = "MarkRound1Scheduled";
        host.Input["ExpectedStatus"] = ActionRequest.Waiting;
        Reject(() => host.InvokeAgain(), "SYNTHETIC_REFERENCE_REJECTED");
        host.Invoke("MarkRound1Scheduled", ActionRequest.Waiting);
        Check(host.Rows.Values.Single(row => row.LogicalName == "os_sr_intv")
            .GetAttributeValue<EntityReference>("os_sr_intv_cand")?.Id == Scope,
            "Manual schedule remains bound to synthetic Candidate and approved TA/Location");
        host.Input.Clear();
        host.Input["ResultNotes"] = "Synthetic result fixture";
        host.Invoke("RecordPass", ActionRequest.Scheduled);
        Check(host.Rows[Scope].GetAttributeValue<OptionSetValue>("os_sr_cand_stat")?.Value == ActionRequest.Passed,
            "The shared mutation matrix preserves the accepted scoped interview-result action");
        Check(!typeof(ApplyCandidateAction).Assembly.GetReferencedAssemblies().Any(name => name.Name == "System.Memory"),
            "Boundary does not introduce unsupported sandbox System.Memory dependency");
        Console.WriteLine("Synthetic isolation fixture assertions passed: " + (passed - before));
    }

    private static void RejectPolicy(Action action, string code)
    {
        try { action(); throw new Exception("Expected " + code); }
        catch (OperationError error) { Check(error.Message == code, "Policy rejects " + code); }
    }

    private static void RejectContains(Action action, string code)
    {
        try { action(); throw new Exception("Expected " + code); }
        catch (InvalidPluginExecutionException error) { Check(error.Message.Contains(code), "API rejects " + code); }
    }

    private static Entity Clone(Entity row)
    {
        var result = new Entity(row.LogicalName, row.Id) { RowVersion = row.RowVersion };
        foreach (var pair in row.Attributes) result[pair.Key] = pair.Value;
        return result;
    }

    private sealed class IsolationHost : IServiceProvider
    {
        public readonly ParameterCollection Input = new ParameterCollection();
        public readonly ParameterCollection Output = new ParameterCollection();
        public readonly Dictionary<Guid, Entity> Rows = new Dictionary<Guid, Entity>();
        public readonly Dictionary<string, Entity> ReferenceRows = new Dictionary<string, Entity>();
        public readonly List<Entity> Steps = new List<Entity>();
        private readonly Stack<IPluginExecutionContext> stack = new Stack<IPluginExecutionContext>();
        private readonly Guid dangerousPrivilege = Guid.NewGuid();
        public bool MissingConfiguration, TdsEnabled, SearchEnabled, ChangeTrackingEnabled, BypassPrivilege;
        public int Writes;
        public IOrganizationService Service { get; }
        private IPluginExecutionContext Current => stack.Peek();

        public IsolationHost()
        {
            Service = Proxy<IOrganizationService>(ServiceCall);
            foreach (var table in SyntheticIsolation.Tables)
            {
                foreach (var message in new[] { "Create", "Update", "Delete", "Retrieve", "RetrieveMultiple" })
                    AddStep(table, message, message == "Retrieve" ? 40 : 20);
                AddStep(table, "RetrieveMultiple", 40);
            }
            AddStep(null, "Associate", 20);
            AddStep(null, "Disassociate", 20);
            AddStep(null, "RetrieveMultiple", 20, true);
            AddStep(null, "RetrieveMultiple", 40, true);
            AddStep(null, "Retrieve", 40, true);
            foreach (var table in new[] { "os_sr_pos", "os_sr_csrc", "os_sr_ta", "os_sr_loc" })
                ReferenceRows[table] = new Entity(table, Reference)
                {
                    [table == "os_sr_pos" ? "os_sr_pos_ttl" : table + "_nm"] = table == "os_sr_pos" ?
                        "[DEV] Software Engineer" : table == "os_sr_csrc" ? "[DEV] Internal Test Source" :
                        table == "os_sr_ta" ? "[DEV] Synthetic Interviewer" : "[DEV] Test Location",
                    ["statecode"] = new OptionSetValue(0)
                };
        }
        private void AddStep(string? table, string message, int stage, bool readGuard = false)
        {
            var step = new Entity("sdkmessageprocessingstep", Guid.NewGuid())
            {
                ["message.name"] = new AliasedValue("sdkmessage", "name", message),
                ["handler.typename"] = new AliasedValue("plugintype", "typename", readGuard ?
                    typeof(SyntheticIsolationReadGuard).FullName : typeof(SyntheticIsolationGuard).FullName),
                ["mode"] = new OptionSetValue(0), ["stage"] = new OptionSetValue(stage)
            };
            if (table != null)
                step["filter.primaryobjecttypecode"] = new AliasedValue("sdkmessagefilter", "primaryobjecttypecode", table);
            Steps.Add(step);
        }
        public void Create()
        {
            Input.Clear();
            var profile = SyntheticIsolation.Parse(IsolationXml);
            Input["CandidateName"] = profile.CandidateName;
            Input["CandidateEmail"] = profile.CandidateEmail;
            Invoke("CreateCandidate");
        }
        public void Call()
        {
            Input.Clear();
            Input["CallOutcome"] = ActionRequest.NeedCall;
            Input["ContactedAt"] = DateTime.UtcNow.AddSeconds(-1);
            Invoke("RecordCall", ActionRequest.NeedCall);
        }
        public void Invoke(string action, int? status = null)
        {
            if (action == SyntheticIsolation.VerifyAction) Input.Clear();
            Input["ActionType"] = action;
            if (action != SyntheticIsolation.VerifyAction)
            {
                Input["SyntheticScopeId"] = Scope;
                Input["CorrelationId"] = Guid.NewGuid();
                if (action != "CreateCandidate") Input["CandidateId"] = Scope;
                if (status.HasValue) Input["ExpectedStatus"] = status.Value;
                if (action == "MarkRound1Scheduled")
                {
                    Input.Remove("CallOutcome");
                    Input.Remove("ContactedAt");
                    Input["InterviewerId"] = Reference; Input["LocationId"] = Reference;
                    Input["StartAt"] = DateTime.UtcNow.AddDays(1);
                    Input["EndAt"] = DateTime.UtcNow.AddDays(1).AddHours(1);
                }
            }
            InvokeAgain();
        }
        public void InvokeAgain()
        {
            Output.Clear();
            var values = Context(Input, new ParameterCollection(), Output);
            values["OrganizationId"] = DevOrganization;
            stack.Push(Execution(values));
            try { new ApplyCandidateAction().Execute(this); }
            finally { stack.Pop(); }
        }
        public void Direct(string message, Entity target)
        {
            var values = Context(new ParameterCollection
            {
                ["Target"] = message == "Associate" || message == "Disassociate" ? (object)target.ToEntityReference() : target
            }, new ParameterCollection(), new ParameterCollection());
            values["OrganizationId"] = DevOrganization; values["MessageName"] = message;
            values["PrimaryEntityName"] = target.LogicalName; values["Stage"] = 20;
            stack.Push(Execution(values));
            try { new SyntheticIsolationGuard().Execute(this); }
            finally { stack.Pop(); }
        }
        public void ReadProbe(QueryBase query, Entity? row = null)
        {
            var input = new ParameterCollection { ["Query"] = query };
            var output = new ParameterCollection
            {
                ["BusinessEntityCollection"] = new EntityCollection(row == null ? new List<Entity>() : new List<Entity> { row })
            };
            var values = Context(input, new ParameterCollection(), output);
            values["OrganizationId"] = DevOrganization; values["MessageName"] = "RetrieveMultiple";
            foreach (var stage in new[] { 20, 40 })
            {
                values["Stage"] = stage;
                stack.Push(Execution(values));
                try { new SyntheticIsolationReadGuard().Execute(this); }
                finally { stack.Pop(); }
            }
        }
        public object GetService(Type type)
        {
            if (type == typeof(IPluginExecutionContext)) return Current;
            if (type == typeof(ITracingService)) return Proxy<ITracingService>(call => null);
            if (type == typeof(IOrganizationServiceFactory))
                return Proxy<IOrganizationServiceFactory>(call => Service);
            throw new Exception("Unexpected isolation service " + type.Name);
        }
        private void Guard(string message, string table, ParameterCollection input, ParameterCollection output, int stage)
        {
            if (!SyntheticIsolation.Tables.Contains(table)) return;
            var values = Context(input, new ParameterCollection(), output);
            values["OrganizationId"] = DevOrganization; values["MessageName"] = message;
            values["PrimaryEntityName"] = table; values["Stage"] = stage;
            values["Depth"] = Current.Depth + 1; values["ParentContext"] = Current;
            stack.Push(Execution(values));
            try { new SyntheticIsolationGuard().Execute(this); }
            finally { stack.Pop(); }
        }
        private object? ServiceCall(IMethodCallMessage call)
        {
            if (call.MethodName == "Retrieve")
            {
                var table = (string)call.Args[0];
                if (table == "organization") return new Entity(table, DevOrganization)
                    { ["enabletdsendpoint"] = TdsEnabled, ["enablerelevancesearch"] = SearchEnabled };
                var row = ReferenceRows.TryGetValue(table, out var reference) ? Clone(reference) : Clone(Rows[(Guid)call.Args[1]]);
                if (stack.Count > 0) Guard("Retrieve", table, new ParameterCollection(),
                    new ParameterCollection { ["BusinessEntity"] = row }, 40);
                return row;
            }
            if (call.MethodName == "RetrieveMultiple")
            {
                var query = (QueryExpression)call.Args[0];
                if (query.EntityName == "environmentvariabledefinition")
                    return Collection(MissingConfiguration ? Array.Empty<Entity>() : new[] {
                        new Entity(query.EntityName, Reference) { ["statecode"] = new OptionSetValue(0) } });
                if (query.EntityName == "environmentvariablevalue")
                    return Collection(new[] { new Entity(query.EntityName, Reference)
                        { ["value"] = IsolationXml, ["statecode"] = new OptionSetValue(0) } });
                if (query.EntityName == "sdkmessageprocessingstep") return Collection(Steps);
                if (query.EntityName == "sdkmessagefilter") return new EntityCollection();
                if (query.EntityName == "privilege")
                    return Collection(new[] { new Entity("privilege", dangerousPrivilege) { ["name"] = "prvBypassCustomPlugins" } });
                if (stack.Count > 0) Guard("RetrieveMultiple", query.EntityName,
                    new ParameterCollection { ["Query"] = query }, new ParameterCollection(), 20);
                var candidates = ReferenceRows.TryGetValue(query.EntityName, out var row) ?
                    new[] { row } : Rows.Values.Where(value => value.LogicalName == query.EntityName);
                var result = Collection(candidates.Where(value => Matches(value, query.Criteria)).Select(Clone));
                if (stack.Count > 0) Guard("RetrieveMultiple", query.EntityName, new ParameterCollection(),
                    new ParameterCollection { ["BusinessEntityCollection"] = result }, 40);
                return result;
            }
            if (call.MethodName == "Create")
            {
                var row = Clone((Entity)call.Args[0]);
                if (row.Id == Guid.Empty) row.Id = Guid.NewGuid();
                Guard("Create", row.LogicalName, new ParameterCollection { ["Target"] = row }, new ParameterCollection(), 20);
                if (row.LogicalName == "os_sr_cand") row["os_sr_cand_cnum"] = "CAND-SYNTHETIC";
                row.RowVersion = "1";
                Rows.Add(row.Id, row); Writes++;
                return row.Id;
            }
            if (call.MethodName == "Execute")
            {
                if (call.Args[0] is RetrieveEntityRequest)
                    return new RetrieveEntityResponse
                    {
                        Results = new ParameterCollection { ["EntityMetadata"] =
                            new Microsoft.Xrm.Sdk.Metadata.EntityMetadata { ChangeTrackingEnabled = ChangeTrackingEnabled } }
                    };
                if (call.Args[0] is RetrieveUserPrivilegesRequest)
                    return new RetrieveUserPrivilegesResponse
                    {
                        Results = new ParameterCollection { ["RolePrivileges"] = BypassPrivilege ?
                            new[] { new RolePrivilege { PrivilegeId = dangerousPrivilege } } : Array.Empty<RolePrivilege>() }
                    };
                if (call.Args[0] is RetrievePrincipalAccessRequest)
                    return new RetrievePrincipalAccessResponse
                        { Results = new ParameterCollection { ["AccessRights"] = AccessRights.ReadAccess } };
                if (call.Args[0] is UpdateRequest update)
                {
                    Guard("Update", update.Target.LogicalName, new ParameterCollection { ["Target"] = update.Target },
                        new ParameterCollection(), 20);
                    var existing = Rows[update.Target.Id];
                    foreach (var pair in update.Target.Attributes) existing[pair.Key] = pair.Value;
                    existing.RowVersion = (int.Parse(existing.RowVersion) + 1).ToString();
                    Writes++;
                    return new UpdateResponse();
                }
            }
            throw new Exception("Unexpected isolation fixture operation " + call.MethodName);
        }
        private static EntityCollection Collection(IEnumerable<Entity> rows) =>
            new EntityCollection(rows.ToList());
        private static bool Matches(Entity row, FilterExpression filter)
        {
            var conditions = filter.Conditions.Select(condition =>
            {
                object? value = condition.AttributeName == row.LogicalName + "id" ? row.Id :
                    row.Contains(condition.AttributeName) ? row[condition.AttributeName] : null;
                if (value is EntityReference reference) value = reference.Id;
                if (value is OptionSetValue option) value = option.Value;
                if (condition.Operator == ConditionOperator.Null) return value == null;
                if (condition.Operator == ConditionOperator.NotNull) return value != null;
                if (condition.Operator != ConditionOperator.Equal) throw new Exception("Unmodeled fixture predicate");
                return Equals(value, condition.Values[0]);
            }).Concat(filter.Filters.Select(child => Matches(row, child)));
            return filter.FilterOperator == LogicalOperator.And ? conditions.All(value => value) : conditions.Any(value => value);
        }
    }
}
