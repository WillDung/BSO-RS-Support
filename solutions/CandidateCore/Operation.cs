using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace os_sr_cact
{
    public sealed class OperationError : Exception
    {
        public OperationError(string code) : base(code) { }
    }

    public sealed class ActionRequest
    {
        public const int NeedCall = 100010000;
        public const int Answered = 100010001;
        public const int Waiting = 100010002;
        public const int Scheduled = 100010003;
        public const int Passed = 100010004;
        public const int Failed = 100010005;
        public Guid Actor { get; }
        public Guid Correlation { get; }
        public Guid? CandidateId { get; }
        public string Action { get; }
        public int? ExpectedStatus { get; }
        public IReadOnlyDictionary<string, object?> Values { get; }
        public string Fingerprint { get; }

        public ActionRequest(Guid actor, IDictionary<string, object?> input, DateTime utcNow)
        {
            Actor = actor;
            if (actor == Guid.Empty) throw new OperationError("INVALID_ACTOR");
            Action = Required<string>(input, "ActionType");
            if (!new[] { "CreateCandidate", "UpdateCandidate", "RecordCall", "ProceedToScheduling",
                "MarkRound1Scheduled", "RecordPass", "RecordFail", "RequestReschedule" }.Contains(Action))
                throw new OperationError("INVALID_ACTION");
            Correlation = Required<Guid>(input, "CorrelationId");
            if (Correlation == Guid.Empty) throw new OperationError("INVALID_CORRELATION");
            CandidateId = input.TryGetValue("CandidateId", out var target) && target is Guid id && id != Guid.Empty ? id : (Guid?)null;
            if (Action != "CreateCandidate" && !CandidateId.HasValue) throw new OperationError("INVALID_CANDIDATE");
            if (Action == "CreateCandidate" && input.ContainsKey("CandidateId")) throw new OperationError("UNEXPECTED_INPUT");
            ExpectedStatus = input.TryGetValue("ExpectedStatus", out var status) && status is int state ? state : (int?)null;
            if (Action != "CreateCandidate" && Action != "UpdateCandidate" && !ExpectedStatus.HasValue)
                throw new OperationError("EXPECTED_STATUS_REQUIRED");
            if (input.ContainsKey("ExpectedStatus") && (!ExpectedStatus.HasValue || ExpectedStatus < NeedCall || ExpectedStatus > Failed))
                throw new OperationError("INVALID_EXPECTED_STATUS");
            var values = new SortedDictionary<string, object?>(StringComparer.Ordinal);
            var common = new[] { "ActionType", "CorrelationId", "CandidateId", "ExpectedStatus" };
            var profile = new[] { "CandidateName", "CandidateEmail", "CandidatePhone", "PositionId", "CandidateSourceId" };
            var allowed = new HashSet<string>(common, StringComparer.Ordinal);
            if (Action == "CreateCandidate" || Action == "UpdateCandidate") allowed.UnionWith(profile);
            if (Action == "RecordCall") allowed.UnionWith(new[] { "CallOutcome", "ContactedAt", "Notes" });
            if (Action == "RequestReschedule") allowed.Add("Reason");
            foreach (var pair in input)
            {
                if (!allowed.Contains(pair.Key)) throw new OperationError("UNEXPECTED_INPUT");
                object? value = pair.Value;
                if (profile.Contains(pair.Key) || pair.Key == "Notes" || pair.Key == "Reason")
                {
                    if (pair.Key.EndsWith("Id", StringComparison.Ordinal))
                    {
                        if (value != null && (!(value is Guid lookup) || lookup == Guid.Empty)) throw new OperationError("INVALID_LOOKUP");
                    }
                    else
                    {
                        if (value != null && !(value is string)) throw new OperationError("INVALID_TEXT");
                        value = (value as string)?.Trim();
                        int length = pair.Key == "Notes" ? 4000 : pair.Key == "Reason" ? 1000 :
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
            if (Action == "RequestReschedule" && !values.ContainsKey("Reason")) throw new OperationError("REASON_REQUIRED");
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
    }

    public sealed class CandidateState
    {
        public Guid Id { get; set; }
        public int Status { get; set; }
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
        void CreateReceipt(ActionRequest request, ActionResult result);
    }

    public static class CandidateOperation
    {
        public static int Transition(string action, int current, int? outcome, bool futureEvidence = false)
        {
            if (action == "RecordCall" && current == ActionRequest.NeedCall &&
                outcome >= ActionRequest.NeedCall && outcome <= ActionRequest.Waiting)
                return outcome == ActionRequest.NeedCall ? ActionRequest.Answered : current;
            if (action == "ProceedToScheduling" && current == ActionRequest.Answered) return ActionRequest.Waiting;
            if (action == "MarkRound1Scheduled" && current == ActionRequest.Waiting)
            {
                if (!futureEvidence) throw new OperationError("SCHEDULER_DEPENDENCY_UNAVAILABLE");
                return ActionRequest.Scheduled;
            }
            if ((action == "RecordPass" || action == "RecordFail" || action == "RequestReschedule") && current == ActionRequest.Scheduled)
            {
                if (!futureEvidence) throw new OperationError("RESULT_OR_CANCELLATION_DEPENDENCY_UNAVAILABLE");
                return action == "RecordPass" ? ActionRequest.Passed : action == "RecordFail" ? ActionRequest.Failed : ActionRequest.NeedCall;
            }
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
