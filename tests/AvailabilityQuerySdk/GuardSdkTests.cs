using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using os_sr_avqg;

internal static partial class Program
{
    private static void TestSdkGuard()
    {
        var available = ResultTarget(QueryState.Available);
        var host = new GuardHost("Update", IntegrationUser, IntegrationUser, available);
        host.Execute();
        Equal(true, host.QueryColumns.Contains("os_sr_avq_stat"), "Guard reads the query state.");
        Equal(true, host.QueryColumns.Contains("os_sr_avq_ta"), "Guard reads the query TA.");
        Equal(true, host.QueryColumns.Contains("os_sr_avq_strt"), "Guard reads the query window.");
        Equal(false, host.QueryColumns.Contains("os_sr_loc_rmeml"), "Query reads do not use Location columns.");
        Equal(2, host.Reads.Count, "Available completion reads only the query and TA.");
        Equal(true, host.Reads.All(name => name == "os_sr_avq" || name == "os_sr_ta"),
            "Available completion has no Candidate Core read path.");

        foreach (var email in new[] { "", "not-an-address", "ta@other.invalid" })
        {
            host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available));
            host.TaRow["os_sr_ta_eml"] = email;
            GuardRejects(host, "INVALID_RESULT", "Available cannot use an invalid current TA address.");
        }
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available));
        host.TaRow["statecode"] = new OptionSetValue(1);
        GuardRejects(host, "INVALID_RESULT", "Available cannot use an inactive current TA.");
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available));
        host.QueryRow["os_sr_avq_mod"] = new OptionSetValue(-1);
        GuardRejects(host, "INVALID_RESULT", "Available rejects an unsupported persisted mode.");
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available));
        host.TaRow["os_sr_ta_eml"] = 123;
        GuardRejects(host, "REFERENCE_READ_FAILED", "Malformed reference data cannot leak a cast exception.");
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available));
        host.QueryRow["os_sr_avq_stat"] = "SYNTHETIC_RAW_STATE";
        GuardRejects(host, "INVALID_REQUEST", "Malformed persisted state receives a safe category.");
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available))
        {
            ReturnWrongReferenceId = true
        };
        GuardRejects(host, "REFERENCE_READ_FAILED", "Reference resolution verifies the returned identity.");
        foreach (var field in new[] { "os_sr_avq_slts", "os_sr_avq_rsn", "os_sr_avq_err" })
        {
            var malformed = ResultTarget(QueryState.Available);
            malformed[field] = 123;
            GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, malformed),
                "INVALID_RESULT", "Malformed result text receives a privacy-safe category.");
        }
        var immutableOnly = new Entity("os_sr_avq", available.Id)
        {
            ["os_sr_avq_dur"] = 30
        };
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, immutableOnly),
            "UNEXPECTED_ATTRIBUTE", "Request-only Update must reach and fail the guard.");
        var ownerOnly = new Entity("os_sr_avq", available.Id)
        {
            ["ownerid"] = new EntityReference("systemuser", IntegrationUser)
        };
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, ownerOnly),
            "UNEXPECTED_ATTRIBUTE", "Ownership-only Update must reach and fail the guard.");

        host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available));
        host.QueryRow["os_sr_avq_mod"] = new OptionSetValue((int)InterviewMode.Onsite);
        host.QueryRow["os_sr_avq_loc"] = host.LocationRow.ToEntityReference();
        host.Execute();
        Equal(3, host.Reads.Count, "Onsite completion reads query, TA and Location only.");
        Equal(true, host.Reads.Contains("os_sr_loc"), "Onsite completion reads the required Location.");
        host.LocationRow["statecode"] = new OptionSetValue(1);
        GuardRejects(host, "INVALID_RESULT", "Available cannot use an inactive current Onsite room.");

        foreach (var state in new[] { QueryState.NoSlots, QueryState.Failed })
        {
            host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(state));
            host.Execute();
            Equal(1, host.Reads.Count, "Terminal " + state + " reads only the Pending query.");
        }
        foreach (var state in new[] { QueryState.Available, QueryState.NoSlots, QueryState.Failed })
        {
            var omittedNulls = ResultTarget(state);
            if (state != QueryState.NoSlots) omittedNulls.Attributes.Remove("os_sr_avq_rsn");
            if (state != QueryState.Failed) omittedNulls.Attributes.Remove("os_sr_avq_err");
            host = new GuardHost("Update", IntegrationUser, IntegrationUser, omittedNulls);
            host.Execute();
            Equal(state == QueryState.Available ? 2 : 1, host.Reads.Count,
                "Terminal " + state + " still accepts omitted null result fields.");
        }
        foreach (var error in new[] { "PROVIDER_THROTTLED", "PROVIDER_TIMEOUT", "PROVIDER_UNAVAILABLE",
                     "PROVIDER_RESPONSE_INVALID", "PROVIDER_TIMEZONE_UNSUPPORTED" })
        {
            var failure = ResultTarget(QueryState.Failed);
            failure["os_sr_avq_err"] = error;
            host = new GuardHost("Update", IntegrationUser, IntegrationUser, failure);
            host.Execute();
            Equal(1, host.Reads.Count, "Safe " + error + " completion reads only the Pending query.");
        }

        var noSlotsWithError = ResultTarget(QueryState.NoSlots);
        noSlotsWithError["os_sr_avq_err"] = "PROVIDER_THROTTLED";
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, noSlotsWithError),
            "INVALID_RESULT", "NoSlots cannot carry a provider error.");
        var failedWithReason = ResultTarget(QueryState.Failed);
        failedWithReason["os_sr_avq_rsn"] = "NO_COMMON_SLOT";
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, failedWithReason),
            "INVALID_RESULT", "Failed cannot carry a NoSlots reason.");
        var failedWithSlots = ResultTarget(QueryState.Failed);
        failedWithSlots["os_sr_avq_slts"] = SlotResultJson.Serialize(
            new[] { new AvailableSlot(Start, Start.AddHours(1)) }, 200, 32768);
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, failedWithSlots),
            "INVALID_RESULT", "Failed cannot carry an available slot.");
        var failedWithRawError = ResultTarget(QueryState.Failed);
        failedWithRawError["os_sr_avq_err"] = "SYNTHETIC_PROVIDER_BODY";
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, failedWithRawError),
            "INVALID_RESULT", "A raw provider error is not an allowed category.");

        var expiryAtLimit = ResultTarget(QueryState.NoSlots);
        expiryAtLimit["os_sr_avq_exp"] = Now.AddMinutes(12).AddSeconds(1);
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, expiryAtLimit);
        host.Execute();
        Equal(1, host.Reads.Count, "Configured expiry plus one second is accepted.");
        var maximumExpiry = ResultTarget(QueryState.Failed);
        maximumExpiry["os_sr_avq_qat"] = DateTime.SpecifyKind(DateTime.MaxValue.AddMinutes(-1), DateTimeKind.Utc);
        maximumExpiry["os_sr_avq_exp"] = DateTime.SpecifyKind(DateTime.MaxValue, DateTimeKind.Utc);
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, maximumExpiry);
        host.Execute();
        Equal(1, host.Reads.Count, "Expiry comparison does not overflow on a valid bounded interval.");
        var expiryPastLimit = ResultTarget(QueryState.NoSlots);
        expiryPastLimit["os_sr_avq_exp"] = Now.AddMinutes(12).AddSeconds(1).AddTicks(1);
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, expiryPastLimit),
            "INVALID_EXPIRY", "Expiry beyond the configured bound is rejected.");

        GuardRejects(new GuardHost("Update", BsoUser, BsoUser, ResultTarget(QueryState.Available)),
            "UPDATE_CALLER", "The BSO requester cannot write a result.");
        GuardRejects(new GuardHost("Update", IntegrationUser, BsoUser, ResultTarget(QueryState.Available)),
            "UPDATE_CALLER", "An impersonated result write is rejected.");
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available));
        host.QueryRow["os_sr_avq_stat"] = new OptionSetValue((int)QueryState.Available);
        GuardRejects(host, "TERMINAL_STATE", "A result cannot overwrite a terminal query.");
        var badResult = ResultTarget(QueryState.Available);
        badResult["os_sr_avq_slts"] = SlotResultJson.Serialize(new[]
        {
            new AvailableSlot(Start.AddMinutes(5), Start.AddMinutes(65))
        }, 200, 32768);
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, badResult),
            "INVALID_RESULT", "The guard independently rejects a misaligned result.");
        var alteredInput = ResultTarget(QueryState.NoSlots);
        alteredInput["os_sr_avq_ta"] = new EntityReference("os_sr_ta", BsoUser);
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, alteredInput),
            "UNEXPECTED_ATTRIBUTE", "The result writer cannot change request inputs.");

        var start = DateTime.UtcNow.Date.AddDays(1).AddHours(2);
        var create = new Entity("os_sr_avq")
        {
            ["os_sr_avq_ta"] = new EntityReference("os_sr_ta", BsoUser),
            ["os_sr_avq_mod"] = new OptionSetValue((int)InterviewMode.Online),
            ["os_sr_avq_strt"] = start,
            ["os_sr_avq_end"] = start.AddHours(8),
            ["os_sr_avq_dur"] = 60
        };
        host = new GuardHost("Create", BsoUser, BsoUser, create);
        host.Execute();
        Equal((int)QueryState.Pending, create.GetAttributeValue<OptionSetValue>("os_sr_avq_stat").Value,
            "The separate BSO requester can create only Pending.");
        create.Attributes.Remove("os_sr_avq_stat");
        create["ownerid"] = new EntityReference("systemuser", IntegrationUser);
        GuardRejects(new GuardHost("Create", BsoUser, BsoUser, create),
            "UNEXPECTED_ATTRIBUTE", "Requester cannot choose a different query owner.");
        create.Attributes.Remove("ownerid");
        GuardRejects(new GuardHost("Create", IntegrationUser, IntegrationUser, create),
            "CREATE_CALLER", "The result writer cannot create requester rows.");

        foreach (var field in new[] { "os_sr_avq_strt", "os_sr_avq_end" })
        {
            foreach (var kind in new[] { DateTimeKind.Unspecified, DateTimeKind.Local })
            {
                var invalid = new Entity("os_sr_avq")
                {
                    ["os_sr_avq_ta"] = new EntityReference("os_sr_ta", BsoUser),
                    ["os_sr_avq_mod"] = new OptionSetValue((int)InterviewMode.Online),
                    ["os_sr_avq_strt"] = start,
                    ["os_sr_avq_end"] = start.AddHours(8),
                    ["os_sr_avq_dur"] = 60
                };
                invalid[field] = DateTime.SpecifyKind(invalid.GetAttributeValue<DateTime>(field), kind);
                host = new GuardHost("Create", BsoUser, BsoUser, invalid);
                GuardRejects(host, "INVALID_REQUEST", field + " rejects " + kind + " transport Kind.");
                Equal(0, host.Reads.Count, "Invalid UTC Kind is rejected before a reference read.");
                Equal(false, invalid.Contains("os_sr_avq_stat"),
                    "Rejected create does not receive a Pending state in the guard target.");
            }
        }
    }

    private static Entity ResultTarget(QueryState state)
    {
        var target = new Entity("os_sr_avq", Guid.Parse("22222222-3333-4444-5555-666666666666"))
        {
            ["os_sr_avq_stat"] = new OptionSetValue((int)state),
            ["os_sr_avq_rsn"] = null,
            ["os_sr_avq_err"] = null,
            ["os_sr_avq_slts"] = state == QueryState.Available
                ? SlotResultJson.Serialize(new[] { new AvailableSlot(Start, Start.AddHours(1)) }, 200, 32768)
                : "[]",
            ["os_sr_avq_qat"] = Now,
            ["os_sr_avq_exp"] = Now.AddMinutes(10)
        };
        if (state == QueryState.NoSlots) target["os_sr_avq_rsn"] = "NO_COMMON_SLOT";
        if (state == QueryState.Failed) target["os_sr_avq_err"] = "REFERENCE_CHANGED";
        return target;
    }

    private static void GuardRejects(GuardHost host, string category, string description)
    {
        assertions++;
        try
        {
            host.Execute();
        }
        catch (InvalidPluginExecutionException exception)
        {
            if (exception.Message == "Availability query rejected: " + category) return;
            throw new InvalidOperationException(description + " Wrong safe category: " + exception.Message);
        }
        throw new InvalidOperationException(description + " Expected rejection: " + category);
    }

    private sealed class GuardHost : IServiceProvider
    {
        private readonly Guid caller;
        private readonly Dictionary<string, object?> context;
        private readonly Entity ta;

        public GuardHost(string message, Guid caller, Guid initiating, Entity target)
        {
            this.caller = caller;
            var input = new ParameterCollection { ["Target"] = target };
            context = new Dictionary<string, object?>
            {
                ["PrimaryEntityName"] = "os_sr_avq",
                ["MessageName"] = message,
                ["Stage"] = 20,
                ["Mode"] = 0,
                ["UserId"] = caller,
                ["InitiatingUserId"] = initiating,
                ["InputParameters"] = input
            };
            ta = new Entity("os_sr_ta", BsoUser)
            {
                ["statecode"] = new OptionSetValue(0),
                ["os_sr_ta_eml"] = "ta@example.invalid"
            };
            LocationRow = new Entity("os_sr_loc", Guid.Parse("33333333-4444-5555-6666-777777777777"))
            {
                ["statecode"] = new OptionSetValue(0),
                ["os_sr_loc_rmeml"] = "room@example.invalid"
            };
            QueryRow = new Entity("os_sr_avq", target.Id)
            {
                ["os_sr_avq_stat"] = new OptionSetValue((int)QueryState.Pending),
                ["os_sr_avq_ta"] = ta.ToEntityReference(),
                ["os_sr_avq_mod"] = new OptionSetValue((int)InterviewMode.Online),
                ["os_sr_avq_strt"] = Start,
                ["os_sr_avq_end"] = End,
                ["os_sr_avq_dur"] = 60
            };
        }

        public Entity QueryRow { get; }
        public Entity TaRow => ta;
        public bool ReturnWrongReferenceId { get; set; }
        public Entity LocationRow { get; }
        public List<string> Reads { get; } = new List<string>();
        public List<string> QueryColumns { get; } = new List<string>();

        public void Execute() => new ProtectAvailabilityQuery(
            AvailabilityConfigurationRenderer.Render(ConfigurationSource(), IntegrationUser), null).Execute(this);

        public object GetService(Type type)
        {
            if (type == typeof(IPluginExecutionContext))
                return Proxy<IPluginExecutionContext>(call => context[call.MethodName.Substring(4)]);
            if (type == typeof(ITracingService))
                return Proxy<ITracingService>(call => null);
            if (type == typeof(IOrganizationServiceFactory))
                return Proxy<IOrganizationServiceFactory>(call =>
                {
                    if ((Guid?)call.Args[0] != caller)
                        throw new InvalidOperationException("The guard changed service identity.");
                    return Proxy<IOrganizationService>(Retrieve);
                });
            throw new InvalidOperationException("Unexpected service requested.");
        }

        private object Retrieve(IMethodCallMessage call)
        {
            if (call.MethodName != "Retrieve")
                throw new InvalidOperationException("The guard must not write through its service.");
            var logicalName = (string)call.Args[0];
            var id = (Guid)call.Args[1];
            var columns = (ColumnSet)call.Args[2];
            var source = logicalName == "os_sr_avq" ? QueryRow :
                logicalName == "os_sr_ta" ? ta :
                logicalName == "os_sr_loc" ? LocationRow :
                throw new InvalidOperationException("Unexpected business-table read.");
            if (id != source.Id) throw new InvalidOperationException("Unexpected row id.");
            Reads.Add(logicalName);
            if (logicalName == "os_sr_avq") QueryColumns.AddRange(columns.Columns);
            var result = new Entity(logicalName,
                ReturnWrongReferenceId && logicalName == "os_sr_ta" ? Guid.Empty : id);
            foreach (var pair in source.Attributes)
                if (columns.AllColumns || columns.Columns.Contains(pair.Key))
                    result[pair.Key] = pair.Value;
            return result;
        }
    }

    private static T Proxy<T>(Func<IMethodCallMessage, object?> invoke) =>
        (T)new GuardProxy(typeof(T), invoke).GetTransparentProxy();

    private sealed class GuardProxy : RealProxy
    {
        private readonly Func<IMethodCallMessage, object?> invoke;

        public GuardProxy(Type type, Func<IMethodCallMessage, object?> invoke) : base(type)
        {
            this.invoke = invoke;
        }

        public override IMessage Invoke(IMessage message)
        {
            var call = (IMethodCallMessage)message;
            try
            {
                return new ReturnMessage(invoke(call), null, 0, call.LogicalCallContext, call);
            }
            catch (Exception exception)
            {
                return new ReturnMessage(exception, call);
            }
        }
    }
}
