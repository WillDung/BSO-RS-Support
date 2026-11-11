using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.ServiceModel;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;

[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("AvailabilityQuerySdk.Tests")]

namespace os_sr_avqg
{
    public sealed class ProtectAvailabilityQuery : IPlugin
    {
        private const string Table = "os_sr_avq";
        private const string TaTable = "os_sr_ta";
        private const string LocationTable = "os_sr_loc";

        private static readonly string[] CreateFields =
        {
            "os_sr_avq_ta", "os_sr_avq_loc", "os_sr_avq_mod",
            "os_sr_avq_strt", "os_sr_avq_end", "os_sr_avq_dur", "os_sr_avq_corr", "os_sr_avqid"
        };

        private static readonly string[] ResultFields =
        {
            "os_sr_avq_stat", "os_sr_avq_rsn", "os_sr_avq_err",
            "os_sr_avq_slts", "os_sr_avq_qat", "os_sr_avq_exp", "os_sr_avq_corr"
        };

        private readonly string? unsecureConfiguration;
        private readonly Func<DateTime> utcNow;

        public ProtectAvailabilityQuery(string? unsecureConfiguration, string? secureConfiguration)
            : this(unsecureConfiguration, secureConfiguration, () => DateTime.UtcNow)
        {
        }

        internal ProtectAvailabilityQuery(string? unsecureConfiguration, string? secureConfiguration,
            Func<DateTime> utcNow)
        {
            this.unsecureConfiguration = unsecureConfiguration;
            this.utcNow = utcNow;
        }

        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var trace = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
            if (context.PrimaryEntityName == Table &&
                (context.MessageName == "Assign" || context.MessageName == "Delete"))
                throw Reject(trace, "IMMUTABLE_REQUEST");
            if (context.PrimaryEntityName != Table ||
                (context.MessageName != "Create" && context.MessageName != "Update") ||
                context.Stage != 20 || context.Mode != 0)
                throw Reject(trace, "UNSUPPORTED_OPERATION");

            var config = PluginConfiguration.Parse(unsecureConfiguration);
            var security = AvailabilityRequestSecurity.Parse(unsecureConfiguration, config.ResultWriterUserId);
            if (context.OrganizationId != security.OrganizationId) throw Reject(trace, "REQUEST_SCOPE");
            var serviceFactory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
            var service = serviceFactory.CreateOrganizationService(context.UserId);
            if (context.MessageName == "Create")
                ValidateCreate(context, service, config, security, trace, utcNow());
            else
                ValidateUpdate(context, service, config, security, trace, utcNow());
        }

        private static void ValidateCreate(IPluginExecutionContext context, IOrganizationService service,
            AvailabilitySettings settings, AvailabilityRequestSecurity security, ITracingService trace, DateTime now)
        {
            if (!AvailabilityMutationPolicy.IsCreateCaller(context.UserId, context.InitiatingUserId,
                    settings.ResultWriterUserId) ||
                !context.InputParameters.Contains("Target") ||
                !(context.InputParameters["Target"] is Entity target) ||
                target.LogicalName != Table)
                throw Reject(trace, "CREATE_CALLER");

            EnsureOnlyAttributes(target, CreateFields, trace);
            security.ValidateRequester(context.OrganizationId, context.UserId, context.InitiatingUserId);
            security.ValidateRole(service);
            AvailabilityRequestSecurity.Correlation(target);
            if (target.Contains("os_sr_avqid") &&
                (!(target["os_sr_avqid"] is Guid id) || id != target.Id))
                throw Reject(trace, "CORRELATION");
            security.ValidateScope(target);
            var taReference = RequiredReference(target, "os_sr_avq_ta", TaTable, trace);
            var mode = RequiredChoice(target, "os_sr_avq_mod", trace);
            var start = RequiredUtc(target, "os_sr_avq_strt", trace);
            var end = RequiredUtc(target, "os_sr_avq_end", trace);
            var duration = RequiredInteger(target, "os_sr_avq_dur", trace);

            Entity? location = null;
            if (target.Contains("os_sr_avq_loc"))
            {
                var locationReference = target["os_sr_avq_loc"] as EntityReference;
                if (locationReference == null || locationReference.LogicalName != LocationTable)
                    throw Reject(trace, "INVALID_LOCATION");
                location = RetrieveReference(service, locationReference, LocationTable, trace);
            }

            var ta = RetrieveReference(service, taReference, TaTable, trace);
            var query = new AvailabilityQuery(
                (InterviewMode)mode,
                start,
                end,
                duration,
                ta.GetAttributeValue<OptionSetValue>("statecode")?.Value == 0,
                ta.GetAttributeValue<string>("os_sr_ta_eml"),
                location == null ? (bool?)null :
                    location.GetAttributeValue<OptionSetValue>("statecode")?.Value == 0,
                location?.GetAttributeValue<string>("os_sr_loc_rmeml"));

            var failure = AvailabilityRules.ValidateQuery(query, settings, now);
            if (failure != null) throw Reject(trace, failure);
            if (now.Kind != DateTimeKind.Utc || now > DateTime.MaxValue.AddMinutes(-settings.ResultExpiryMinutes))
                throw Reject(trace, "REQUEST_EXPIRED");
            target["ownerid"] = new EntityReference("systemuser", context.UserId);
            target["os_sr_avq_cat"] = now;
            target["os_sr_avq_dead"] = now.AddMinutes(settings.ResultExpiryMinutes);
            target["os_sr_avq_stat"] = new OptionSetValue((int)QueryState.Pending);
            trace.Trace("AVQ_GUARD_CREATE_ALLOWED");
        }

        private static void ValidateUpdate(IPluginExecutionContext context, IOrganizationService service,
            AvailabilitySettings settings, AvailabilityRequestSecurity security, ITracingService trace, DateTime now)
        {
            if (!AvailabilityMutationPolicy.IsResultUpdateCaller(context.UserId, context.InitiatingUserId,
                    settings.ResultWriterUserId) ||
                !context.InputParameters.Contains("Target") ||
                !(context.InputParameters["Target"] is Entity target) ||
                target.LogicalName != Table ||
                target.Id == Guid.Empty)
                throw Reject(trace, "UPDATE_CALLER");

            EnsureOnlyAttributes(target, ResultFields, trace);
            AvailabilityRequestSecurity.Correlation(target);
            if (!context.InputParameters.TryGetValue("ConcurrencyBehavior", out var concurrency) ||
                !(concurrency is ConcurrencyBehavior behavior) || behavior != ConcurrencyBehavior.IfRowVersionMatches ||
                string.IsNullOrEmpty(target.RowVersion))
                throw Reject(trace, "CONCURRENCY_REQUIRED");
            var current = RetrieveReference(service, new EntityReference(Table, target.Id), Table, trace);
            security.ValidateOrigin(current);
            security.ValidateRole(service);
            if (current.RowVersion != target.RowVersion) throw Reject(trace, "CONCURRENCY_MISMATCH");
            if (!string.Equals(current.GetAttributeValue<string>("os_sr_avq_corr"),
                    target.GetAttributeValue<string>("os_sr_avq_corr"), StringComparison.OrdinalIgnoreCase))
                throw Reject(trace, "CORRELATION");
            if (RequiredChoice(current, "os_sr_avq_stat", trace) != (int)QueryState.Pending)
                throw Reject(trace, "TERMINAL_STATE");

            var state = RequiredChoice(target, "os_sr_avq_stat", trace);
            if (!AvailabilityMutationPolicy.IsTerminalTransition(QueryState.Pending, (QueryState)state))
                throw Reject(trace, "INVALID_RESULT_STATE");

            var slots = OptionalText(target, "os_sr_avq_slts", trace);
            var reason = OptionalText(target, "os_sr_avq_rsn", trace);
            var error = OptionalText(target, "os_sr_avq_err", trace);
            var queriedAt = RequiredUtc(target, "os_sr_avq_qat", trace);
            var expiresAt = RequiredUtc(target, "os_sr_avq_exp", trace);
            AvailabilityRequestSecurity.ValidateFreshness(
                RequiredUtc(current, "os_sr_avq_cat", trace), RequiredUtc(current, "os_sr_avq_dead", trace),
                now, queriedAt, expiresAt, settings.ResultExpiryMinutes);
            if (expiresAt <= queriedAt ||
                expiresAt.Ticks - queriedAt.Ticks >
                    (long)settings.ResultExpiryMinutes * TimeSpan.TicksPerMinute + TimeSpan.TicksPerSecond)
                throw Reject(trace, "INVALID_EXPIRY");

            IReadOnlyList<AvailableSlot> parsedSlots;
            try
            {
                parsedSlots = SlotResultJson.ValidateCanonical(slots ?? "", settings.MaximumSlotCount,
                    settings.MaximumPayloadLength);
            }
            catch (AvailabilityFailure failure)
            {
                throw Reject(trace, failure.Category);
            }

            if (state == (int)QueryState.Available)
            {
                var query = ReadCurrentQuery(current, service, trace);
                if (parsedSlots.Count == 0 || reason != null || error != null ||
                    AvailabilityRules.ValidateReferences(query, settings) != null ||
                    !AreSlotsWithinQuery(parsedSlots, query, settings, queriedAt))
                    throw Reject(trace, "INVALID_RESULT");
            }
            else if (state == (int)QueryState.NoSlots)
            {
                if (parsedSlots.Count != 0 || !SlotResultJson.IsSafeReason(reason) || error != null)
                    throw Reject(trace, "INVALID_RESULT");
            }
            else if (parsedSlots.Count != 0 || reason != null || !SlotResultJson.IsSafeError(error))
            {
                throw Reject(trace, "INVALID_RESULT");
            }

            trace.Trace("AVQ_GUARD_UPDATE_ALLOWED");
        }

        private static AvailabilityQuery ReadCurrentQuery(Entity current,
            IOrganizationService service, ITracingService trace)
        {
            var taReference = RequiredReference(current, "os_sr_avq_ta", TaTable, trace);
            var ta = RetrieveReference(service, taReference, TaTable, trace);
            Entity? location = null;
            if (current.Contains("os_sr_avq_loc") && current["os_sr_avq_loc"] != null)
            {
                var locationReference = RequiredReference(current, "os_sr_avq_loc", LocationTable, trace);
                location = RetrieveReference(service, locationReference, LocationTable, trace);
            }
            return new AvailabilityQuery(
                (InterviewMode)RequiredChoice(current, "os_sr_avq_mod", trace),
                RequiredUtc(current, "os_sr_avq_strt", trace),
                RequiredUtc(current, "os_sr_avq_end", trace),
                RequiredInteger(current, "os_sr_avq_dur", trace),
                ta.GetAttributeValue<OptionSetValue>("statecode")?.Value == 0,
                ta.GetAttributeValue<string>("os_sr_ta_eml"),
                location == null ? (bool?)null :
                    location.GetAttributeValue<OptionSetValue>("statecode")?.Value == 0,
                location?.GetAttributeValue<string>("os_sr_loc_rmeml"));
        }

        private static bool AreSlotsWithinQuery(IReadOnlyList<AvailableSlot> slots,
            AvailabilityQuery query, AvailabilitySettings settings, DateTime queriedAtUtc)
        {
            if ((query.Mode != InterviewMode.Online && query.Mode != InterviewMode.Onsite) ||
                query.StartUtc.Kind != DateTimeKind.Utc || query.EndUtc.Kind != DateTimeKind.Utc ||
                query.EndUtc <= query.StartUtc ||
                query.EndUtc - query.StartUtc > TimeSpan.FromDays(settings.MaximumHorizonDays) ||
                query.StartUtc.Ticks % TimeSpan.TicksPerMinute != 0 ||
                query.EndUtc.Ticks % TimeSpan.TicksPerMinute != 0 ||
                query.StartUtc.Minute % AvailabilitySettings.IntervalMinutes != 0 ||
                query.EndUtc.Minute % AvailabilitySettings.IntervalMinutes != 0 ||
                !settings.AllowedDurationsMinutes.Contains(query.DurationMinutes) ||
                query.DurationMinutes % AvailabilitySettings.IntervalMinutes != 0 ||
                queriedAtUtc.Kind != DateTimeKind.Utc)
                return false;
            foreach (var slot in slots)
            {
                if (!AvailabilityRules.IsEligibleSlot(slot, query, settings, queriedAtUtc))
                    return false;
            }
            return true;
        }

        private static Entity RetrieveReference(IOrganizationService service,
            EntityReference reference, string expectedTable, ITracingService trace)
        {
            if (reference.LogicalName != expectedTable || reference.Id == Guid.Empty)
                throw Reject(trace, "INVALID_REFERENCE");
            try
            {
                var columns = expectedTable == TaTable
                    ? new ColumnSet("statecode", "os_sr_ta_eml")
                    : expectedTable == LocationTable
                        ? new ColumnSet("statecode", "os_sr_loc_rmeml")
                        : new ColumnSet("os_sr_avq_stat", "os_sr_avq_ta", "os_sr_avq_loc",
                            "os_sr_avq_mod", "os_sr_avq_strt", "os_sr_avq_end", "os_sr_avq_dur",
                            "ownerid", "createdby", "createdonbehalfby", "os_sr_avq_corr",
                            "os_sr_avq_cat", "os_sr_avq_dead", "versionnumber");
                var row = service.Retrieve(expectedTable, reference.Id, columns);
                if (row == null || row.LogicalName != expectedTable || row.Id != reference.Id)
                    throw Reject(trace, "REFERENCE_READ_FAILED");
                if (expectedTable != Table)
                {
                    var emailColumn = expectedTable == TaTable ? "os_sr_ta_eml" : "os_sr_loc_rmeml";
                    if ((row.Attributes.TryGetValue("statecode", out var state) &&
                            state != null && !(state is OptionSetValue)) ||
                        (row.Attributes.TryGetValue(emailColumn, out var email) &&
                            email != null && !(email is string)))
                        throw Reject(trace, "REFERENCE_READ_FAILED");
                }
                return row;
            }
            catch (FaultException<OrganizationServiceFault>)
            {
                throw Reject(trace, "REFERENCE_READ_FAILED");
            }
        }

        private static EntityReference RequiredReference(Entity target, string name, string table,
            ITracingService trace)
        {
            if (!target.Attributes.TryGetValue(name, out var raw) ||
                !(raw is EntityReference value) || value.LogicalName != table || value.Id == Guid.Empty)
                throw Reject(trace, "INVALID_REFERENCE");
            return value;
        }

        private static string? OptionalText(Entity target, string name, ITracingService trace)
        {
            if (!target.Attributes.TryGetValue(name, out var value) || value == null) return null;
            if (!(value is string text)) throw Reject(trace, "INVALID_RESULT");
            return text;
        }

        private static int RequiredChoice(Entity target, string name, ITracingService trace)
        {
            if (!target.Attributes.TryGetValue(name, out var value) || !(value is OptionSetValue choice))
                throw Reject(trace, "INVALID_REQUEST");
            return choice.Value;
        }

        private static DateTime RequiredUtc(Entity target, string name, ITracingService trace)
        {
            if (!target.Attributes.TryGetValue(name, out var value) ||
                !(value is DateTime time) || time.Kind != DateTimeKind.Utc)
                throw Reject(trace, "INVALID_REQUEST");
            return time;
        }

        private static int RequiredInteger(Entity target, string name, ITracingService trace)
        {
            if (!target.Attributes.TryGetValue(name, out var value) || !(value is int number))
                throw Reject(trace, "INVALID_REQUEST");
            return number;
        }

        private static void EnsureOnlyAttributes(Entity entity, IEnumerable<string> allowed,
            ITracingService trace)
        {
            var allowedFields = allowed as string[] ?? allowed.ToArray();
            var isAllowed = Enumerable.SequenceEqual(allowedFields, CreateFields)
                ? AvailabilityMutationPolicy.IsCreateFieldSetAllowed(entity.Attributes.Keys)
                : AvailabilityMutationPolicy.IsResultFieldSetAllowed(entity.Attributes.Keys);
            if (!isAllowed)
                throw Reject(trace, "UNEXPECTED_ATTRIBUTE");
        }

        private static InvalidPluginExecutionException Reject(ITracingService trace, string category)
        {
            trace.Trace("AVQ_GUARD_REJECTED:{0}", category);
            return new InvalidPluginExecutionException("Availability query rejected: " + category);
        }
    }

    internal static class PluginConfiguration
    {
        private static readonly HashSet<string> AllowedKeys = new HashSet<string>(new[]
        {
            "ResultWriterUserId", "AllowedEmailDomains", "AllowedDurationsMinutes",
            "MaximumHorizonDays", "MinimumLeadTimeMinutes", "ResultExpiryMinutes", "MaximumCandidates"
        }.Concat(AvailabilityRequestSecurity.ConfigurationKeys)
            .Concat(Enum.GetNames(typeof(DayOfWeek)).Select(day => "BusinessHours." + day)),
            StringComparer.OrdinalIgnoreCase);

        public static AvailabilitySettings Parse(string? configuration)
        {
            if (string.IsNullOrWhiteSpace(configuration))
                throw new InvalidPluginExecutionException("Availability query configuration is missing.");

            var source = configuration!;
            var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var line in source.Split(new[] { '\r', '\n' },
                         StringSplitOptions.RemoveEmptyEntries))
            {
                var safeLine = line ?? "";
                var separator = safeLine.IndexOf('=');
                var name = separator > 0 ? safeLine.Substring(0, separator).Trim() : "";
                if (separator <= 0 || values.ContainsKey(name) || !AllowedKeys.Contains(name))
                    throw new InvalidPluginExecutionException("Availability query configuration is invalid.");
                values.Add(name, safeLine.Substring(separator + 1).Trim());
            }

            if (!values.TryGetValue("ResultWriterUserId", out var resultWriterText) ||
                !Guid.TryParse(resultWriterText, out var resultWriterId) ||
                !values.TryGetValue("AllowedEmailDomains", out var domainsText) ||
                !values.TryGetValue("AllowedDurationsMinutes", out var durationsText) ||
                !values.TryGetValue("MaximumHorizonDays", out var horizonText) ||
                !values.TryGetValue("MinimumLeadTimeMinutes", out var leadText) ||
                !values.TryGetValue("ResultExpiryMinutes", out var expiryText) ||
                !values.TryGetValue("MaximumCandidates", out var candidatesText) ||
                !int.TryParse(horizonText, NumberStyles.None, CultureInfo.InvariantCulture, out var horizon) ||
                !int.TryParse(leadText, NumberStyles.None, CultureInfo.InvariantCulture, out var lead) ||
                !int.TryParse(expiryText, NumberStyles.None, CultureInfo.InvariantCulture, out var expiry) ||
                !int.TryParse(candidatesText, NumberStyles.None, CultureInfo.InvariantCulture, out var candidates))
                throw new InvalidPluginExecutionException("Availability query configuration is invalid.");

            var durations = ParseIntegers(durationsText);
            var hours = new Dictionary<DayOfWeek, DailyBusinessHours>();
            foreach (var pair in values.Where(item => item.Key.StartsWith("BusinessHours.", StringComparison.OrdinalIgnoreCase)))
            {
                if (!Enum.TryParse(pair.Key.Substring("BusinessHours.".Length), true, out DayOfWeek day) ||
                    !Enum.IsDefined(typeof(DayOfWeek), day) || hours.ContainsKey(day))
                    throw new InvalidPluginExecutionException("Availability query configuration is invalid.");
                var bounds = pair.Value.Split('-');
                if (bounds.Length != 2 ||
                    !TimeSpan.TryParseExact(bounds[0], @"hh\:mm", CultureInfo.InvariantCulture, out var opens) ||
                    !TimeSpan.TryParseExact(bounds[1], @"hh\:mm", CultureInfo.InvariantCulture, out var closes))
                    throw new InvalidPluginExecutionException("Availability query configuration is invalid.");
                try
                {
                    hours.Add(day, new DailyBusinessHours(opens, closes));
                }
                catch (AvailabilityFailure)
                {
                    throw new InvalidPluginExecutionException("Availability query configuration is invalid.");
                }
            }

            try
            {
                return new AvailabilitySettings(
                    domainsText.Split(','),
                    durations,
                    hours,
                    lead,
                    horizon,
                    expiry,
                    resultWriterId,
                    candidates);
            }
            catch (AvailabilityFailure)
            {
                throw new InvalidPluginExecutionException("Availability query configuration is invalid.");
            }
        }

        private static int[] ParseIntegers(string value)
        {
            var result = new List<int>();
            foreach (var part in value.Split(','))
            {
                if (!int.TryParse(part.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out var number))
                    throw new InvalidPluginExecutionException("Availability query configuration is invalid.");
                result.Add(number);
            }
            return result.ToArray();
        }
    }
}
