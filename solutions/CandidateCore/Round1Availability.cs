using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace os_sr_cact
{
    public enum Round1BusyState { Unknown, Free, Busy, Tentative, OutOfOffice }

    public sealed class Round1Selection
    {
        public Round1Selection(Guid actor, Guid candidate, Guid room, Guid ta, DateTime date,
            TimeSpan opens, TimeSpan closes, Guid correlation)
        {
            if (new[] { actor, candidate, room, ta, correlation }.Any(id => id == Guid.Empty) ||
                date.Kind != DateTimeKind.Unspecified || date.TimeOfDay != TimeSpan.Zero ||
                date.Year >= 9999 || opens < TimeSpan.Zero || closes > TimeSpan.FromDays(1) || opens >= closes)
                throw new OperationError("AVAILABILITY_REQUEST_INVALID");
            Actor = actor; Candidate = candidate; Room = room; Ta = ta; Date = date;
            Opens = opens; Closes = closes; Correlation = correlation;
        }
        public Guid Actor { get; }
        public Guid Candidate { get; }
        public Guid Room { get; }
        public Guid Ta { get; }
        public DateTime Date { get; }
        public TimeSpan Opens { get; }
        public TimeSpan Closes { get; }
        public Guid Correlation { get; }
        public bool Matches(Round1Selection other) =>
            other != null && Actor == other.Actor && Candidate == other.Candidate && Room == other.Room &&
            Ta == other.Ta && Date == other.Date && Opens == other.Opens && Closes == other.Closes &&
            Correlation == other.Correlation;
    }

    public sealed class Round1ProviderInterval
    {
        public Round1ProviderInterval(DateTimeOffset start, DateTimeOffset end, Round1BusyState state)
        { Start = start.ToUniversalTime(); End = end.ToUniversalTime(); State = state; }
        public DateTimeOffset Start { get; }
        public DateTimeOffset End { get; }
        public Round1BusyState State { get; }
    }

    public sealed class Round1ResourceEvidence
    {
        public Round1ResourceEvidence(Guid resource, Guid correlation, DateTimeOffset observedAt,
            DateTimeOffset expiresAt, DateTimeOffset start, DateTimeOffset end, bool complete,
            IEnumerable<Round1ProviderInterval> intervals)
        {
            Resource = resource; Correlation = correlation;
            ObservedAt = observedAt.ToUniversalTime(); ExpiresAt = expiresAt.ToUniversalTime();
            Start = start.ToUniversalTime(); End = end.ToUniversalTime(); Complete = complete;
            Intervals = Array.AsReadOnly((intervals ??
                throw new OperationError("AVAILABILITY_EVIDENCE_INCOMPLETE")).Take(2049).ToArray());
        }
        public Guid Resource { get; }
        public Guid Correlation { get; }
        public DateTimeOffset ObservedAt { get; }
        public DateTimeOffset ExpiresAt { get; }
        public DateTimeOffset Start { get; }
        public DateTimeOffset End { get; }
        public bool Complete { get; }
        public IReadOnlyList<Round1ProviderInterval> Intervals { get; }
    }

    public sealed class Round1ProviderEvidence
    {
        public Round1ProviderEvidence(Round1Selection selection, Guid evidenceId,
            Round1ResourceEvidence? room, Round1ResourceEvidence? ta)
        { Selection = selection; EvidenceId = evidenceId; Room = room; Ta = ta; }
        public Round1Selection Selection { get; }
        public Guid EvidenceId { get; }
        public Round1ResourceEvidence? Room { get; }
        public Round1ResourceEvidence? Ta { get; }
    }

    public sealed class Round1Slot
    {
        internal Round1Slot(DateTime start, DateTime end, Guid correlation)
        { StartUtc = start; EndUtc = end; EvidenceCorrelation = correlation; }
        public DateTime StartUtc { get; }
        public DateTime EndUtc { get; }
        public Guid EvidenceCorrelation { get; }
    }

    public sealed class Round1AvailabilityResult
    {
        internal Round1AvailabilityResult(Round1Selection selection, Guid evidenceId, DateTime observed,
            DateTime expires, IEnumerable<Round1Slot> slots)
        {
            Selection = selection; EvidenceId = evidenceId; ObservedAtUtc = observed; ExpiresAtUtc = expires;
            Slots = Array.AsReadOnly(slots.ToArray());
        }
        public Round1Selection Selection { get; }
        public Guid EvidenceId { get; }
        public DateTime ObservedAtUtc { get; }
        public DateTime ExpiresAtUtc { get; }
        public IReadOnlyList<Round1Slot> Slots { get; }

        public string ToJson()
        {
            var result = new StringBuilder("{\"schemaVersion\":1,\"state\":\"Ready\",\"queryId\":\"")
                .Append(Selection.Correlation.ToString("D")).Append("\",\"candidateId\":\"")
                .Append(Selection.Candidate.ToString("D")).Append("\",\"actorId\":\"")
                .Append(Selection.Actor.ToString("D")).Append("\",\"roomId\":\"")
                .Append(Selection.Room.ToString("D")).Append("\",\"taId\":\"")
                .Append(Selection.Ta.ToString("D")).Append("\",\"date\":\"")
                .Append(Selection.Date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture))
                .Append("\",\"correlationId\":\"").Append(Selection.Correlation.ToString("D"))
                .Append("\",\"evidenceId\":\"").Append(EvidenceId.ToString("D"))
                .Append("\",\"observedAtUtc\":\"").Append(Stamp(ObservedAtUtc))
                .Append("\",\"expiresAtUtc\":\"").Append(Stamp(ExpiresAtUtc)).Append("\",\"slots\":[");
            foreach (var slot in Slots)
            {
                if (result[result.Length - 1] != '[') result.Append(',');
                result.Append("{\"startUtc\":\"").Append(Stamp(slot.StartUtc))
                    .Append("\",\"endUtc\":\"").Append(Stamp(slot.EndUtc))
                    .Append("\",\"evidenceCorrelationId\":\"").Append(slot.EvidenceCorrelation.ToString("D"))
                    .Append("\"}");
            }
            return result.Append("]}").ToString();
        }
        private static string Stamp(DateTime value) =>
            value.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
    }

    public interface IRound1AvailabilityProvider
    {
        bool IsOperational { get; }
        Round1ProviderEvidence Query(Round1Selection selection, DateTime nowUtc);
    }

    internal sealed class UnavailableRound1AvailabilityProvider : IRound1AvailabilityProvider
    {
        public bool IsOperational => false;
        public Round1ProviderEvidence Query(Round1Selection selection, DateTime nowUtc) =>
            throw new OperationError("AVAILABILITY_PROVIDER_UNAVAILABLE");
    }

    public static class Round1Availability
    {
        public const string CapabilitiesAction = "GetRound1SchedulingCapabilities";
        public const string QueryAction = "GetRound1Availability";
        public const string TimeZoneId = "SE Asia Standard Time";
        public static readonly TimeSpan MaximumEvidenceAge = TimeSpan.FromMinutes(2);
        internal static IRound1AvailabilityProvider Provider { get; } = new UnavailableRound1AvailabilityProvider();

        public static bool IsReadAction(string? action) =>
            action == CapabilitiesAction || action == QueryAction;

        internal static DateTime LocalDate(DateTime utc) => TimeZoneInfo.ConvertTimeFromUtc(utc, Zone()).Date;

        private static TimeZoneInfo Zone()
        {
            try { return TimeZoneInfo.FindSystemTimeZoneById(TimeZoneId); }
            catch (TimeZoneNotFoundException) { throw new OperationError("AVAILABILITY_TIME_ZONE_UNAVAILABLE"); }
            catch (InvalidTimeZoneException) { throw new OperationError("AVAILABILITY_TIME_ZONE_UNAVAILABLE"); }
        }

        public static Round1Selection FromRequest(ActionRequest request)
        {
            var start = (DateTime)request.Values["StartAt"]!;
            var end = (DateTime)request.Values["EndAt"]!;
            if (start.Kind != DateTimeKind.Utc || end.Kind != DateTimeKind.Utc)
                throw new OperationError("AVAILABILITY_REQUEST_INVALID");
            var date = TimeZoneInfo.ConvertTimeFromUtc(start, Zone()).Date;
            var selection = new Round1Selection(request.Actor, request.CandidateId!.Value,
                (Guid)request.Values["LocationId"]!, (Guid)request.Values["InterviewerId"]!,
                date, TimeSpan.FromHours(9), TimeSpan.FromHours(17), request.Correlation);
            if (request.Action == QueryAction &&
                (start != Utc(date.Add(selection.Opens)) || end != Utc(date.Add(selection.Closes))))
                throw new OperationError("AVAILABILITY_REQUEST_INVALID");
            return selection;
        }

        public static Round1AvailabilityResult Calculate(Round1Selection selection,
            Round1ProviderEvidence evidence, DateTime nowUtc)
        {
            if (nowUtc.Kind != DateTimeKind.Utc || selection == null)
                throw new OperationError("AVAILABILITY_REQUEST_INVALID");
            var today = TimeZoneInfo.ConvertTimeFromUtc(nowUtc, Zone()).Date;
            if (selection.Date < today || selection.Date > today.AddDays(61))
                throw new OperationError("AVAILABILITY_DATE_OUT_OF_RANGE");
            if (evidence == null || evidence.EvidenceId == Guid.Empty || !selection.Matches(evidence.Selection))
                throw new OperationError("AVAILABILITY_EVIDENCE_MISMATCH");
            var start = Utc(selection.Date.Add(selection.Opens));
            var end = Utc(selection.Date.Add(selection.Closes));
            var room = ValidateResource(evidence.Room, selection.Room, selection.Correlation, start, end, nowUtc);
            var ta = ValidateResource(evidence.Ta, selection.Ta, selection.Correlation, start, end, nowUtc);
            var slots = new List<Round1Slot>();
            if (selection.Date.DayOfWeek != DayOfWeek.Saturday && selection.Date.DayOfWeek != DayOfWeek.Sunday)
            {
                var step = TimeSpan.FromMinutes(30).Ticks;
                var first = ((selection.Opens.Ticks + step - 1) / step) * step;
                for (var ticks = first; ticks + step <= selection.Closes.Ticks; ticks += step)
                {
                    var slotStart = Utc(selection.Date.AddTicks(ticks));
                    var slotEnd = Utc(selection.Date.AddTicks(ticks + step));
                    if (slotStart <= nowUtc || !FreeForWholeSlot(room, slotStart, slotEnd) ||
                        !FreeForWholeSlot(ta, slotStart, slotEnd)) continue;
                    slots.Add(new Round1Slot(slotStart, slotEnd, selection.Correlation));
                }
            }
            return new Round1AvailabilityResult(selection, evidence.EvidenceId,
                (evidence.Room!.ObservedAt > evidence.Ta!.ObservedAt ? evidence.Room.ObservedAt : evidence.Ta.ObservedAt).UtcDateTime,
                (evidence.Room.ExpiresAt < evidence.Ta.ExpiresAt ? evidence.Room.ExpiresAt : evidence.Ta.ExpiresAt).UtcDateTime, slots);
        }

        public static Round1Slot ValidateSave(Round1Selection selection, DateTime startUtc,
            DateTime endUtc, IRound1AvailabilityProvider provider, Func<DateTime> utcNow)
        {
            var nowUtc = utcNow();
            if (startUtc.Kind != DateTimeKind.Utc || endUtc.Kind != DateTimeKind.Utc ||
                endUtc - startUtc != TimeSpan.FromMinutes(30) || startUtc <= nowUtc)
                throw new OperationError("AVAILABILITY_SLOT_INVALID");
            if (!provider.IsOperational) throw new OperationError("AVAILABILITY_PROVIDER_UNAVAILABLE");
            // Evidence is fetched server-side for this save, never supplied by a browser flag or JSON body.
            var evidence = provider.Query(selection, nowUtc);
            var result = Calculate(selection, evidence, utcNow());
            return result.Slots.SingleOrDefault(slot => slot.StartUtc == startUtc && slot.EndUtc == endUtc)
                ?? throw new OperationError("AVAILABILITY_SLOT_UNAVAILABLE");
        }

        private static DateTime Utc(DateTime local) => TimeZoneInfo.ConvertTimeToUtc(local, Zone());

        private static Round1ProviderInterval[] ValidateResource(Round1ResourceEvidence? evidence,
            Guid resource, Guid correlation, DateTime start, DateTime end, DateTime now)
        {
            if (evidence == null || !evidence.Complete || evidence.Intervals.Count == 0 ||
                evidence.Intervals.Count > 2048)
                throw new OperationError("AVAILABILITY_EVIDENCE_INCOMPLETE");
            if (evidence.Resource != resource || evidence.Correlation != correlation ||
                evidence.Start.UtcDateTime != start || evidence.End.UtcDateTime != end)
                throw new OperationError("AVAILABILITY_EVIDENCE_MISMATCH");
            if (evidence.ObservedAt.UtcDateTime > now || evidence.ExpiresAt.UtcDateTime <= now ||
                evidence.ExpiresAt <= evidence.ObservedAt || now - evidence.ObservedAt.UtcDateTime > MaximumEvidenceAge ||
                evidence.ExpiresAt - evidence.ObservedAt > MaximumEvidenceAge)
                throw new OperationError("AVAILABILITY_EVIDENCE_STALE");
            if (evidence.Intervals.Any(interval => interval == null))
                throw new OperationError("AVAILABILITY_EVIDENCE_INCOMPLETE");
            var ordered = evidence.Intervals.OrderBy(interval => interval.Start).ToArray();
            var cursor = new DateTimeOffset(start);
            foreach (var interval in ordered)
            {
                if (interval.Start != cursor || interval.End <= interval.Start || interval.End.UtcDateTime > end)
                    throw new OperationError("AVAILABILITY_EVIDENCE_INCOMPLETE");
                cursor = interval.End;
            }
            if (cursor.UtcDateTime != end) throw new OperationError("AVAILABILITY_EVIDENCE_INCOMPLETE");
            return ordered;
        }

        private static bool FreeForWholeSlot(IEnumerable<Round1ProviderInterval> intervals, DateTime start, DateTime end) =>
            intervals.Where(interval => interval.Start.UtcDateTime < end && interval.End.UtcDateTime > start)
                .All(interval => interval.State == Round1BusyState.Free);
    }
}
