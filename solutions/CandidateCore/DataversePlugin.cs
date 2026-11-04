using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.ServiceModel;
using System.Text;
using Microsoft.Crm.Sdk.Messages;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Query;

namespace os_sr_cact
{
    public sealed class ApplyCandidateAction : IPlugin
    {
        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var trace = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
            string? action = null;
            var createCandidateStage = "INPUT_VALIDATION";
            try
            {
                if (context.MessageName == DevCandidateSlice.MessageName)
                {
                    DevCandidateSlice.Execute(serviceProvider, context, trace);
                    return;
                }
                if (context.MessageName != "os_sr_cact" || context.Stage != 30 || context.Mode != 0 ||
                    !context.IsInTransaction || context.UserId != context.InitiatingUserId || context.Depth != 1)
                    throw new OperationError("UNSUPPORTED_EXECUTION_CONTEXT");
                if (context.InputParameters.TryGetValue("ActionType", out var actionValue) &&
                    actionValue is string inputAction && inputAction == "CreateCandidate")
                    action = inputAction;
                var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
                var callerService = factory.CreateOrganizationService(context.InitiatingUserId);
                var request = CandidateActionInputAdapter.Create(context.InitiatingUserId, context.InputParameters, DateTime.UtcNow);
                action = request.Action;
                if (action == "CreateCandidate") createCandidateStage = "REFERENCE_VALIDATION";
                ValidateCallerReferences(callerService, request, trace);
                var systemService = factory.CreateOrganizationService(null);
                var store = new DataverseStore(systemService, context, trace, request.Action,
                    stage => createCandidateStage = stage);
                var result = CandidateOperation.Execute(request, store);
                if (action == "CreateCandidate") createCandidateStage = "RESPONSE";
                context.OutputParameters["ResultCode"] = result.Replay ? "DuplicateReplay" : "Applied";
                if (result.Previous.HasValue) context.OutputParameters["PreviousStatus"] = result.Previous.Value;
                context.OutputParameters["CurrentStatus"] = result.Current;
                if (result.CallId.HasValue) context.OutputParameters["CallLogId"] = result.CallId.Value;
                if (result.HistoryId.HasValue) context.OutputParameters["StatusHistoryId"] = result.HistoryId.Value;
                trace.Trace("os_sr_cact result={0} action={1}", result.Replay ? "DuplicateReplay" : "Applied", request.Action);
            }
            catch (OperationError error)
            {
                if (action == "CreateCandidate")
                {
                    var diagnostic = FormatCreateCandidateFailure(
                        error.Message, createCandidateStage);
                    trace.Trace("os_sr_cact rejected code={0}", diagnostic);
                    throw new InvalidPluginExecutionException(diagnostic);
                }
                trace.Trace("os_sr_cact rejected code={0}", error.Message);
                throw new InvalidPluginExecutionException(error.Message, error);
            }
            catch (FaultException<OrganizationServiceFault> error)
            {
                if (action == "CreateCandidate")
                {
                    var diagnostic = string.Format(CultureInfo.InvariantCulture,
                        "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:{0}:0x{1:X8}",
                        createCandidateStage, error.Detail.ErrorCode);
                    trace.Trace("os_sr_cact rejected code={0}", diagnostic);
                    throw new InvalidPluginExecutionException(diagnostic);
                }
                trace.Trace("os_sr_cact Dataverse fault code={0}", error.Detail.ErrorCode);
                // Do not swallow a service fault or issue another service call inside a failed transaction.
                string code = error.Detail.ErrorCode == unchecked((int)0x80040237) ? "CORRELATION_OR_KEY_CONFLICT" :
                    error.Detail.ErrorCode == unchecked((int)0x80060882) ? "ROW_VERSION_CONFLICT" : "DATAVERSE_OPERATION_REJECTED";
                throw new InvalidPluginExecutionException(code);
            }
            catch (Exception)
            {
                if (action != "CreateCandidate") throw;
                var diagnostic = FormatCreateCandidateFailure("CANDIDATE_CORE_FAILURE:OTHER",
                    createCandidateStage);
                trace.Trace("os_sr_cact rejected code={0}", diagnostic);
                throw new InvalidPluginExecutionException(diagnostic);
            }
        }

        private static string FormatCreateCandidateFailure(string errorMessage, string stage)
        {
            if (stage != "INPUT_VALIDATION" && stage != "REFERENCE_VALIDATION" &&
                stage != "RECEIPT_READ" && stage != "CANDIDATE_CREATE" &&
                stage != "CANDIDATE_READBACK" && stage != "RECEIPT_CREATE" && stage != "RESPONSE")
                stage = "RESPONSE";

            var parts = errorMessage.Split(':');
            string? safeCode = null;
            if (parts.Length == 3 && parts[0] == "DATAVERSE_OPERATION_REJECTED" &&
                uint.TryParse(parts[2].StartsWith("0x", StringComparison.OrdinalIgnoreCase)
                        ? parts[2].Substring(2) : "",
                    NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var faultCode))
            {
                safeCode = "0x" + faultCode.ToString("X8", CultureInfo.InvariantCulture);
            }
            else if (parts.Length == 3 && parts[0] == "CANDIDATE_CORE_FAILURE" &&
                new[] { "TIMEOUT", "PLUGIN_EXECUTION", "INVALID_OPERATION", "SERVICE_FAULT", "OTHER" }
                    .Contains(parts[2], StringComparer.Ordinal))
            {
                safeCode = parts[2];
            }
            else if (errorMessage.StartsWith("REFERENCE_NOT_AVAILABLE:", StringComparison.Ordinal))
            {
                safeCode = "REFERENCE_NOT_AVAILABLE";
            }
            else if (parts.Length > 0 && parts[0].Length <= 64 &&
                parts[0][0] >= 'A' && parts[0][0] <= 'Z' &&
                parts[0].All(character =>
                    character == '_' || character >= 'A' && character <= 'Z' ||
                    character >= '0' && character <= '9'))
            {
                safeCode = parts[0];
            }

            safeCode ??= "INVALID_OPERATION";
            return string.Format(CultureInfo.InvariantCulture,
                "CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:{0}:{1}", stage, safeCode);
        }

        private static void ValidateCallerReferences(
            IOrganizationService callerService,
            ActionRequest request,
            ITracingService trace)
        {
            foreach (var reference in new[]
            {
                (Input: "PositionId", Table: "os_sr_pos"),
                (Input: "CandidateSourceId", Table: "os_sr_csrc"),
                (Input: "AssignedTaId", Table: "os_sr_ta"),
                (Input: "InterviewerId", Table: "os_sr_ta"),
                (Input: "LocationId", Table: "os_sr_loc")
            })
            {
                if (!request.Values.TryGetValue(reference.Input, out var value) || !(value is Guid id))
                    continue;

                try
                {
                    var row = callerService.Retrieve(reference.Table, id, new ColumnSet("statecode"));
                    if (row.GetAttributeValue<OptionSetValue>("statecode")?.Value != 0)
                        throw new OperationError("REFERENCE_NOT_AVAILABLE:" + reference.Input);
                }
                catch (FaultException<OrganizationServiceFault> error)
                {
                    trace.Trace("CC_REFERENCE_VALIDATION_FAILED:{0}:0x{1:X8}",
                        reference.Input, error.Detail.ErrorCode);
                    if (request.Action == "CreateCandidate")
                        throw new OperationError(
                            "DATAVERSE_OPERATION_REJECTED:REFERENCE_VALIDATION:0x" +
                            error.Detail.ErrorCode.ToString("X8", CultureInfo.InvariantCulture), error);
                    throw new OperationError("REFERENCE_NOT_AVAILABLE:" + reference.Input, error);
                }
            }
        }
    }

    internal static class DevCandidateSlice
    {
        public const string MessageName = "os_sr_devcs";
        private static readonly Guid DevelopmentOrganizationId = new Guid("0706072c-54ea-f011-872b-000d3ab60060");
        private const int NeedCallCandidate = 100010000;
        private const int CandidateAnswered = 100010001;
        private const int WaitingManualScheduling = 100010002;
        private const int CallAnswered = 100010000;
        private const int CallNoAnswer = 100010001;
        private const int CallBackRequested = 100010002;

        public static void Execute(
            IServiceProvider serviceProvider, IPluginExecutionContext context, ITracingService trace)
        {
            if (context.OrganizationId != DevelopmentOrganizationId)
                throw new OperationError("DEV_SLICE_ENVIRONMENT_REJECTED");
            if (context.Stage != 30 || context.Mode != 0 || !context.IsInTransaction ||
                context.UserId != context.InitiatingUserId || context.Depth != 1)
                throw new OperationError("DEV_SLICE_INPUT_REJECTED:CONTEXT");

            var action = ReadRequiredString(context.InputParameters, "ActionType");
            if (action != "CreateCandidate" && action != "RecordCall")
                throw new OperationError("DEV_SLICE_INPUT_REJECTED:ACTION");

            var allowedInputs = action == "CreateCandidate"
                ? new[] { "ActionType", "CorrelationId", "CandidateName", "CandidateEmail", "CandidatePhone", "PositionId", "CandidateSourceId" }
                : new[] { "ActionType", "CorrelationId", "CandidateId", "ExpectedStatus", "CallOutcome", "ContactedAt", "Notes" };
            foreach (var parameter in context.InputParameters)
                if (!ActionRequest.IsDeclaredInputName(parameter.Key) ||
                    (!allowedInputs.Contains(parameter.Key, StringComparer.Ordinal) && parameter.Value != null))
                    throw new OperationError("DEV_SLICE_INPUT_REJECTED:PARAMETER_SHAPE");

            var correlationId = ParseGuid(ReadRequiredString(context.InputParameters, "CorrelationId"),
                "DEV_SLICE_INPUT_REJECTED");
            var service = GetService(serviceProvider, context.InitiatingUserId, trace);
            Guid candidateId;
            if (action == "CreateCandidate")
            {
                var name = ReadRequiredString(context.InputParameters, "CandidateName").Trim();
                var email = ReadRequiredString(context.InputParameters, "CandidateEmail").Trim();
                var phone = ReadOptionalString(context.InputParameters, "CandidatePhone");
                var positionId = ReadOptionalGuid(context.InputParameters, "PositionId");
                var sourceId = ReadOptionalGuid(context.InputParameters, "CandidateSourceId");
                if (!IsSyntheticProfile(name, email) || name.Length > 200 || email.Length > 254 ||
                    (phone != null && phone.Length > 50))
                    throw new OperationError("DEV_SLICE_INPUT_REJECTED:SYNTHETIC_PROFILE");

                var row = new Entity("os_sr_cand")
                {
                    ["os_sr_cand_nm"] = name,
                    ["os_sr_cand_eml"] = email,
                    ["os_sr_cand_stat"] = new OptionSetValue(NeedCallCandidate),
                    ["os_sr_cand_corid"] = correlationId.ToString("D"),
                    ["ownerid"] = new EntityReference("systemuser", context.InitiatingUserId)
                };
                if (phone != null) row["os_sr_cand_phn"] = phone;
                if (positionId.HasValue) row["os_sr_cand_pos"] = new EntityReference("os_sr_pos", positionId.Value);
                if (sourceId.HasValue) row["os_sr_cand_csrc"] = new EntityReference("os_sr_csrc", sourceId.Value);

                candidateId = RunStage(trace, "DEV_SLICE_CANDIDATE_CREATE_FAILED", () => service.Create(row));
                var saved = RunStage(trace, "DEV_SLICE_CANDIDATE_READBACK_FAILED", () =>
                    service.Retrieve("os_sr_cand", candidateId, new ColumnSet(
                        "os_sr_cand_nm", "os_sr_cand_eml", "os_sr_cand_phn", "os_sr_cand_stat",
                        "os_sr_cand_cnum", "os_sr_cand_pos", "os_sr_cand_csrc", "ownerid")));
                if (saved.Id != candidateId ||
                    saved.GetAttributeValue<string>("os_sr_cand_nm") != name ||
                    saved.GetAttributeValue<string>("os_sr_cand_eml") != email ||
                    saved.GetAttributeValue<OptionSetValue>("os_sr_cand_stat")?.Value != NeedCallCandidate ||
                    string.IsNullOrWhiteSpace(saved.GetAttributeValue<string>("os_sr_cand_cnum")))
                    throw new OperationError("DEV_SLICE_CANDIDATE_READBACK_FAILED");
            }
            else
            {
                candidateId = ParseGuid(ReadRequiredString(context.InputParameters, "CandidateId"),
                    "DEV_SLICE_INPUT_REJECTED");
                var expectedStatus = ReadRequiredInt(context.InputParameters, "ExpectedStatus");
                var outcome = ReadRequiredInt(context.InputParameters, "CallOutcome");
                var contactedAt = ParseUtcDateTime(ReadRequiredString(context.InputParameters, "ContactedAt"));
                var notes = ReadOptionalString(context.InputParameters, "Notes");
                if (!IsSupportedStatus(expectedStatus) ||
                    (outcome != CallAnswered && outcome != CallNoAnswer && outcome != CallBackRequested) ||
                    (notes != null && notes.Length > 4000))
                    throw new OperationError("DEV_SLICE_INPUT_REJECTED:CALL_PARAMETERS");

                var candidate = RunStage(trace, "DEV_SLICE_CANDIDATE_READBACK_FAILED", () =>
                    service.Retrieve("os_sr_cand", candidateId,
                        new ColumnSet("os_sr_cand_nm", "os_sr_cand_eml", "os_sr_cand_stat")));
                var currentStatus = candidate.GetAttributeValue<OptionSetValue>("os_sr_cand_stat")?.Value;
                if (candidate.Id != candidateId ||
                    !IsSyntheticProfile(candidate.GetAttributeValue<string>("os_sr_cand_nm"),
                        candidate.GetAttributeValue<string>("os_sr_cand_eml")) ||
                    !currentStatus.HasValue || currentStatus.Value != expectedStatus)
                    throw new OperationError("DEV_SLICE_CANDIDATE_READBACK_FAILED");

                var call = new Entity("os_sr_call")
                {
                    ["os_sr_call_cand"] = new EntityReference("os_sr_cand", candidateId),
                    ["os_sr_call_out"] = new OptionSetValue(outcome),
                    ["os_sr_call_ctat"] = contactedAt,
                    ["os_sr_call_ctby"] = new EntityReference("systemuser", context.InitiatingUserId),
                    ["os_sr_call_corid"] = correlationId.ToString("D"),
                    ["ownerid"] = new EntityReference("systemuser", context.InitiatingUserId)
                };
                if (notes != null) call["os_sr_call_nts"] = notes;
                RunStage(trace, "DEV_SLICE_CALL_CREATE_FAILED", () => service.Create(call));

                if (outcome == CallAnswered && currentStatus.Value == NeedCallCandidate)
                {
                    var update = new Entity("os_sr_cand", candidateId)
                    {
                        ["os_sr_cand_stat"] = new OptionSetValue(CandidateAnswered)
                    };
                    RunStage(trace, "DEV_SLICE_STATUS_UPDATE_FAILED", () => service.Update(update));
                    var history = new Entity("os_sr_csh")
                    {
                        ["os_sr_csh_cand"] = new EntityReference("os_sr_cand", candidateId),
                        ["os_sr_csh_prevstat"] = new OptionSetValue(NeedCallCandidate),
                        ["os_sr_csh_newstat"] = new OptionSetValue(CandidateAnswered),
                        ["os_sr_csh_actr"] = new EntityReference("systemuser", context.InitiatingUserId),
                        ["os_sr_csh_chg"] = DateTime.UtcNow,
                        ["os_sr_csh_corid"] = correlationId.ToString("D"),
                        ["os_sr_csh_cact"] = "RecordCall",
                        ["os_sr_csh_rsn"] = "DEV Candidate Slice: RecordCall Answered",
                        ["ownerid"] = new EntityReference("systemuser", context.InitiatingUserId)
                    };
                    RunStage(trace, "DEV_SLICE_HISTORY_CREATE_FAILED", () => service.Create(history));
                }
            }

            try
            {
                context.OutputParameters["ResultCode"] = "Applied";
                context.OutputParameters["CandidateId"] = candidateId.ToString("D");
            }
            catch (Exception error)
            {
                trace.Trace("DEV_SLICE_STAGE:DEV_SLICE_RESPONSE_FAILED");
                throw new OperationError("DEV_SLICE_RESPONSE_FAILED", error);
            }
        }

        private static IOrganizationService GetService(IServiceProvider serviceProvider, Guid actor, ITracingService trace)
        {
            try
            {
                var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
                return factory.CreateOrganizationService(actor);
            }
            catch (FaultException<OrganizationServiceFault> error)
            {
                throw StageError(trace, "DEV_SLICE_RESPONSE_FAILED", error);
            }
            catch (Exception error)
            {
                throw new OperationError("DEV_SLICE_RESPONSE_FAILED", error);
            }
        }

        private static T RunStage<T>(ITracingService trace, string category, Func<T> operation)
        {
            trace.Trace("DEV_SLICE_STAGE:{0}", category);
            try
            {
                return operation();
            }
            catch (FaultException<OrganizationServiceFault> error)
            {
                throw StageError(trace, category, error);
            }
            catch (Exception error)
            {
                throw new OperationError(category, error);
            }
        }

        private static void RunStage(ITracingService trace, string category, Action operation)
        {
            RunStage(trace, category, () =>
            {
                operation();
                return true;
            });
        }

        private static OperationError StageError(
            ITracingService trace, string category, FaultException<OrganizationServiceFault> error)
        {
            var code = error.Detail == null ? 0 : error.Detail.ErrorCode;
            var safeCode = code == 0 ? category :
                category + ":0x" + unchecked((uint)code).ToString("X8", CultureInfo.InvariantCulture);
            trace.Trace("DEV_SLICE_FAILURE:{0}", safeCode);
            return new OperationError(safeCode, error);
        }

        private static string ReadRequiredString(ParameterCollection parameters, string name)
        {
            if (!parameters.TryGetValue(name, out var value) || !(value is string text) ||
                string.IsNullOrWhiteSpace(text))
                throw new OperationError("DEV_SLICE_INPUT_REJECTED:REQUIRED_VALUE");
            return text;
        }

        private static string? ReadOptionalString(ParameterCollection parameters, string name)
        {
            if (!parameters.TryGetValue(name, out var value) || value == null) return null;
            if (!(value is string text)) throw new OperationError("DEV_SLICE_INPUT_REJECTED:OPTIONAL_TEXT");
            return text;
        }

        private static int ReadRequiredInt(ParameterCollection parameters, string name)
        {
            if (!parameters.TryGetValue(name, out var value) || !(value is int number))
                throw new OperationError("DEV_SLICE_INPUT_REJECTED:REQUIRED_VALUE");
            return number;
        }

        private static Guid ParseGuid(string value, string errorCode)
        {
            if (!Guid.TryParse(value, out var id) || id == Guid.Empty)
                throw new OperationError(errorCode);
            return id;
        }

        private static Guid? ReadOptionalGuid(ParameterCollection parameters, string name)
        {
            var value = ReadOptionalString(parameters, name);
            if (value == null) return null;
            return ParseGuid(value, "DEV_SLICE_INPUT_REJECTED:OPTIONAL_LOOKUP");
        }

        private static DateTime ParseUtcDateTime(string value)
        {
            if (!DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None,
                out var timestamp) || timestamp.Offset != TimeSpan.Zero)
                throw new OperationError("DEV_SLICE_INPUT_REJECTED:CONTACTED_AT");
            return timestamp.UtcDateTime;
        }

        private static bool IsSyntheticProfile(string? name, string? email)
        {
            if (name == null || email == null) return false;
            var at = email.LastIndexOf('@');
            return name.StartsWith("[SYNTHETIC-E2E]", StringComparison.Ordinal) &&
                at > 0 && at < email.Length - 1 &&
                email.IndexOfAny(new[] { ' ', '\t', '\r', '\n' }) < 0 &&
                email.Substring(at + 1).EndsWith(".invalid", StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsSupportedStatus(int status) =>
            status == NeedCallCandidate || status == CandidateAnswered || status == WaitingManualScheduling;
    }

    internal static class CandidateActionInputAdapter
    {
        public static ActionRequest Create(Guid actor, ParameterCollection parameters, DateTime utcNow)
        {
            var input = new Dictionary<string, object?>(StringComparer.Ordinal);
            var hasAction = parameters.TryGetValue("ActionType", out var actionValue);
            if (hasAction) input["ActionType"] = actionValue;
            if (parameters.TryGetValue("CorrelationId", out var correlationValue))
                input["CorrelationId"] = correlationValue;

            var action = actionValue as string;
            if (action == null || !ActionRequest.IsSupportedAction(action))
                return new ActionRequest(actor, input, utcNow);

            foreach (var parameter in parameters)
            {
                if (!ActionRequest.IsDeclaredInputName(parameter.Key))
                    throw new OperationError("UNEXPECTED_INPUT:SDK_ADAPTER:OTHER");
            }

            if (action != null)
            {
                foreach (var name in ActionRequest.ApplicableInputNames(action))
                {
                    if (name == "ActionType" || name == "CorrelationId") continue;
                    if (!parameters.TryGetValue(name, out var value)) continue;
                    // Dataverse supplies Guid.Empty for omitted optional GUIDs; explicit null still means clear.
                    if (action == "UpdateCandidate" && ActionRequest.IsOptionalProfileLookup(name) &&
                        value is Guid id && id == Guid.Empty) continue;
                    input[name] = value;
                }
            }

            return new ActionRequest(actor, input, utcNow);
        }
    }

    internal sealed class DataverseStore : IOperationStore
    {
        private readonly IOrganizationService systemService;
        private readonly IPluginExecutionContext context;
        private readonly ITracingService trace;
        private readonly string action;
        private readonly Action<string> stageChanged;

        public DataverseStore(
            IOrganizationService systemService,
            IPluginExecutionContext context,
            ITracingService trace,
            string action,
            Action<string> stageChanged)
        {
            this.systemService = systemService;
            this.context = context;
            this.trace = trace;
            this.action = action;
            this.stageChanged = stageChanged;
        }

        public void RequireTransaction()
        {
            if (!context.IsInTransaction || context.UserId != context.InitiatingUserId)
                throw new OperationError("UNSUPPORTED_EXECUTION_CONTEXT");
        }

        public Receipt? FindReceipt(Guid correlation)
        {
            SetCreateCandidateStage("RECEIPT_READ");
            var query = new QueryExpression("os_sr_oprc")
            {
                ColumnSet = new ColumnSet("os_sr_oprc_cand", "os_sr_oprc_cact", "os_sr_oprc_hash",
                    "os_sr_oprc_ver", "os_sr_oprc_prevstat", "os_sr_oprc_newstat", "os_sr_oprc_callref", "os_sr_oprc_histref"),
                TopCount = 2
            };
            query.Criteria.AddCondition("os_sr_oprc_corid", ConditionOperator.Equal, correlation.ToString("D"));
            var rows = ExecuteAtStage("CC_READ_RECEIPT", () => systemService.RetrieveMultiple(query)).Entities;
            if (rows.Count == 0) return null;
            if (rows.Count != 1) throw new OperationError("RECEIPT_INTEGRITY_FAILURE");
            var row = rows[0];
            var candidate = row.GetAttributeValue<EntityReference>("os_sr_oprc_cand");
            if (candidate == null ||
                !row.Contains("os_sr_oprc_newstat") || string.IsNullOrEmpty(row.GetAttributeValue<string>("os_sr_oprc_hash")))
                throw new OperationError("RECEIPT_INTEGRITY_FAILURE");
            return new Receipt
            {
                Action = row.GetAttributeValue<string>("os_sr_oprc_cact"),
                Fingerprint = row.GetAttributeValue<string>("os_sr_oprc_hash"),
                Version = row.GetAttributeValue<string>("os_sr_oprc_ver"),
                Result = new ActionResult { CandidateId = candidate.Id,
                    Previous = row.Contains("os_sr_oprc_prevstat") ? row.GetAttributeValue<int>("os_sr_oprc_prevstat") : (int?)null,
                    Current = row.GetAttributeValue<int>("os_sr_oprc_newstat"),
                    CallId = ReadGuid(row, "os_sr_oprc_callref"), HistoryId = ReadGuid(row, "os_sr_oprc_histref") }
            };
        }

        private static Guid? ReadGuid(Entity row, string name)
        {
            var value = row.GetAttributeValue<string>(name);
            if (value == null) return null;
            if (!Guid.TryParseExact(value, "D", out var guid) || guid == Guid.Empty)
                throw new OperationError("RECEIPT_INTEGRITY_FAILURE");
            return guid;
        }

        public CandidateState GetCandidate(Guid id)
        {
            SetCreateCandidateStage("CANDIDATE_READBACK");
            EnsureCallerReadAccess(new EntityReference("os_sr_cand", id));
            var row = ExecuteAtStage("CC_READ_CANDIDATE",
                () => systemService.Retrieve("os_sr_cand", id, new ColumnSet("os_sr_cand_stat", "versionnumber")));
            if (!row.Contains("os_sr_cand_stat")) throw new OperationError("CANDIDATE_INTEGRITY_FAILURE");
            int status = row.GetAttributeValue<OptionSetValue>("os_sr_cand_stat").Value;
            if (status < ActionRequest.NeedCall || status > ActionRequest.Failed) throw new OperationError("INVALID_CANDIDATE_STATUS");
            return new CandidateState { Id = id, Status = status, RowVersion = row.RowVersion };
        }

        private void EnsureCallerReadAccess(EntityReference target)
        {
            var response = (RetrievePrincipalAccessResponse)ExecuteAtStage("CC_CHECK_PROTECTED_READ_ACCESS",
                () => systemService.Execute(new RetrievePrincipalAccessRequest
                {
                    Target = target,
                    Principal = new EntityReference("systemuser", context.InitiatingUserId)
                }));
            if ((response.AccessRights & AccessRights.ReadAccess) != AccessRights.ReadAccess)
                throw new OperationError("CALLER_READ_ACCESS_REQUIRED");
        }

        private void SetCreateCandidateStage(string stage)
        {
            if (action == "CreateCandidate") stageChanged(stage);
        }

        private Guid Create(Entity row, string action, string mutation, string stage)
        {
            EnsureAllowedMutation(action, mutation);
            if (row.Id == Guid.Empty) row.Id = Guid.NewGuid();
            return ExecuteAtStage(stage, () => systemService.Create(row));
        }

        private static void EnsureAllowedMutation(string action, string mutation)
        {
            if (!CandidateOperation.AllowsMutation(action, mutation))
                throw new OperationError("UNSUPPORTED_MUTATION:" + action + ":" + mutation);
        }

        private T ExecuteAtStage<T>(string stage, Func<T> operation)
        {
            trace.Trace("CC_STAGE:{0}", stage);
            try
            {
                return operation();
            }
            catch (FaultException<OrganizationServiceFault> error)
            {
                var faultCode = "0x" + error.Detail.ErrorCode.ToString("X8", CultureInfo.InvariantCulture);
                trace.Trace("CC_SERVICE_FAULT:{0}:{1}", stage, faultCode);
                throw new OperationError("DATAVERSE_OPERATION_REJECTED:" + stage + ":" + faultCode, error);
            }
            catch (Exception error)
            {
                var category = ExceptionCategory(error);
                trace.Trace("CC_SERVICE_FAILURE:{0}:{1}", stage, category);
                throw new OperationError("CANDIDATE_CORE_FAILURE:" + stage + ":" + category, error);
            }
        }

        private static string ExceptionCategory(Exception error)
        {
            if (error is TimeoutException) return "TIMEOUT";
            if (error is InvalidPluginExecutionException) return "PLUGIN_EXECUTION";
            if (error is InvalidOperationException) return "INVALID_OPERATION";
            if (error is FaultException) return "SERVICE_FAULT";
            return "OTHER";
        }

        private static void SetProfile(Entity row, ActionRequest request)
        {
            var map = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["CandidateName"] = "os_sr_cand_nm", ["CandidateEmail"] = "os_sr_cand_eml",
                ["CandidatePhone"] = "os_sr_cand_phn", ["CandidateCvUrl"] = "os_sr_cand_cvurl",
                ["PositionId"] = "os_sr_cand_pos", ["CandidateSourceId"] = "os_sr_cand_csrc",
                ["AssignedTaId"] = "os_sr_cand_ta"
            };
            var lookupTables = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["PositionId"] = "os_sr_pos",
                ["CandidateSourceId"] = "os_sr_csrc",
                ["AssignedTaId"] = "os_sr_ta"
            };
            foreach (var pair in map)
            {
                if (!request.Values.TryGetValue(pair.Key, out var value)) continue;
                if (value is Guid id) row[pair.Value] = new EntityReference(lookupTables[pair.Key], id);
                else row[pair.Value] = value;
            }
        }

        public Guid CreateCandidate(ActionRequest request)
        {
            SetCreateCandidateStage("CANDIDATE_CREATE");
            EnsureAllowedMutation(request.Action, "CANDIDATE_CREATE");
            var row = new Entity("os_sr_cand");
            SetProfile(row, request);
            row["os_sr_cand_stat"] = new OptionSetValue(ActionRequest.NeedCall);
            row["os_sr_cand_corid"] = request.Correlation.ToString("D");
            row["ownerid"] = new EntityReference("systemuser", request.Actor);
            return Create(row, request.Action, "CANDIDATE_CREATE", "CC_CREATE_CANDIDATE");
        }

        public void UpdateCandidate(ActionRequest request, CandidateState candidate, int status)
        {
            EnsureAllowedMutation(request.Action, "CANDIDATE_UPDATE");
            var row = new Entity("os_sr_cand", candidate.Id) { RowVersion = candidate.RowVersion };
            if (request.Action == "UpdateCandidate") SetProfile(row, request);
            else row["os_sr_cand_stat"] = new OptionSetValue(status);
            ExecuteAtStage("CC_UPDATE_CANDIDATE",
                () => systemService.Execute(new UpdateRequest { Target = row, ConcurrencyBehavior = ConcurrencyBehavior.IfRowVersionMatches }));
        }

        public Guid CreateCall(ActionRequest request, Guid candidateId)
        {
            EnsureAllowedMutation(request.Action, "CALL_LOG_CREATE");
            var row = new Entity("os_sr_call");
            row["os_sr_call_cand"] = new EntityReference("os_sr_cand", candidateId);
            row["os_sr_call_out"] = new OptionSetValue((int)request.Values["CallOutcome"]!);
            row["os_sr_call_ctat"] = (DateTime)request.Values["ContactedAt"]!;
            row["os_sr_call_ctby"] = new EntityReference("systemuser", request.Actor);
            row["os_sr_call_corid"] = request.Correlation.ToString("D");
            row["ownerid"] = new EntityReference("systemuser", request.Actor);
            if (request.Values.TryGetValue("Notes", out var notes)) row["os_sr_call_nts"] = notes;
            return Create(row, request.Action, "CALL_LOG_CREATE", "CC_CREATE_CALL_LOG");
        }

        public Guid CreateHistory(ActionRequest request, Guid candidateId, int previous, int current)
        {
            EnsureAllowedMutation(request.Action, "STATUS_HISTORY_CREATE");
            var row = new Entity("os_sr_csh");
            row["os_sr_csh_cand"] = new EntityReference("os_sr_cand", candidateId);
            row["os_sr_csh_prevstat"] = new OptionSetValue(previous);
            row["os_sr_csh_newstat"] = new OptionSetValue(current);
            row["os_sr_csh_actr"] = new EntityReference("systemuser", request.Actor);
            row["os_sr_csh_chg"] = DateTime.UtcNow;
            row["os_sr_csh_corid"] = request.Correlation.ToString("D");
            row["os_sr_csh_cact"] = request.Action;
            row["ownerid"] = new EntityReference("systemuser", request.Actor);
            if (request.Values.TryGetValue("Reason", out var reason)) row["os_sr_csh_rsn"] = reason;
            return Create(row, request.Action, "STATUS_HISTORY_CREATE", "CC_CREATE_STATUS_HISTORY");
        }

        public InterviewScheduleState? GetCurrentRound1Schedule(Guid candidateId)
        {
            var query = new QueryExpression("os_sr_intv")
            {
                ColumnSet = new ColumnSet(false),
                TopCount = 2
            };
            query.Criteria.AddCondition("os_sr_intv_cand", ConditionOperator.Equal, candidateId);
            query.Criteria.AddCondition("os_sr_intv_rnd", ConditionOperator.Equal, ActionRequest.Round1);
            var active = new FilterExpression(LogicalOperator.Or);
            active.AddCondition("os_sr_intv_stat", ConditionOperator.Null);
            active.AddCondition("os_sr_intv_stat", ConditionOperator.Equal, ActionRequest.ScheduleActive);
            query.Criteria.AddFilter(active);
            return ReadUniqueSchedule(query, "ACTIVE_SCHEDULE_REQUIRED",
                new[] { ActionRequest.ScheduleActive });
        }

        public InterviewScheduleState? GetProposedRound1Schedule(Guid candidateId)
        {
            var query = new QueryExpression("os_sr_intv")
            {
                ColumnSet = new ColumnSet(false),
                TopCount = 2
            };
            query.Criteria.AddCondition("os_sr_intv_cand", ConditionOperator.Equal, candidateId);
            query.Criteria.AddCondition("os_sr_intv_rnd", ConditionOperator.Equal, ActionRequest.Round1);
            query.Criteria.AddCondition("os_sr_intv_stat", ConditionOperator.Equal, ActionRequest.ScheduleProposed);
            return ReadUniqueSchedule(query, "PROPOSED_SCHEDULE_AMBIGUOUS",
                new[] { ActionRequest.ScheduleProposed });
        }

        private static ColumnSet ScheduleColumns() => new ColumnSet(
            "os_sr_intv_cand", "os_sr_intv_rnd", "os_sr_intv_ta", "os_sr_intv_loc",
            "os_sr_intv_strt", "os_sr_intv_end", "os_sr_intv_nts", "os_sr_intv_stat",
            "os_sr_intv_res", "os_sr_intv_rsn", "os_sr_intv_chg", "versionnumber");

        private InterviewScheduleState? ReadUniqueSchedule(
            QueryExpression query, string ambiguityCode, int[] acceptedStatuses)
        {
            var identities = ExecuteAtStage("CC_READ_INTERVIEW_SCHEDULE_IDS",
                () => systemService.RetrieveMultiple(query)).Entities;
            if (identities.Count == 0) return null;
            foreach (var identity in identities)
            {
                if (identity.Id == Guid.Empty) throw new OperationError("SCHEDULE_INTEGRITY_FAILURE");
                EnsureCallerReadAccess(identity.ToEntityReference());
            }
            if (identities.Count > 1) throw new OperationError(ambiguityCode);
            var row = ExecuteAtStage("CC_READ_INTERVIEW_SCHEDULE",
                () => systemService.Retrieve("os_sr_intv", identities[0].Id, ScheduleColumns()));
            var result = row.GetAttributeValue<OptionSetValue>("os_sr_intv_res")?.Value;
            var status = row.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value;
            var candidate = row.GetAttributeValue<EntityReference>("os_sr_intv_cand");
            var interviewer = row.GetAttributeValue<EntityReference>("os_sr_intv_ta");
            var location = row.GetAttributeValue<EntityReference>("os_sr_intv_loc");
            if (row.Id == Guid.Empty || candidate == null || candidate.LogicalName != "os_sr_cand" ||
                interviewer == null || interviewer.LogicalName != "os_sr_ta" ||
                location == null || location.LogicalName != "os_sr_loc" ||
                row.GetAttributeValue<OptionSetValue>("os_sr_intv_rnd")?.Value != ActionRequest.Round1 ||
                !row.Contains("os_sr_intv_strt") || !row.Contains("os_sr_intv_end") ||
                (status.HasValue && !acceptedStatuses.Contains(status.Value)) ||
                (result.HasValue && result.Value != ActionRequest.ResultPending &&
                    result.Value != ActionRequest.ResultPass && result.Value != ActionRequest.ResultFail))
                throw new OperationError("SCHEDULE_INTEGRITY_FAILURE");
            return new InterviewScheduleState
            {
                Id = row.Id,
                CandidateId = candidate.Id,
                InterviewerId = interviewer.Id,
                LocationId = location.Id,
                StartAt = row.GetAttributeValue<DateTime>("os_sr_intv_strt"),
                EndAt = row.GetAttributeValue<DateTime>("os_sr_intv_end"),
                Notes = row.GetAttributeValue<string>("os_sr_intv_nts") ?? "",
                Reason = row.GetAttributeValue<string>("os_sr_intv_rsn") ?? "",
                ChangedAt = row.Contains("os_sr_intv_chg")
                    ? row.GetAttributeValue<DateTime>("os_sr_intv_chg") : (DateTime?)null,
                Status = status,
                Result = result,
                RowVersion = row.RowVersion
            };
        }

        public InterviewScheduleState CreateRound1Schedule(
            ActionRequest request, Guid candidateId, int scheduleStatus)
        {
            EnsureAllowedMutation(request.Action, "INTERVIEW_SCHEDULE_CREATE");
            if (request.Action != "MarkRound1Scheduled" && request.Action != "RequestReschedule")
                throw new OperationError("UNSUPPORTED_MUTATION:" + request.Action + ":INTERVIEW_SCHEDULE_CREATE");
            if (scheduleStatus != ActionRequest.ScheduleActive &&
                !(request.Action == "RequestReschedule" && scheduleStatus == ActionRequest.ScheduleProposed))
                throw new OperationError("UNSUPPORTED_SCHEDULE_STATE");

            var row = new Entity("os_sr_intv");
            SetScheduleInputs(row, request, candidateId);
            row["os_sr_intv_stat"] = new OptionSetValue(scheduleStatus);
            row["os_sr_intv_res"] = new OptionSetValue(ActionRequest.ResultPending);
            row["ownerid"] = new EntityReference("systemuser", request.Actor);
            var id = Create(row, request.Action, "INTERVIEW_SCHEDULE_CREATE", "CC_CREATE_INTERVIEW_SCHEDULE");
            return ReadBackSchedule(request, id, candidateId, scheduleStatus);
        }

        public InterviewScheduleState UpdateRound1Schedule(
            ActionRequest request, InterviewScheduleState schedule, int scheduleStatus)
        {
            EnsureAllowedMutation(request.Action, "INTERVIEW_SCHEDULE_UPDATE");
            if (schedule.Id == Guid.Empty || schedule.CandidateId == Guid.Empty ||
                string.IsNullOrEmpty(schedule.RowVersion))
                throw new OperationError("ROW_VERSION_UNAVAILABLE");

            var row = new Entity("os_sr_intv", schedule.Id) { RowVersion = schedule.RowVersion };
            row["os_sr_intv_stat"] = new OptionSetValue(scheduleStatus);
            if (request.Action == "MarkRound1Scheduled" &&
                schedule.Status == ActionRequest.ScheduleProposed &&
                scheduleStatus == ActionRequest.ScheduleActive)
            {
                SetScheduleInputs(row, request, schedule.CandidateId);
            }
            else if (request.Action == "RequestReschedule" &&
                scheduleStatus == ActionRequest.ScheduleSuperseded)
            {
                row["os_sr_intv_rsn"] = request.Values["Reason"];
                row["os_sr_intv_chg"] = DateTime.UtcNow;
            }
            else if (request.Action == "CancelRound1" &&
                scheduleStatus == ActionRequest.ScheduleCancelled)
            {
                row["os_sr_intv_rsn"] = request.Values["Reason"];
                row["os_sr_intv_chg"] = DateTime.UtcNow;
            }
            else
            {
                throw new OperationError("UNSUPPORTED_SCHEDULE_STATE");
            }

            ExecuteAtStage("CC_UPDATE_INTERVIEW_SCHEDULE",
                () => systemService.Execute(new UpdateRequest
                {
                    Target = row,
                    ConcurrencyBehavior = ConcurrencyBehavior.IfRowVersionMatches
                }));
            return ReadBackSchedule(request, schedule.Id, schedule.CandidateId, scheduleStatus);
        }

        private static void SetScheduleInputs(Entity row, ActionRequest request, Guid candidateId)
        {
            row["os_sr_intv_cand"] = new EntityReference("os_sr_cand", candidateId);
            row["os_sr_intv_rnd"] = new OptionSetValue(ActionRequest.Round1);
            row["os_sr_intv_ta"] = new EntityReference("os_sr_ta", (Guid)request.Values["InterviewerId"]!);
            row["os_sr_intv_loc"] = new EntityReference("os_sr_loc", (Guid)request.Values["LocationId"]!);
            row["os_sr_intv_strt"] = (DateTime)request.Values["StartAt"]!;
            row["os_sr_intv_end"] = (DateTime)request.Values["EndAt"]!;
            if (request.Values.TryGetValue("Notes", out var notes))
                row["os_sr_intv_nts"] = notes;
        }

        private InterviewScheduleState ReadBackSchedule(
            ActionRequest request, Guid id, Guid candidateId, int expectedStatus)
        {
            EnsureCallerReadAccess(new EntityReference("os_sr_intv", id));
            var row = ExecuteAtStage("CC_VERIFY_INTERVIEW_SCHEDULE",
                () => systemService.Retrieve("os_sr_intv", id, ScheduleColumns()));
            if (row.Id != id || row.GetAttributeValue<EntityReference>("os_sr_intv_cand")?.Id != candidateId ||
                row.GetAttributeValue<OptionSetValue>("os_sr_intv_rnd")?.Value != ActionRequest.Round1 ||
                row.GetAttributeValue<OptionSetValue>("os_sr_intv_stat")?.Value != expectedStatus)
                throw new OperationError("SCHEDULE_PERSISTENCE_NOT_CONFIRMED");

            var state = new InterviewScheduleState
            {
                Id = row.Id,
                CandidateId = candidateId,
                InterviewerId = row.GetAttributeValue<EntityReference>("os_sr_intv_ta")?.Id ?? Guid.Empty,
                LocationId = row.GetAttributeValue<EntityReference>("os_sr_intv_loc")?.Id ?? Guid.Empty,
                StartAt = row.GetAttributeValue<DateTime>("os_sr_intv_strt"),
                EndAt = row.GetAttributeValue<DateTime>("os_sr_intv_end"),
                Notes = row.GetAttributeValue<string>("os_sr_intv_nts") ?? "",
                Reason = row.GetAttributeValue<string>("os_sr_intv_rsn") ?? "",
                ChangedAt = row.Contains("os_sr_intv_chg")
                    ? row.GetAttributeValue<DateTime>("os_sr_intv_chg") : (DateTime?)null,
                Status = expectedStatus,
                Result = row.GetAttributeValue<OptionSetValue>("os_sr_intv_res")?.Value,
                RowVersion = row.RowVersion
            };
            if (state.InterviewerId == Guid.Empty || state.LocationId == Guid.Empty ||
                !row.Contains("os_sr_intv_strt") || !row.Contains("os_sr_intv_end"))
                throw new OperationError("SCHEDULE_PERSISTENCE_NOT_CONFIRMED");
            if ((request.Action == "RequestReschedule" && expectedStatus == ActionRequest.ScheduleSuperseded) ||
                (request.Action == "CancelRound1" && expectedStatus == ActionRequest.ScheduleCancelled))
            {
                if (!string.Equals(state.Reason, (string)request.Values["Reason"]!, StringComparison.Ordinal) ||
                    !state.ChangedAt.HasValue)
                    throw new OperationError("SCHEDULE_PERSISTENCE_NOT_CONFIRMED");
            }
            if (request.Action == "MarkRound1Scheduled" ||
                (request.Action == "RequestReschedule" && expectedStatus == ActionRequest.ScheduleProposed))
            {
                if (state.InterviewerId != (Guid)request.Values["InterviewerId"]! ||
                    state.LocationId != (Guid)request.Values["LocationId"]! ||
                    state.StartAt != (DateTime)request.Values["StartAt"]! ||
                    state.EndAt != (DateTime)request.Values["EndAt"]! ||
                    (request.Values.TryGetValue("Notes", out var notes) &&
                        !string.Equals(state.Notes, (string?)notes ?? "", StringComparison.Ordinal)))
                    throw new OperationError("SCHEDULE_PERSISTENCE_NOT_CONFIRMED");
            }
            return state;
        }

        public void RecordRound1Result(ActionRequest request, InterviewScheduleState schedule, int result)
        {
            EnsureAllowedMutation(request.Action, "INTERVIEW_SCHEDULE_UPDATE");
            if (schedule.Id == Guid.Empty || string.IsNullOrEmpty(schedule.RowVersion))
                throw new OperationError("ROW_VERSION_UNAVAILABLE");
            if (result != ActionRequest.ResultPass && result != ActionRequest.ResultFail)
                throw new OperationError("UNSUPPORTED_INTERVIEW_RESULT");
            var row = new Entity("os_sr_intv", schedule.Id) { RowVersion = schedule.RowVersion };
            row["os_sr_intv_res"] = new OptionSetValue(result);
            row["os_sr_intv_recat"] = DateTime.UtcNow;
            row["os_sr_intv_rnts"] = request.Values.TryGetValue("ResultNotes", out var notes) ? notes : null;
            ExecuteAtStage("CC_UPDATE_INTERVIEW_SCHEDULE",
                () => systemService.Execute(new UpdateRequest
                {
                    Target = row,
                    ConcurrencyBehavior = ConcurrencyBehavior.IfRowVersionMatches
                }));
        }

        public void CreateReceipt(ActionRequest request, ActionResult result)
        {
            SetCreateCandidateStage("RECEIPT_CREATE");
            EnsureAllowedMutation(request.Action, "RECEIPT_CREATE");
            var row = new Entity("os_sr_oprc");
            row["os_sr_oprc_nm"] = request.Correlation.ToString("D");
            row["os_sr_oprc_corid"] = request.Correlation.ToString("D");
            row["os_sr_oprc_cact"] = request.Action;
            row["os_sr_oprc_hash"] = request.Fingerprint;
            row["os_sr_oprc_ver"] = "1";
            row["os_sr_oprc_cand"] = new EntityReference("os_sr_cand", result.CandidateId);
            row["os_sr_oprc_newstat"] = result.Current;
            if (result.Previous.HasValue) row["os_sr_oprc_prevstat"] = result.Previous.Value;
            if (result.CallId.HasValue) row["os_sr_oprc_callref"] = result.CallId.Value.ToString("D");
            if (result.HistoryId.HasValue) row["os_sr_oprc_histref"] = result.HistoryId.Value.ToString("D");
            Create(row, request.Action, "RECEIPT_CREATE", "CC_CREATE_RECEIPT");
        }
    }

    // Superseded as the production security boundary; retained for inactive historical registrations.
    public sealed class ProtectCandidateCore : IPlugin
    {
        private const int MaximumParentContexts = 8;
        internal static readonly string[] DiagnosticWriteCodes = { "CANDIDATE_CREATE", "CANDIDATE_UPDATE",
            "CALL_LOG_CREATE", "STATUS_HISTORY_CREATE", "RECEIPT_CREATE" };
        private static readonly string[] ProjectTables = { "os_sr_cand", "os_sr_call", "os_sr_csh", "os_sr_oprc" };
        private static readonly string[] ProjectRelationships = { "os_sr_pos_cand", "os_sr_csrc_cand", "os_sr_ta_cand",
            "os_sr_cand_call", "os_sr_cand_csh", "os_sr_usr_call_ctby", "os_sr_usr_csh_actr", "os_sr_cand_oprc" };

        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var trace = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
            if (context.MessageName == "Associate" || context.MessageName == "Disassociate")
            {
                var relationship = context.InputParameters.Contains("Relationship") ? context.InputParameters["Relationship"] as Relationship : null;
                var targetReference = context.InputParameters.Contains("Target") ? context.InputParameters["Target"] as EntityReference : null;
                var related = context.InputParameters.Contains("RelatedEntities") ? context.InputParameters["RelatedEntities"] as EntityReferenceCollection : null;
                if (relationship != null && ProjectRelationships.Contains(relationship.SchemaName, StringComparer.OrdinalIgnoreCase))
                    throw Rejection(trace, "ASSOCIATION_PROJECT_RELATIONSHIP");
                if (targetReference != null && ProjectTables.Contains(targetReference.LogicalName, StringComparer.OrdinalIgnoreCase))
                    throw Rejection(trace, "ASSOCIATION_PROJECT_TABLE");
                if (related != null && related.Any(reference => ProjectTables.Contains(reference.LogicalName, StringComparer.OrdinalIgnoreCase)))
                    throw Rejection(trace, "ASSOCIATION_CONTAINS_PROJECT_TABLE");
                return;
            }
            var operation = RegisteredWriteCode(context.MessageName, context.PrimaryEntityName);
            if (operation == null)
                throw Rejection(trace, "UNSUPPORTED_PROTECTED_WRITE");
            if (context.Stage != 10 || context.Mode != 0 || !context.IsInTransaction ||
                context.Depth <= 1 || context.ParentContext == null)
                throw Rejection(trace, operation + ":PARENT_CONTEXT");
            if (context.UserId != context.InitiatingUserId)
                throw Rejection(trace, operation + ":CALLER_CONTEXT");
            if (!HasTrustedAncestor(context, operation, trace, out var searched, out var failure))
            {
                trace.Trace("CC_GUARD_TRUSTED_PARENT_NOT_FOUND:ANCESTOR_HOPS:{0}", searched);
                throw Rejection(trace, operation + ":TRUSTED_PARENT:" + failure);
            }
            trace.Trace("CC_GUARD_TRUSTED_PARENT_FOUND:ANCESTOR_HOPS:{0}", searched);
            trace.Trace("CC_GUARD_ALLOWED:{0}", operation);
        }

        private static string? RegisteredWriteCode(string messageName, string entityName)
        {
            if (messageName == "Create" && entityName == "os_sr_cand") return "CANDIDATE_CREATE";
            if (messageName == "Update" && entityName == "os_sr_cand") return "CANDIDATE_UPDATE";
            if (messageName == "Create" && entityName == "os_sr_call") return "CALL_LOG_CREATE";
            if (messageName == "Create" && entityName == "os_sr_csh") return "STATUS_HISTORY_CREATE";
            if (messageName == "Create" && entityName == "os_sr_oprc") return "RECEIPT_CREATE";
            if (messageName == "Update" && entityName == "os_sr_oprc") return "RECEIPT_UPDATE";
            return null;
        }

        private static bool HasTrustedAncestor(
            IPluginExecutionContext context, string operation, ITracingService trace,
            out int searched, out string failure)
        {
            var ancestor = context.ParentContext;
            searched = 0;
            failure = "PARENT_CONTEXT";
            while (ancestor != null && searched < MaximumParentContexts)
            {
                searched++;
                var predicate = TrustedParentFailure(ancestor, context, operation);
                trace.Trace("CC_GUARD_ANCESTOR:HOP:{0}:PREDICATE:{1}", searched, predicate ?? "TRUSTED");
                if (predicate == null) return true;
                if (searched == 1) failure = predicate;
                ancestor = ancestor.ParentContext;
            }
            if (ancestor != null) failure = "ANCESTOR_BOUND_EXCEEDED";
            return false;
        }

        private static string? TrustedParentFailure(
            IPluginExecutionContext ancestor, IPluginExecutionContext context, string operation)
        {
            if (ancestor.MessageName != "os_sr_cact") return "API_MESSAGE_MISMATCH";
            if (ancestor.Stage != 30) return "STAGE_MISMATCH";
            if (ancestor.Mode != 0) return "MODE_MISMATCH";
            if (!ancestor.IsInTransaction) return "TRANSACTION_MISMATCH";
            if (!(ancestor.Depth > 0 && ancestor.Depth < context.Depth)) return "DEPTH_MISMATCH";
            if (ancestor.UserId != context.UserId) return "USER_CONTEXT_MISMATCH";
            if (ancestor.InitiatingUserId != context.InitiatingUserId) return "INITIATING_USER_MISMATCH";
            if (!ancestor.InputParameters.TryGetValue("ActionType", out var action) || action == null)
                return "ACTIONTYPE_MISSING";
            if (!IsActionForOperation(ancestor, operation)) return "ACTIONTYPE_MISMATCH";
            return null;
        }

        private static bool IsActionForOperation(IPluginExecutionContext context, string operation)
        {
            if (!context.InputParameters.TryGetValue("ActionType", out var value) ||
                !(value is string action) || !ActionRequest.IsSupportedAction(action))
                return false;
            if (operation == "CANDIDATE_CREATE") return action == "CreateCandidate";
            if (operation == "CALL_LOG_CREATE") return action == "RecordCall";
            if (operation == "CANDIDATE_UPDATE")
                return action == "UpdateCandidate" || action == "RecordCall" || action == "ProceedToScheduling";
            if (operation == "STATUS_HISTORY_CREATE")
                return action == "RecordCall" || action == "ProceedToScheduling";
            return operation == "RECEIPT_CREATE" &&
                (action == "CreateCandidate" || action == "UpdateCandidate" ||
                 action == "RecordCall" || action == "ProceedToScheduling");
        }

        private static InvalidPluginExecutionException Rejection(ITracingService trace, string category)
        {
            var diagnostic = "DIRECT_WRITE_GUARD_REJECTED:" + category;
            trace.Trace("CC_GUARD_REJECTED:{0}", category);
            return new InvalidPluginExecutionException(diagnostic);
        }

    }
}
