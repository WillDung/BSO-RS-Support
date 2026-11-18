using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;

namespace os_sr_cact
{
    internal enum AsyncAvailabilityState
    {
        Pending,
        Ready,
        Failed,
        Expired
    }

    internal sealed class AsyncAvailabilityResponse
    {
        private AsyncAvailabilityResponse(AsyncAvailabilityState state, Round1Selection selection,
            Guid queryId, string? errorCode, Round1AvailabilityResult? result)
        {
            State = state;
            Selection = selection;
            QueryId = queryId;
            ErrorCode = errorCode;
            Result = result;
        }

        public AsyncAvailabilityState State { get; }
        public Round1Selection Selection { get; }
        public Guid QueryId { get; }
        public string? ErrorCode { get; }
        public Round1AvailabilityResult? Result { get; }

        public static AsyncAvailabilityResponse Pending(Round1Selection selection) =>
            new AsyncAvailabilityResponse(AsyncAvailabilityState.Pending, selection,
                selection.Correlation, null, null);

        public static AsyncAvailabilityResponse Ready(Round1Selection selection,
            Round1AvailabilityResult result) =>
            new AsyncAvailabilityResponse(AsyncAvailabilityState.Ready, selection,
                selection.Correlation, null, result);

        public static AsyncAvailabilityResponse Failed(Round1Selection selection, string errorCode) =>
            new AsyncAvailabilityResponse(AsyncAvailabilityState.Failed, selection,
                selection.Correlation, errorCode, null);

        public static AsyncAvailabilityResponse Expired(Round1Selection selection) =>
            new AsyncAvailabilityResponse(AsyncAvailabilityState.Expired, selection,
                selection.Correlation, "AVAILABILITY_EVIDENCE_STALE", null);

        public string ToJson()
        {
            if (Result != null)
                return Result.ToJson();
            var builder = new StringBuilder("{\"schemaVersion\":1,\"state\":\"")
                .Append(State.ToString()).Append("\",\"candidateId\":\"")
                .Append(Selection.Candidate.ToString("D")).Append("\",\"actorId\":\"")
                .Append(Selection.Actor.ToString("D")).Append("\",\"roomId\":\"")
                .Append(Selection.Room.ToString("D")).Append("\",\"taId\":\"")
                .Append(Selection.Ta.ToString("D")).Append("\",\"date\":\"")
                .Append(Selection.Date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture))
                .Append("\",\"correlationId\":\"").Append(QueryId.ToString("D"))
                .Append("\",\"queryId\":\"").Append(QueryId.ToString("D"))
                .Append("\",\"slots\":[]");
            if (ErrorCode != null)
                builder.Append(",\"errorCode\":\"").Append(ErrorCode).Append('"');
            return builder.Append('}').ToString();
        }
    }

    internal sealed class AsyncRound1AvailabilityProvider : IRound1AvailabilityProvider
    {
        private sealed class AvailableSlot
        {
            public AvailableSlot(DateTime startUtc, DateTime endUtc)
            {
                StartUtc = startUtc;
                EndUtc = endUtc;
            }

            public DateTime StartUtc { get; }
            public DateTime EndUtc { get; }
        }

        private const string QueryTable = "os_sr_avq";
        private const int Pending = 100000000;
        private const int Available = 100000001;
        private const int NoSlots = 100000002;
        private const int Failed = 100000003;
        private const int Onsite = 100000001;
        private const int MeetingMinutes = 30;
        private static readonly Regex SlotPattern = new Regex(
            "\\{\"startUtc\":\"(?<start>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\",\"endUtc\":\"(?<end>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\"\\}",
            RegexOptions.CultureInvariant);
        private static readonly ColumnSet QueryColumns = new ColumnSet(
            "ownerid", "createdby", "createdonbehalfby", "createdon", "modifiedby", "versionnumber",
            "os_sr_avq_corr", "os_sr_avq_ta", "os_sr_avq_loc", "os_sr_avq_mod",
            "os_sr_avq_strt", "os_sr_avq_end", "os_sr_avq_dur", "os_sr_avq_stat",
            "os_sr_avq_err", "os_sr_avq_rsn", "os_sr_avq_slts", "os_sr_avq_qat", "os_sr_avq_exp",
            "os_sr_avq_dead");
        private readonly IOrganizationService service;
        private readonly Guid actor;

        public AsyncRound1AvailabilityProvider(IOrganizationService service, Guid actor)
        {
            this.service = service ?? throw new ArgumentNullException(nameof(service));
            if (actor == Guid.Empty) throw new OperationError("INVALID_ACTOR");
            this.actor = actor;
        }

        public bool IsOperational => TrustedResultHandoffVerified();

        public AsyncAvailabilityResponse StartOrRead(Round1Selection selection, DateTime nowUtc)
        {
            if (selection == null || selection.Actor != actor || nowUtc.Kind != DateTimeKind.Utc)
                throw new OperationError("AVAILABILITY_REQUEST_INVALID");
            if (!IsOperational)
                return AsyncAvailabilityResponse.Failed(selection, "AVAILABILITY_PROVIDER_UNAVAILABLE");
            var row = Find(selection.Correlation);
            if (row == null)
            {
                var request = CreateRequest(selection);
                var createdId = service.Create(request);
                if (createdId != selection.Correlation)
                    throw new OperationError("AVAILABILITY_REQUEST_INVALID");
                return AsyncAvailabilityResponse.Pending(selection);
            }

            ValidateRequest(row, selection);
            var deadline = ReadUtc(row, "os_sr_avq_dead");
            if (nowUtc >= deadline) return AsyncAvailabilityResponse.Expired(selection);

            var status = row.GetAttributeValue<OptionSetValue>("os_sr_avq_stat")?.Value
                ?? throw new OperationError("AVAILABILITY_RESULT_INVALID");
            if (status == Pending) return AsyncAvailabilityResponse.Pending(selection);
            if (status == Failed)
            {
                var error = row.GetAttributeValue<string>("os_sr_avq_err");
                return AsyncAvailabilityResponse.Failed(selection, IsSafeError(error)
                    ? error! : "AVAILABILITY_PROVIDER_UNAVAILABLE");
            }
            if (status != Available && status != NoSlots)
                throw new OperationError("AVAILABILITY_RESULT_INVALID");

            var queriedAt = ReadUtc(row, "os_sr_avq_qat");
            var expiresAt = ReadUtc(row, "os_sr_avq_exp");
            if (queriedAt < ReadUtc(row, "createdon") || queriedAt > nowUtc ||
                expiresAt <= nowUtc || expiresAt <= queriedAt ||
                nowUtc - queriedAt > Round1Availability.MaximumEvidenceAge ||
                expiresAt - queriedAt > Round1Availability.MaximumEvidenceAge)
                return AsyncAvailabilityResponse.Expired(selection);

            var slots = ParseSlots(row.GetAttributeValue<string>("os_sr_avq_slts"), selection);
            if ((status == Available) != (slots.Count > 0))
                throw new OperationError("AVAILABILITY_RESULT_INVALID");
            if (!TrustedResultHandoffVerified())
                return AsyncAvailabilityResponse.Failed(selection, "AVAILABILITY_RESULT_UNTRUSTED");

            var evidence = CreateEvidence(selection, row.Id, queriedAt, expiresAt, slots);
            return AsyncAvailabilityResponse.Ready(selection,
                Round1Availability.Calculate(selection, evidence, nowUtc));
        }

        public Round1ProviderEvidence Query(Round1Selection selection, DateTime nowUtc)
        {
            if (!IsOperational)
                throw new OperationError("AVAILABILITY_PROVIDER_UNAVAILABLE");
            var row = Find(selection.Correlation);
            if (row == null)
                throw new OperationError("AVAILABILITY_EVIDENCE_INCOMPLETE");
            ValidateRequest(row, selection);
            var deadline = ReadUtc(row, "os_sr_avq_dead");
            var queriedAt = ReadUtc(row, "os_sr_avq_qat");
            var expiresAt = ReadUtc(row, "os_sr_avq_exp");
            if (nowUtc >= deadline || queriedAt < ReadUtc(row, "createdon") ||
                queriedAt > nowUtc || expiresAt <= nowUtc || expiresAt <= queriedAt ||
                nowUtc - queriedAt > Round1Availability.MaximumEvidenceAge ||
                expiresAt - queriedAt > Round1Availability.MaximumEvidenceAge)
                throw new OperationError("AVAILABILITY_EVIDENCE_STALE");
            if (row.GetAttributeValue<OptionSetValue>("os_sr_avq_stat")?.Value != Available)
                throw new OperationError("AVAILABILITY_SLOT_UNAVAILABLE");
            return CreateEvidence(selection, row.Id, queriedAt, expiresAt,
                ParseSlots(row.GetAttributeValue<string>("os_sr_avq_slts"), selection));
        }

        private Entity? Find(Guid queryId)
        {
            var query = new QueryExpression(QueryTable)
            {
                ColumnSet = QueryColumns,
                TopCount = 2
            };
            query.Criteria.AddCondition("os_sr_avqid", ConditionOperator.Equal, queryId);
            var rows = service.RetrieveMultiple(query).Entities;
            if (rows.Count > 1) throw new OperationError("AVAILABILITY_RESULT_INVALID");
            return rows.SingleOrDefault();
        }

        private static Entity CreateRequest(Round1Selection selection) =>
            new Entity(QueryTable, selection.Correlation)
            {
                ["os_sr_avq_corr"] = selection.Correlation.ToString("D"),
                ["os_sr_avq_ta"] = new EntityReference("os_sr_ta", selection.Ta),
                ["os_sr_avq_loc"] = new EntityReference("os_sr_loc", selection.Room),
                ["os_sr_avq_mod"] = new OptionSetValue(Onsite),
                ["os_sr_avq_strt"] = ToUtc(selection.Date.Add(selection.Opens)),
                ["os_sr_avq_end"] = ToUtc(selection.Date.Add(selection.Closes)),
                ["os_sr_avq_dur"] = MeetingMinutes
            };

        private void ValidateRequest(Entity row, Round1Selection selection)
        {
            if (row.LogicalName != QueryTable || row.Id != selection.Correlation ||
                row.GetAttributeValue<string>("os_sr_avq_corr") != selection.Correlation.ToString("D") ||
                !OwnedBy(row, "ownerid", actor) || !OwnedBy(row, "createdby", actor) ||
                row.GetAttributeValue<EntityReference>("createdonbehalfby") != null ||
                row.GetAttributeValue<EntityReference>("os_sr_avq_ta")?.Id != selection.Ta ||
                row.GetAttributeValue<EntityReference>("os_sr_avq_loc")?.Id != selection.Room ||
                row.GetAttributeValue<OptionSetValue>("os_sr_avq_mod")?.Value != Onsite ||
                ReadUtc(row, "os_sr_avq_strt") != ToUtc(selection.Date.Add(selection.Opens)) ||
                ReadUtc(row, "os_sr_avq_end") != ToUtc(selection.Date.Add(selection.Closes)) ||
                row.GetAttributeValue<int?>("os_sr_avq_dur") != MeetingMinutes)
                throw new OperationError("AVAILABILITY_EVIDENCE_MISMATCH");
        }

        private static Round1ProviderEvidence CreateEvidence(Round1Selection selection, Guid evidenceId,
            DateTime observedAt, DateTime expiresAt, IReadOnlyList<AvailableSlot> availableSlots)
        {
            var workStart = ToUtc(selection.Date.Add(selection.Opens));
            var workEnd = ToUtc(selection.Date.Add(selection.Closes));
            var slots = new HashSet<DateTime>(availableSlots.Select(slot => slot.StartUtc));
            var intervals = new List<Round1ProviderInterval>();
            for (var start = workStart; start < workEnd; start = start.AddMinutes(MeetingMinutes))
            {
                var end = start.AddMinutes(MeetingMinutes);
                var state = slots.Contains(start) ? Round1BusyState.Free : Round1BusyState.Unknown;
                intervals.Add(new Round1ProviderInterval(new DateTimeOffset(start),
                    new DateTimeOffset(end), state));
            }
            Round1ResourceEvidence Resource(Guid id) =>
                new Round1ResourceEvidence(id, selection.Correlation,
                    new DateTimeOffset(observedAt), new DateTimeOffset(expiresAt),
                    workStart, workEnd, true, intervals);
            return new Round1ProviderEvidence(selection, evidenceId,
                Resource(selection.Room), Resource(selection.Ta));
        }

        private static IReadOnlyList<AvailableSlot> ParseSlots(string? json, Round1Selection selection)
        {
            if (json == null || json.Length == 0 || json.Length > 32768)
                throw new OperationError("AVAILABILITY_RESULT_INVALID");
            if (json == "[]") return Array.Empty<AvailableSlot>();
            var matches = SlotPattern.Matches(json);
            if (matches.Count == 0) throw new OperationError("AVAILABILITY_RESULT_INVALID");
            var slots = new List<AvailableSlot>(matches.Count);
            var builder = new StringBuilder("[");
            foreach (Match match in matches)
            {
                if (builder.Length > 1) builder.Append(',');
                if (!DateTime.TryParseExact(match.Groups["start"].Value,
                        "yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var start) ||
                    !DateTime.TryParseExact(match.Groups["end"].Value,
                        "yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var end))
                    throw new OperationError("AVAILABILITY_RESULT_INVALID");
                start = DateTime.SpecifyKind(start, DateTimeKind.Utc);
                end = DateTime.SpecifyKind(end, DateTimeKind.Utc);
                if (end - start != TimeSpan.FromMinutes(MeetingMinutes) ||
                    start < ToUtc(selection.Date.Add(selection.Opens)) ||
                    end > ToUtc(selection.Date.Add(selection.Closes)) ||
                    start.Ticks % TimeSpan.FromMinutes(MeetingMinutes).Ticks != 0 ||
                    slots.Count > 0 && start <= slots[slots.Count - 1].StartUtc)
                    throw new OperationError("AVAILABILITY_RESULT_INVALID");
                slots.Add(new AvailableSlot(start, end));
                builder.Append("{\"startUtc\":\"").Append(match.Groups["start"].Value)
                    .Append("\",\"endUtc\":\"").Append(match.Groups["end"].Value).Append("\"}");
            }
            builder.Append(']');
            if (!string.Equals(builder.ToString(), json, StringComparison.Ordinal))
                throw new OperationError("AVAILABILITY_RESULT_INVALID");
            return slots;
        }

        private static DateTime ReadUtc(Entity row, string name)
        {
            if (!row.Attributes.TryGetValue(name, out var value) ||
                !(value is DateTime time) || time.Kind != DateTimeKind.Utc)
                throw new OperationError("AVAILABILITY_RESULT_INVALID");
            return time;
        }

        private static bool OwnedBy(Entity row, string name, Guid actor)
        {
            var owner = row.GetAttributeValue<EntityReference>(name);
            return owner != null && owner.LogicalName == "systemuser" && owner.Id == actor;
        }

        private static bool IsSafeError(string? value) =>
            value != null && value.Length > 0 && value.Length <= 40 &&
            value.All(character => character >= 'A' && character <= 'Z' ||
                character >= '0' && character <= '9' || character == '_');

        private static bool TrustedResultHandoffVerified() => false;

        private static DateTime ToUtc(DateTime local) =>
            TimeZoneInfo.ConvertTimeToUtc(local, TimeZoneInfo.FindSystemTimeZoneById(Round1Availability.TimeZoneId));
    }
}
