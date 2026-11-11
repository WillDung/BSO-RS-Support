using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Runtime.Remoting.Messaging;
using System.ServiceModel;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using os_sr_avqg;

internal static partial class Program
{
    private static readonly Guid BridgeQueryId = Guid.Parse("22222222-3333-4444-5555-666666666666");

    private static int RunCalendarBridge()
    {
        var json = Console.In.ReadToEnd();
        Console.WriteLine(CalendarBridge(json, out var exitCode));
        return exitCode;
    }

    // Test-only SDK boundary: reference reads and effective-role queries stay in memory.
    private static string CalendarBridge(string json, out int exitCode)
    {
        var serializer = new BridgeJsonSerializer();
        exitCode = 0;
        try
        {
            var input = BridgeObject(serializer.DeserializeObject(json));
            var operation = BridgeString(input, "operation");
            if (operation != "Create" && operation != "Update") throw new FormatException();
            var caller = BridgeIdentity(BridgeString(input, "caller"));
            var initiating = input.ContainsKey("initiatingCaller")
                ? BridgeIdentity(BridgeString(input, "initiatingCaller")) : caller;
            var settings = BridgeObject(input["settings"]).Select(pair =>
                new KeyValuePair<string, string>(pair.Key, pair.Value as string ??
                    throw new FormatException())).ToArray();
            var now = input.TryGetValue("now", out var clock)
                ? DateTime.Parse((string)clock, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind)
                : DateTime.UtcNow;
            var query = operation == "Update" ? BridgeEntity(BridgeObject(input["query"]), BridgeQueryId)
                : new Entity("os_sr_avq", BridgeQueryId);
            var target = BridgeEntity(BridgeObject(input["payload"]), query.Id);
            query.Id = target.Id;
            var references = BridgeObject(input["references"]);
            var taId = Guid.Parse(BridgeString(BridgeObject(references["ta"]), "id"));
            var locationId = references.TryGetValue("location", out var locationReference) && locationReference != null
                ? Guid.Parse(BridgeString(BridgeObject(locationReference), "id")) : SecurityLocation;
            var configuration = AvailabilityConfigurationRenderer.RenderSecured(settings, IntegrationUser,
                new Dictionary<string, string>
                {
                    ["SecurityVersion"] = "2", ["OrganizationId"] = SecurityOrganization.ToString("D"),
                    ["RequesterUserId"] = BsoUser.ToString("D"), ["RequesterRoleId"] = SecurityRole.ToString("D"),
                    ["TaId"] = taId.ToString("D"), ["LocationId"] = locationId.ToString("D")
                });
            if (input.TryGetValue("expectedEtag", out var expected) && expected is string etag &&
                etag.StartsWith("W/\"", StringComparison.Ordinal) && etag.EndsWith("\"", StringComparison.Ordinal))
                target.RowVersion = etag.Substring(3, etag.Length - 4);
            var rows = new List<Entity>();
            foreach (var name in new[] { "ta", "location" })
            {
                if (!references.TryGetValue(name, out var raw) || raw == null) continue;
                var reference = BridgeObject(raw);
                var table = name == "ta" ? "os_sr_ta" : "os_sr_loc";
                var row = new Entity(table, Guid.Parse(BridgeString(reference, "id")));
                row["statecode"] = new OptionSetValue(Convert.ToInt32(reference["statecode"],
                    CultureInfo.InvariantCulture));
                var emailField = name == "ta" ? "email" : "roomEmail";
                row[name == "ta" ? "os_sr_ta_eml" : "os_sr_loc_rmeml"] =
                    reference.TryGetValue(emailField, out var email) ? email : null;
                rows.Add(row);
            }
            if (operation == "Update") rows.Add(query);
            var host = new CalendarBridgeHost(operation, caller, initiating, target, rows);
            new ProtectAvailabilityQuery(configuration, null, () => now).Execute(host);
            foreach (var pair in target.Attributes) query[pair.Key] = pair.Value;
            if (operation == "Create") query["createdby"] = new EntityReference("systemuser", caller);
            query.RowVersion = "1";
            return serializer.Serialize(new Dictionary<string, object?>
            {
                ["accepted"] = true,
                ["row"] = BridgeRow(query),
                ["reads"] = host.Reads
            });
        }
        catch (InvalidPluginExecutionException exception)
        {
            const string prefix = "Availability query rejected: ";
            var category = exception.Message.StartsWith(prefix, StringComparison.Ordinal)
                ? exception.Message.Substring(prefix.Length) : "CONFIGURATION_INVALID";
            if (category.Length == 0 || category.Any(character =>
                    (character < 'A' || character > 'Z') && character != '_'))
            {
                category = "BRIDGE_INTERNAL_ERROR";
                exitCode = 2;
            }
            return serializer.Serialize(new { accepted = false, error = category });
        }
        catch (AvailabilityFailure failure)
        {
            return serializer.Serialize(new { accepted = false,
                error = SlotResultJson.IsSafeError(failure.Category) ? failure.Category : "CONFIGURATION_INVALID" });
        }
        catch (Exception exception) when (exception is FormatException || exception is ArgumentException ||
            exception is KeyNotFoundException || exception is InvalidCastException ||
            exception is OverflowException)
        {
            exitCode = 2;
            return serializer.Serialize(new { accepted = false, error = "BRIDGE_INPUT_INVALID" });
        }
        catch (Exception)
        {
            exitCode = 2;
            return serializer.Serialize(new { accepted = false, error = "BRIDGE_INTERNAL_ERROR" });
        }
    }

    private static Guid BridgeIdentity(string name) =>
        name == "requester" ? BsoUser : name == "writer" ? IntegrationUser : throw new FormatException();

    private static Dictionary<string, object> BridgeObject(object value) =>
        value as Dictionary<string, object> ?? throw new FormatException();

    private static string BridgeString(Dictionary<string, object> source, string name) =>
        source[name] as string ?? throw new FormatException();

    private static Entity BridgeEntity(Dictionary<string, object> source, Guid defaultId)
    {
        var id = source.TryGetValue("os_sr_avqid", out var rawId)
            ? Guid.Parse((string)rawId) : defaultId;
        var row = new Entity("os_sr_avq", id);
        foreach (var pair in source)
        {
            var name = pair.Key;
            var value = pair.Value;
            if (name == "os_sr_avqid") continue;
            if (name == "@odata.etag")
            {
                var etag = (string)value;
                row.RowVersion = etag.Substring(3, etag.Length - 4);
                continue;
            }
            if (name.StartsWith("@", StringComparison.Ordinal)) continue;
            if (name == "_ownerid_value" || name == "ownerid" || name == "_createdby_value")
            {
                row[name == "_createdby_value" ? "createdby" : "ownerid"] =
                    new EntityReference("systemuser", Guid.Parse((string)value));
                continue;
            }
            if (name == "_os_sr_avq_ta_value" || name == "_os_sr_avq_loc_value")
                name = name == "_os_sr_avq_ta_value" ? "os_sr_avq_ta" : "os_sr_avq_loc";
            if (name.EndsWith("@odata.bind", StringComparison.Ordinal))
                name = name.Substring(0, name.Length - "@odata.bind".Length);
            if (value != null && (name == "os_sr_avq_ta" || name == "os_sr_avq_loc"))
            {
                var table = name == "os_sr_avq_ta" ? "os_sr_ta" : "os_sr_loc";
                if (value is string binding)
                {
                    var start = binding.IndexOf('(');
                    var text = start >= 0 && binding.EndsWith(")", StringComparison.Ordinal)
                        ? binding.Substring(start + 1, binding.Length - start - 2) : binding;
                    value = new EntityReference(table, Guid.Parse(text));
                }
                else
                {
                    var lookup = BridgeObject(value);
                    value = new EntityReference(BridgeString(lookup, "logicalName"),
                        Guid.Parse(BridgeString(lookup, "id")));
                }
            }
            else if (value is int choice && (name == "os_sr_avq_mod" || name == "os_sr_avq_stat"))
                value = new OptionSetValue(choice);
            else if (value is string time && (name == "os_sr_avq_strt" || name == "os_sr_avq_end" ||
                     name == "os_sr_avq_qat" || name == "os_sr_avq_exp" ||
                     name == "os_sr_avq_cat" || name == "os_sr_avq_dead"))
            {
                if (!DateTime.TryParseExact(time, new[] { "yyyy-MM-dd'T'HH:mm:ss'Z'",
                        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'", "yyyy-MM-dd'T'HH:mm:ss",
                        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF" }, CultureInfo.InvariantCulture,
                        DateTimeStyles.None, out var parsed)) throw new FormatException();
                value = DateTime.SpecifyKind(parsed, time.EndsWith("Z", StringComparison.Ordinal)
                    ? DateTimeKind.Utc : DateTimeKind.Unspecified);
            }
            row[name] = value;
        }
        return row;
    }

    private static Dictionary<string, object?> BridgeRow(Entity row)
    {
        var result = new Dictionary<string, object?>
        {
            ["os_sr_avqid"] = row.Id.ToString("D"),
            ["@odata.etag"] = "W/\"" + row.RowVersion + "\""
        };
        foreach (var pair in row.Attributes)
        {
            if (pair.Value is EntityReference reference)
                result["_" + pair.Key + "_value"] = reference.Id.ToString("D");
            else if (pair.Value is OptionSetValue choice)
                result[pair.Key] = choice.Value;
            else if (pair.Value is DateTime time)
                result[pair.Key] = time.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
                    CultureInfo.InvariantCulture);
            else result[pair.Key] = pair.Value;
        }
        if (!result.ContainsKey("_ownerid_value"))
            result["_ownerid_value"] = BsoUser.ToString("D");
        result["ownerid"] = result["_ownerid_value"];
        return result;
    }

    private sealed class CalendarBridgeHost : IServiceProvider
    {
        private readonly Dictionary<string, object> context;
        private readonly Guid caller;
        private readonly List<Entity> rows;

        public CalendarBridgeHost(string message, Guid caller, Guid initiating, Entity target,
            List<Entity> rows)
        {
            this.caller = caller;
            this.rows = rows;
            context = new Dictionary<string, object>
            {
                ["PrimaryEntityName"] = "os_sr_avq", ["MessageName"] = message,
                ["Stage"] = 20, ["Mode"] = 0, ["UserId"] = caller,
                ["InitiatingUserId"] = initiating, ["OrganizationId"] = SecurityOrganization,
                ["InputParameters"] = new ParameterCollection
                { ["Target"] = target, ["ConcurrencyBehavior"] = ConcurrencyBehavior.IfRowVersionMatches }
            };
        }

        public List<string> Reads { get; } = new List<string>();

        public object GetService(Type type)
        {
            if (type == typeof(IPluginExecutionContext))
                return Proxy<IPluginExecutionContext>(call => context[call.MethodName.Substring(4)]);
            if (type == typeof(ITracingService)) return Proxy<ITracingService>(call => null);
            if (type == typeof(IOrganizationServiceFactory))
                return Proxy<IOrganizationServiceFactory>(call =>
                {
                    if ((Guid?)call.Args[0] != caller) throw new InvalidOperationException();
                    return Proxy<IOrganizationService>(Retrieve);
                });
            throw new InvalidOperationException();
        }

        private object Retrieve(IMethodCallMessage call)
        {
            if (call.MethodName == "RetrieveMultiple")
            {
                var roles = new EntityCollection();
                roles.Entities.Add(new Entity("role", SecurityRole));
                return roles;
            }
            if (call.MethodName != "Retrieve") throw new InvalidOperationException();
            var table = (string)call.Args[0];
            var id = (Guid)call.Args[1];
            Reads.Add(table);
            var row = rows.SingleOrDefault(item => item.LogicalName == table && item.Id == id);
            if (row == null) throw new FaultException<OrganizationServiceFault>(
                new OrganizationServiceFault(), "Synthetic reference unavailable.");
            var result = new Entity(table, id) { RowVersion = row.RowVersion };
            var columns = (ColumnSet)call.Args[2];
            foreach (var pair in row.Attributes)
                if (columns.Columns.Contains(pair.Key)) result[pair.Key] = pair.Value;
            return result;
        }
    }

    private static void TestCalendarBridge()
    {
        var serializer = new BridgeJsonSerializer();
        var clock = DateTime.UtcNow;
        clock = new DateTime(clock.Ticks - clock.Ticks % TimeSpan.TicksPerSecond, DateTimeKind.Utc);
        var start = clock.Date.AddDays(1).AddHours(2);
        while (start.DayOfWeek != DayOfWeek.Monday) start = start.AddDays(1);
        var envelope = new Dictionary<string, object>
        {
            ["operation"] = "Create", ["caller"] = "requester",
            ["now"] = clock.ToString("o"),
            ["settings"] = ConfigurationSource().ToDictionary(pair => pair.Key, pair => pair.Value),
            ["payload"] = new Dictionary<string, object>
            {
                ["os_sr_avqid"] = BridgeQueryId.ToString("D"),
                ["os_sr_avq_corr"] = BridgeQueryId.ToString("D"),
                ["os_sr_avq_ta@odata.bind"] = "/os_sr_tas(" + BsoUser + ")",
                ["os_sr_avq_mod"] = (int)InterviewMode.Online,
                ["os_sr_avq_strt"] = start.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"),
                ["os_sr_avq_end"] = start.AddHours(8).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"),
                ["os_sr_avq_dur"] = 60
            },
            ["references"] = new Dictionary<string, object>
            {
                ["ta"] = new { id = BsoUser.ToString(), statecode = 0, email = "ta@example.invalid" }
            }
        };
        var output = BridgeObject(serializer.DeserializeObject(CalendarBridge(serializer.Serialize(envelope),
            out var exit)));
        Equal(0, exit, "Bridge runs without a network or write service.");
        Equal(true, output["accepted"], "Bridge invokes real Create guard.");
        var query = BridgeObject(output["row"]);
        Equal((int)QueryState.Pending, query["os_sr_avq_stat"], "Bridge returns server-owned Pending.");
        Equal(BsoUser.ToString(), query["_ownerid_value"], "Bridge models requesting-user ownership.");
        envelope["caller"] = "writer";
        output = BridgeObject(serializer.DeserializeObject(CalendarBridge(serializer.Serialize(envelope), out exit)));
        Equal("CREATE_CALLER", output["error"], "Bridge preserves writer/requester separation.");
        envelope["caller"] = "requester";
        envelope["initiatingCaller"] = "writer";
        output = BridgeObject(serializer.DeserializeObject(CalendarBridge(serializer.Serialize(envelope), out exit)));
        Equal("CREATE_CALLER", output["error"], "Bridge rejects impersonated Create.");
        envelope.Remove("initiatingCaller");
        envelope["operation"] = "Update";
        envelope["caller"] = "writer";
        envelope["query"] = query;
        envelope["expectedEtag"] = query["@odata.etag"];
        envelope["payload"] = new Dictionary<string, object?>
        {
            ["os_sr_avq_corr"] = BridgeQueryId.ToString("D"),
            ["os_sr_avq_stat"] = (int)QueryState.NoSlots,
            ["os_sr_avq_slts"] = "[]", ["os_sr_avq_rsn"] = "NO_COMMON_SLOT",
            ["os_sr_avq_qat"] = clock.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"),
            ["os_sr_avq_exp"] = clock.AddMinutes(10).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        };
        output = BridgeObject(serializer.DeserializeObject(CalendarBridge(serializer.Serialize(envelope), out exit)));
        Equal(true, output["accepted"], "Bridge invokes real terminal Update guard.");
        envelope["query"] = output["row"];
        output = BridgeObject(serializer.DeserializeObject(CalendarBridge(serializer.Serialize(envelope), out exit)));
        Equal("TERMINAL_STATE", output["error"], "Bridge rejects terminal overwrites.");
        CalendarBridge("{\"private\":\"SYNTHETIC_RAW_INPUT\"}", out exit);
        Equal(2, exit, "Malformed harness input exits nonzero without raw input.");
    }

    // Reuse the adapter's existing framework JSON dependency without adding a test-project dependency.
    private sealed class BridgeJsonSerializer
    {
        private readonly Type type;
        private readonly object instance;

        public BridgeJsonSerializer()
        {
            var dependency = typeof(OutlookMeetingTimesAdapter).Assembly.GetReferencedAssemblies()
                .Single(name => name.Name == "System.Web.Extensions");
            type = Assembly.Load(dependency).GetType("System.Web.Script.Serialization.JavaScriptSerializer", true);
            instance = Activator.CreateInstance(type);
            type.GetProperty("MaxJsonLength").SetValue(instance, 131072, null);
            type.GetProperty("RecursionLimit").SetValue(instance, 32, null);
        }

        public object DeserializeObject(string json)
        {
            if (json.Length > 131072) throw new FormatException();
            try
            {
                return type.GetMethod("DeserializeObject").Invoke(instance, new object[] { json });
            }
            catch (TargetInvocationException)
            {
                throw new FormatException();
            }
        }

        public string Serialize(object value) =>
            (string)type.GetMethod("Serialize", new[] { typeof(object) }).Invoke(instance, new[] { value });
    }
}
