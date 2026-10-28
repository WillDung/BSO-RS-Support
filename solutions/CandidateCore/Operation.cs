using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace os_sr_cact
{
    public sealed class OperationError : Exception
    {
        public OperationError(string code) : base(code) { }
        public OperationError(string code, Exception innerException) : base(code, innerException) { }
    }

    public sealed class ActionRequest
    {
        public const int NeedCall = 100010000;
        public const int Answered = 100010001;
        public const int Waiting = 100010002;
        public const int Scheduled = 100010003;
        public const int Passed = 100010004;
        public const int Failed = 100010005;
        public const int Round1 = 100000000;
        public const int ResultPending = 100000000;
        public const int ResultPass = 100000001;
        public const int ResultFail = 100000002;
        public const int ScheduleProposed = 100000000;
        public const int ScheduleActive = 100000001;
        public const int ScheduleCancelled = 100000002;
        public const int ScheduleSuperseded = 100000003;
        public Guid Actor { get; }
        public Guid Correlation { get; }
        public Guid? CandidateId { get; }
        public string Action { get; }
        public int? ExpectedStatus { get; }
        public IReadOnlyDictionary<string, object?> Values { get; }
        public string Fingerprint { get; }

        private static readonly string[] DeclaredInputNames =
        {
            "ActionType", "CorrelationId", "CandidateId", "ExpectedStatus", "CandidateName",
            "CandidateEmail", "CandidatePhone", "PositionId", "CandidateSourceId", "CallOutcome",
            "ContactedAt", "Notes", "Reason", "InterviewerId", "LocationId", "StartAt", "EndAt", "ResultNotes"
        };

        private static readonly HashSet<string> DeclaredInputNameSet =
            new HashSet<string>(DeclaredInputNames, StringComparer.Ordinal);

        public static bool IsSupportedAction(string action) =>
            new[] { "CreateCandidate", "UpdateCandidate", "RecordCall", "ProceedToScheduling",
                "MarkRound1Scheduled", "RecordPass", "RecordFail", "RequestReschedule",
                "CancelRound1" }.Contains(action);

        public static IEnumerable<string> ApplicableInputNames(string action)
        {
            var common = new[] { "ActionType", "CorrelationId" };
            if (action == "CreateCandidate")
                return common.Concat(new[] { "CandidateName", "CandidateEmail", "CandidatePhone", "PositionId", "CandidateSourceId" });
            if (action == "UpdateCandidate")
                return common.Concat(new[] { "CandidateId", "ExpectedStatus", "CandidateName", "CandidateEmail",
                    "CandidatePhone", "PositionId", "CandidateSourceId" });
            if (action == "RecordCall")
                return common.Concat(new[] { "CandidateId", "ExpectedStatus", "CallOutcome", "ContactedAt", "Notes" });
            if (action == "MarkRound1Scheduled" || action == "RequestReschedule")
                return common.Concat(new[] { "CandidateId", "ExpectedStatus", "InterviewerId", "LocationId",
                    "StartAt", "EndAt", "Notes" }).Concat(action == "RequestReschedule" ? new[] { "Reason" } : Array.Empty<string>());
            if (action == "CancelRound1")
                return common.Concat(new[] { "CandidateId", "ExpectedStatus", "Reason" });
            if (action == "RecordPass" || action == "RecordFail")
                return common.Concat(new[] { "CandidateId", "ExpectedStatus", "ResultNotes" });
            if (action == "ProceedToScheduling" || action == "MarkRound1Scheduled" ||
                action == "RecordPass" || action == "RecordFail")
                return common.Concat(new[] { "CandidateId", "ExpectedStatus" });
            return common;
        }

        public static bool IsDeclaredInputName(string name) => DeclaredInputNameSet.Contains(name);

        public ActionRequest(Guid actor, IDictionary<string, object?> input, DateTime utcNow)
        {
            Actor = actor;
            if (actor == Guid.Empty) throw new OperationError("INVALID_ACTOR");
            Action = Required<string>(input, "ActionType");
            if (!IsSupportedAction(Action))
                throw new OperationError("INVALID_ACTION");
            Correlation = Required<Guid>(input, "CorrelationId");
            if (Correlation == Guid.Empty) throw new OperationError("INVALID_CORRELATION");
            CandidateId = input.TryGetValue("CandidateId", out var target) && target is Guid id && id != Guid.Empty ? id : (Guid?)null;
            if (Action != "CreateCandidate" && !CandidateId.HasValue) throw new OperationError("INVALID_CANDIDATE");
            if (Action == "CreateCandidate" && input.TryGetValue("CandidateId", out var createTarget))
            {
                if (createTarget is Guid createId)
                {
                    if (createId != Guid.Empty) throw new OperationError("UNEXPECTED_INPUT:ACTION_REQUEST:CandidateId");
                }
                else if (createTarget != null)
                {
                    throw new OperationError("INVALID_CANDIDATEID");
                }
            }
            ExpectedStatus = null;
            if (Action != "CreateCandidate")
            {
                var hasExpectedStatus = input.TryGetValue("ExpectedStatus", out var status);
                ExpectedStatus = hasExpectedStatus && status is int state ? state : (int?)null;
                if (Action != "UpdateCandidate" && !ExpectedStatus.HasValue)
                    throw new OperationError("EXPECTED_STATUS_REQUIRED");
                if (hasExpectedStatus && (!ExpectedStatus.HasValue || ExpectedStatus < NeedCall || ExpectedStatus > Failed))
                    throw new OperationError("INVALID_EXPECTED_STATUS");
            }
            var values = new SortedDictionary<string, object?>(StringComparer.Ordinal);
            var profile = new[] { "CandidateName", "CandidateEmail", "CandidatePhone", "PositionId", "CandidateSourceId" };
            var optionalGuidProfile = new[] { "PositionId", "CandidateSourceId" };
            var allowed = new HashSet<string>(ApplicableInputNames(Action), StringComparer.Ordinal);
            foreach (var pair in input)
            {
                if (Action == "CreateCandidate" && (pair.Key == "ExpectedStatus" || pair.Key == "CandidateId"))
                    continue;
                if (!allowed.Contains(pair.Key))
                    throw new OperationError("UNEXPECTED_INPUT:ACTION_REQUEST:" +
                        (IsDeclaredInputName(pair.Key) ? pair.Key : "OTHER"));
                object? value = pair.Value;
                if (profile.Contains(pair.Key) || pair.Key == "Notes" || pair.Key == "Reason" ||
                    pair.Key == "ResultNotes")
                {
                    if (optionalGuidProfile.Contains(pair.Key))
                    {
                        if (!NormalizeOptionalGuid(Action, pair.Key, value, out value)) continue;
                    }
                    else
                    {
                        if (value != null && !(value is string)) throw new OperationError("INVALID_TEXT");
                        value = (value as string)?.Trim();
                        int length = pair.Key == "Notes" ? (Action == "RecordCall" ? 4000 : 1000) :
                            pair.Key == "Reason" || pair.Key == "ResultNotes" ? 1000 :
                            pair.Key == "CandidateName" ? 200 : pair.Key == "CandidateEmail" ? 254 : 50;
                        if (value is string text && text.Length > length) throw new OperationError("TEXT_TOO_LONG");
                        if (pair.Key == "CandidateName" || pair.Key == "CandidateEmail" || pair.Key == "Reason")
                        {
                            if (string.IsNullOrWhiteSpace(value as string)) throw new OperationError("REQUIRED_TEXT");
                        }
                        if (pair.Key == "CandidateEmail" && value is string email &&
                            (email.IndexOf('@') <= 0 || email.EndsWith("@", StringComparison.Ordinal) ||
                             email.Any(char.IsWhiteSpace))) throw new OperationError("INVALID_EMAIL");
                    }
                }
                values.Add(pair.Key, value);
            }
            if (Action == "CreateCandidate" && (!values.ContainsKey("CandidateName") || !values.ContainsKey("CandidateEmail")))
                throw new OperationError("CONTACT_REQUIRED");
            if (Action == "UpdateCandidate" && !profile.Any(values.ContainsKey)) throw new OperationError("EMPTY_UPDATE");
            if (Action == "RecordCall")
            {
                int outcome = Required<int>(values, "CallOutcome");
                if (outcome < NeedCall || outcome > Waiting) throw new OperationError("INVALID_OUTCOME");
                var time = Required<DateTime>(values, "ContactedAt");
                if (time.Kind != DateTimeKind.Utc || time > utcNow) throw new OperationError("INVALID_CONTACT_TIME");
            }
            if (Action == "RequestReschedule" || Action == "CancelRound1")
            {
                if (!values.ContainsKey("Reason")) throw new OperationError("REASON_REQUIRED");
            }
            if (Action == "MarkRound1Scheduled" || Action == "RequestReschedule")
            {
                var interviewer = Required<Guid>(values, "InterviewerId");
                var location = Required<Guid>(values, "LocationId");
                var start = Required<DateTime>(values, "StartAt");
                var end = Required<DateTime>(values, "EndAt");
                if (interviewer == Guid.Empty || location == Guid.Empty)
                    throw new OperationError("INVALID_SCHEDULE_REFERENCE");
                if (start.Kind != DateTimeKind.Utc || end.Kind != DateTimeKind.Utc ||
                    start <= utcNow || end <= start || start.Date != end.Date)
                    throw new OperationError("INVALID_SCHEDULE_TIME");
            }
            Values = values;
            // Length prefixes distinguish omitted, null, empty, delimiters and different typed values.
            var canonical = new StringBuilder("os_sr_cact:1");
            Append(canonical, "Actor", actor.ToString("D"));
            foreach (var pair in values)
                Append(canonical, pair.Key, CanonicalValue(pair.Value));
            using (var hash = SHA256.Create())
                Fingerprint = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(canonical.ToString()))).Replace("-", "").ToLowerInvariant();
        }

        private static string CanonicalValue(object? value)
        {
            if (value == null) return "null";
            if (value is Guid guid) return "g:" + guid.ToString("D").ToLowerInvariant();
            if (value is int integer) return "i:" + integer.ToString(CultureInfo.InvariantCulture);
            if (value is DateTime date) return "d:" + date.ToString("O", CultureInfo.InvariantCulture);
            if (value is string text) return "s:" + text;
            throw new OperationError("INVALID_INPUT_TYPE");
        }

        private static void Append(StringBuilder builder, string key, string value)
        {
            builder.Append('|').Append(key.Length).Append(':').Append(key)
                .Append('|').Append(value.Length).Append(':').Append(value);
        }

        public static T Required<T>(IDictionary<string, object?> input, string name)
        {
            if (!input.TryGetValue(name, out var value) || !(value is T typed)) throw new OperationError("INVALID_" + name.ToUpperInvariant());
            return typed;
        }

        private static bool NormalizeOptionalGuid(string action, string name, object? value, out object? normalized)
        {
            normalized = value;
            if (value == null)
                return action != "CreateCandidate";
            if (!(value is Guid id))
                throw new OperationError("INVALID_GUID_PARAMETER:" + name);
            if (id != Guid.Empty)
            {
                normalized = id;
                return true;
            }
            if (action == "CreateCandidate")
            {
                normalized = null;
                return false;
            }
            throw new OperationError("INVALID_GUID_PARAMETER:" + name);
        }
    }

    public sealed class CandidateState
    {
        public Guid Id { get; set; }
        public int Status { get; set; }
        public string RowVersion { get; set; } = "";
    }

    public sealed class InterviewScheduleState
    {
        public Guid Id { get; set; }
        public Guid CandidateId { get; set; }
        public Guid InterviewerId { get; set; }
        public Guid LocationId { get; set; }
        public DateTime StartAt { get; set; }
        public DateTime EndAt { get; set; }
        public string Notes { get; set; } = "";
        public string Reason { get; set; } = "";
        public DateTime? ChangedAt { get; set; }
        public int? Status { get; set; }
        public int? Result { get; set; }
        public string RowVersion { get; set; } = "";
    }

    public sealed class ActionResult
    {
        public bool Replay { get; set; }
        public Guid CandidateId { get; set; }
        public int? Previous { get; set; }
        public int Current { get; set; }
        public Guid? CallId { get; set; }
        public Guid? HistoryId { get; set; }
    }

    public sealed class Receipt
    {
        public Guid Actor { get; set; }
        public string Action { get; set; } = "";
        public string Fingerprint { get; set; } = "";
        public string Version { get; set; } = "";
        public ActionResult Result { get; set; } = new ActionResult();
    }

    public interface IOperationStore
    {
        void RequireTransaction();
        Receipt? FindReceipt(Guid correlation);
        CandidateState GetCandidate(Guid id);
        Guid CreateCandidate(ActionRequest request);
        void UpdateCandidate(ActionRequest request, CandidateState candidate, int status);
        Guid CreateCall(ActionRequest request, Guid candidateId);
        Guid CreateHistory(ActionRequest request, Guid candidateId, int previous, int current);
        InterviewScheduleState? GetCurrentRound1Schedule(Guid candidateId);
        InterviewScheduleState? GetProposedRound1Schedule(Guid candidateId);
        InterviewScheduleState CreateRound1Schedule(ActionRequest request, Guid candidateId, int scheduleStatus);
        InterviewScheduleState UpdateRound1Schedule(
            ActionRequest request, InterviewScheduleState schedule, int scheduleStatus);
        void RecordRound1Result(ActionRequest request, InterviewScheduleState schedule, int result);
        void CreateReceipt(ActionRequest request, ActionResult result);
    }

    public static class CandidateOperation
    {
        private static readonly IReadOnlyDictionary<string, IReadOnlyCollection<string>> AllowedMutations =
            new ReadOnlyDictionary<string, IReadOnlyCollection<string>>(
                new Dictionary<string, IReadOnlyCollection<string>>(StringComparer.Ordinal)
                {
                    ["CreateCandidate"] = Array.AsReadOnly(new[] { "CANDIDATE_CREATE", "RECEIPT_CREATE" }),
                    ["UpdateCandidate"] = Array.AsReadOnly(new[] { "CANDIDATE_UPDATE", "RECEIPT_CREATE" }),
                    ["RecordCall"] = Array.AsReadOnly(new[] { "CANDIDATE_UPDATE", "CALL_LOG_CREATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" }),
                    ["ProceedToScheduling"] = Array.AsReadOnly(new[] { "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" }),
                    ["MarkRound1Scheduled"] = Array.AsReadOnly(new[] { "INTERVIEW_SCHEDULE_CREATE",
                        "INTERVIEW_SCHEDULE_UPDATE", "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" }),
                    ["RecordPass"] = Array.AsReadOnly(new[] { "CANDIDATE_UPDATE", "INTERVIEW_SCHEDULE_UPDATE",
                        "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" }),
                    ["RecordFail"] = Array.AsReadOnly(new[] { "CANDIDATE_UPDATE", "INTERVIEW_SCHEDULE_UPDATE",
                        "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" }),
                    ["RequestReschedule"] = Array.AsReadOnly(new[] { "INTERVIEW_SCHEDULE_CREATE",
                        "INTERVIEW_SCHEDULE_UPDATE", "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" }),
                    ["CancelRound1"] = Array.AsReadOnly(new[] { "INTERVIEW_SCHEDULE_UPDATE",
                        "CANDIDATE_UPDATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" })
                });

        public static IReadOnlyDictionary<string, IReadOnlyCollection<string>> MutationMatrix => AllowedMutations;

        public static bool AllowsMutation(string action, string mutation) =>
            AllowedMutations.TryGetValue(action, out var mutations) && mutations.Contains(mutation, StringComparer.Ordinal);

        public static int Transition(string action, int current, int? outcome)
        {
            if (action == "RecordCall" && current == ActionRequest.NeedCall &&
                outcome >= ActionRequest.NeedCall && outcome <= ActionRequest.Waiting)
                return outcome == ActionRequest.NeedCall ? ActionRequest.Answered : current;
            if (action == "ProceedToScheduling" && current == ActionRequest.Answered) return ActionRequest.Waiting;
            if (action == "MarkRound1Scheduled" && current == ActionRequest.Waiting)
                return ActionRequest.Scheduled;
            if ((action == "RecordPass" || action == "RecordFail" || action == "RequestReschedule" ||
                action == "CancelRound1") && current == ActionRequest.Scheduled)
            {
                if (action == "RecordPass" || action == "RecordFail")
                    throw new OperationError("RESULT_EVIDENCE_REQUIRED");
                return ActionRequest.NeedCall;
            }
            throw new OperationError("INVALID_TRANSITION");
        }

        private static int ResultTransition(string action, int current)
        {
            if (current != ActionRequest.Scheduled) throw new OperationError("INVALID_TRANSITION");
            if (action == "RecordPass") return ActionRequest.Passed;
            if (action == "RecordFail") return ActionRequest.Failed;
            throw new OperationError("INVALID_TRANSITION");
        }

        public static ActionResult Execute(ActionRequest request, IOperationStore store)
        {
            store.RequireTransaction();
            var receipt = store.FindReceipt(request.Correlation);
            if (receipt != null)
            {
                if (receipt.Actor != request.Actor || receipt.Action != request.Action ||
                    receipt.Fingerprint != request.Fingerprint || receipt.Version != "1")
                    throw new OperationError("CORRELATION_CONFLICT");
                if (request.CandidateId.HasValue && request.CandidateId != receipt.Result.CandidateId)
                    throw new OperationError("CORRELATION_CONFLICT");
                store.GetCandidate(receipt.Result.CandidateId);
                return new ActionResult { Replay = true, CandidateId = receipt.Result.CandidateId,
                    Previous = receipt.Result.Previous, Current = receipt.Result.Current,
                    CallId = receipt.Result.CallId, HistoryId = receipt.Result.HistoryId };
            }
            var result = new ActionResult();
            if (request.Action == "CreateCandidate")
            {
                result.CandidateId = store.CreateCandidate(request);
                result.Current = ActionRequest.NeedCall;
            }
            else
            {
                var candidate = store.GetCandidate(request.CandidateId!.Value);
                if (request.ExpectedStatus.HasValue && request.ExpectedStatus != candidate.Status)
                    throw new OperationError("STALE_EXPECTED_STATUS");
                if (string.IsNullOrEmpty(candidate.RowVersion)) throw new OperationError("ROW_VERSION_UNAVAILABLE");
                result.CandidateId = candidate.Id;
                result.Previous = candidate.Status;
                result.Current = candidate.Status;
                if (request.Action == "UpdateCandidate") store.UpdateCandidate(request, candidate, candidate.Status);
                else
                {
                    int? outcome = request.Values.TryGetValue("CallOutcome", out var raw) ? (int?)raw : null;
                    if (request.Action == "MarkRound1Scheduled")
                    {
                        result.Current = Transition(request.Action, candidate.Status, outcome);
                        var activeSchedule = store.GetCurrentRound1Schedule(candidate.Id);
                        var proposedSchedule = store.GetProposedRound1Schedule(candidate.Id);
                        if (activeSchedule != null && proposedSchedule != null)
                            throw new OperationError("SCHEDULE_STATE_AMBIGUOUS");
                        if (activeSchedule != null)
                            throw new OperationError("ACTIVE_SCHEDULE_CONFLICT");
                        if (proposedSchedule == null)
                            store.CreateRound1Schedule(request, candidate.Id, ActionRequest.ScheduleActive);
                        else
                            store.UpdateRound1Schedule(request, proposedSchedule, ActionRequest.ScheduleActive);
                    }
                    else if (request.Action == "RecordPass" || request.Action == "RecordFail")
                    {
                        result.Current = ResultTransition(request.Action, candidate.Status);
                        var schedule = store.GetCurrentRound1Schedule(candidate.Id) ??
                            throw new OperationError("ACTIVE_SCHEDULE_REQUIRED");
                        if (schedule.Result.HasValue && schedule.Result.Value != ActionRequest.ResultPending)
                            throw new OperationError("SCHEDULE_RESULT_ALREADY_RECORDED");
                        store.RecordRound1Result(request, schedule,
                            request.Action == "RecordPass" ? ActionRequest.ResultPass : ActionRequest.ResultFail);
                    }
                    else if (request.Action == "RequestReschedule" || request.Action == "CancelRound1")
                    {
                        result.Current = Transition(request.Action, candidate.Status, outcome);
                        var schedule = store.GetCurrentRound1Schedule(candidate.Id) ??
                            throw new OperationError("ACTIVE_SCHEDULE_REQUIRED");
                        if (schedule.Result.HasValue && schedule.Result.Value != ActionRequest.ResultPending)
                            throw new OperationError("SCHEDULE_RESULT_ALREADY_RECORDED");
                        if (request.Action == "RequestReschedule")
                        {
                            if (store.GetProposedRound1Schedule(candidate.Id) != null)
                                throw new OperationError("SCHEDULE_STATE_AMBIGUOUS");
                            store.UpdateRound1Schedule(request, schedule, ActionRequest.ScheduleSuperseded);
                            store.CreateRound1Schedule(request, candidate.Id, ActionRequest.ScheduleProposed);
                        }
                        else
                        {
                            if (store.GetProposedRound1Schedule(candidate.Id) != null)
                                throw new OperationError("SCHEDULE_STATE_AMBIGUOUS");
                            store.UpdateRound1Schedule(request, schedule, ActionRequest.ScheduleCancelled);
                        }
                    }
                    else
                        result.Current = Transition(request.Action, candidate.Status, outcome);
                    if (result.Current != candidate.Status) store.UpdateCandidate(request, candidate, result.Current);
                    if (request.Action == "RecordCall") result.CallId = store.CreateCall(request, candidate.Id);
                    if (result.Current != candidate.Status)
                        result.HistoryId = store.CreateHistory(request, candidate.Id, candidate.Status, result.Current);
                }
            }
            store.CreateReceipt(request, result);
            return result;
        }
    }
}
