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

        host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(QueryState.Available));
        host.QueryRow["os_sr_avq_mod"] = new OptionSetValue((int)InterviewMode.Onsite);
        host.QueryRow["os_sr_avq_loc"] = host.LocationRow.ToEntityReference();
        host.Execute();
        Equal(3, host.Reads.Count, "Onsite completion reads query, TA and Location only.");
        Equal(true, host.Reads.Contains("os_sr_loc"), "Onsite completion reads the required Location.");

        foreach (var state in new[] { QueryState.NoSlots, QueryState.Failed })
        {
            host = new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(state));
            host.Execute();
            Equal(1, host.Reads.Count, "Terminal " + state + " reads only the Pending query.");
        }

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
        GuardRejects(new GuardHost("Create", IntegrationUser, IntegrationUser, create),
            "CREATE_CALLER", "The result writer cannot create requester rows.");
    }

    private static Entity ResultTarget(QueryState state)
    {
        var target = new Entity("os_sr_avq", Guid.Parse("22222222-3333-4444-5555-666666666666"))
        {
            ["os_sr_avq_stat"] = new OptionSetValue((int)state),
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
            var result = new Entity(logicalName, id);
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
