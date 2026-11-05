using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using os_sr_avqg;

internal static partial class Program
{
    private static void TestOutlookRequest()
    {
        var online = OutlookMeetingTimesAdapter.CreateRequest(
            Query(InterviewMode.Online, taEmail: " TA@EXAMPLE.INVALID "), Settings(), Now);
        Equal("ta@example.invalid", online.RequiredAttendees, "Required attendee is the normalized TA.");
        Equal("", online.ResourceAttendees, "Online does not request a room.");
        Equal(60, online.MeetingDuration, "Meeting duration is passed in minutes.");
        Equal(Start, online.Start, "Requested UTC start is passed exactly.");
        Equal(End, online.End, "Requested UTC end is passed exactly.");
        Equal(25, online.MaxCandidates, "Configured bounded maximum is passed.");
        Equal("100", online.MinimumAttendeePercentage, "Minimum percentage is a string.");
        Equal(true, online.IsOrganizerOptional, "Organizer is explicitly optional.");
        Equal("Work", online.ActivityDomain, "Activity domain is Work.");
        var onsite = OutlookMeetingTimesAdapter.CreateRequest(
            Query(InterviewMode.Onsite, roomEmail: " ROOM@EXAMPLE.INVALID "), Settings(), Now);
        Equal("room@example.invalid", onsite.ResourceAttendees, "Onsite requests the room as a resource.");
        var properties = typeof(OutlookMeetingTimesRequest).GetProperties().Select(property => property.Name).ToArray();
        Equal(false, properties.Contains("Candidate"), "Request contains no Candidate input.");
        Equal(false, properties.Contains("InterviewSchedule"), "Request contains no Interview Schedule input.");
        Equal(false, properties.Contains("TimeZone"), "Connector request contains no timezone input.");
        ThrowsCategory(() => OutlookMeetingTimesAdapter.CreateRequest(
            Query(InterviewMode.Online, taActive: false), Settings(), Now), "TA_INACTIVE",
            "Invalid references never produce a provider request.");
    }

    private static void TestOutlookAttendees()
    {
        var online = Query(InterviewMode.Online);
        var onsite = Query(InterviewMode.Onsite);
        var ta = Attendee("ta@example.invalid", "required", "free");
        var room = Attendee("room@example.invalid", "resource", "free");
        Equal(QueryState.Available, Evaluate(online, Suggestion(Start, Start.AddHours(1), ta)).State,
            "Online TA free is available.");
        foreach (var unavailable in new[] { "tentative", "busy", "oof", "workingElsewhere", "unknown" })
        {
            AssertNoSlots(Evaluate(online, Suggestion(Start, Start.AddHours(1),
                Attendee("ta@example.invalid", "required", unavailable))),
                "Online TA " + unavailable);
            AssertNoSlots(Evaluate(onsite, Suggestion(Start, Start.AddHours(1), ta,
                Attendee("room@example.invalid", "resource", unavailable))),
                "Onsite room " + unavailable);
        }
        AssertNoSlots(Evaluate(online, Suggestion(Start, Start.AddHours(1))),
            "Missing TA is not free");
        AssertNoSlots(Evaluate(online, Suggestion(Start, Start.AddHours(1), ta, ta)),
            "Duplicate TA is not free");
        AssertNoSlots(Evaluate(online, Suggestion(Start, Start.AddHours(1),
            Attendee("ta@example.invalid", "resource", "free"))),
            "TA must be a required attendee");
        Equal(QueryState.Available, Evaluate(online, Suggestion(Start, Start.AddHours(1), ta,
            Attendee("room@example.invalid", "resource", "busy"))).State,
            "Online ignores room availability.");
        Equal(QueryState.Available, Evaluate(onsite, Suggestion(Start, Start.AddHours(1), ta, room)).State,
            "Onsite requires both TA and room free.");
        AssertNoSlots(Evaluate(onsite, Suggestion(Start, Start.AddHours(1), ta)),
            "Missing room is not free");
        AssertNoSlots(Evaluate(onsite, Suggestion(Start, Start.AddHours(1), ta, room, room)),
            "Duplicate room is not free");
        AssertNoSlots(Evaluate(onsite, Suggestion(Start, Start.AddHours(1), ta,
            Attendee("room@example.invalid", "required", "free"))),
            "Room must be a resource attendee");
        Equal(QueryState.Available, Evaluate(onsite, Suggestion(Start, Start.AddHours(1),
            Attendee("TA@EXAMPLE.INVALID", "required", "free"),
            Attendee("ROOM@EXAMPLE.INVALID", "resource", "free"))).State,
            "Attendee addresses match the normalized reference snapshots.");

        foreach (var organizer in new string?[] { null, "free", "busy", "tentative", "oof", "unknown" })
        {
            var suggestion = SuggestionWithOptions(Start, Start.AddHours(1), "UTC", "UTC", organizer, ta);
            Equal(QueryState.Available, Evaluate(online, suggestion).State,
                "Organizer availability does not decide accepted slots: " + (organizer ?? "missing"));
        }
        AssertNoSlots(Evaluate(online, SuggestionWithOptions(Start, Start.AddHours(1), "UTC", "UTC",
            "free", Attendee("ta@example.invalid", "required", "busy"))),
            "A free organizer cannot override a busy TA");
    }

    private static void TestOutlookResponseShape()
    {
        var query = Query(InterviewMode.Online);
        var ta = Attendee("ta@example.invalid", "required", "free");
        var valid = Provider(Suggestion(Start, Start.AddHours(1), ta));
        var empty = AvailabilityRules.Calculate(query, Provider(), Settings(), Now);
        AssertNoSlots(empty, "A valid zero-suggestion response");
        Equal(false, (empty.Reason ?? "").Contains("SYNTHETIC_PROVIDER_REASON"),
            "Provider empty reason is not exposed.");

        var malformed = new (string? Json, string Description)[]
        {
            (null, "Missing provider response"),
            ("", "Empty provider response"),
            ("[]", "Non-object provider response"),
            ("{}", "Missing top-level fields"),
            ("{\"emptySuggestionsReason\":\"\",\"meetingTimeSuggestions\":{}}", "Suggestion list is not an array"),
            ("{\"emptySuggestionsReason\":null,\"meetingTimeSuggestions\":[]}", "Missing reason shape"),
            ("{\"emptySuggestionsReason\":\"\",\"meetingTimeSuggestions\":[null]}", "Malformed suggestion"),
            ("{\"emptySuggestionsReason\":\"\",\"meetingTimeSuggestions\":[{}]}", "Missing suggestion fields"),
            (valid + "{}", "Trailing JSON"),
            (valid.Replace("\"emptySuggestionsReason\":\"SYNTHETIC_PROVIDER_REASON\"",
                "\"emptySuggestionsReason\":\"a\",\"emptySuggestionsReason\":\"b\""), "Duplicate top-level field"),
            (valid.Replace("\"confidence\":100", "\"confidence\":\"100\""), "Malformed confidence"),
            (valid.Replace("\"confidence\":100", "\"confidence\":101"), "Out-of-range confidence"),
            (valid.Replace("\"confidence\":100", "\"confidence\":1e9999"), "Unrepresentable confidence"),
            (valid.Replace("\"confidence\":100", "\"unknownProperty\":100"), "Unknown suggestion field"),
            (valid.Replace("\"attendeeAvailability\":[", "\"attendeeAvailability\":{\"unexpected\":["), "Malformed attendee list"),
            (Provider(Suggestion(Start, Start.AddHours(1), "{}")), "Malformed attendee availability"),
            (Provider(Suggestion(Start, Start.AddHours(1),
                "{\"attendee\":{\"emailAddress\":{\"address\":\"ta@example.invalid\"}},\"availability\":\"free\"}")),
                "Missing attendee type"),
            (Provider(Suggestion(Start, Start.AddHours(1),
                "{\"attendee\":{\"type\":\"required\",\"emailAddress\":{}},\"availability\":\"free\"}")),
                "Missing attendee address"),
            (Provider(Suggestion(Start, Start.AddHours(1),
                "{\"attendee\":{\"type\":\"required\",\"emailAddress\":{\"address\":\"ta@example.invalid\"}}}")),
                "Missing attendee availability"),
            (Provider(Suggestion(Start, Start.AddHours(1),
                Attendee("ta@example.invalid", "required", "provider-changed"))), "Unknown availability shape"),
            (Provider(Suggestion(Start, Start.AddHours(1),
                Attendee("ta@example.invalid", "changed-type", "free"))), "Unknown attendee type"),
            (Provider(Suggestion(Start, Start.AddHours(1),
                Attendee("not-an-address", "required", "free"))), "Malformed attendee address"),
            (valid.Replace("\"timeZone\":\"UTC\"", "\"timeZone\":null"), "Malformed timezone"),
            (valid.Replace("\"dateTime\":\"2026-01-05T02:00:00.0000000\"",
                "\"dateTime\":\"2026-01-05T02:00:00+00:00\""), "Unrecognized dateTime representation"),
            (Provider(Suggestion(Start, Start, ta)), "Non-positive interval"),
            ("{\"error\":{\"message\":\"SYNTHETIC_CONNECTOR_ERROR\"}}", "Provider error body"),
            ("{\"emptySuggestionsReason\":\"" + new string('x', 1048576) + "\",\"meetingTimeSuggestions\":[]}",
                "Oversized provider response")
        };
        foreach (var item in malformed)
            AssertFailed(AvailabilityRules.Calculate(query, item.Json, Settings(), Now),
                "PROVIDER_RESPONSE_INVALID", item.Description);

        foreach (var zones in new[] { ("Pacific Standard Time", "UTC"), ("UTC", "SE Asia Standard Time") })
        {
            var suggestion = SuggestionWithOptions(Start, Start.AddHours(1), zones.Item1, zones.Item2, "busy", ta);
            AssertFailed(Evaluate(query, suggestion), "PROVIDER_TIMEZONE_UNSUPPORTED",
                "An unsupported start or end timezone must stop");
        }
        var withUnsupportedLast = Provider(Suggestion(Start, Start.AddHours(1), ta),
            SuggestionWithOptions(Start.AddMinutes(15), Start.AddMinutes(75), "Pacific Standard Time", "UTC", "busy", ta));
        AssertFailed(AvailabilityRules.Calculate(query, withUnsupportedLast, Settings(), Now),
            "PROVIDER_TIMEZONE_UNSUPPORTED", "A later unknown timezone invalidates the entire response");

        var zulu = valid.Replace("2026-01-05T02:00:00.0000000", "2026-01-05T02:00:00Z")
            .Replace("2026-01-05T03:00:00.0000000", "2026-01-05T03:00:00Z");
        Equal(QueryState.Available, AvailabilityRules.Calculate(query, zulu, Settings(), Now).State,
            "An explicit Z timestamp with the recognized UTC timezone is supported.");
        var tooMany = Provider(Suggestion(Start, Start.AddHours(1), ta),
            Suggestion(Start.AddMinutes(15), Start.AddMinutes(75), ta));
        AssertFailed(AvailabilityRules.Calculate(query, tooMany, Settings(maxCandidates: 1), Now),
            "PROVIDER_RESPONSE_INVALID", "Provider response exceeding MaxCandidates");
    }

    private static void TestOutlookSlotFiltering()
    {
        var ta = Attendee("ta@example.invalid", "required", "free");
        var query = Query(InterviewMode.Online);
        AssertNoSlots(Evaluate(query, Suggestion(Start, Start.AddMinutes(45), ta)),
            "Wrong duration");
        AssertNoSlots(Evaluate(query, Suggestion(Start.AddMinutes(-15), Start.AddMinutes(45), ta)),
            "Start outside requested window");
        AssertNoSlots(Evaluate(query, Suggestion(End.AddMinutes(-30), End.AddMinutes(30), ta)),
            "End outside requested window");
        AssertNoSlots(Evaluate(query, Suggestion(Start.AddMinutes(5), Start.AddMinutes(65), ta)),
            "Misaligned slot");

        var now = Utc("2026-01-05T01:00:00Z");
        AssertNoSlots(AvailabilityRules.Calculate(query, Provider(Suggestion(Start, Start.AddHours(1), ta)),
            Settings(leadMinutes: 90), now), "Lead-time rejection");
        var leadAccepted = AvailabilityRules.Calculate(query,
            Provider(Suggestion(Start.AddMinutes(30), Start.AddMinutes(90), ta)),
            Settings(leadMinutes: 90), now);
        Equal(QueryState.Available, leadAccepted.State, "Exact lead-time boundary is accepted.");
        AssertNoSlots(AvailabilityRules.Calculate(query, Provider(Suggestion(Start, Start.AddHours(1), ta)),
            Settings(leadMinutes: int.MaxValue), Now), "Extreme lead time does not overflow");

        var wide = Query(InterviewMode.Online, Utc("2026-01-05T01:45:00Z"), End.AddHours(1));
        AssertNoSlots(Evaluate(wide, Suggestion(Utc("2026-01-05T01:45:00Z"),
            Utc("2026-01-05T02:45:00Z"), ta)), "Before local business hours");
        AssertNoSlots(Evaluate(wide, Suggestion(Utc("2026-01-05T09:15:00Z"),
            Utc("2026-01-05T10:15:00Z"), ta)), "After local business hours");
        var overnightSettings = new AvailabilitySettings(
            new[] { "example.invalid" }, new[] { 60 },
            new Dictionary<DayOfWeek, DailyBusinessHours>
            {
                { DayOfWeek.Monday, new DailyBusinessHours(TimeSpan.FromHours(22), TimeSpan.FromDays(1)) }
            }, 0, 61, 10, IntegrationUser, 25);
        var overnight = Query(InterviewMode.Online, Utc("2026-01-05T16:15:00Z"),
            Utc("2026-01-05T17:45:00Z"));
        AssertNoSlots(AvailabilityRules.Calculate(overnight, Provider(Suggestion(
            Utc("2026-01-05T16:30:00Z"), Utc("2026-01-05T17:30:00Z"), ta)),
            overnightSettings, Now), "Crossing the local business day");

        var unordered = Provider(
            Suggestion(Start.AddMinutes(30), Start.AddMinutes(90), ta),
            Suggestion(Start, Start.AddHours(1), ta),
            Suggestion(Start.AddMinutes(15), Start.AddMinutes(75), ta),
            Suggestion(Start, Start.AddHours(1), ta));
        var available = AvailabilityRules.Calculate(query, unordered, Settings(), Now);
        Equal(QueryState.Available, available.State, "Valid suggestions produce availability.");
        Equal(3, available.Slots.Count, "Identical duplicate slots are removed.");
        Equal(Start, available.Slots[0].StartUtc, "Slots are ordered by UTC start.");
        Equal(Start.AddMinutes(15), available.Slots[1].StartUtc, "Second slot is ordered.");
        Equal(Start.AddMinutes(30), available.Slots[2].StartUtc, "Third slot is ordered.");
        var json = SlotResultJson.Serialize(available.Slots, 200, 32768);
        Equal(false, json.Contains("example.invalid"), "Canonical slots contain no mailbox.");
        Equal(false, json.Contains("confidence") || json.Contains("suggestionReason") ||
            json.Contains("availability") || json.Contains("organizer") || json.Contains("locations"),
            "Canonical slots contain no provider metadata.");
        Equal(3, SlotResultJson.ValidateCanonical(json, 200, 32768).Count,
            "Only canonical UTC slots are persisted.");

        var conflicting = Provider(Suggestion(Start, Start.AddHours(1), ta),
            Suggestion(Start, Start.AddHours(1), Attendee("ta@example.invalid", "required", "busy")));
        AssertFailed(AvailabilityRules.Calculate(query, conflicting, Settings(), Now),
            "PROVIDER_RESPONSE_INVALID", "Conflicting duplicate observations fail closed");
        var five = Enumerable.Range(0, 5).Select(index =>
            Suggestion(Start.AddMinutes(index * 15), Start.AddMinutes(index * 15 + 60), ta)).ToArray();
        AssertFailed(AvailabilityRules.Calculate(query, Provider(five),
            Settings(maxCandidates: 5, maxPayloadLength: 256), Now),
            "RESULT_TOO_LARGE", "Canonical JSON length is bounded");
        ThrowsCategory(() => Settings(maxCandidates: 2, maxSlots: 1), "CONFIGURATION_INVALID",
            "Candidate limit cannot exceed the canonical slot limit.");
    }

    private static AvailabilityResult Evaluate(AvailabilityQuery query, string suggestion) =>
        AvailabilityRules.Calculate(query, Provider(suggestion), Settings(), Now);

    private static string Attendee(string address, string type, string availability) =>
        "{\"attendee\":{\"emailAddress\":{\"address\":\"" + address + "\"},\"type\":\"" +
        type + "\"},\"availability\":\"" + availability + "\"}";

    private static string Provider(params string[] suggestions) =>
        "{\"emptySuggestionsReason\":\"SYNTHETIC_PROVIDER_REASON\",\"meetingTimeSuggestions\":[" +
        string.Join(",", suggestions) + "]}";

    private static string Suggestion(DateTime start, DateTime end, params string[] attendees) =>
        SuggestionWithOptions(start, end, "UTC", "UTC", "busy", attendees);

    private static string SuggestionWithOptions(DateTime start, DateTime end, string startZone,
        string endZone, string? organizer, params string[] attendees)
    {
        var organizerJson = organizer == null ? "" : ",\"organizerAvailability\":\"" + organizer + "\"";
        return "{\"confidence\":100" + organizerJson +
            ",\"suggestionReason\":\"SYNTHETIC_SUGGESTION_REASON\",\"locations\":[{\"displayName\":\"Synthetic room\"}]" +
            ",\"meetingTimeSlot\":{\"start\":{\"dateTime\":\"" + ProviderTime(start) +
            "\",\"timeZone\":\"" + startZone + "\"},\"end\":{\"dateTime\":\"" + ProviderTime(end) +
            "\",\"timeZone\":\"" + endZone + "\"}},\"attendeeAvailability\":[" +
            string.Join(",", attendees) + "]}";
    }

    private static string ProviderTime(DateTime value) =>
        value.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff", CultureInfo.InvariantCulture);

    private static void AssertNoSlots(AvailabilityResult result, string description)
    {
        Equal(QueryState.NoSlots, result.State, description + " produces NoSlots.");
        Equal("NO_COMMON_SLOT", result.Reason, description + " uses the deterministic reason.");
        Equal(0, result.Slots.Count, description + " cannot return slots.");
    }

    private static void AssertFailed(AvailabilityResult result, string category, string description)
    {
        Equal(QueryState.Failed, result.State, description + " fails closed.");
        Equal(category, result.Error, description + " returns a safe category.");
        Equal(0, result.Slots.Count, description + " cannot return slots.");
        Equal<string?>(null, result.Reason, description + " cannot expose a provider reason.");
    }
}
