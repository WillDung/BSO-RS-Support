using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Xrm.Sdk;
using os_sr_cact;

internal static partial class Program
{
    private sealed class Round1TestProvider : IRound1AvailabilityProvider
    {
        public bool IsOperational => true;
        public Func<Round1Selection, DateTime, Round1ProviderEvidence> Read = null!;
        public int Reads;
        public Round1ProviderEvidence Query(Round1Selection selection, DateTime now)
        { Reads++; return Read(selection, now); }
    }

    private static Round1ProviderEvidence FreeEvidence(Round1Selection selection, DateTime now,
        Round1BusyState firstRoomState = Round1BusyState.Free)
    {
        var start = TimeZoneInfo.ConvertTimeToUtc(selection.Date.Add(selection.Opens),
            TimeZoneInfo.FindSystemTimeZoneById(Round1Availability.TimeZoneId));
        var end = TimeZoneInfo.ConvertTimeToUtc(selection.Date.Add(selection.Closes),
            TimeZoneInfo.FindSystemTimeZoneById(Round1Availability.TimeZoneId));
        Round1ResourceEvidence Resource(Guid id, bool room)
        {
            var intervals = new List<Round1ProviderInterval>();
            for (var cursor = start; cursor < end; cursor = cursor.AddMinutes(15))
                intervals.Add(new Round1ProviderInterval(new DateTimeOffset(cursor).ToOffset(TimeSpan.FromHours(7)),
                    new DateTimeOffset(cursor.AddMinutes(15) < end ? cursor.AddMinutes(15) : end),
                    room && cursor == start ? firstRoomState : Round1BusyState.Free));
            return new Round1ResourceEvidence(id, selection.Correlation, now.AddSeconds(-1), now.AddSeconds(90),
                start, end, true, intervals);
        }
        return new Round1ProviderEvidence(selection, Guid.NewGuid(), Resource(selection.Room, true), Resource(selection.Ta, false));
    }

    private static void RejectAvailability(Action action, string code)
    {
        try { action(); throw new Exception("Expected " + code); }
        catch (OperationError error) { Check(error.Message == code, "Availability rejects " + code + ": " + error.Message); }
    }

    private static void TestRound1Availability()
    {
        var date = new DateTime(2026, 11, 16);
        var now = new DateTime(2026, 11, 16, 1, 0, 0, DateTimeKind.Utc);
        var selection = new Round1Selection(Actor, Candidate, Guid.NewGuid(), Guid.NewGuid(), date,
            TimeSpan.FromHours(9), TimeSpan.FromHours(17), Guid.NewGuid());
        var free = FreeEvidence(selection, now);
        var result = Round1Availability.Calculate(selection, free, now);
        Check(result.Slots.Count == 16 && result.Slots[0].StartUtc.Hour == 2 &&
            result.Slots.Last().EndUtc.Hour == 10 &&
            result.Slots.All(slot => slot.EndUtc - slot.StartUtc == TimeSpan.FromMinutes(30) &&
                slot.EvidenceCorrelation == selection.Correlation),
            "32 adjacent provider quarters produce exactly sixteen bound 30-minute UTC slots");
        Check(result.ToJson().Contains("\"date\":\"2026-11-16\"") &&
            result.ToJson().Contains("\"state\":\"Ready\"") &&
            result.ToJson().Contains("\"queryId\":\"" + selection.Correlation.ToString("D") + "\"") &&
            result.ToJson().Contains("\"evidenceCorrelationId\":\"" + selection.Correlation.ToString("D") + "\""),
            "Ready availability wire envelope includes local date, query ID and evidence correlation");
        foreach (var unavailable in new[] { Round1BusyState.Busy, Round1BusyState.Tentative,
            Round1BusyState.OutOfOffice, Round1BusyState.Unknown, (Round1BusyState)99 })
        {
            var blocked = FreeEvidence(selection, now, unavailable);
            Check(Round1Availability.Calculate(selection, blocked, now).Slots.Count == 15,
                "Any unavailable first quarter excludes the entire first slot: " + unavailable);
            var taBlocked = new Round1ProviderEvidence(selection, Guid.NewGuid(), free.Room,
                new Round1ResourceEvidence(selection.Ta, selection.Correlation, now, now.AddMinutes(1),
                    free.Ta!.Start, free.Ta.End, true, blocked.Room!.Intervals));
            Check(Round1Availability.Calculate(selection, taBlocked, now).Slots.Count == 15,
                "The full-slot intersection independently checks TA " + unavailable);
        }
        var room = free.Room!;
        Round1ProviderEvidence WithRoom(Round1ResourceEvidence? replacement) =>
            new Round1ProviderEvidence(selection, Guid.NewGuid(), replacement, free.Ta);
        Round1ResourceEvidence CopyRoom(IEnumerable<Round1ProviderInterval> intervals,
            DateTime? observed = null, DateTime? expires = null, bool complete = true, Guid? correlation = null, Guid? id = null) =>
            new Round1ResourceEvidence(id ?? selection.Room, correlation ?? selection.Correlation,
                observed ?? now.AddSeconds(-1), expires ?? now.AddSeconds(90), room.Start, room.End, complete, intervals);
        foreach (var incomplete in new[] {
            WithRoom(null), WithRoom(CopyRoom(room.Intervals.Skip(1))),
            WithRoom(CopyRoom(room.Intervals.Concat(room.Intervals.Take(1)))),
            WithRoom(CopyRoom(room.Intervals, complete: false)) })
            RejectAvailability(() => Round1Availability.Calculate(selection, incomplete, now), "AVAILABILITY_EVIDENCE_INCOMPLETE");
        foreach (var stale in new[] {
            CopyRoom(room.Intervals, observed: now.AddSeconds(1)),
            CopyRoom(room.Intervals, observed: now.AddMinutes(-3)),
            CopyRoom(room.Intervals, expires: now),
            CopyRoom(room.Intervals, expires: now.AddMinutes(3)) })
            RejectAvailability(() => Round1Availability.Calculate(selection, WithRoom(stale), now), "AVAILABILITY_EVIDENCE_STALE");
        foreach (var mismatch in new[] {
            CopyRoom(room.Intervals, correlation: Guid.NewGuid()), CopyRoom(room.Intervals, id: Guid.NewGuid()) })
            RejectAvailability(() => Round1Availability.Calculate(selection, WithRoom(mismatch), now), "AVAILABILITY_EVIDENCE_MISMATCH");
        foreach (var other in new[] {
            new Round1Selection(Guid.NewGuid(), Candidate, selection.Room, selection.Ta, date, selection.Opens, selection.Closes, selection.Correlation),
            new Round1Selection(Actor, Guid.NewGuid(), selection.Room, selection.Ta, date, selection.Opens, selection.Closes, selection.Correlation),
            new Round1Selection(Actor, Candidate, selection.Room, selection.Ta, date.AddDays(1), selection.Opens, selection.Closes, selection.Correlation),
            new Round1Selection(Actor, Candidate, selection.Room, selection.Ta, date, selection.Opens, selection.Closes, Guid.NewGuid()) })
            RejectAvailability(() => Round1Availability.Calculate(selection,
                new Round1ProviderEvidence(other, Guid.NewGuid(), free.Room, free.Ta), now), "AVAILABILITY_EVIDENCE_MISMATCH");
        var lateNow = now.AddHours(1).AddMinutes(15);
        Check(Round1Availability.Calculate(selection, FreeEvidence(selection, lateNow), lateNow).Slots.Count == 15,
            "Past slot starts are excluded even when the remaining quarter is free");
        var overnight = new Round1Selection(Actor, Candidate, selection.Room, selection.Ta, date,
            TimeSpan.Zero, TimeSpan.FromHours(1), Guid.NewGuid());
        var beforeMidnight = now.AddHours(-9);
        Check(Round1Availability.Calculate(overnight, FreeEvidence(overnight, beforeMidnight), beforeMidnight)
            .Slots.All(slot => slot.StartUtc.Date == date.AddDays(-1)),
            "Local midnight windows normalize correctly across the UTC date boundary");
        var weekend = new Round1Selection(Actor, Candidate, selection.Room, selection.Ta, date.AddDays(5),
            selection.Opens, selection.Closes, Guid.NewGuid());
        Check(Round1Availability.Calculate(weekend, FreeEvidence(weekend, now), now).Slots.Count == 0,
            "Weekend responses never produce slots");
        var provider = new Round1TestProvider { Read = (requested, _) => FreeEvidence(requested, now.AddSeconds(2)) };
        var clocks = new Queue<DateTime>(new[] { now, now.AddSeconds(2) });
        var savedSlot = Round1Availability.ValidateSave(selection, result.Slots[0].StartUtc,
            result.Slots[0].EndUtc, provider, () => clocks.Dequeue());
        Check(provider.Reads == 1 && savedSlot.EvidenceCorrelation == selection.Correlation,
            "Save rechecks server provider and validates timestamps after the provider returns");
        provider.Read = (requested, clock) => FreeEvidence(requested, clock, Round1BusyState.Busy);
        RejectAvailability(() => Round1Availability.ValidateSave(selection, result.Slots[0].StartUtc,
            result.Slots[0].EndUtc, provider, () => now), "AVAILABILITY_SLOT_UNAVAILABLE");
        RejectAvailability(() => Round1Availability.ValidateSave(selection, result.Slots[0].StartUtc,
            result.Slots[0].EndUtc.AddMinutes(15), provider, () => now), "AVAILABILITY_SLOT_INVALID");

        Host SchedulingHost(string action)
        {
            var host = new Host(-1) { Status = ActionRequest.Waiting };
            SetScheduleAction(host, action, ActionRequest.Waiting);
            var nextDate = DateTime.UtcNow.Date.AddDays(2);
            host.Input["StartAt"] = nextDate.AddHours(2);
            host.Input["EndAt"] = nextDate.AddHours(action == Round1Availability.QueryAction ? 10 : 2).AddMinutes(
                action == Round1Availability.QueryAction ? 0 : 30);
            return host;
        }
        var capability = SchedulingHost(Round1Availability.CapabilitiesAction);
        new ApplyCandidateAction().Execute(capability);
        Check((string)capability.Output["ResultCode"] == "AvailabilityRead" &&
            (string)capability.Output["ScopedData"] ==
                "{\"schemaVersion\":1,\"providerOperational\":false,\"manualSchedulingOperational\":true}" &&
            capability.Updates == 0 && capability.Receipt == null,
            "Production capability is server-controlled, explicitly false and read-only");
        var query = SchedulingHost(Round1Availability.QueryAction);
        new ApplyCandidateAction().Execute(query);
        var blockedQuery = (string)query.Output["ScopedData"];
        Check((string)query.Output["ResultCode"] == "AvailabilityRead" &&
            blockedQuery.Contains("\"state\":\"Failed\"") &&
            blockedQuery.Contains("\"errorCode\":\"AVAILABILITY_PROVIDER_UNAVAILABLE\"") &&
            blockedQuery.Contains("\"queryId\":\"" + ((Guid)query.Input["CorrelationId"]).ToString("D") + "\"") &&
            query.ServiceOperations.All(operation => !operation.Contains("os_sr_avq")) &&
            query.Updates == 0 && query.Receipt == null,
            "Unverified availability returns Failed without reading or creating AVQ requests or Candidate writes");
        foreach (var promote in new[] { false, true })
        {
            var blockedSave = SchedulingHost("MarkRound1Scheduled");
            if (promote) blockedSave.ProposedRound1Schedule = ScheduleEntity(ActionRequest.ScheduleProposed);
            Reject(() => new ApplyCandidateAction().Execute(blockedSave), "AVAILABILITY_PROVIDER_UNAVAILABLE");
            Check(blockedSave.ScheduleCreates == 0 && blockedSave.ScheduleUpdates == 0 &&
                blockedSave.Updates == 0 && blockedSave.Histories == 0 && blockedSave.Receipt == null,
                "Unavailable provider blocks before any " + (promote ? "promotion" : "new schedule") + " write");
        }
        var denied = SchedulingHost(Round1Availability.CapabilitiesAction);
        denied.CandidateWriteAccess = false;
        Reject(() => new ApplyCandidateAction().Execute(denied), "NORMAL_SCHEDULE_WRITE_ACCESS_REQUIRED");
        var fabricated = SchedulingHost(Round1Availability.QueryAction);
        fabricated.Input["FreeBusy"] = "Free";
        Reject(() => new ApplyCandidateAction().Execute(fabricated), "UNEXPECTED_INPUT:SDK_ADAPTER:OTHER");
        var replay = SchedulingHost("MarkRound1Scheduled");
        var replayRequest = new ActionRequest(Actor,
            replay.Input.ToDictionary(pair => pair.Key, pair => (object?)pair.Value), DateTime.UtcNow);
        replay.Receipt = new Entity("os_sr_oprc", Guid.NewGuid())
        {
            ["os_sr_oprc_cand"] = new EntityReference("os_sr_cand", Candidate),
            ["os_sr_oprc_cact"] = "MarkRound1Scheduled", ["os_sr_oprc_ver"] = "1",
            ["os_sr_oprc_hash"] = replayRequest.Fingerprint,
            ["os_sr_oprc_prevstat"] = ActionRequest.Waiting, ["os_sr_oprc_newstat"] = ActionRequest.Scheduled
        };
        replay.Status = ActionRequest.Scheduled;
        new ApplyCandidateAction().Execute(replay);
        Check((string)replay.Output["ResultCode"] == "DuplicateReplay" && replay.ScheduleCreates == 0 &&
            replay.ScheduleUpdates == 0 && replay.Histories == 0,
            "Committed scheduling receipt replays without querying unavailable or expired provider evidence");

        foreach (var promote in new[] { false, true })
        {
            var manual = SchedulingHost(ActionRequest.ManualScheduleAction);
            manual.MainValues["OrganizationId"] = DevOrganization;
            manual.NormalCreatePolicyOrganizationId = DevOrganization;
            const string notes = "  Synthetic manual notes\r\n<literal text>  ";
            manual.Input["Notes"] = notes;
            var scheduleOwner = promote ? Guid.NewGuid() : Actor;
            if (promote)
            {
                manual.ProposedRound1Schedule = ScheduleEntity(ActionRequest.ScheduleProposed);
                manual.ProposedRound1Schedule["ownerid"] = new EntityReference("systemuser", scheduleOwner);
            }
            var previousId = manual.ProposedRound1Schedule?.Id;
            new ApplyCandidateAction().Execute(manual);
            Check(manual.Status == ActionRequest.Scheduled && manual.Histories == 1 &&
                manual.ScheduleCreates == (promote ? 0 : 1) && manual.ScheduleUpdates == (promote ? 1 : 0) &&
                manual.Round1Schedule!.GetAttributeValue<string>("os_sr_intv_nts") == notes &&
                (!promote || manual.Round1Schedule.Id == previousId) &&
                manual.Round1Schedule.GetAttributeValue<EntityReference>("ownerid")?.Id == scheduleOwner,
                "Explicit manual operation persists exact Notes, caller ownership and canonical " +
                (promote ? "proposed promotion" : "schedule creation"));
            Check(manual.CreatedHistory!.GetAttributeValue<string>("os_sr_csh_cact") == ActionRequest.ManualScheduleAction &&
                manual.CreatedHistory.GetAttributeValue<string>("os_sr_csh_rsn").Contains("availability not checked") &&
                manual.Receipt!.GetAttributeValue<string>("os_sr_oprc_cact") == ActionRequest.ManualScheduleAction,
                "Manual operation remains explicitly distinguishable in durable history and receipt");
            new ApplyCandidateAction().Execute(manual);
            Check((string)manual.Output["ResultCode"] == "DuplicateReplay" && manual.Histories == 1 &&
                manual.ScheduleCreates + manual.ScheduleUpdates == 1,
                "Manual replay does not duplicate a schedule, history or receipt");
            manual.Input["ActionType"] = "MarkRound1Scheduled";
            Reject(() => new ApplyCandidateAction().Execute(manual), "CORRELATION_CONFLICT");
        }
        foreach (var denial in new[] { "write", "read", "disabled", "organization", "scope", "ta", "room", "status", "time" })
        {
            var manual = SchedulingHost(ActionRequest.ManualScheduleAction);
            string error;
            switch (denial)
            {
                case "write": manual.CandidateWriteAccess = false; error = "NORMAL_SCHEDULE_WRITE_ACCESS_REQUIRED"; break;
                case "read": manual.CallerReadDeniedTables.Add("os_sr_cand"); error = "NORMAL_SCHEDULE_WRITE_ACCESS_REQUIRED"; break;
                case "disabled": manual.NormalCreatePolicyEnabled = false; error = "NORMAL_CREATE_DISABLED"; break;
                case "organization": manual.NormalCreatePolicyOrganizationId = Guid.NewGuid(); error = "NORMAL_CREATE_ORGANIZATION_REJECTED"; break;
                case "scope": manual.Input["SyntheticScopeId"] = Guid.NewGuid(); error = "MANUAL_SCHEDULE_NORMAL_CONTEXT_REQUIRED"; break;
                case "ta": manual.InactiveReferenceTable = "os_sr_ta"; error = "REFERENCE_NOT_AVAILABLE:InterviewerId"; break;
                case "room": manual.InactiveReferenceTable = "os_sr_loc"; error = "REFERENCE_NOT_AVAILABLE:LocationId"; break;
                case "status": manual.Status = ActionRequest.Answered; error = "STALE_EXPECTED_STATUS"; break;
                default: manual.Input["StartAt"] = DateTime.UtcNow.AddMinutes(-1); error = "INVALID_SCHEDULE_TIME"; break;
            }
            Reject(() => new ApplyCandidateAction().Execute(manual), error);
            Check(manual.ScheduleCreates == 0 && manual.ScheduleUpdates == 0 && manual.Updates == 0 &&
                manual.Histories == 0 && manual.Receipt == null, "Manual " + denial + " rejection occurs before writes");
        }
        foreach (var omit in new[] { false, true })
        {
            var manual = SchedulingHost(ActionRequest.ManualScheduleAction);
            manual.ProposedRound1Schedule = ScheduleEntity(ActionRequest.ScheduleProposed);
            manual.ProposedRound1Schedule["os_sr_intv_nts"] = "Existing synthetic notes";
            if (omit) manual.Input.Remove("Notes"); else manual.Input["Notes"] = " \r\n ";
            new ApplyCandidateAction().Execute(manual);
            Check(manual.Round1Schedule!.GetAttributeValue<string>("os_sr_intv_nts") ==
                (omit ? "Existing synthetic notes" : null),
                "Manual notes distinguish an omitted field from an explicitly blank value");
        }
    }
}
