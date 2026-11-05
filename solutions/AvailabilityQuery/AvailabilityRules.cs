using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Linq;
using System.Net.Mail;
using System.Text;
using System.Text.RegularExpressions;

namespace os_sr_avqg
{
    public enum InterviewMode
    {
        Online = 100000000,
        Onsite = 100000001
    }

    public enum QueryState
    {
        Pending = 100000000,
        Available = 100000001,
        NoSlots = 100000002,
        Failed = 100000003
    }

    public sealed class AvailabilityFailure : Exception
    {
        public AvailabilityFailure(string category) : base(category)
        {
            Category = category;
        }

        public string Category { get; }
    }

    public sealed class DailyBusinessHours
    {
        public DailyBusinessHours(TimeSpan opens, TimeSpan closes)
        {
            if (opens < TimeSpan.Zero || closes > TimeSpan.FromDays(1) || opens >= closes)
                throw new AvailabilityFailure("CONFIGURATION_INVALID");
            Opens = opens;
            Closes = closes;
        }

        public TimeSpan Opens { get; }
        public TimeSpan Closes { get; }
    }

    public sealed class AvailabilitySettings
    {
        public const int IntervalMinutes = 15;
        public const int HardMaximumHorizonDays = 61;
        public const string TimeZoneId = "SE Asia Standard Time";
        public const int DefaultMaximumSlots = 200;
        public const int DefaultMaximumPayloadLength = 32768;

        public AvailabilitySettings(
            IEnumerable<string> allowedEmailDomains,
            IEnumerable<int> allowedDurationsMinutes,
            IDictionary<DayOfWeek, DailyBusinessHours> businessHours,
            int minimumLeadTimeMinutes,
            int maximumHorizonDays,
            int resultExpiryMinutes,
            Guid integrationApplicationUserId,
            int maximumSlotCount = DefaultMaximumSlots,
            int maximumPayloadLength = DefaultMaximumPayloadLength)
        {
            var domains = (allowedEmailDomains ?? throw new AvailabilityFailure("CONFIGURATION_INVALID"))
                .Select(NormalizeDomain)
                .ToArray();
            var durations = (allowedDurationsMinutes ?? throw new AvailabilityFailure("CONFIGURATION_INVALID"))
                .Distinct()
                .ToArray();
            if (domains.Length == 0 || domains.Any(domain => domain.Length == 0) ||
                durations.Length == 0 || durations.Any(duration => duration <= 0 || duration > 480 ||
                    duration % IntervalMinutes != 0) ||
                businessHours == null || businessHours.Count == 0 ||
                businessHours.Keys.Any(day => !Enum.IsDefined(typeof(DayOfWeek), day)) ||
                minimumLeadTimeMinutes < 0 ||
                maximumHorizonDays < 1 || maximumHorizonDays > HardMaximumHorizonDays ||
                resultExpiryMinutes < 1 || resultExpiryMinutes > 1440 ||
                integrationApplicationUserId == Guid.Empty ||
                maximumSlotCount < 1 || maximumSlotCount > 1000 ||
                maximumPayloadLength < 256 || maximumPayloadLength > 262144)
                throw new AvailabilityFailure("CONFIGURATION_INVALID");

            AllowedEmailDomains = Array.AsReadOnly(domains);
            AllowedDurationsMinutes = Array.AsReadOnly(durations);
            BusinessHours = new ReadOnlyDictionary<DayOfWeek, DailyBusinessHours>(
                new Dictionary<DayOfWeek, DailyBusinessHours>(businessHours));
            MinimumLeadTimeMinutes = minimumLeadTimeMinutes;
            MaximumHorizonDays = maximumHorizonDays;
            ResultExpiryMinutes = resultExpiryMinutes;
            IntegrationApplicationUserId = integrationApplicationUserId;
            MaximumSlotCount = maximumSlotCount;
            MaximumPayloadLength = maximumPayloadLength;
            try
            {
                TimeZone = TimeZoneInfo.FindSystemTimeZoneById(TimeZoneId);
            }
            catch (TimeZoneNotFoundException)
            {
                throw new AvailabilityFailure("TIME_ZONE_UNAVAILABLE");
            }
            catch (InvalidTimeZoneException)
            {
                throw new AvailabilityFailure("TIME_ZONE_UNAVAILABLE");
            }
        }

        public IReadOnlyCollection<string> AllowedEmailDomains { get; }
        public IReadOnlyCollection<int> AllowedDurationsMinutes { get; }
        public IReadOnlyDictionary<DayOfWeek, DailyBusinessHours> BusinessHours { get; }
        public int MinimumLeadTimeMinutes { get; }
        public int MaximumHorizonDays { get; }
        public int ResultExpiryMinutes { get; }
        public Guid IntegrationApplicationUserId { get; }
        public int MaximumSlotCount { get; }
        public int MaximumPayloadLength { get; }
        public TimeZoneInfo TimeZone { get; }

        internal static string NormalizeDomain(string domain)
        {
            var value = (domain ?? "").Trim().TrimEnd('.').ToLowerInvariant();
            if (value.Length == 0 || value.Contains("@") || value.Contains("/") ||
                value.Contains(" ") || value.Contains("..") || value.StartsWith(".", StringComparison.Ordinal))
                return "";
            return value;
        }
    }

    public sealed class AvailabilityQuery
    {
        public AvailabilityQuery(
            InterviewMode mode,
            DateTime startUtc,
            DateTime endUtc,
            int durationMinutes,
            bool taActive,
            string? taEmail,
            bool? locationActive,
            string? roomEmail)
        {
            Mode = mode;
            StartUtc = startUtc;
            EndUtc = endUtc;
            DurationMinutes = durationMinutes;
            TaActive = taActive;
            TaEmail = taEmail;
            LocationActive = locationActive;
            RoomEmail = roomEmail;
        }

        public InterviewMode Mode { get; }
        public DateTime StartUtc { get; }
        public DateTime EndUtc { get; }
        public int DurationMinutes { get; }
        public bool TaActive { get; }
        public string? TaEmail { get; }
        public bool? LocationActive { get; }
        public string? RoomEmail { get; }
    }

    public sealed class ScheduleSource
    {
        public ScheduleSource(string? availabilityView, bool hasError)
        {
            AvailabilityView = availabilityView;
            HasError = hasError;
        }

        public string? AvailabilityView { get; }
        public bool HasError { get; }
    }

    public sealed class AvailableSlot
    {
        public AvailableSlot(DateTime startUtc, DateTime endUtc)
        {
            StartUtc = startUtc;
            EndUtc = endUtc;
        }

        public DateTime StartUtc { get; }
        public DateTime EndUtc { get; }
    }

    public sealed class AvailabilityResult
    {
        private AvailabilityResult(QueryState state, string? reason, string? error,
            IReadOnlyList<AvailableSlot> slots)
        {
            State = state;
            Reason = reason;
            Error = error;
            Slots = slots;
        }

        public QueryState State { get; }
        public string? Reason { get; }
        public string? Error { get; }
        public IReadOnlyList<AvailableSlot> Slots { get; }

        public static AvailabilityResult Available(IReadOnlyList<AvailableSlot> slots) =>
            new AvailabilityResult(QueryState.Available, null, null,
                Array.AsReadOnly(slots.ToArray()));

        public static AvailabilityResult NoSlots(string reason) =>
            new AvailabilityResult(QueryState.NoSlots, reason, null, new AvailableSlot[0]);

        public static AvailabilityResult Failed(string category) =>
            new AvailabilityResult(QueryState.Failed, null, category, new AvailableSlot[0]);
    }

    public static class AvailabilityRules
    {
        private static readonly string[] SafeGraphCategories =
        {
            "GRAPH_AUTH", "GRAPH_PERMISSION", "MAILBOX_NOT_FOUND", "GRAPH_THROTTLED",
            "GRAPH_TIMEOUT", "GRAPH_UNAVAILABLE"
        };

        public static string NormalizeGraphError(int? httpStatus, bool timedOut = false)
        {
            if (timedOut) return "GRAPH_TIMEOUT";
            if (httpStatus == 401) return "GRAPH_AUTH";
            if (httpStatus == 403) return "GRAPH_PERMISSION";
            if (httpStatus == 404) return "MAILBOX_NOT_FOUND";
            if (httpStatus == 429) return "GRAPH_THROTTLED";
            return "GRAPH_UNAVAILABLE";
        }

        public static AvailabilityResult Calculate(
            AvailabilityQuery query,
            ScheduleSource? taSchedule,
            ScheduleSource? roomSchedule,
            AvailabilitySettings settings,
            DateTime nowUtc)
        {
            var validation = ValidateQuery(query, settings, nowUtc);
            if (validation != null) return AvailabilityResult.Failed(validation);

            var expectedBlocks = checked((int)((query.EndUtc - query.StartUtc).TotalMinutes /
                AvailabilitySettings.IntervalMinutes));
            var taBlocks = DecodeSchedule(taSchedule, expectedBlocks, "SOURCE_UNKNOWN_TA", out var taFailure);
            if (taBlocks == null) return AvailabilityResult.Failed(taFailure);

            var roomBlocks = Array.Empty<int>();
            if (query.Mode == InterviewMode.Onsite)
            {
                roomBlocks = DecodeSchedule(roomSchedule, expectedBlocks, "SOURCE_UNKNOWN_ROOM", out var roomFailure);
                if (roomBlocks == null) return AvailabilityResult.Failed(roomFailure);
            }

            var slots = new List<AvailableSlot>();
            var durationBlocks = query.DurationMinutes / AvailabilitySettings.IntervalMinutes;
            var step = TimeSpan.FromMinutes(AvailabilitySettings.IntervalMinutes);
            var earliestStart = AddMinutesSaturating(nowUtc, settings.MinimumLeadTimeMinutes);

            for (var index = 0; index + durationBlocks <= expectedBlocks; index++)
            {
                var start = query.StartUtc.AddTicks(step.Ticks * index);
                var end = start.AddMinutes(query.DurationMinutes);
                if (start < earliestStart || !WithinBusinessHours(start, end, settings)) continue;

                var free = true;
                for (var block = index; block < index + durationBlocks; block++)
                {
                    if (taBlocks[block] != 0 ||
                        (query.Mode == InterviewMode.Onsite && roomBlocks[block] != 0))
                    {
                        free = false;
                        break;
                    }
                }

                if (free)
                {
                    slots.Add(new AvailableSlot(start, end));
                    if (slots.Count > settings.MaximumSlotCount)
                        return AvailabilityResult.Failed("RESULT_TOO_LARGE");
                }
            }

            if (slots.Count == 0)
                return AvailabilityResult.NoSlots("NO_COMMON_SLOT");

            try
            {
                SlotResultJson.Serialize(slots, settings.MaximumSlotCount, settings.MaximumPayloadLength);
            }
            catch (AvailabilityFailure failure)
            {
                return AvailabilityResult.Failed(failure.Category);
            }
            return AvailabilityResult.Available(slots);
        }

        public static string? ValidateQuery(
            AvailabilityQuery query, AvailabilitySettings settings, DateTime nowUtc)
        {
            if (query == null || settings == null || nowUtc.Kind != DateTimeKind.Utc)
                return "INVALID_REQUEST";
            if (query.Mode != InterviewMode.Online && query.Mode != InterviewMode.Onsite)
                return "INVALID_REQUEST";
            if (!query.TaActive) return "TA_INACTIVE";
            var taEmailError = ValidateEmail(query.TaEmail, settings, "TA_EMAIL");
            if (taEmailError != null) return taEmailError;
            if (query.Mode == InterviewMode.Onsite)
            {
                if (!query.LocationActive.HasValue) return "LOCATION_REQUIRED";
                if (!query.LocationActive.Value) return "LOCATION_INACTIVE";
                var roomError = ValidateEmail(query.RoomEmail, settings, "ROOM_EMAIL");
                if (roomError != null) return roomError;
            }
            if (query.StartUtc.Kind != DateTimeKind.Utc || query.EndUtc.Kind != DateTimeKind.Utc ||
                query.StartUtc <= nowUtc || query.EndUtc <= query.StartUtc ||
                query.StartUtc.Minute % AvailabilitySettings.IntervalMinutes != 0 ||
                query.StartUtc.Ticks % TimeSpan.TicksPerMinute != 0 ||
                query.EndUtc.Minute % AvailabilitySettings.IntervalMinutes != 0 ||
                query.EndUtc.Ticks % TimeSpan.TicksPerMinute != 0 ||
                query.EndUtc > nowUtc.AddDays(Math.Min(settings.MaximumHorizonDays,
                    AvailabilitySettings.HardMaximumHorizonDays)) ||
                !settings.AllowedDurationsMinutes.Contains(query.DurationMinutes) ||
                query.DurationMinutes % AvailabilitySettings.IntervalMinutes != 0 ||
                query.EndUtc - query.StartUtc < TimeSpan.FromMinutes(query.DurationMinutes))
                return "INVALID_REQUEST";
            return null;
        }

        private static string? ValidateEmail(string? email, AvailabilitySettings settings, string prefix)
        {
            if (email == null || string.IsNullOrWhiteSpace(email)) return prefix + "_MISSING";
            try
            {
                var address = new MailAddress(email.Trim());
                if (!string.Equals(address.Address, email.Trim(), StringComparison.OrdinalIgnoreCase) ||
                    address.Address.Count(character => character == '@') != 1)
                    return prefix + "_INVALID";
                var domain = AvailabilitySettings.NormalizeDomain(address.Host);
                if (!settings.AllowedEmailDomains.Contains(domain))
                    return prefix + "_DOMAIN_NOT_ALLOWED";
            }
            catch (FormatException)
            {
                return prefix + "_INVALID";
            }
            return null;
        }

        private static int[]? DecodeSchedule(
            ScheduleSource? schedule, int expectedBlocks, string missingCategory, out string failure)
        {
            failure = "AVAILABILITY_VIEW_INVALID";
            if (schedule == null || schedule.HasError)
            {
                failure = missingCategory;
                return null;
            }
            var view = schedule.AvailabilityView;
            if (view == null || view.Length != expectedBlocks)
            {
                return null;
            }

            var blocks = new int[view.Length];
            for (var index = 0; index < view.Length; index++)
            {
                var code = view[index] - '0';
                if (code < 0 || code > 3)
                {
                    return null;
                }
                blocks[index] = code;
            }
            return blocks;
        }

        internal static DateTime AddMinutesSaturating(DateTime value, int minutes)
        {
            var ticks = (long)minutes * TimeSpan.TicksPerMinute;
            return ticks > DateTime.MaxValue.Ticks - value.Ticks
                ? DateTime.MaxValue
                : value.AddTicks(ticks);
        }

        private static bool WithinBusinessHours(DateTime startUtc, DateTime endUtc,
            AvailabilitySettings settings)
        {
            var localStart = TimeZoneInfo.ConvertTimeFromUtc(startUtc, settings.TimeZone);
            var localEnd = TimeZoneInfo.ConvertTimeFromUtc(endUtc, settings.TimeZone);
            if (localStart.Date != localEnd.Date ||
                !settings.BusinessHours.TryGetValue(localStart.DayOfWeek, out var hours))
                return false;
            return localStart.TimeOfDay >= hours.Opens && localEnd.TimeOfDay <= hours.Closes;
        }
    }

    public static class SlotResultJson
    {
        private static readonly Regex SlotPattern = new Regex(
            "\\{\\\"startUtc\\\":\\\"(?<start>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\\\",\\\"endUtc\\\":\\\"(?<end>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\\\"\\}",
            RegexOptions.CultureInvariant);
        private const string TimestampFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'";

        public static string Serialize(IEnumerable<AvailableSlot> slots, int maximumSlotCount,
            int maximumPayloadLength)
        {
            var list = (slots ?? throw new AvailabilityFailure("RESULT_INVALID"))
                .OrderBy(slot => slot.StartUtc)
                .ToArray();
            if (list.Length > maximumSlotCount || list.Any(slot => slot.StartUtc.Kind != DateTimeKind.Utc ||
                    slot.EndUtc.Kind != DateTimeKind.Utc ||
                    slot.StartUtc.Ticks % TimeSpan.TicksPerMinute != 0 ||
                    slot.EndUtc.Ticks % TimeSpan.TicksPerMinute != 0 ||
                    slot.EndUtc <= slot.StartUtc) ||
                list.Select(slot => slot.StartUtc).Distinct().Count() != list.Length)
                throw new AvailabilityFailure("RESULT_INVALID");

            var builder = new StringBuilder("[");
            for (var index = 0; index < list.Length; index++)
            {
                if (index > 0) builder.Append(',');
                builder.Append("{\"startUtc\":\"")
                    .Append(list[index].StartUtc.ToString(TimestampFormat, CultureInfo.InvariantCulture))
                    .Append("\",\"endUtc\":\"")
                    .Append(list[index].EndUtc.ToString(TimestampFormat, CultureInfo.InvariantCulture))
                    .Append("\"}");
            }
            builder.Append(']');
            if (builder.Length > maximumPayloadLength)
                throw new AvailabilityFailure("RESULT_TOO_LARGE");
            return builder.ToString();
        }

        public static IReadOnlyList<AvailableSlot> ValidateCanonical(string json,
            int maximumSlotCount, int maximumPayloadLength)
        {
            if (json == null || json.Length > maximumPayloadLength || json.Length < 2 ||
                json[0] != '[' || json[json.Length - 1] != ']')
                throw new AvailabilityFailure("RESULT_INVALID");
            if (json == "[]") return new AvailableSlot[0];

            var matches = SlotPattern.Matches(json);
            if (matches.Count > maximumSlotCount)
                throw new AvailabilityFailure("RESULT_TOO_LARGE");
            var items = new List<AvailableSlot>();
            foreach (Match match in matches)
            {
                if (!DateTime.TryParseExact(match.Groups["start"].Value, TimestampFormat,
                        CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                        out var start) ||
                    !DateTime.TryParseExact(match.Groups["end"].Value, TimestampFormat,
                        CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                        out var end) ||
                    end <= start)
                    throw new AvailabilityFailure("RESULT_INVALID");
                items.Add(new AvailableSlot(start, end));
            }

            if (items.Select(item => item.StartUtc).Distinct().Count() != items.Count ||
                !items.SequenceEqual(items.OrderBy(item => item.StartUtc)))
                throw new AvailabilityFailure("RESULT_INVALID");
            var canonical = Serialize(items, maximumSlotCount, maximumPayloadLength);
            if (!string.Equals(canonical, json, StringComparison.Ordinal))
                throw new AvailabilityFailure("RESULT_INVALID");
            return items;
        }

        public static bool IsSafeError(string? error) =>
            error != null && (new[]
            {
                "TA_INACTIVE", "TA_EMAIL_MISSING", "TA_EMAIL_INVALID", "TA_EMAIL_DOMAIN_NOT_ALLOWED",
                "LOCATION_REQUIRED", "LOCATION_INACTIVE", "ROOM_EMAIL_MISSING", "ROOM_EMAIL_INVALID",
                "ROOM_EMAIL_DOMAIN_NOT_ALLOWED", "INVALID_REQUEST", "CONFIGURATION_INVALID",
                "TIME_ZONE_UNAVAILABLE", "SOURCE_UNKNOWN_TA", "SOURCE_UNKNOWN_ROOM",
                "AVAILABILITY_VIEW_INVALID", "GRAPH_AUTH", "GRAPH_PERMISSION", "MAILBOX_NOT_FOUND",
                "GRAPH_THROTTLED", "GRAPH_TIMEOUT", "GRAPH_UNAVAILABLE", "RESULT_TOO_LARGE",
                "RESULT_INVALID", "REFERENCE_READ_FAILED", "REFERENCE_CHANGED"
            }).Contains(error, StringComparer.Ordinal);

        public static bool IsSafeReason(string? reason) =>
            reason == "NO_COMMON_SLOT";
    }

    public static class AvailabilityMutationPolicy
    {
        private static readonly HashSet<string> CreateFieldSet = new HashSet<string>(new[]
        {
            "os_sr_avq_ta", "os_sr_avq_loc", "os_sr_avq_mod",
            "os_sr_avq_strt", "os_sr_avq_end", "os_sr_avq_dur"
        }, StringComparer.Ordinal);

        private static readonly HashSet<string> ResultFieldSet = new HashSet<string>(new[]
        {
            "os_sr_avq_stat", "os_sr_avq_rsn", "os_sr_avq_err",
            "os_sr_avq_slts", "os_sr_avq_qat", "os_sr_avq_exp"
        }, StringComparer.Ordinal);

        public static bool IsCreateCaller(Guid caller, Guid initiating, Guid integrationUser) =>
            caller != Guid.Empty && caller != integrationUser && caller == initiating;

        public static bool IsResultUpdateCaller(Guid caller, Guid initiating, Guid integrationUser) =>
            caller != Guid.Empty && caller == initiating && caller == integrationUser;

        public static bool IsCreateFieldSetAllowed(IEnumerable<string> fields) =>
            fields.All(CreateFieldSet.Contains);

        public static bool IsResultFieldSetAllowed(IEnumerable<string> fields) =>
            fields.Any() && fields.All(ResultFieldSet.Contains);

        public static bool IsTerminalTransition(QueryState current, QueryState next) =>
            current == QueryState.Pending &&
            (next == QueryState.Available || next == QueryState.NoSlots || next == QueryState.Failed);
    }
}
