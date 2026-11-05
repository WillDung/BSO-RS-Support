using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.ServiceModel;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;

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
            "os_sr_avq_strt", "os_sr_avq_end", "os_sr_avq_dur"
        };

        private static readonly string[] ResultFields =
        {
            "os_sr_avq_stat", "os_sr_avq_rsn", "os_sr_avq_err",
            "os_sr_avq_slts", "os_sr_avq_qat", "os_sr_avq_exp"
        };

        private readonly string? unsecureConfiguration;

        public ProtectAvailabilityQuery(string? unsecureConfiguration, string? secureConfiguration)
        {
            this.unsecureConfiguration = unsecureConfiguration;
        }

        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var trace = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
            if (context.PrimaryEntityName != Table ||
                (context.MessageName != "Create" && context.MessageName != "Update") ||
                context.Stage != 20 || context.Mode != 0)
                throw Reject(trace, "UNSUPPORTED_OPERATION");

            var config = PluginConfiguration.Parse(unsecureConfiguration);
            var serviceFactory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
            var service = serviceFactory.CreateOrganizationService(context.UserId);
            if (context.MessageName == "Create")
                ValidateCreate(context, service, config, trace);
            else
                ValidateUpdate(context, service, config, trace);
        }

        private static void ValidateCreate(IPluginExecutionContext context, IOrganizationService service,
            AvailabilitySettings settings, ITracingService trace)
        {
            if (!AvailabilityMutationPolicy.IsCreateCaller(context.UserId, context.InitiatingUserId,
                    settings.IntegrationApplicationUserId) ||
                !context.InputParameters.Contains("Target") ||
                !(context.InputParameters["Target"] is Entity target) ||
                target.LogicalName != Table)
                throw Reject(trace, "CREATE_CALLER");

            EnsureOnlyAttributes(target, CreateFields, trace);
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

            var failure = AvailabilityRules.ValidateQuery(query, settings, DateTime.UtcNow);
            if (failure != null) throw Reject(trace, failure);
            target["os_sr_avq_stat"] = new OptionSetValue((int)QueryState.Pending);
            trace.Trace("AVQ_GUARD_CREATE_ALLOWED");
        }

        private static void ValidateUpdate(IPluginExecutionContext context, IOrganizationService service,
            AvailabilitySettings settings, ITracingService trace)
        {
            if (!AvailabilityMutationPolicy.IsResultUpdateCaller(context.UserId, context.InitiatingUserId,
                    settings.IntegrationApplicationUserId) ||
                !context.InputParameters.Contains("Target") ||
                !(context.InputParameters["Target"] is Entity target) ||
                target.LogicalName != Table ||
                target.Id == Guid.Empty)
                throw Reject(trace, "UPDATE_CALLER");

            EnsureOnlyAttributes(target, ResultFields, trace);
            var current = RetrieveReference(service, new EntityReference(Table, target.Id), Table, trace);
            if (current.GetAttributeValue<OptionSetValue>("os_sr_avq_stat")?.Value != (int)QueryState.Pending)
                throw Reject(trace, "TERMINAL_STATE");

            var state = RequiredChoice(target, "os_sr_avq_stat", trace);
            if (!AvailabilityMutationPolicy.IsTerminalTransition(QueryState.Pending, (QueryState)state))
                throw Reject(trace, "INVALID_RESULT_STATE");

            var slots = target.GetAttributeValue<string>("os_sr_avq_slts");
            var reason = target.GetAttributeValue<string>("os_sr_avq_rsn");
            var error = target.GetAttributeValue<string>("os_sr_avq_err");
            var queriedAt = RequiredUtc(target, "os_sr_avq_qat", trace);
            var expiresAt = RequiredUtc(target, "os_sr_avq_exp", trace);
            if (expiresAt <= queriedAt ||
                expiresAt > queriedAt.AddMinutes(settings.ResultExpiryMinutes).AddSeconds(1))
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
            var taReference = current.GetAttributeValue<EntityReference>("os_sr_avq_ta");
            if (taReference == null) throw Reject(trace, "INVALID_TA");
            var ta = RetrieveReference(service, taReference, TaTable, trace);
            Entity? location = null;
            var locationReference = current.GetAttributeValue<EntityReference>("os_sr_avq_loc");
            if (locationReference != null)
                location = RetrieveReference(service, locationReference, LocationTable, trace);
            return new AvailabilityQuery(
                (InterviewMode)(current.GetAttributeValue<OptionSetValue>("os_sr_avq_mod")?.Value ?? -1),
                current.GetAttributeValue<DateTime>("os_sr_avq_strt"),
                current.GetAttributeValue<DateTime>("os_sr_avq_end"),
                current.GetAttributeValue<int>("os_sr_avq_dur"),
                ta.GetAttributeValue<OptionSetValue>("statecode")?.Value == 0,
                ta.GetAttributeValue<string>("os_sr_ta_eml"),
                location == null ? (bool?)null :
                    location.GetAttributeValue<OptionSetValue>("statecode")?.Value == 0,
                location?.GetAttributeValue<string>("os_sr_loc_rmeml"));
        }

        private static bool AreSlotsWithinQuery(IReadOnlyList<AvailableSlot> slots,
            AvailabilityQuery query, AvailabilitySettings settings, DateTime queriedAtUtc)
        {
            if (query.StartUtc.Kind != DateTimeKind.Utc || query.EndUtc.Kind != DateTimeKind.Utc ||
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
            var earliest = AvailabilityRules.AddMinutesSaturating(queriedAtUtc,
                settings.MinimumLeadTimeMinutes);
            foreach (var slot in slots)
            {
                if (slot.StartUtc < query.StartUtc || slot.EndUtc > query.EndUtc ||
                    slot.EndUtc - slot.StartUtc != TimeSpan.FromMinutes(query.DurationMinutes) ||
                    slot.StartUtc.Ticks % TimeSpan.TicksPerMinute != 0 ||
                    slot.EndUtc.Ticks % TimeSpan.TicksPerMinute != 0 ||
                    slot.StartUtc.Minute % AvailabilitySettings.IntervalMinutes != 0 ||
                    slot.StartUtc < earliest)
                    return false;
                var localStart = TimeZoneInfo.ConvertTimeFromUtc(slot.StartUtc, settings.TimeZone);
                var localEnd = TimeZoneInfo.ConvertTimeFromUtc(slot.EndUtc, settings.TimeZone);
                if (localStart.Date != localEnd.Date ||
                    !settings.BusinessHours.TryGetValue(localStart.DayOfWeek, out var hours) ||
                    localStart.TimeOfDay < hours.Opens || localEnd.TimeOfDay > hours.Closes)
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
                    : new ColumnSet("statecode", "os_sr_loc_rmeml");
                return service.Retrieve(expectedTable, reference.Id, columns);
            }
            catch (FaultException<OrganizationServiceFault>)
            {
                throw Reject(trace, "REFERENCE_READ_FAILED");
            }
        }

        private static EntityReference RequiredReference(Entity target, string name, string table,
            ITracingService trace)
        {
            var value = target.GetAttributeValue<EntityReference>(name);
            if (value == null || value.LogicalName != table || value.Id == Guid.Empty)
                throw Reject(trace, "INVALID_REFERENCE");
            return value;
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
            var isAllowed = allowedFields.SequenceEqual(CreateFields)
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
                if (separator <= 0 || values.ContainsKey(name))
                    throw new InvalidPluginExecutionException("Availability query configuration is invalid.");
                values.Add(name, safeLine.Substring(separator + 1).Trim());
            }

            if (!values.TryGetValue("IntegrationApplicationUserId", out var integrationUserText) ||
                !Guid.TryParse(integrationUserText, out var integrationUserId) ||
                !values.TryGetValue("AllowedEmailDomains", out var domainsText) ||
                !values.TryGetValue("AllowedDurationsMinutes", out var durationsText) ||
                !values.TryGetValue("MaximumHorizonDays", out var horizonText) ||
                !values.TryGetValue("MinimumLeadTimeMinutes", out var leadText) ||
                !values.TryGetValue("ResultExpiryMinutes", out var expiryText) ||
                !int.TryParse(horizonText, NumberStyles.None, CultureInfo.InvariantCulture, out var horizon) ||
                !int.TryParse(leadText, NumberStyles.None, CultureInfo.InvariantCulture, out var lead) ||
                !int.TryParse(expiryText, NumberStyles.None, CultureInfo.InvariantCulture, out var expiry))
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
                    integrationUserId);
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
