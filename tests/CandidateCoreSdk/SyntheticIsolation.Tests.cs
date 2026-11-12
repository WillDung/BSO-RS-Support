using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Serialization.Json;
using Microsoft.Crm.Sdk.Messages;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Query;
using Microsoft.Xrm.Sdk.Metadata;
using os_sr_cact;

internal static partial class Program
{
    private static readonly Guid DevOrganization = (Guid)typeof(ApplyCandidateAction).Assembly
        .GetType("os_sr_cact.DevCandidateSlice")!.GetField("DevelopmentOrganizationId",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!.GetValue(null)!;
    private static readonly Guid Scope = Guid.Parse("10000000-0000-4000-8000-000000000001");
    private static readonly Guid SingleUserScope = Guid.Parse("10000000-0000-4000-8000-000000000002");
    private static readonly Guid Reference = Guid.Parse("20000000-0000-4000-8000-000000000001");
    private static readonly Guid SingleUserActor = Guid.Parse("30000000-0000-4000-8000-000000000001");
    private static string IsolationXml => "<syntheticIsolation organizationId=\"" + DevOrganization +
        "\" environmentId=\"" + Organization + "\" actorId=\"" + Actor + "\" scopeId=\"" + Scope +
        "\" expiresUtc=\"" + DateTime.UtcNow.AddHours(1).ToString("yyyy-MM-ddTHH:mm:ssZ") +
        "\" positionId=\"" + Reference + "\" sourceId=\"" + Reference + "\" taId=\"" + Reference +
        "\" locationId=\"" + Reference + "\" />";

    private static void TestSyntheticIsolation()
    {
        var before = passed;
        TestScopedServerProof();
        TestVerifierCorrelationContract();
        TestPersistentDevProfile();
        TestSingleUserDevScope();
        TestSyntheticApiScope();
        var policy = SyntheticIsolation.Parse(IsolationXml);
        policy.ValidateContext(DevOrganization, Actor, DateTime.UtcNow);
        Check(policy.ScopeId == Scope && policy.CandidateEmail.EndsWith(".invalid"), "Server derives exact marker identity");
        RejectPolicy(() => policy.ValidateContext(Organization, Actor, DateTime.UtcNow), "SYNTHETIC_ORGANIZATION_REJECTED");
        RejectPolicy(() => policy.ValidateContext(DevOrganization, Guid.NewGuid(), DateTime.UtcNow), "SYNTHETIC_ACTOR_REJECTED");
        RejectPolicy(() => policy.ValidateContext(DevOrganization, Actor, policy.ExpiresUtc!.Value), "SYNTHETIC_SCOPE_EXPIRED");
        RejectPolicy(() => SyntheticIsolation.Parse(IsolationXml.Replace("scopeId=", "forged=")),
            "SYNTHETIC_CONFIGURATION_INVALID");
        RejectPolicy(() => SyntheticIsolation.Parse(IsolationXml.Replace(Scope.ToString(), "forged")),
            "SYNTHETIC_CONFIGURATION_INVALID");
        var unscopedDefault = CreateCandidateHost();
        unscopedDefault.Input["SyntheticScopeId"] = Guid.Empty;
        new ApplyCandidateAction().Execute(unscopedDefault);
        Check((string)unscopedDefault.Output["ResultCode"] == "Applied",
            "New optional Guid transport default preserves the ordinary unscoped API");

        var host = new IsolationHost { LegacyGuardVerification = true };
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
        host.OwnerReadMissing = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_OWNER_REFERENCE_READ_REQUIRED");
        host.OwnerReadMissing = false;
        host.ReceiptReadGranted = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_RECEIPT_READ_REJECTED");
        host.ReceiptReadGranted = false;
        host.MissingPrivilegeMetadata = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_PRIVILEGE_METADATA_MISSING");
        host.MissingPrivilegeMetadata = false;
        foreach (var name in new[] { "prvCreateos_sr_cand", "prvWriteRole", "prvReadContact",
            "prvWriteEnvironmentVariableValue", "prvNewUnknownPrivilege" })
        {
            host.ExtraPrivilegeName = name;
            Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        }

        host.ExtraPrivilegeName = null;
        host.BypassPrivilege = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        host.BypassPrivilege = false;
        host.AddRedundantPostStep();
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_GUARD_COVERAGE_REDUNDANT");
        host.Steps.RemoveAt(host.Steps.Count - 1);
        Check(host.Steps.Count == 32, "All 27 per-table read steps are consolidated into three required global read steps");
        foreach (var globalRead in host.Steps.Where(row =>
            row.GetAttributeValue<AliasedValue>("handler.typename")?.Value as string ==
                typeof(SyntheticIsolationReadGuard).FullName).ToArray())
        {
            host.Steps.Remove(globalRead);
            Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_GUARD_COVERAGE_MISSING");
            host.Steps.Add(globalRead);
        }
        foreach (var message in new[] { "Upsert", "SetState", "SetStateDynamicEntity", "Assign", "Merge",
            "CreateMultiple", "UpdateMultiple", "UpsertMultiple", "DeleteMultiple" })
        {
            host.AddSupportedMessage(message, true);
            Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_GUARD_COVERAGE_MISSING");
            host.AddSupportedGuard(message);
            host.Invoke(SyntheticIsolation.VerifyAction);
            Check((string)host.Output["ResultCode"] == "SyntheticIsolationVerified", "Supported extra message coverage: " + message);
            host.Steps.RemoveAt(host.Steps.Count - 1);
            host.SupportedRows.Clear();
            host.AddSupportedMessage(message, false);
            Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_UNGUARDABLE_MESSAGE");
            host.SupportedRows.Clear();
        }

        var unrelated = new IsolationHost { CallerId = Guid.NewGuid() };
        unrelated.Direct("Create", new Entity("os_sr_cand", Guid.NewGuid()));
        unrelated.Direct("Update", new Entity("os_sr_ta", Guid.NewGuid()));
        unrelated.Direct("Associate", new Entity("os_sr_cand", Guid.NewGuid()));
        var unrelatedJoin = new QueryExpression("account");
        unrelatedJoin.AddLink("os_sr_cand", "accountid", "os_sr_candid");
        unrelated.ReadProbe(unrelatedJoin);
        unrelated.ReadProbe(new QueryExpression("os_sr_cand"),
            new Entity("os_sr_cand", Guid.NewGuid()) { ["os_sr_cand_nm"] = "Unrelated synthetic fixture" });
        RejectContains(() => unrelated.OrdinaryCreate(), "SYNTHETIC_PROFILE_REQUIRED");
        Check(unrelated.Writes == 0,
            "Unscoped ordinary API writes are closed in DEV for callers without an approved profile");
        var metadataOnly = new IsolationHost { MissingConfiguration = true };
        metadataOnly.ReadProbe(new QueryExpression("systemuser"), new Entity("systemuser", Guid.NewGuid()));
        Check(metadataOnly.ProfileLoads == 0, "Unrelated metadata/system reads do not depend on profile availability");

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
        Reject(() => host.ReadProbe(new FetchExpression(
            "<fetch xmlns='urn:fixture'><entity name='account'><link-entity name='os_sr_cand'/></entity></fetch>")),
            "SYNTHETIC_CROSS_ROOT_QUERY_REJECTED");
        Reject(() => host.ReadProbe(new QueryExpression("os_sr_cand"),
            new Entity("os_sr_cand", Scope) { ["os_sr_cand_nm"] = "Outside synthetic scope" }),
            "SYNTHETIC_PROFILE_REJECTED");
        Reject(() => host.ReadProbe(new QueryByAttribute("os_sr_cand")), "SYNTHETIC_QUERY_REJECTED");
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
        Check(host.MaxDepth <= 5 && host.SystemReadGuardCalls > 0 && host.ControlReadGuardCalls > 0,
            "SYSTEM nested Retrieve/query and metadata reads are bounded without a recursive Retrieve loop");
        Console.WriteLine("Synthetic isolation fixture assertions passed: " + (passed - before));
    }

    private static void TestSyntheticApiScope()
    {
        var host = new IsolationHost
        {
            GuardsInstalled = false, TdsEnabled = true, SearchEnabled = true, LegacyGuardVerification = true
        };
        host.Steps.Clear();
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_GUARD_COVERAGE_MISSING");
        Check(host.Writes == 0, "API-only enforcement never issues a full isolation proof");
        host.MissingConfiguration = true;
        RejectContains(() => host.Create(), "SYNTHETIC_CONFIGURATION_MISSING");
        host.MissingConfiguration = false;
        host.Input["CandidateName"] = "[SYNTHETIC-E2E] forged";
        RejectContains(() => host.InvokeAgain(), "SYNTHETIC_PROFILE_REJECTED");
        host.Input["CandidateName"] = SyntheticIsolation.Parse(IsolationXml).CandidateName;
        host.Input.Remove("SyntheticScopeId");
        RejectContains(() => host.InvokeAgain(), "SYNTHETIC_SCOPE_REQUIRED");
        host.Input["SyntheticScopeId"] = Scope;
        host.CallerId = Guid.NewGuid();
        RejectContains(() => host.InvokeAgain(), "SYNTHETIC_ACTOR_REJECTED");
        host.CallerId = Actor;
        host.OrganizationId = Organization;
        RejectContains(() => host.InvokeAgain(), "SYNTHETIC_ORGANIZATION_REJECTED");
        host.OrganizationId = DevOrganization;
        host.ReferenceRows["os_sr_ta"]["statecode"] = new OptionSetValue(1);
        RejectContains(() => host.InvokeAgain(), "SYNTHETIC_REFERENCE_REJECTED");
        host.ReferenceRows["os_sr_ta"]["statecode"] = new OptionSetValue(0);
        Check(host.Writes == 0, "Invalid API scope, identity and references reject without installed guards");
        host.Create();
        var writes = host.Writes;
        host.InvokeAgain();
        Check(host.Writes == writes && (string)host.Output["ResultCode"] == "DuplicateReplay",
            "API-only Create retains receipt idempotency");
        var receipt = host.Rows.Values.Single(row => row.LogicalName == "os_sr_oprc");
        receipt["os_sr_oprc_cand"] = new EntityReference("os_sr_cand", Candidate);
        RejectContains(() => host.InvokeAgain(), "SYNTHETIC_CANDIDATE_REJECTED");
        receipt["os_sr_oprc_cand"] = new EntityReference("os_sr_cand", Scope);
        host.Call();
        writes = host.Writes;
        host.Input["CandidateId"] = Candidate;
        Reject(() => host.InvokeAgain(), "SYNTHETIC_CANDIDATE_REJECTED");
        host.Input["CandidateId"] = Scope;
        var candidate = host.Rows[Scope];
        var profile = SyntheticIsolation.Parse(IsolationXml);
        candidate["os_sr_cand_nm"] = "Outside approved marker";
        Reject(() => host.InvokeAgain(), "SYNTHETIC_PROFILE_REJECTED");
        candidate["os_sr_cand_nm"] = profile.CandidateName;
        candidate["os_sr_cand_eml"] = "outside@example.invalid";
        Reject(() => host.InvokeAgain(), "SYNTHETIC_PROFILE_REJECTED");
        candidate["os_sr_cand_eml"] = profile.CandidateEmail;
        candidate["ownerid"] = new EntityReference("systemuser", Candidate);
        Reject(() => host.InvokeAgain(), "SYNTHETIC_PROFILE_REJECTED");
        candidate["ownerid"] = new EntityReference("team", Actor);
        Reject(() => host.InvokeAgain(), "SYNTHETIC_PROFILE_REJECTED");
        candidate["ownerid"] = new EntityReference("systemuser", Actor);
        host.BeforeCandidateStateRead = row => row["os_sr_cand_nm"] = "Changed after caller validation";
        Reject(() => host.Invoke("ProceedToScheduling", ActionRequest.Answered), "SYNTHETIC_PROFILE_REJECTED");
        host.BeforeCandidateStateRead = null;
        candidate["os_sr_cand_nm"] = profile.CandidateName;
        Check(host.Writes == writes, "Stored identity is revalidated with the row version before any mutation");
        Reject(() => host.Invoke("ProceedToScheduling", ActionRequest.NeedCall), "STALE_EXPECTED_STATUS");
        host.Invoke("ProceedToScheduling", ActionRequest.Answered);
        host.Input["ActionType"] = "MarkRound1Scheduled";
        host.Input["CorrelationId"] = Guid.NewGuid();
        host.Input["ExpectedStatus"] = ActionRequest.Waiting;
        host.Input["InterviewerId"] = Candidate;
        host.Input["LocationId"] = Reference;
        host.Input["StartAt"] = DateTime.UtcNow.AddDays(1);
        host.Input["EndAt"] = DateTime.UtcNow.AddDays(1).AddHours(1);
        Reject(() => host.InvokeAgain(), "SYNTHETIC_REFERENCE_REJECTED");
        host.Input["InterviewerId"] = Reference;
        var scheduleId = Guid.NewGuid();
        host.Rows[scheduleId] = new Entity("os_sr_intv", scheduleId)
        {
            ["os_sr_intv_cand"] = new EntityReference("os_sr_cand", Scope),
            ["os_sr_intv_rnd"] = new OptionSetValue(ActionRequest.Round1),
            ["os_sr_intv_stat"] = new OptionSetValue(ActionRequest.ScheduleProposed),
            ["os_sr_intv_ta"] = new EntityReference("os_sr_ta", Candidate),
            ["os_sr_intv_loc"] = new EntityReference("os_sr_loc", Reference)
        };
        writes = host.Writes;
        Reject(() => host.InvokeAgain(), "SYNTHETIC_REFERENCE_REJECTED");
        Check(host.Writes == writes, "Stored out-of-scope schedule rejects before any update without read guards");
        host.Rows.Remove(scheduleId);
        host.InvokeAgain();
        writes = host.Writes;
        host.InvokeAgain();
        Check(host.Writes == writes && (string)host.Output["ResultCode"] == "DuplicateReplay" &&
            host.Rows[Scope].GetAttributeValue<OptionSetValue>("os_sr_cand_stat")?.Value == ActionRequest.Scheduled,
            "All four API operations complete offline with no guard registrations or channel setting changes");
        Check(host.Rows.Values.Where(row => row.LogicalName != "os_sr_cand").All(row =>
            row.GetAttributeValue<EntityReference>(row.LogicalName + "_cand")?.Id == Scope),
            "API-only Call, History, Schedule and Receipt rows remain bound to the same Candidate");
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_GUARD_COVERAGE_MISSING");
        host.Service.Create(new Entity("os_sr_cand", Candidate)
        {
            ["ownerid"] = new EntityReference("systemuser", Actor),
            ["os_sr_cand_nm"] = "Outside approved marker",
            ["os_sr_cand_eml"] = "outside@example.invalid"
        });
        Check(host.Rows.ContainsKey(Candidate),
            "Modeled elevated native writes are outside API-only enforcement; full isolation is not certified");
    }

    private static void TestScopedServerProof()
    {
        var host = new IsolationHost
        { GuardsInstalled = false, TdsEnabled = true, SearchEnabled = true, IncludeCreateReferences = true };
        host.Steps.Clear();
        host.Invoke(SyntheticIsolation.VerifyAction);
        Check(host.Writes == 0 && ((string)host.Output["IsolationContract"]).Contains(
            "\"boundary\":\"ScopedCandidateCoreApi\""), "Read-only scoped proof needs no guards or global channel changes");
        foreach (var name in new[] { "prvCreateos_sr_cand", "prvWriteos_sr_call", "prvDeleteos_sr_intv",
            "prvAssignos_sr_cand", "prvShareos_sr_cand", "prvBypassCustomPlugins", "prvBypassCustomBusinessLogic",
            "prvActOnBehalfOfAnotherUser", "prvWriteEnvironmentVariableValue", "prvWritePluginAssembly",
            "prvWriteRole", "prvWriteTeam", "prvImportCustomization", "prvWriteWorkflow", "prvWriteWebResource" })
        {
            host.ExtraPrivilegeName = name;
            Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
            RejectContains(() => host.Create(), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        }
        host.ExtraPrivilegeName = "prvWriteUserSettings";
        host.Invoke(SyntheticIsolation.VerifyAction);
        Check(host.Writes == 0, "Unrelated user-setting privileges are not business writes or verifier failures");
        host.ExtraPrivilegeName = null;
        host.OwnerReadMissing = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        host.OwnerReadMissing = false;
        host.ApiContractInvalid = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_API_CONTRACT_REJECTED");
        host.ApiContractInvalid = false;
        host.MissingProofOutput = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_API_CONTRACT_REJECTED");
        host.MissingProofOutput = false;
        host.MissingScopeInput = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_API_CONTRACT_REJECTED");
        host.MissingScopeInput = false;
        host.TeamPrivilegeName = "prvBypassCustomPlugins";
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        host.TeamPrivilegeName = null;
        host.GlobalBusinessRead = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        host.GlobalBusinessRead = false;
        host.InactiveCaller = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_INELIGIBLE");
        host.InactiveCaller = false;
        host.ProfileOverride = IsolationXml.Replace("expiresUtc=\"", "expiresUtc=\"2000-01-01T00:00:00Z\" unused=\"");
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CONFIGURATION_INVALID");
        var expiredProfile = System.Xml.Linq.XElement.Parse(IsolationXml);
        expiredProfile.SetAttributeValue("expiresUtc", "2000-01-01T00:00:00Z");
        host.ProfileOverride = expiredProfile.ToString();
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_SCOPE_EXPIRED");
        host.ProfileOverride = null;
        RejectPolicy(() => host.CallerService.Create(new Entity("os_sr_cand", Scope)), "NATIVE_WRITE_DENIED");
        host.Create();
        host.DenyReadback = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_READBACK_DENIED");
        host.DenyReadback = false;
        host.Invoke(SyntheticIsolation.VerifyAction);
        host.ProfileOverride = expiredProfile.ToString();
        Reject(() => host.Invoke("ProceedToScheduling", ActionRequest.NeedCall), "SYNTHETIC_SCOPE_EXPIRED");
        host.ProfileOverride = null;
        host.Call();
        host.Invoke("ProceedToScheduling", ActionRequest.Answered);
        host.Invoke("MarkRound1Scheduled", ActionRequest.Waiting);
        host.Invoke(SyntheticIsolation.VerifyAction);
        Check(host.Rows[Scope].GetAttributeValue<OptionSetValue>("os_sr_cand_stat")?.Value == ActionRequest.Scheduled &&
            host.Rows.Values.Count(row => row.LogicalName == "os_sr_call") == 1 &&
            host.Rows.Values.Count(row => row.LogicalName == "os_sr_intv") == 1 &&
            host.Rows.Values.Count(row => row.LogicalName == "os_sr_oprc") == 4 &&
            host.Rows.Values.Count(row => row.LogicalName == "os_sr_csh") == 3,
            "Restricted caller completes four API operations with History, receipts and scoped readback");
        Check(host.EffectivePrivilegeRequests > 4, "Team-effective privilege message is rechecked on every API write and proof");
    }

    private static string PersistentIsolationXml
    {
        get
        {
            var root = System.Xml.Linq.XElement.Parse(IsolationXml);
            root.Attribute("expiresUtc")!.Remove();
            root.SetAttributeValue("profileVersion", "2");
            root.SetAttributeValue("lifetime", "PersistentDev");
            root.SetAttributeValue("enabled", "true");
            return root.ToString();
        }
    }

    private static string SingleUserDevXml
    {
        get
        {
            var root = System.Xml.Linq.XElement.Parse(PersistentIsolationXml);
            root.SetAttributeValue("profileVersion", "3");
            root.Add(new System.Xml.Linq.XElement("singleUserDev",
                new System.Xml.Linq.XAttribute("mode", "SingleUserDev"),
                new System.Xml.Linq.XAttribute("actorId", SingleUserActor.ToString("D")),
                new System.Xml.Linq.XAttribute("scopeId", SingleUserScope.ToString("D")),
                new System.Xml.Linq.XAttribute("enabled", "true")));
            return root.ToString();
        }
    }

    private static void TestPersistentDevProfile()
    {
        var xml = PersistentIsolationXml;
        var policy = SyntheticIsolation.Parse(xml);
        Check(policy.Enabled && policy.PersistentDev && !policy.ExpiresUtc.HasValue,
            "Persistent DEV is explicit, enabled and has no expiry sentinel");
        policy.ValidateContext(DevOrganization, Actor, DateTime.UtcNow.AddYears(10));
        Check(policy.CandidateName == SyntheticIsolation.Parse(IsolationXml).CandidateName &&
            policy.CandidateEmail == SyntheticIsolation.Parse(IsolationXml).CandidateEmail,
            "Persistent mode preserves the exact synthetic marker");
        RejectPolicy(() => policy.ValidateContext(Organization, Actor, DateTime.UtcNow),
            "SYNTHETIC_ORGANIZATION_REJECTED");
        RejectPolicy(() => policy.ValidateContext(DevOrganization, Guid.NewGuid(), DateTime.UtcNow),
            "SYNTHETIC_ACTOR_REJECTED");
        foreach (var attribute in new[] { "profileVersion", "lifetime", "enabled", "actorId", "scopeId",
            "organizationId", "environmentId", "positionId", "sourceId", "taId", "locationId" })
        {
            var corrupt = System.Xml.Linq.XElement.Parse(xml);
            corrupt.Attribute(attribute)!.Remove();
            RejectPolicy(() => SyntheticIsolation.Parse(corrupt.ToString()), "SYNTHETIC_CONFIGURATION_INVALID");
        }
        foreach (var change in new Dictionary<string, string> {
            ["profileVersion"] = "3", ["lifetime"] = "Unlimited", ["enabled"] = "TRUE",
            ["expiresUtc"] = "2099-01-01T00:00:00Z", ["actorId"] = "invalid",
            ["organizationId"] = Organization.ToString() })
        {
            var corrupt = System.Xml.Linq.XElement.Parse(xml);
            corrupt.SetAttributeValue(change.Key, change.Value);
            RejectPolicy(() => SyntheticIsolation.Parse(corrupt.ToString()), "SYNTHETIC_CONFIGURATION_INVALID");
        }
        var noExpiry = System.Xml.Linq.XElement.Parse(IsolationXml);
        noExpiry.Attribute("expiresUtc")!.Remove();
        RejectPolicy(() => SyntheticIsolation.Parse(noExpiry.ToString()), "SYNTHETIC_CONFIGURATION_INVALID");
        var disabled = xml.Replace("enabled=\"true\"", "enabled=\"false\"");
        RejectPolicy(() => SyntheticIsolation.Parse(disabled).Contract(), "SYNTHETIC_PROFILE_DISABLED");
        var host = new IsolationHost { GuardsInstalled = false, IncludeCreateReferences = true, ProfileOverride = xml };
        host.Invoke(SyntheticIsolation.VerifyAction);
        var contract = (string)host.Output["IsolationContract"];
        Check(contract.Contains("\"version\":2") && contract.Contains("\"boundary\":\"ScopedCandidateCoreApi\"") &&
            contract.Contains("\"actorId\":\"" + Actor + "\"") && contract.Contains("\"scopeId\":\"" + Scope + "\"") &&
            contract.Contains("\"calendarEnabled\":false"), "Persistent profile returns existing scoped v2 proof bindings");
        var expires = contract.Split(new[] { "\"validUntil\":\"" }, StringSplitOptions.None)[1].Split('"')[0];
        var validUntil = DateTime.ParseExact(expires, "yyyy-MM-ddTHH:mm:ssZ", System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal);
        Check(validUntil > DateTime.UtcNow && validUntil <= DateTime.UtcNow.AddSeconds(121),
            "Persistent server profile does not make browser proofs persistent");
        host.MissingScopedDataOutput = true;
        host.Invoke(SyntheticIsolation.VerifyAction);
        Check((string)host.Output["ResultCode"] == "SyntheticIsolationVerified",
            "The existing BSO proof does not depend on the new SingleUserDev read response property");
        host.MissingScopedDataOutput = false;
        host.ProfileOverride = disabled;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_PROFILE_DISABLED");
        RejectContains(() => host.Create(), "SYNTHETIC_PROFILE_DISABLED");
        foreach (var action in new[] { "RecordCall", "ProceedToScheduling", "MarkRound1Scheduled" })
            Reject(() => host.Invoke(action, ActionRequest.NeedCall), "SYNTHETIC_PROFILE_DISABLED");
        Check(host.Writes == 0 && host.Rows.Count == 0, "Revocation blocks fresh proof and all scoped mutations before storage");
        host.ProfileOverride = xml;
        host.MissingConfiguration = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CONFIGURATION_MISSING");
        RejectContains(() => host.Create(), "SYNTHETIC_CONFIGURATION_MISSING");
        host.MissingConfiguration = false;
        host.CallerId = Guid.NewGuid();
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_ACTOR_REJECTED");
        host.CallerId = Actor;
        host.OrganizationId = Organization;
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_ORGANIZATION_REJECTED");
        host.OrganizationId = DevOrganization;
        foreach (var reference in host.ReferenceRows.Values)
        {
            reference["statecode"] = new OptionSetValue(1);
            Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_REFERENCE_REJECTED");
            reference["statecode"] = new OptionSetValue(0);
        }
        host.TeamPrivilegeName = "prvBypassCustomPlugins";
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        host.TeamPrivilegeName = null;
        host.ExtraPrivilegeName = "prvCreateos_sr_cand";
        RejectContains(() => host.Create(), "SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        host.ExtraPrivilegeName = null;
        host.Invoke(SyntheticIsolation.VerifyAction);
        Check(host.Writes == 0 && host.Rows.Count == 0, "Enabled restore issues proof without business mutation or receipt");
        host.Create();
        var writes = host.Writes;
        host.Rows[Scope]["os_sr_cand_nm"] = "Out-of-scope synthetic fixture";
        Reject(() => host.Invoke(SyntheticIsolation.VerifyAction), "SYNTHETIC_PROFILE_REJECTED");
        Reject(() => host.Invoke("ProceedToScheduling", ActionRequest.NeedCall), "SYNTHETIC_PROFILE_REJECTED");
        host.Rows[Scope]["os_sr_cand_nm"] = policy.CandidateName;
        host.Input["SyntheticScopeId"] = Guid.NewGuid();
        Reject(() => host.InvokeAgain(), "SYNTHETIC_SCOPE_REQUIRED");
        Check(host.Writes == writes, "Real-row and scope mismatch failures leave all stored records unchanged");
    }

    private static void TestSingleUserDevScope()
    {
        var existingBso = new IsolationHost
        {
            CallerId = Actor,
            ProfileOverride = SingleUserDevXml
        };
        existingBso.Invoke(SyntheticIsolation.VerifyAction);
        Check(((string)existingBso.Output["IsolationContract"]).Contains("\"version\":2") &&
            ((string)existingBso.Output["IsolationContract"]).Contains("\"actorId\":\"" + Actor + "\"") &&
            ((string)existingBso.Output["IsolationContract"]).Contains("\"scopeId\":\"" + Scope + "\""),
            "The embedded operator scope preserves the existing BSO v2 proof bindings");
        existingBso.ReadProbe(new QueryExpression("os_sr_cand"));
        var existingBsoList = (QueryExpression)existingBso.LastReadQuery!;
        bool IncludesBsoScope(FilterExpression filter) =>
            filter.Conditions.Any(condition => condition.Values.Contains(Scope)) ||
            filter.Filters.Any(IncludesBsoScope);
        Check(IncludesBsoScope(existingBsoList.Criteria),
            "The existing BSO guards retain their original scope with the dual-actor profile");

        var host = new IsolationHost
        {
            CallerId = SingleUserActor,
            ProfileOverride = SingleUserDevXml,
            IncludeCreateReferences = true,
            GuardsInstalled = false
        };
        host.Steps.Clear();
        var policy = SyntheticIsolation.ParseSingleUserDev(SingleUserDevXml);
        var bsoPolicy = SyntheticIsolation.Parse(PersistentIsolationXml);
        Check(policy.SingleUserDev && policy.PersistentDev && !policy.ExpiresUtc.HasValue,
            "SingleUserDev is explicit, persistent and separate from the BSO profile");
        Check(policy.ScopeId == SingleUserScope && policy.ScopeId != bsoPolicy.ScopeId &&
            policy.CandidateName == bsoPolicy.CandidateName &&
            policy.CandidateEmail == bsoPolicy.CandidateEmail,
            "SingleUserDev uses a distinct row scope with the exact existing synthetic marker");
        host.Invoke(SyntheticIsolation.VerifySingleUserDevAction);
        var contract = (string)host.Output["IsolationContract"];
        Check((string)host.Output["ResultCode"] == "SingleUserDevVerified" &&
            contract.Contains("\"version\":4") && contract.Contains("\"mode\":\"SingleUserDev\"") &&
            contract.Contains("\"boundary\":\"SingleUserDevCandidateCoreApi\"") &&
            contract.Contains("\"actorId\":\"" + SingleUserActor + "\"") &&
            contract.Contains("\"nativeWritesDenied\":false") &&
            contract.Contains("\"scopedReads\":true") &&
            contract.Contains("\"globalGuardsRequired\":false") &&
            contract.Contains("\"calendarEnabled\":false"),
            "SingleUserDev proof is actor-bound and advertises fixed scoped reads without claiming native privilege isolation");
        var missingGuards = new IsolationHost
        {
            CallerId = SingleUserActor,
            ProfileOverride = SingleUserDevXml,
            GuardsInstalled = false
        };
        missingGuards.Steps.Clear();
        missingGuards.Invoke(SyntheticIsolation.VerifySingleUserDevAction);
        Check((string)missingGuards.Output["ResultCode"] == "SingleUserDevVerified",
            "SingleUserDev proof does not depend on global pipeline guards");
        host.MissingScopedDataOutput = true;
        Reject(() => host.Invoke(SyntheticIsolation.VerifySingleUserDevAction),
            "SYNTHETIC_API_CONTRACT_REJECTED");
        host.MissingScopedDataOutput = false;
        host.Create();
        Check(host.Rows.ContainsKey(SingleUserScope) &&
            host.Rows[SingleUserScope].GetAttributeValue<EntityReference>("ownerid")?.Id == SingleUserActor &&
            host.Writes == 2, "SingleUserDev Create uses only the approved synthetic scope and receipt");
        host.Call();
        var callWrites = host.Writes;
        host.InvokeAgain();
        Check((string)host.Output["ResultCode"] == "DuplicateReplay" && host.Writes == callWrites,
            "SingleUserDev duplicate Call replays the receipt without a second mutation");
        host.Invoke("ProceedToScheduling", ActionRequest.Answered);

        host.Input.Clear();
        host.Input["ActionType"] = "MarkRound1Scheduled";
        host.Input["SyntheticScopeId"] = SingleUserScope;
        host.Input["CandidateId"] = SingleUserScope;
        host.Input["ExpectedStatus"] = ActionRequest.Waiting;
        host.Input["CorrelationId"] = Guid.NewGuid();
        host.Input["InterviewerId"] = Guid.NewGuid();
        host.Input["LocationId"] = Reference;
        host.Input["StartAt"] = DateTime.UtcNow.AddDays(1);
        host.Input["EndAt"] = DateTime.UtcNow.AddDays(1).AddHours(1);
        Reject(() => host.InvokeAgain(), "SYNTHETIC_REFERENCE_REJECTED");
        Check(host.Writes == callWrites + 3, "Rejected reference mutation writes no schedule or receipt");

        host.Invoke("MarkRound1Scheduled", ActionRequest.Waiting);
        var history = host.Rows.Values.Where(row => row.LogicalName == "os_sr_csh").ToArray();
        Check(history.Length == 3 && history.All(row =>
            row.GetAttributeValue<EntityReference>("os_sr_csh_actr")?.Id == SingleUserActor) &&
            host.Rows[SingleUserScope].GetAttributeValue<OptionSetValue>("os_sr_cand_stat")?.Value == ActionRequest.Scheduled,
            "SingleUserDev lifecycle persists three actor-bound Status History transitions and schedule status");
        var writesBeforeReplay = host.Writes;
        host.InvokeAgain();
        Check((string)host.Output["ResultCode"] == "DuplicateReplay" && host.Writes == writesBeforeReplay,
            "SingleUserDev scheduling receipt blocks duplicate transition replay");

        var scopedReadActions = new Dictionary<string, string>
        {
            ["ReadScopedCandidates"] = "os_sr_cand",
            ["ReadScopedPositions"] = "os_sr_pos",
            ["ReadScopedSources"] = "os_sr_csrc",
            ["ReadScopedTas"] = "os_sr_ta",
            ["ReadScopedLocations"] = "os_sr_loc",
            ["ReadScopedCalls"] = "os_sr_call",
            ["ReadScopedHistory"] = "os_sr_csh",
            ["ReadScopedSchedules"] = "os_sr_intv"
        };
        var unrelatedCandidateId = Guid.NewGuid();
        host.Rows[unrelatedCandidateId] = new Entity("os_sr_cand", unrelatedCandidateId)
        {
            ["os_sr_cand_nm"] = "Real candidate",
            ["os_sr_cand_eml"] = "real@example.invalid",
            ["ownerid"] = new EntityReference("systemuser", SingleUserActor)
        };
        var writesBeforeReads = host.Writes;
        foreach (var action in scopedReadActions)
        {
            host.Input.Clear();
            host.Input["ActionType"] = action.Key;
            host.Input["CorrelationId"] = Guid.NewGuid();
            host.Input["SyntheticScopeId"] = SingleUserScope;
            host.InvokeAgain();
            Check((string)host.Output["ResultCode"] == "ScopedRead" &&
                ((string)host.Output["ScopedData"]).Contains("\"__logicalName\":\"" + action.Value + "\""),
                "Fixed SingleUserDev read returns only the mapped entity type: " + action.Key + " " +
                (string)host.Output["ScopedData"]);
        }
        host.Input.Clear();
        host.Input["ActionType"] = "ReadScopedCandidates";
        host.Input["CorrelationId"] = Guid.NewGuid();
        host.Input["SyntheticScopeId"] = SingleUserScope;
        host.InvokeAgain();
        var scopedCandidates = (string)host.Output["ScopedData"];
        Check(scopedCandidates.StartsWith("[{\"__logicalName\":\"os_sr_cand\",", StringComparison.Ordinal) &&
            scopedCandidates.Contains("\"os_sr_candid\":\"" + SingleUserScope + "\"") &&
            !scopedCandidates.Contains("real@example.invalid") &&
            host.Writes == writesBeforeReads,
            "Scoped Candidate read uses the Console JSON shape, excludes unrelated rows, and performs no mutations");
        host.Input["Table"] = "os_sr_cand";
        Reject(() => host.InvokeAgain(), "SYNTHETIC_READ_INPUT_REJECTED");
        Check(host.Writes == writesBeforeReads,
            "Caller-supplied table/query parameters are rejected before storage");

        host.Input.Clear();
        host.Input["ActionType"] = "RecordCall";
        host.Input["CorrelationId"] = Guid.NewGuid();
        host.Input["CandidateId"] = SingleUserScope;
        host.Input["ExpectedStatus"] = ActionRequest.NeedCall;
        host.Input["CallOutcome"] = ActionRequest.NeedCall;
        host.Input["ContactedAt"] = DateTime.UtcNow.AddSeconds(-1);
        Reject(() => host.InvokeAgain(), "SYNTHETIC_SCOPE_REQUIRED");
        Check(host.Writes == writesBeforeReplay, "Unscoped DEV API mutation is rejected before storage");

        Reject(() => host.Direct("Create", new Entity("os_sr_cand", Guid.NewGuid())),
            "SYNTHETIC_DIRECT_WRITE_REJECTED");

        var wrongActor = new IsolationHost
        {
            CallerId = Actor,
            ProfileOverride = SingleUserDevXml
        };
        Reject(() => wrongActor.Invoke(SyntheticIsolation.VerifySingleUserDevAction), "SYNTHETIC_ACTOR_REJECTED");
        var wrongOrganization = new IsolationHost
        {
            CallerId = SingleUserActor,
            ProfileOverride = SingleUserDevXml,
            OrganizationId = Organization
        };
        Reject(() => wrongOrganization.Invoke(SyntheticIsolation.VerifySingleUserDevAction),
            "SYNTHETIC_ORGANIZATION_REJECTED");
        var missingSingleUserProfile = new IsolationHost
        {
            CallerId = SingleUserActor,
            ProfileOverride = PersistentIsolationXml
        };
        Reject(() => missingSingleUserProfile.Invoke(SyntheticIsolation.VerifySingleUserDevAction),
            "SINGLE_USER_DEV_CONFIGURATION_MISSING");

        var wrongScope = new IsolationHost
        {
            CallerId = SingleUserActor,
            ProfileOverride = SingleUserDevXml
        };
        wrongScope.Input["ActionType"] = "RecordCall";
        wrongScope.Input["CorrelationId"] = Guid.NewGuid();
        wrongScope.Input["CandidateId"] = SingleUserScope;
        wrongScope.Input["ExpectedStatus"] = ActionRequest.NeedCall;
        wrongScope.Input["CallOutcome"] = ActionRequest.NeedCall;
        wrongScope.Input["ContactedAt"] = DateTime.UtcNow.AddSeconds(-1);
        wrongScope.Input["SyntheticScopeId"] = Guid.NewGuid();
        Reject(() => wrongScope.InvokeAgain(), "SYNTHETIC_SCOPE_REQUIRED");
        var sameActorProfiles = new IsolationHost
        {
            CallerId = SingleUserActor,
            ProfileOverride = SingleUserDevXml.Replace(Actor.ToString(), SingleUserActor.ToString())
        };
        Reject(() => sameActorProfiles.Invoke(SyntheticIsolation.VerifySingleUserDevAction),
            "SINGLE_USER_DEV_CONFIGURATION_INVALID");
    }

    private static void TestVerifierCorrelationContract()
    {
        var host = new IsolationHost { GuardsInstalled = false, IncludeCreateReferences = true };
        using (var wire = typeof(Program).Assembly.GetManifestResourceStream("synthetic-verifier-request.json"))
        {
            var serializer = new DataContractJsonSerializer(typeof(Dictionary<string, string>),
                new DataContractJsonSerializerSettings { UseSimpleDictionaryFormat = true });
            var body = (Dictionary<string, string>)serializer.ReadObject(wire!)!;
            Check(body.Count == 2 && body["ActionType"] == SyntheticIsolation.VerifyAction,
                "Exact browser wire fixture contains only read-only action and correlation");
            host.Input["ActionType"] = body["ActionType"];
            host.Input["CorrelationId"] = Guid.Parse(body["CorrelationId"]);
            host.InvokeAgain();
        }
        foreach (var invalid in new object?[] { null, Guid.Empty, "malformed",
            Guid.NewGuid().ToString("D"), 42 })
        {
            if (invalid == null) host.Input.Remove("CorrelationId");
            else host.Input["CorrelationId"] = invalid;
            Reject(() => host.InvokeAgain(), "INVALID_CORRELATIONID");
        }
        host.Input["CorrelationId"] = Guid.NewGuid();
        foreach (var name in new[] { "CandidateId", "SyntheticScopeId", "PositionId",
            "CandidateSourceId", "AssignedTaId", "InterviewerId", "LocationId" })
            host.Input[name] = Guid.Empty;
        foreach (var name in new[] { "StartAt", "EndAt", "ContactedAt" })
            host.Input[name] = DateTime.MinValue;
        foreach (var name in new[] { "ExpectedStatus", "CallOutcome" }) host.Input[name] = 0;
        foreach (var name in new[] { "CandidateName", "CandidateEmail", "CandidatePhone",
            "CandidateCvUrl", "Notes", "Reason", "ResultNotes", "ProfileFieldMask" })
            host.Input[name] = "";
        host.InvokeAgain();
        var proof = (string)host.Output["IsolationContract"];
        Check(proof.Contains("\"actorId\":\"" + Actor + "\"") &&
            proof.Contains("\"scopeId\":\"" + Scope + "\"") && host.Writes == 0 &&
            !host.Rows.Values.Any(row => row.LogicalName == "os_sr_oprc"),
            "Browser GUID converted by Guid metadata plus optional wire defaults yields bound read-only proof, no receipt");
        foreach (var change in new Dictionary<string, object>
        {
            ["SyntheticScopeId"] = Scope, ["CandidateId"] = Scope,
            ["CandidateName"] = "unexpected", ["StartAt"] = DateTime.UtcNow,
            ["ExpectedStatus"] = ActionRequest.NeedCall, ["Other"] = null!
        })
        {
            var present = host.Input.TryGetValue(change.Key, out var previous);
            host.Input[change.Key] = change.Value;
            Reject(() => host.InvokeAgain(), "SYNTHETIC_VERIFIER_INPUT_REJECTED");
            if (present) host.Input[change.Key] = previous;
            else host.Input.Remove(change.Key);
        }
        Check(host.Writes == 0 && host.Rows.Count == 0,
            "Invalid verifier wire inputs never create business rows or receipts");
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
        public readonly List<Entity> SupportedRows = new List<Entity>();
        private readonly Stack<IPluginExecutionContext> stack = new Stack<IPluginExecutionContext>();
        private readonly Guid dangerousPrivilege = Guid.NewGuid();
        private readonly Dictionary<string, Guid> readPrivileges = SyntheticIsolation.Tables
            .ToDictionary(table => table, table => Guid.NewGuid());
        private readonly Dictionary<string, Guid> scopedPrivilegeCatalog = new Dictionary<string, Guid>();
        public bool MissingConfiguration, TdsEnabled, SearchEnabled, ChangeTrackingEnabled, BypassPrivilege;
        public bool OwnerReadMissing, ReceiptReadGranted, MissingPrivilegeMetadata;
        public bool LegacyGuardVerification, ApiContractInvalid, DenyReadback;
        public bool MissingProofOutput, MissingScopeInput, MissingScopedDataOutput, InactiveCaller,
            GlobalBusinessRead, IncludeCreateReferences;
        public string? TeamPrivilegeName;
        public string? ProfileOverride;
        public int EffectivePrivilegeRequests;
        private readonly Guid apiId = Guid.NewGuid(), typeId = Guid.NewGuid(), assemblyId = Guid.NewGuid();
        public bool GuardsInstalled = true;
        public Guid OrganizationId = DevOrganization;
        public Action<Entity>? BeforeCandidateStateRead;
        public string? ExtraPrivilegeName;
        public Guid CallerId = Actor;
        public int MaxDepth, SystemReadGuardCalls, ControlReadGuardCalls, ProfileLoads;
        public int Writes;
        public QueryBase? LastReadQuery;
        public IOrganizationService Service { get; }
        public IOrganizationService CallerService { get; }
        private IPluginExecutionContext Current => stack.Peek();

        public IsolationHost()
        {
            Service = Proxy<IOrganizationService>(call => ServiceCall(call));
            CallerService = Proxy<IOrganizationService>(call => ServiceCall(call, true));
            foreach (var table in SyntheticIsolation.Tables)
            {
                foreach (var message in new[] { "Create", "Update", "Delete" })
                    AddStep(table, message, 20);
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
        public void AddRedundantPostStep() => AddStep("os_sr_cand", "RetrieveMultiple", 40);
        public void AddSupportedGuard(string message) => AddStep("os_sr_cand", message, 20);
        public void AddSupportedMessage(string message, bool guardable) => SupportedRows.Add(
            new Entity("sdkmessagefilter", Guid.NewGuid()) {
                ["primaryobjecttypecode"] = "os_sr_cand",
                ["iscustomprocessingstepallowed"] = guardable,
                ["message.name"] = new AliasedValue("sdkmessage", "name", message)
            });
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
            var profile = CallerId == SingleUserActor
                ? SyntheticIsolation.ParseSingleUserDev(ProfileOverride ?? SingleUserDevXml)
                : SyntheticIsolation.Parse(ProfileOverride ?? IsolationXml);
            Input["CandidateName"] = profile.CandidateName;
            Input["CandidateEmail"] = profile.CandidateEmail;
            if (IncludeCreateReferences)
            {
                Input["PositionId"] = Reference;
                Input["CandidateSourceId"] = Reference;
                Input["AssignedTaId"] = Reference;
            }
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
            if (action == SyntheticIsolation.VerifyAction || action == SyntheticIsolation.VerifySingleUserDevAction)
            {
                Input.Clear();
                Input["CorrelationId"] = Guid.NewGuid();
            }
            Input["ActionType"] = action;
            if (action != SyntheticIsolation.VerifyAction && action != SyntheticIsolation.VerifySingleUserDevAction)
            {
                var scope = CallerId == SingleUserActor ? SingleUserScope : Scope;
                Input["SyntheticScopeId"] = scope;
                Input["CorrelationId"] = Guid.NewGuid();
                if (action != "CreateCandidate") Input["CandidateId"] = scope;
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
            values["OrganizationId"] = OrganizationId;
            values["UserId"] = CallerId; values["InitiatingUserId"] = CallerId;
            stack.Push(Execution(values));
            try
            {
                if (LegacyGuardVerification && Equals(Input["ActionType"], SyntheticIsolation.VerifyAction))
                {
                    // Retain stopped full-guard helper regressions without routing the new API proof through them.
                    try
                    {
                        var profile = SyntheticIsolation.Load(Service, Current);
                        SyntheticIsolation.RequireGuardCoverage(Service);
                        SyntheticIsolation.RequireRestrictedCaller(Service, Current);
                        profile.ValidateReferences(Service);
                        Output["ResultCode"] = "SyntheticIsolationVerified";
                        Output["IsolationContract"] = profile.Contract();
                    }
                    catch (OperationError error) { throw new InvalidPluginExecutionException(error.Message); }
                }
                else new ApplyCandidateAction().Execute(this);
            }
            finally { stack.Pop(); }
        }
        public void OrdinaryCreate()
        {
            Input.Clear();
            Input["ActionType"] = "CreateCandidate"; Input["CorrelationId"] = Guid.NewGuid();
            Input["CandidateName"] = "Unrelated synthetic fixture"; Input["CandidateEmail"] = "unrelated@example.invalid";
            InvokeAgain();
        }
        public void Direct(string message, Entity target)
        {
            var values = Context(new ParameterCollection
            {
                ["Target"] = message == "Associate" || message == "Disassociate" ? (object)target.ToEntityReference() : target
            }, new ParameterCollection(), new ParameterCollection());
            values["OrganizationId"] = DevOrganization; values["MessageName"] = message;
            values["UserId"] = CallerId; values["InitiatingUserId"] = CallerId;
            values["PrimaryEntityName"] = target.LogicalName; values["Stage"] = 20;
            stack.Push(Execution(values));
            try { new SyntheticIsolationGuard().Execute(this); }
            finally { stack.Pop(); }
        }
        public void ReadProbe(QueryBase query, Entity? row = null)
        {
            LastReadQuery = query;
            var input = new ParameterCollection { ["Query"] = query };
            var output = new ParameterCollection
            {
                ["BusinessEntityCollection"] = new EntityCollection(row == null ? new List<Entity>() : new List<Entity> { row })
            };
            var values = Context(input, new ParameterCollection(), output);
            values["OrganizationId"] = DevOrganization; values["MessageName"] = "RetrieveMultiple";
            values["UserId"] = CallerId; values["InitiatingUserId"] = CallerId;
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
                return Proxy<IOrganizationServiceFactory>(call => call.Args[0] == null ? Service : CallerService);
            throw new Exception("Unexpected isolation service " + type.Name);
        }
        private void Guard(string message, string table, ParameterCollection input, ParameterCollection output, int stage)
        {
            if (!GuardsInstalled) return;
            if (!SyntheticIsolation.Tables.Contains(table) && !(message == "RetrieveMultiple" && stage == 40)) return;
            var values = Context(input, new ParameterCollection(), output);
            values["OrganizationId"] = DevOrganization; values["MessageName"] = message;
            values["PrimaryEntityName"] = table; values["Stage"] = stage;
            values["Depth"] = Current.Depth + 1; values["ParentContext"] = Current;
            values["UserId"] = Guid.Empty; values["InitiatingUserId"] = Current.InitiatingUserId;
            MaxDepth = Math.Max(MaxDepth, (int)values["Depth"]!);
            if ((int)values["Depth"]! > 8) throw new Exception("Fixture detects recursive guard calls");
            if (message == "Retrieve" || message == "RetrieveMultiple") SystemReadGuardCalls++;
            if (!SyntheticIsolation.Tables.Contains(table)) ControlReadGuardCalls++;
            stack.Push(Execution(values));
            try
            {
                if (message == "Retrieve" || message == "RetrieveMultiple") new SyntheticIsolationReadGuard().Execute(this);
                else new SyntheticIsolationGuard().Execute(this);
            }
            finally { stack.Pop(); }
        }
        private object? ServiceCall(IMethodCallMessage call, bool asCaller = false)
        {
            if (call.MethodName == "Retrieve")
            {
                var table = (string)call.Args[0];
                if (table == "systemuser") return new Entity(table, (Guid)call.Args[1])
                    { ["isdisabled"] = InactiveCaller, ["islicensed"] = true, ["accessmode"] = new OptionSetValue(0) };
                if (table == "plugintype") return new Entity(table, typeId)
                    { ["typename"] = typeof(ApplyCandidateAction).FullName,
                        ["pluginassemblyid"] = new EntityReference("pluginassembly", assemblyId) };
                if (table == "pluginassembly") return new Entity(table, assemblyId)
                    { ["name"] = typeof(ApplyCandidateAction).Assembly.GetName().Name,
                        ["version"] = typeof(ApplyCandidateAction).Assembly.GetName().Version.ToString(),
                        ["isolationmode"] = new OptionSetValue(2), ["sourcetype"] = new OptionSetValue(4),
                        ["packageid"] = new EntityReference("pluginpackage", Reference) };
                if (DenyReadback && asCaller && table == "os_sr_cand")
                    throw new OperationError("SYNTHETIC_READBACK_DENIED");
                if (table == "organization") return new Entity(table, DevOrganization)
                    { ["enabletdsendpoint"] = TdsEnabled, ["enablerelevancesearch"] = SearchEnabled };
                if (table == "os_sr_cand" && ((ColumnSet)call.Args[2]).Columns.Contains("os_sr_cand_stat"))
                    BeforeCandidateStateRead?.Invoke(Rows[(Guid)call.Args[1]]);
                var row = ReferenceRows.TryGetValue(table, out var reference) ? Clone(reference) : Clone(Rows[(Guid)call.Args[1]]);
                if (stack.Count > 0) Guard("Retrieve", table, new ParameterCollection(),
                    new ParameterCollection { ["BusinessEntity"] = row }, 40);
                return row;
            }
            if (call.MethodName == "RetrieveMultiple")
            {
                var query = (QueryExpression)call.Args[0];
                if (query.EntityName == "environmentvariabledefinition")
                {
                    ProfileLoads++;
                    return ReadResult(query.EntityName, Collection(MissingConfiguration ? Array.Empty<Entity>() : new[] {
                        new Entity(query.EntityName, Reference) { ["statecode"] = new OptionSetValue(0) } }));
                }
                if (query.EntityName == "environmentvariablevalue")
                    return ReadResult(query.EntityName, Collection(new[] { new Entity(query.EntityName, Reference)
                        { ["value"] = ProfileOverride ?? IsolationXml, ["statecode"] = new OptionSetValue(0) } }));
                if (query.EntityName == "customapi")
                    return Collection(new[] { new Entity("customapi", apiId)
                    {
                        ["plugintypeid"] = new EntityReference("plugintype", typeId),
                        ["executeprivilegename"] = ApiContractInvalid ? "prvWriteos_sr_cand" : "prvReados_sr_cand",
                        ["isprivate"] = true, ["isfunction"] = false,
                        ["allowedcustomprocessingsteptype"] = new OptionSetValue(0)
                    } });
                if (query.EntityName == "customapirequestparameter" || query.EntityName == "customapiresponseproperty")
                {
                    var missing = query.EntityName == "customapirequestparameter" ? MissingScopeInput :
                        MissingProofOutput || MissingScopedDataOutput &&
                        query.Criteria.Conditions.Any(condition => condition.AttributeName == "uniquename" &&
                            condition.Values.Contains("ScopedData"));
                    if (missing)
                        return Collection(Array.Empty<Entity>());
                    return Collection(new[] { new Entity(query.EntityName, Reference)
                    { ["type"] = new OptionSetValue(query.EntityName == "customapirequestparameter" ? 12 : 10),
                        ["isoptional"] = true } });
                }
                if (query.EntityName == "sdkmessageprocessingstep") return ReadResult(query.EntityName, Collection(Steps));
                if (query.EntityName == "sdkmessagefilter") return ReadResult(query.EntityName, Collection(SupportedRows));
                if (query.EntityName == "privilege")
                {
                    if (query.Criteria.Conditions.Any(condition => condition.AttributeName == "name"))
                    {
                        var requested = query.Criteria.Conditions.Single().Values.Cast<string>();
                        foreach (var name in requested)
                            if (!scopedPrivilegeCatalog.ContainsKey(name))
                                scopedPrivilegeCatalog[name] = Guid.NewGuid();
                        return Collection(scopedPrivilegeCatalog.Select(pair =>
                            new Entity("privilege", pair.Value) { ["name"] = pair.Key }));
                    }
                    var names = EffectiveReadPrivileges().Select(pair =>
                        new Entity("privilege", pair.Value) { ["name"] = "prvRead" + pair.Key }).ToList();
                    if (BypassPrivilege || ExtraPrivilegeName != null)
                        names.Add(new Entity("privilege", dangerousPrivilege) {
                            ["name"] = ExtraPrivilegeName ?? "prvBypassCustomPlugins" });
                    return ReadResult(query.EntityName, Collection(names));
                }
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
                if (asCaller && SyntheticIsolation.IsProtectedTable(row.LogicalName))
                    throw new OperationError("NATIVE_WRITE_DENIED");
                Check(row.Id != Guid.Empty, "Create target ID is explicit before the platform Create pipeline");
                if (row.LogicalName == "os_sr_cand")
                    Check(row.GetAttributeValue<EntityReference>("ownerid")?.Id == CallerId,
                        "Candidate owner is explicit and preserves the initiating BSO");
                Guard("Create", row.LogicalName, new ParameterCollection { ["Target"] = row }, new ParameterCollection(), 20);
                if (row.LogicalName == "os_sr_cand") row["os_sr_cand_cnum"] = "CAND-SYNTHETIC";
                row.RowVersion = "1";
                Rows.Add(row.Id, row); Writes++;
                return row.Id;
            }
            if (call.MethodName == "Execute")
            {
                if (call.Args[0] is RetrieveUserSetOfPrivilegesByNamesRequest effectiveRequest)
                {
                    EffectivePrivilegeRequests++;
                    Check(effectiveRequest.UserId == Actor, "Effective privilege request binds configured actor");
                    var names = EffectiveReadPrivileges().Select(pair => "prvRead" + pair.Key).ToList();
                    if (BypassPrivilege) names.Add("prvBypassCustomPlugins");
                    if (ExtraPrivilegeName != null) names.Add(ExtraPrivilegeName);
                    if (TeamPrivilegeName != null) names.Add(TeamPrivilegeName);
                    return new RetrieveUserSetOfPrivilegesByNamesResponse
                    { Results = new ParameterCollection { ["RolePrivileges"] = names
                        .Where(name => effectiveRequest.PrivilegeNames.Contains(name))
                        .Select(name => new RolePrivilege { PrivilegeId = scopedPrivilegeCatalog[name],
                            Depth = GlobalBusinessRead ? PrivilegeDepth.Global : PrivilegeDepth.Basic }).ToArray() } };
                }
                if (call.Args[0] is RetrieveEntityRequest metadataRequest)
                {
                    var metadata = new EntityMetadata { ChangeTrackingEnabled = ChangeTrackingEnabled };
                    var privilege = (SecurityPrivilegeMetadata)Activator.CreateInstance(typeof(SecurityPrivilegeMetadata), true)!;
                    var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
                    typeof(SecurityPrivilegeMetadata).GetField("_privilegeId", flags)!.SetValue(privilege, readPrivileges[metadataRequest.LogicalName]);
                    typeof(SecurityPrivilegeMetadata).GetField("_privilegeType", flags)!.SetValue(privilege, PrivilegeType.Read);
                    typeof(EntityMetadata).GetProperty("Privileges")!.SetValue(metadata,
                        MissingPrivilegeMetadata ? Array.Empty<SecurityPrivilegeMetadata>() : new[] { privilege });
                    return new RetrieveEntityResponse
                    {
                        Results = new ParameterCollection { ["EntityMetadata"] = metadata }
                    };
                }
                if (call.Args[0] is RetrieveUserPrivilegesRequest)
                    return new RetrieveUserPrivilegesResponse
                    {
                        Results = new ParameterCollection { ["RolePrivileges"] =
                            EffectiveReadPrivileges().Select(pair => new RolePrivilege { PrivilegeId = pair.Value })
                            .Concat(BypassPrivilege || ExtraPrivilegeName != null ?
                                new[] { new RolePrivilege { PrivilegeId = dangerousPrivilege } } : Array.Empty<RolePrivilege>()).ToArray() }
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
        private IEnumerable<KeyValuePair<string, Guid>> EffectiveReadPrivileges() =>
            readPrivileges.Where(pair => (pair.Key != "os_sr_oprc" || ReceiptReadGranted) &&
                (pair.Key != "os_sr_cand" || !OwnerReadMissing));
        private EntityCollection ReadResult(string table, EntityCollection rows)
        {
            if (stack.Count > 0) Guard("RetrieveMultiple", table, new ParameterCollection(),
                new ParameterCollection { ["BusinessEntityCollection"] = rows }, 40);
            return rows;
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
