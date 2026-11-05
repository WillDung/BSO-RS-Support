using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Xrm.Sdk;
using os_sr_avqg;

internal static partial class Program
{
    private static int assertions;
    private static readonly Guid IntegrationUser = Guid.Parse("11111111-2222-3333-4444-555555555555");
    private static readonly Guid BsoUser = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
    private static readonly DateTime Now = Utc("2026-01-05T00:00:00Z");
    private static readonly DateTime Start = Utc("2026-01-05T02:00:00Z");
    private static readonly DateTime End = Utc("2026-01-05T10:00:00Z");

    private static int Main()
    {
        TestOutlookRequest();
        TestOutlookAttendees();
        TestOutlookResponseShape();
        TestOutlookSlotFiltering();
        TestReferenceAndInputValidation();
        TestRulesAndTimeZone();
        TestCanonicalSlotJson();
        TestMutationPolicy();
        TestSafeProviderErrors();
        TestReferenceDrift();
        TestConfigurationRendering();
        TestSdkGuard();
        Console.WriteLine("Availability Query SDK checks passed: " + assertions);
        return 0;
    }

    private static void TestReferenceAndInputValidation()
    {
        Equal("INVALID_REQUEST", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, Start: DateTime.SpecifyKind(Start, DateTimeKind.Unspecified)),
            Settings(), Now), "Unspecified transport Kind remains rejected; no automatic normalization.");
        Equal("INVALID_REQUEST", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, Start: DateTime.SpecifyKind(Start, DateTimeKind.Local)),
            Settings(), Now), "Local Kind remains rejected.");
        Equal("TA_INACTIVE", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, taActive: false), Settings(), Now), "Inactive TA is rejected.");
        Equal("TA_EMAIL_MISSING", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, taEmail: null), Settings(), Now), "Missing TA address is rejected.");
        Equal("TA_EMAIL_INVALID", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, taEmail: "not-an-address"), Settings(), Now), "Invalid TA address is rejected.");
        Equal("TA_EMAIL_DOMAIN_NOT_ALLOWED", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, taEmail: "ta@other.invalid"), Settings(), Now), "Disallowed TA domain is rejected.");
        Equal("LOCATION_REQUIRED", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Onsite, locationActive: null), Settings(), Now), "Onsite requires a location.");
        Equal("LOCATION_INACTIVE", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Onsite, locationActive: false), Settings(), Now), "Inactive Location is rejected.");
        Equal("ROOM_EMAIL_MISSING", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Onsite, roomEmail: null), Settings(), Now), "Missing room mailbox is rejected.");
        Equal("ROOM_EMAIL_INVALID", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Onsite, roomEmail: "not-an-address"), Settings(), Now), "Invalid room address is rejected.");
        Equal("ROOM_EMAIL_DOMAIN_NOT_ALLOWED", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Onsite, roomEmail: "room@other.invalid"), Settings(), Now), "Disallowed room domain is rejected.");
        Equal("ROOM_EMAIL_INVALID", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Onsite, roomEmail: "TA@example.invalid"), Settings(), Now),
            "The required TA and room cannot be the same mailbox.");
        Equal(null, AvailabilityRules.ValidateQuery(Query(InterviewMode.Online, locationActive: null),
            Settings(), Now), "Online does not require a Location.");

        Equal("INVALID_REQUEST", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, Start: Start.AddMinutes(1)), Settings(), Now), "Unaligned start is rejected.");
        Equal("INVALID_REQUEST", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, Start: Start.AddTicks(1)), Settings(), Now),
            "Sub-minute start precision is rejected.");
        Equal("INVALID_REQUEST", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, Start: Start.AddDays(-1)), Settings(), Now), "Past window is rejected.");
        Equal("INVALID_REQUEST", AvailabilityRules.ValidateQuery(
            Query(InterviewMode.Online, End: Start.AddMinutes(15), duration: 30), Settings(), Now),
            "Duration must fit within the requested window.");
    }

    private static void TestRulesAndTimeZone()
    {
        var tooLong = Query(InterviewMode.Online,
            Now.AddDays(60), Now.AddDays(61), 60);
        Equal(null, AvailabilityRules.ValidateQuery(tooLong, Settings(), Now),
            "A query ending at the 61-day horizon is accepted.");
        var overHorizon = Query(InterviewMode.Online,
            Now.AddDays(61), Now.AddDays(62), 60);
        Equal("INVALID_REQUEST", AvailabilityRules.ValidateQuery(overHorizon, Settings(), Now),
            "A query beyond 61 days is rejected.");
        ThrowsCategory(() => Settings(horizon: 62), "CONFIGURATION_INVALID",
            "Configured horizon cannot exceed the approved 61-day limit.");

        var zone = TimeZoneInfo.FindSystemTimeZoneById(AvailabilitySettings.TimeZoneId);
        Equal(TimeSpan.FromHours(7), zone.GetUtcOffset(Utc("2026-01-05T00:00:00Z")),
            "SE Asia Standard Time uses UTC+07 in winter.");
        Equal(TimeSpan.FromHours(7), zone.GetUtcOffset(Utc("2026-07-05T00:00:00Z")),
            "SE Asia Standard Time does not shift for daylight time.");
    }

    private static void TestCanonicalSlotJson()
    {
        var first = new AvailableSlot(Start.AddMinutes(15), Start.AddMinutes(75));
        var second = new AvailableSlot(Start, Start.AddMinutes(60));
        var json = SlotResultJson.Serialize(new[] { first, second }, 10, 1024);
        var expected = "[{\"startUtc\":\"2026-01-05T02:00:00Z\",\"endUtc\":\"2026-01-05T03:00:00Z\"}," +
                       "{\"startUtc\":\"2026-01-05T02:15:00Z\",\"endUtc\":\"2026-01-05T03:15:00Z\"}]";
        Equal(expected, json, "Slot JSON is canonical and sorted.");
        Equal(2, SlotResultJson.ValidateCanonical(json, 10, 1024).Count, "Canonical JSON validates.");
        Equal(0, SlotResultJson.ValidateCanonical("[]", 10, 1024).Count, "Empty results use [] only.");
        ThrowsCategory(() => SlotResultJson.ValidateCanonical(
            "[{\"startUtc\":\"2026-01-05T02:00:00Z\",\"endUtc\":\"2026-01-05T03:00:00Z\",\"email\":\"x\"}]",
            10, 1024), "RESULT_INVALID", "Additional JSON fields are rejected.");
        ThrowsCategory(() => SlotResultJson.ValidateCanonical(
            "[{\"startUtc\":\"2026-01-05T02:00:00Z\",\"endUtc\":\"2026-01-05T03:00:00Z\"}," +
            "{\"startUtc\":\"2026-01-05T02:00:00Z\",\"endUtc\":\"2026-01-05T03:00:00Z\"}]",
            10, 1024), "RESULT_INVALID", "Duplicate slots are rejected.");
        ThrowsCategory(() => SlotResultJson.Serialize(new[] { second }, 10, 8),
            "RESULT_TOO_LARGE", "Payload size is bounded.");
        ThrowsCategory(() => SlotResultJson.Serialize(new[]
        {
            new AvailableSlot(DateTime.SpecifyKind(Start, DateTimeKind.Unspecified), End)
        }, 10, 1024), "RESULT_INVALID", "Non-UTC slot values are not reinterpreted as UTC.");
        ThrowsCategory(() => SlotResultJson.Serialize(new[]
        {
            new AvailableSlot(Start.AddTicks(1), End)
        }, 10, 1024), "RESULT_INVALID", "Sub-minute slot precision is rejected.");
        ThrowsCategory(() => SlotResultJson.Serialize(
            Enumerable.Range(0, 3).Select(index => new AvailableSlot(Start.AddMinutes(index * 15),
                Start.AddMinutes(index * 15 + 60))), 2, 1024),
            "RESULT_INVALID", "Slot count is bounded.");
        Equal(false, SlotResultJson.IsSafeError("Request failed: credential leaked"),
            "Exception and credential text is not an allowed category.");
        Equal(true, SlotResultJson.IsSafeError("PROVIDER_TIMEOUT"), "Safe error category is accepted.");
        Equal(false, SlotResultJson.IsSafeReason("No slots: ta@domain"), "Reason cannot contain provider data.");
    }

    private static void TestMutationPolicy()
    {
        Equal(true, AvailabilityMutationPolicy.IsCreateCaller(BsoUser, BsoUser, IntegrationUser),
            "BSO can submit query input.");
        Equal(false, AvailabilityMutationPolicy.IsCreateCaller(IntegrationUser, IntegrationUser, IntegrationUser),
            "Integration identity cannot create requester rows.");
        Equal(false, AvailabilityMutationPolicy.IsCreateCaller(BsoUser, IntegrationUser, IntegrationUser),
            "Mismatched initiating identity is rejected.");
        Equal(true, AvailabilityMutationPolicy.IsResultUpdateCaller(IntegrationUser, IntegrationUser, IntegrationUser),
            "Configured result writer can complete result.");
        Equal(false, AvailabilityMutationPolicy.IsResultUpdateCaller(BsoUser, BsoUser, IntegrationUser),
            "BSO cannot write results.");
        Equal(false, AvailabilityMutationPolicy.IsResultUpdateCaller(IntegrationUser, BsoUser, IntegrationUser),
            "Impersonated update is rejected.");
        Equal(true, AvailabilityMutationPolicy.IsCreateFieldSetAllowed(new[]
        {
            "os_sr_avq_ta", "os_sr_avq_mod", "os_sr_avq_strt", "os_sr_avq_end", "os_sr_avq_dur"
        }), "Allowed input fields are accepted.");
        Equal(false, AvailabilityMutationPolicy.IsCreateFieldSetAllowed(new[] { "os_sr_avq_stat" }),
            "BSO cannot set query state.");
        Equal(false, AvailabilityMutationPolicy.IsCreateFieldSetAllowed(new[] { "os_sr_avq_slts" }),
            "BSO cannot submit result slots.");
        Equal(false, AvailabilityMutationPolicy.IsCreateFieldSetAllowed(new[] { "os_sr_avq_ta", "os_sr_avq_cand" }),
            "Candidate lookup is not allowed.");
        Equal(true, AvailabilityMutationPolicy.IsResultFieldSetAllowed(new[]
        {
            "os_sr_avq_stat", "os_sr_avq_slts", "os_sr_avq_qat", "os_sr_avq_exp"
        }), "Integration result fields are allowed.");
        Equal(false, AvailabilityMutationPolicy.IsResultFieldSetAllowed(new[]
        {
            "os_sr_avq_stat", "os_sr_avq_ta"
        }), "Integration cannot change original inputs.");
        Equal(false, AvailabilityMutationPolicy.IsResultFieldSetAllowed(Array.Empty<string>()),
            "Empty update rejected.");
        Equal(true, AvailabilityMutationPolicy.IsTerminalTransition(QueryState.Pending, QueryState.Available),
            "Pending can become Available.");
        Equal(true, AvailabilityMutationPolicy.IsTerminalTransition(QueryState.Pending, QueryState.NoSlots),
            "Pending can become NoSlots.");
        Equal(true, AvailabilityMutationPolicy.IsTerminalTransition(QueryState.Pending, QueryState.Failed),
            "Pending can become Failed.");
        Equal(false, AvailabilityMutationPolicy.IsTerminalTransition(QueryState.Available, QueryState.Failed),
            "Terminal state cannot transition again.");
    }

    private static void TestSafeProviderErrors()
    {
        Equal("PROVIDER_AUTH", AvailabilityRules.NormalizeProviderError(401), "401 is sanitized.");
        Equal("PROVIDER_PERMISSION", AvailabilityRules.NormalizeProviderError(403), "403 is sanitized.");
        Equal("MAILBOX_NOT_FOUND", AvailabilityRules.NormalizeProviderError(404), "404 is sanitized.");
        Equal("PROVIDER_THROTTLED", AvailabilityRules.NormalizeProviderError(429), "429 is sanitized.");
        Equal("PROVIDER_TIMEOUT", AvailabilityRules.NormalizeProviderError(null, true), "Timeout is sanitized.");
        Equal("PROVIDER_UNAVAILABLE", AvailabilityRules.NormalizeProviderError(500), "Provider error is sanitized.");
        var failed = AvailabilityRules.ProviderFailure(500);
        Equal(QueryState.Failed, failed.State, "Provider failure is a Failed result.");
        Equal(0, failed.Slots.Count, "Provider failure cannot expose slots.");
    }

    private static void TestReferenceDrift()
    {
        var ta = new CalendarReferenceSnapshot(BsoUser, 0, "TA@example.invalid ");
        var room = new CalendarReferenceSnapshot(IntegrationUser, 0, "room@example.invalid");
        var available = AvailabilityResult.Available(new[] { new AvailableSlot(Start, End) });
        var cases = new[]
        {
            (InterviewMode.Online, new CalendarReferenceSnapshot(BsoUser, 0, "changed@example.invalid"), room, "TA address changed"),
            (InterviewMode.Online, new CalendarReferenceSnapshot(BsoUser, 1, "ta@example.invalid"), room, "TA became inactive"),
            (InterviewMode.Onsite, ta, new CalendarReferenceSnapshot(IntegrationUser, 0, "changed@example.invalid"), "Room address changed"),
            (InterviewMode.Onsite, ta, new CalendarReferenceSnapshot(IntegrationUser, 1, "room@example.invalid"), "Location became inactive"),
            (InterviewMode.Onsite, new CalendarReferenceSnapshot(Guid.Empty, 0, "ta@example.invalid"), room, "TA id missing"),
            (InterviewMode.Onsite, ta, new CalendarReferenceSnapshot(BsoUser, 0, "room@example.invalid"), "Location id changed")
        };
        foreach (var item in cases)
        {
            foreach (var proposed in new[] { available, AvailabilityResult.NoSlots("NO_COMMON_SLOT"),
                         AvailabilityResult.Failed("PROVIDER_TIMEOUT") })
            {
                var result = ReferenceDriftPolicy.BeforeTerminalWrite(item.Item1, ta, room,
                    item.Item2, item.Item3, proposed);
                Equal(QueryState.Failed, result.State, item.Item4 + ": failed before every terminal write.");
                Equal("REFERENCE_CHANGED", result.Error, item.Item4 + ": deterministic drift category.");
                Equal<string?>(null, result.Reason, item.Item4 + ": no stale NoSlots reason.");
                Equal("[]", SlotResultJson.Serialize(result.Slots, 200, 32768),
                    item.Item4 + ": no slots returned.");
                var fields = new[]
                {
                    "os_sr_avq_stat", "os_sr_avq_err", "os_sr_avq_rsn",
                    "os_sr_avq_slts", "os_sr_avq_qat", "os_sr_avq_exp"
                };
                Equal(true, AvailabilityMutationPolicy.IsResultFieldSetAllowed(fields),
                    item.Item4 + ": completion is restricted to operational result fields.");
                Equal(false, AvailabilityMutationPolicy.IsResultFieldSetAllowed(
                    fields.Concat(new[] { "os_sr_cand_stat", "os_sr_intv_stat", "os_sr_cact",
                        "os_sr_csh", "os_sr_oprc", "os_sr_clog" })),
                    item.Item4 + ": no Candidate/Core mutation path in completion.");
            }
        }
        Equal("REFERENCE_CHANGED", ReferenceDriftPolicy.BeforeTerminalWrite(
            InterviewMode.Online, ta, null, null, null, available).Error, "Unreadable TA fails closed.");
        Equal("REFERENCE_CHANGED", ReferenceDriftPolicy.BeforeTerminalWrite(
            InterviewMode.Onsite, ta, room, ta, null, available).Error, "Unreadable Location fails closed.");
        Equal(true, SlotResultJson.IsSafeError("REFERENCE_CHANGED"), "Guard permits safe drift failure.");
        Equal(1, available.Slots.Count, "Drift never mutates the proposed result in memory.");

        var record = new Dictionary<string, object>
        {
            ["id"] = BsoUser, ["statecode"] = 0, ["email"] = "ta@example.invalid", ["name"] = "Old name"
        };
        CalendarReferenceSnapshot Capture(Dictionary<string, object> row) =>
            new CalendarReferenceSnapshot((Guid)row["id"], (int)row["statecode"], (string)row["email"]);
        var beforeNameChange = Capture(record);
        record["name"] = "New name";
        var roomRecord = new Dictionary<string, object>
        {
            ["id"] = IntegrationUser, ["statecode"] = 0, ["email"] = "room@example.invalid", ["name"] = "Old room"
        };
        var beforeRoomNameChange = Capture(roomRecord);
        roomRecord["name"] = "New room";
        Equal(available, ReferenceDriftPolicy.BeforeTerminalWrite(InterviewMode.Onsite,
            beforeNameChange, beforeRoomNameChange, Capture(record), Capture(roomRecord), available),
            "Unrelated TA/Location display-name changes do not invalidate availability.");
        Equal(available, ReferenceDriftPolicy.BeforeTerminalWrite(InterviewMode.Online,
            ta, room, new CalendarReferenceSnapshot(BsoUser, 0, "ta@EXAMPLE.INVALID"), null, available),
            "Normalization is consistent and Online ignores Location.");
    }

    private static void TestConfigurationRendering()
    {
        var source = ConfigurationSource();
        var rendered = AvailabilityConfigurationRenderer.Render(source, IntegrationUser);
        Equal(rendered, AvailabilityConfigurationRenderer.Render(source.Reverse(), IntegrationUser),
            "Environment enumeration order does not affect rendering.");
        var reorderedDays = new Dictionary<string, string>(source)
        {
            ["os_sr_avq_bhrs"] = "{\"monday\":{\"closes\":\"17:00\",\"opens\":\"09:00\"},\"friday\":{\"opens\":\"10:00\",\"closes\":\"16:00\"}}"
        };
        Equal(rendered, AvailabilityConfigurationRenderer.Render(reorderedDays, IntegrationUser),
            "JSON property order does not affect rendering.");
        Equal(false, rendered.Contains("\r"), "Canonical output uses LF separators.");
        var parsed = PluginConfiguration.Parse(rendered);
        Equal(IntegrationUser, parsed.ResultWriterUserId, "Environment-specific writer identity round-trips.");
        Equal(25, parsed.MaximumCandidates, "Configured candidate limit round-trips exactly.");
        Equal(60, parsed.MaximumHorizonDays, "Source horizon round-trips exactly.");
        Equal(45, parsed.MinimumLeadTimeMinutes, "Source lead time round-trips exactly.");
        Equal(12, parsed.ResultExpiryMinutes, "Source expiry round-trips exactly.");
        Equal("30,60,90", string.Join(",", parsed.AllowedDurationsMinutes),
            "Source duration values and order round-trip exactly.");
        Equal("example.invalid,calendar.invalid", string.Join(",", parsed.AllowedEmailDomains),
            "Source allowed domains round-trip exactly.");
        Equal(2, parsed.BusinessHours.Count, "Exactly the source business days are parsed.");
        Equal(TimeSpan.FromHours(9), parsed.BusinessHours[DayOfWeek.Monday].Opens, "Monday open round-trips.");
        Equal(TimeSpan.FromHours(17), parsed.BusinessHours[DayOfWeek.Monday].Closes, "Monday close round-trips.");
        Equal(TimeSpan.FromHours(10), parsed.BusinessHours[DayOfWeek.Friday].Opens, "Friday open round-trips.");
        Equal(TimeSpan.FromHours(16), parsed.BusinessHours[DayOfWeek.Friday].Closes, "Friday close round-trips.");
        foreach (var key in source.Keys)
        {
            ConfigurationRejects(() => AvailabilityConfigurationRenderer.Render(
                source.Where(pair => pair.Key != key), IntegrationUser), "Missing environment setting " + key);
        }
        ConfigurationRejects(() => AvailabilityConfigurationRenderer.Render(
            source.Concat(source.Take(1)), IntegrationUser), "Duplicate environment settings reject.");
        foreach (var unknown in new[] { "unknown", "client_secret", "access_token", "certificate", "refresh_token" })
        {
            ConfigurationRejects(() => AvailabilityConfigurationRenderer.Render(
                source.Concat(new[] { new KeyValuePair<string, string>(unknown, "synthetic-not-a-secret") }),
                IntegrationUser), "Unknown/credential settings never render: " + unknown);
            ConfigurationRejects(() => PluginConfiguration.Parse(rendered + "\n" + unknown + "=synthetic"),
                "Unknown parser setting rejects: " + unknown);
        }
        ConfigurationRejects(() => AvailabilityConfigurationRenderer.Render(source, Guid.Empty),
            "Missing integration identity rejects.");
        void RejectValue(string key, string value)
        {
            var changed = new Dictionary<string, string>(source) { [key] = value };
            ConfigurationRejects(() => AvailabilityConfigurationRenderer.Render(changed, IntegrationUser),
                "Invalid source rejects: " + key);
        }
        RejectValue("os_sr_avq_hzn", "62");
        RejectValue("os_sr_avq_hzn", "0");
        RejectValue("os_sr_avq_maxc", "0");
        RejectValue("os_sr_avq_maxc", "201");
        RejectValue("os_sr_avq_durs", "30,40");
        RejectValue("os_sr_avq_durs", "30,30");
        RejectValue("os_sr_avq_dom", "example.invalid\nclient_secret=synthetic");
        RejectValue("os_sr_avq_exp", "12\nUnknown=value");
        RejectValue("os_sr_avq_bhrs", "{}");
        RejectValue("os_sr_avq_bhrs", "{\"monday\":{\"opens\":\"09:00\",\"closes\":\"17:00\",\"secret\":\"x\"}}");
        RejectValue("os_sr_avq_bhrs", "{\"__type\":\"x\",\"monday\":{\"opens\":\"09:00\",\"closes\":\"17:00\"}}");
        RejectValue("os_sr_avq_bhrs", "{\"monday\":{\"__type\":\"x\",\"opens\":\"09:00\",\"closes\":\"17:00\"}}");
        RejectValue("os_sr_avq_bhrs", "{\"monday\":{\"opens\":900,\"closes\":\"17:00\"}}");
        RejectValue("os_sr_avq_bhrs", "{\"monday\":{\"opens\":\"09:00\",\"opens\":\"10:00\",\"closes\":\"17:00\"}}");
        RejectValue("os_sr_avq_bhrs", "{\"monday\":{\"opens\":\"09:00\",\"closes\":\"17:00\"},\"monday\":{\"opens\":\"10:00\",\"closes\":\"16:00\"}}");
        RejectValue("os_sr_avq_bhrs", "{\"monday\":{\"opens\":\"09:00\",\"closes\":\"17:00\"},\"Monday\":{\"opens\":\"10:00\",\"closes\":\"16:00\"}}");
        RejectValue("os_sr_avq_bhrs", "{\"0\":{\"opens\":\"09:00\",\"closes\":\"17:00\"}}");
        RejectValue("os_sr_avq_bhrs", "{\"monday\":{\"opens\":\"17:00\",\"closes\":\"09:00\"}}");
        RejectValue("os_sr_avq_bhrs", source["os_sr_avq_bhrs"] + "{}");

        foreach (var line in rendered.Split('\n'))
        {
            ConfigurationRejects(() => PluginConfiguration.Parse(rendered + "\n" + line),
                "Duplicate parser key rejects.");
        }
        ConfigurationRejects(() => PluginConfiguration.Parse(rendered + "\nmaximumhorizondays=60"),
            "Case-insensitive duplicate parser key rejects.");
        foreach (var key in new[] { "ResultWriterUserId", "AllowedEmailDomains",
                     "AllowedDurationsMinutes", "MaximumHorizonDays", "MinimumLeadTimeMinutes",
                     "ResultExpiryMinutes", "MaximumCandidates", "BusinessHours." })
        {
            ConfigurationRejects(() => PluginConfiguration.Parse(string.Join("\n",
                rendered.Split('\n').Where(line => !line.StartsWith(key, StringComparison.Ordinal)))),
                "Parser rejects missing required setting: " + key);
        }
        ConfigurationRejects(() => PluginConfiguration.Parse(rendered.Replace("MaximumHorizonDays=60",
            "MaximumHorizonDays=62")), "Real parser rejects horizon above 61.");
        ConfigurationRejects(() => PluginConfiguration.Parse(rendered.Replace("30,60,90", "30,40")),
            "Real parser rejects durations not divisible by 15.");
        ConfigurationRejects(() => PluginConfiguration.Parse(rendered + "\nBusinessHours.Holiday=09:00-17:00"),
            "Unknown business-day parser key rejects.");
        ConfigurationRejects(() => PluginConfiguration.Parse(rendered + "\nIntegrationApplicationUserId=" +
            IntegrationUser.ToString("D")), "The superseded application-user setting is rejected.");
        Equal(false, rendered.Contains("synthetic-not-a-secret"), "Rejected credential input never reaches output.");
    }

    private static Dictionary<string, string> ConfigurationSource() => new Dictionary<string, string>
    {
        ["os_sr_avq_bhrs"] = "{\"friday\":{\"opens\":\"10:00\",\"closes\":\"16:00\"},\"monday\":{\"opens\":\"09:00\",\"closes\":\"17:00\"}}",
        ["os_sr_avq_durs"] = "30,60,90",
        ["os_sr_avq_lead"] = "45",
        ["os_sr_avq_hzn"] = "60",
        ["os_sr_avq_exp"] = "12",
        ["os_sr_avq_dom"] = "example.invalid,calendar.invalid",
        ["os_sr_avq_maxc"] = "25"
    };

    private static void ConfigurationRejects(Action action, string description)
    {
        assertions++;
        try { action(); }
        catch (InvalidPluginExecutionException exception)
        {
            if (exception.Message.Contains("configuration")) return;
            throw;
        }
        throw new InvalidOperationException(description);
    }

    private static AvailabilitySettings Settings(int leadMinutes = 0, int horizon = 61,
        int maxCandidates = 25, int maxSlots = 200, int maxPayloadLength = 32768)
    {
        return new AvailabilitySettings(
            new[] { "example.invalid" },
            new[] { 30, 45, 60 },
            new Dictionary<DayOfWeek, DailyBusinessHours>
            {
                { DayOfWeek.Monday, new DailyBusinessHours(TimeSpan.FromHours(9), TimeSpan.FromHours(17)) },
                { DayOfWeek.Tuesday, new DailyBusinessHours(TimeSpan.FromHours(9), TimeSpan.FromHours(17)) },
                { DayOfWeek.Wednesday, new DailyBusinessHours(TimeSpan.FromHours(9), TimeSpan.FromHours(17)) },
                { DayOfWeek.Thursday, new DailyBusinessHours(TimeSpan.FromHours(9), TimeSpan.FromHours(17)) },
                { DayOfWeek.Friday, new DailyBusinessHours(TimeSpan.FromHours(9), TimeSpan.FromHours(17)) }
            },
            leadMinutes,
            horizon,
            10,
            IntegrationUser,
            maxCandidates,
            maxSlots,
            maxPayloadLength);
    }

    private static AvailabilityQuery Query(
        InterviewMode mode,
        DateTime? Start = null,
        DateTime? End = null,
        int duration = 60,
        bool taActive = true,
        string? taEmail = "ta@example.invalid",
        bool? locationActive = true,
        string? roomEmail = "room@example.invalid")
    {
        return new AvailabilityQuery(mode, Start ?? Program.Start, End ?? Program.End, duration,
            taActive, taEmail, locationActive, roomEmail);
    }

    private static DateTime Utc(string value) =>
        DateTime.Parse(value, null, System.Globalization.DateTimeStyles.AdjustToUniversal |
            System.Globalization.DateTimeStyles.AssumeUniversal);

    private static void Equal<T>(T expected, T actual, string description)
    {
        assertions++;
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException(description + " Expected: " + expected + "; actual: " + actual);
    }

    private static void ThrowsCategory(Action action, string category, string description)
    {
        assertions++;
        try
        {
            action();
        }
        catch (AvailabilityFailure failure)
        {
            if (failure.Category == category) return;
            throw new InvalidOperationException(description + " Wrong failure category: " + failure.Category);
        }
        throw new InvalidOperationException(description + " Expected " + category);
    }
}
