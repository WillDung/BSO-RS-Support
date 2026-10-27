using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.ServiceModel;
using System.Text;
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
                var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
                var service = factory.CreateOrganizationService(context.InitiatingUserId);
                var request = CandidateActionInputAdapter.Create(context.InitiatingUserId, context.InputParameters, DateTime.UtcNow);
                var result = CandidateOperation.Execute(request, new DataverseStore(service, context, trace));
                context.OutputParameters["ResultCode"] = result.Replay ? "DuplicateReplay" : "Applied";
                if (result.Previous.HasValue) context.OutputParameters["PreviousStatus"] = result.Previous.Value;
                context.OutputParameters["CurrentStatus"] = result.Current;
                if (result.CallId.HasValue) context.OutputParameters["CallLogId"] = result.CallId.Value;
                if (result.HistoryId.HasValue) context.OutputParameters["StatusHistoryId"] = result.HistoryId.Value;
                trace.Trace("os_sr_cact result={0} action={1}", result.Replay ? "DuplicateReplay" : "Applied", request.Action);
            }
            catch (OperationError error)
            {
                trace.Trace("os_sr_cact rejected code={0}", error.Message);
                throw new InvalidPluginExecutionException(error.Message, error);
            }
            catch (FaultException<OrganizationServiceFault> error)
            {
                trace.Trace("os_sr_cact Dataverse fault code={0}", error.Detail.ErrorCode);
                // Do not swallow a service fault or issue another service call inside a failed transaction.
                string code = error.Detail.ErrorCode == unchecked((int)0x80040237) ? "CORRELATION_OR_KEY_CONFLICT" :
                    error.Detail.ErrorCode == unchecked((int)0x80060882) ? "ROW_VERSION_CONFLICT" : "DATAVERSE_OPERATION_REJECTED";
                throw new InvalidPluginExecutionException(code);
            }
        }
    }

    internal static class DevCandidateSlice
    {
        public const string MessageName = "os_sr_devcs";

        private static readonly HashSet<string> DeclaredInputs = new HashSet<string>(StringComparer.Ordinal)
        {
            "ActionType", "CorrelationId", "CandidateId", "ExpectedStatus", "CandidateName",
            "CandidateEmail", "CandidatePhone", "PositionId", "CandidateSourceId", "CallOutcome",
            "ContactedAt", "Notes"
        };

        public static void Execute(
            IServiceProvider serviceProvider, IPluginExecutionContext context, ITracingService trace)
        {
            if (context.Stage != 30 || context.Mode != 0 || !context.IsInTransaction ||
                context.UserId != context.InitiatingUserId || context.Depth != 1)
                throw new OperationError("UNSUPPORTED_EXECUTION_CONTEXT");

            var action = ReadRequiredString(context.InputParameters, "ActionType");
            if (action != "CreateCandidate" && action != "RecordCall")
                throw new OperationError("DEV_ACTION_NOT_SUPPORTED");

            foreach (var parameter in context.InputParameters)
            {
                if (!DeclaredInputs.Contains(parameter.Key))
                    throw new OperationError("UNEXPECTED_INPUT:DEV_SLICE");
                if (!ActionRequest.ApplicableInputNames(action).Contains(parameter.Key) &&
                    parameter.Value != null)
                    throw new OperationError("UNEXPECTED_INPUT:DEV_SLICE");
            }

            var input = new Dictionary<string, object?>(StringComparer.Ordinal)
            {
                ["ActionType"] = action,
                ["CorrelationId"] = ParseGuid(ReadRequiredString(context.InputParameters, "CorrelationId"),
                    "INVALID_CORRELATION")
            };

            if (action == "CreateCandidate")
            {
                var name = ReadRequiredString(context.InputParameters, "CandidateName").Trim();
                var email = ReadRequiredString(context.InputParameters, "CandidateEmail").Trim();
                RequireSyntheticProfile(name, email);
                input["CandidateName"] = name;
                input["CandidateEmail"] = email;
                input["CandidatePhone"] = ReadOptionalString(context.InputParameters, "CandidatePhone");
                input["PositionId"] = ReadOptionalGuid(context.InputParameters, "PositionId");
                input["CandidateSourceId"] = ReadOptionalGuid(context.InputParameters, "CandidateSourceId");
            }
            else
            {
                var candidateId = ParseGuid(ReadRequiredString(context.InputParameters, "CandidateId"),
                    "INVALID_CANDIDATE");
                input["CandidateId"] = candidateId;
                input["ExpectedStatus"] = ReadRequiredInt(context.InputParameters, "ExpectedStatus");
                input["CallOutcome"] = ReadRequiredInt(context.InputParameters, "CallOutcome");
                input["ContactedAt"] = ParseUtcDateTime(
                    ReadRequiredString(context.InputParameters, "ContactedAt"));
                input["Notes"] = ReadOptionalString(context.InputParameters, "Notes");

                var factory = (IOrganizationServiceFactory)serviceProvider.GetService(
                    typeof(IOrganizationServiceFactory));
                var service = factory.CreateOrganizationService(context.InitiatingUserId);
                var candidate = service.Retrieve("os_sr_cand", candidateId,
                    new ColumnSet("os_sr_cand_nm", "os_sr_cand_eml"));
                RequireSyntheticProfile(
                    candidate.GetAttributeValue<string>("os_sr_cand_nm"),
                    candidate.GetAttributeValue<string>("os_sr_cand_eml"));

                var result = CandidateOperation.Execute(
                    new ActionRequest(context.InitiatingUserId, input, DateTime.UtcNow),
                    new DataverseStore(service, context, trace));
                WriteResult(context, result);
                return;
            }

            var organizationServiceFactory = (IOrganizationServiceFactory)serviceProvider.GetService(
                typeof(IOrganizationServiceFactory));
            var organizationService = organizationServiceFactory.CreateOrganizationService(context.InitiatingUserId);
            var createResult = CandidateOperation.Execute(
                new ActionRequest(context.InitiatingUserId, input, DateTime.UtcNow),
                new DataverseStore(organizationService, context, trace));
            WriteResult(context, createResult);
        }

        private static void WriteResult(IPluginExecutionContext context, ActionResult result)
        {
            context.OutputParameters["ResultCode"] = result.Replay ? "DuplicateReplay" : "Applied";
            context.OutputParameters["CandidateId"] = result.CandidateId.ToString("D");
        }

        private static string ReadRequiredString(ParameterCollection parameters, string name)
        {
            if (!parameters.TryGetValue(name, out var value) || !(value is string text) ||
                string.IsNullOrWhiteSpace(text))
                throw new OperationError("INVALID_" + name.ToUpperInvariant());
            return text;
        }

        private static string? ReadOptionalString(ParameterCollection parameters, string name)
        {
            if (!parameters.TryGetValue(name, out var value) || value == null) return null;
            if (!(value is string text)) throw new OperationError("INVALID_TEXT");
            return text;
        }

        private static int ReadRequiredInt(ParameterCollection parameters, string name)
        {
            if (!parameters.TryGetValue(name, out var value) || !(value is int number))
                throw new OperationError("INVALID_" + name.ToUpperInvariant());
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
            return ParseGuid(value, "INVALID_GUID_PARAMETER:" + name);
        }

        private static DateTime ParseUtcDateTime(string value)
        {
            if (!DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None,
                out var timestamp) || timestamp.Offset != TimeSpan.Zero)
                throw new OperationError("INVALID_CONTACT_TIME");
            return timestamp.UtcDateTime;
        }

        private static void RequireSyntheticProfile(string name, string email)
        {
            var at = email.LastIndexOf('@');
            if (!name.StartsWith("[SYNTHETIC-E2E]", StringComparison.Ordinal) ||
                at <= 0 || at == email.Length - 1 ||
                email.IndexOfAny(new[] { ' ', '\t', '\r', '\n' }) >= 0 ||
                !email.Substring(at + 1).EndsWith(".invalid", StringComparison.OrdinalIgnoreCase))
                throw new OperationError("DEV_SYNTHETIC_DATA_REQUIRED");
        }
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
                    if (parameters.TryGetValue(name, out var value)) input[name] = value;
                }
            }

            return new ActionRequest(actor, input, utcNow);
        }
    }

    internal sealed class DataverseStore : IOperationStore
    {
        private readonly IOrganizationService service;
        private readonly IPluginExecutionContext context;
        private readonly ITracingService trace;
        private static readonly string[] GuardDiagnostics =
        {
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:PARENT_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:CALLER_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_UPDATE:PARENT_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_UPDATE:CALLER_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:CALL_LOG_CREATE:PARENT_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:CALL_LOG_CREATE:CALLER_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:STATUS_HISTORY_CREATE:PARENT_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:STATUS_HISTORY_CREATE:CALLER_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:RECEIPT_CREATE:PARENT_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:RECEIPT_CREATE:CALLER_CONTEXT",
            "DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE",
            "DIRECT_WRITE_GUARD_REJECTED:LEGACY_GENERIC_GUARD"
        };

        public DataverseStore(IOrganizationService service, IPluginExecutionContext context, ITracingService trace)
        {
            this.service = service;
            this.context = context;
            this.trace = trace;
        }

        public void RequireTransaction()
        {
            if (!context.IsInTransaction || context.UserId != context.InitiatingUserId)
                throw new OperationError("UNSUPPORTED_EXECUTION_CONTEXT");
        }

        public Receipt? FindReceipt(Guid correlation)
        {
            var query = new QueryExpression("os_sr_oprc")
            {
                ColumnSet = new ColumnSet("createdby", "ownerid", "os_sr_oprc_cand", "os_sr_oprc_cact", "os_sr_oprc_hash",
                    "os_sr_oprc_ver", "os_sr_oprc_prevstat", "os_sr_oprc_newstat", "os_sr_oprc_callref", "os_sr_oprc_histref"),
                TopCount = 2
            };
            query.Criteria.AddCondition("os_sr_oprc_corid", ConditionOperator.Equal, correlation.ToString("D"));
            var rows = ExecuteAtStage("CC_READ_RECEIPT", () => service.RetrieveMultiple(query)).Entities;
            if (rows.Count == 0) return null;
            if (rows.Count != 1) throw new OperationError("RECEIPT_INTEGRITY_FAILURE");
            var row = rows[0];
            var actor = row.GetAttributeValue<EntityReference>("createdby");
            var owner = row.GetAttributeValue<EntityReference>("ownerid");
            var candidate = row.GetAttributeValue<EntityReference>("os_sr_oprc_cand");
            if (actor == null || owner == null || owner.LogicalName != "systemuser" || actor.Id != owner.Id || candidate == null ||
                !row.Contains("os_sr_oprc_newstat") || string.IsNullOrEmpty(row.GetAttributeValue<string>("os_sr_oprc_hash")))
                throw new OperationError("RECEIPT_INTEGRITY_FAILURE");
            return new Receipt
            {
                Actor = actor.Id,
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
            var row = ExecuteAtStage("CC_READ_CANDIDATE",
                () => service.Retrieve("os_sr_cand", id, new ColumnSet("os_sr_cand_stat", "versionnumber")));
            if (!row.Contains("os_sr_cand_stat")) throw new OperationError("CANDIDATE_INTEGRITY_FAILURE");
            int status = row.GetAttributeValue<OptionSetValue>("os_sr_cand_stat").Value;
            if (status < ActionRequest.NeedCall || status > ActionRequest.Failed) throw new OperationError("INVALID_CANDIDATE_STATUS");
            return new CandidateState { Id = id, Status = status, RowVersion = row.RowVersion };
        }

        private Guid Create(Entity row, string stage)
        {
            if (row.Id == Guid.Empty) row.Id = Guid.NewGuid();
            return ExecuteAtStage(stage, () => service.Create(row));
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
                var guardDiagnostic = FindGuardDiagnostic(error.Detail.Message);
                var code = guardDiagnostic == null
                    ? "DATAVERSE_OPERATION_REJECTED:" + stage + ":" + faultCode
                    : guardDiagnostic + ":" + stage + ":" + faultCode;
                throw new OperationError(code, error);
            }
            catch (Exception error)
            {
                var guardDiagnostic = FindGuardDiagnostic(error.Message);
                var category = ExceptionCategory(error);
                trace.Trace("CC_SERVICE_FAILURE:{0}:{1}", stage, category);
                var code = guardDiagnostic == null
                    ? "CANDIDATE_CORE_FAILURE:" + stage + ":" + category
                    : guardDiagnostic + ":" + stage;
                throw new OperationError(code, error);
            }
        }

        private static string? FindGuardDiagnostic(string message)
        {
            if (message == null) return null;
            var normalized = message.Trim();
            var predicates = new[] { "API_MESSAGE_MISMATCH", "STAGE_MISMATCH", "MODE_MISMATCH",
                "TRANSACTION_MISMATCH", "DEPTH_MISMATCH", "USER_CONTEXT_MISMATCH", "INITIATING_USER_MISMATCH",
                "ACTIONTYPE_MISSING", "ACTIONTYPE_MISMATCH", "ANCESTOR_BOUND_EXCEEDED" };
            foreach (var operation in ProtectCandidateCore.DiagnosticWriteCodes)
                foreach (var predicate in predicates)
                {
                    var diagnostic = "DIRECT_WRITE_GUARD_REJECTED:" + operation + ":TRUSTED_PARENT:" + predicate;
                    if (normalized == diagnostic) return diagnostic;
                }
            var guardDiagnostic = GuardDiagnostics.FirstOrDefault(diagnostic =>
                string.Equals(normalized, diagnostic, StringComparison.Ordinal));
            if (guardDiagnostic != null) return guardDiagnostic;
            return string.Equals(normalized, "DIRECT_CANDIDATE_CORE_WRITE_BLOCKED", StringComparison.Ordinal)
                ? "DIRECT_WRITE_GUARD_REJECTED:LEGACY_GENERIC_GUARD"
                : null;
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
                ["CandidatePhone"] = "os_sr_cand_phn", ["PositionId"] = "os_sr_cand_pos",
                ["CandidateSourceId"] = "os_sr_cand_csrc"
            };
            foreach (var pair in map)
            {
                if (!request.Values.TryGetValue(pair.Key, out var value)) continue;
                if (value is Guid id) row[pair.Value] = new EntityReference(pair.Key == "PositionId" ? "os_sr_pos" : "os_sr_csrc", id);
                else row[pair.Value] = value;
            }
        }

        public Guid CreateCandidate(ActionRequest request)
        {
            var row = new Entity("os_sr_cand");
            SetProfile(row, request);
            row["os_sr_cand_stat"] = new OptionSetValue(ActionRequest.NeedCall);
            row["os_sr_cand_corid"] = request.Correlation.ToString("D");
            row["ownerid"] = new EntityReference("systemuser", request.Actor);
            return Create(row, "CC_CREATE_CANDIDATE");
        }

        public void UpdateCandidate(ActionRequest request, CandidateState candidate, int status)
        {
            var row = new Entity("os_sr_cand", candidate.Id) { RowVersion = candidate.RowVersion };
            if (request.Action == "UpdateCandidate") SetProfile(row, request);
            else row["os_sr_cand_stat"] = new OptionSetValue(status);
            ExecuteAtStage("CC_UPDATE_CANDIDATE",
                () => service.Execute(new UpdateRequest { Target = row, ConcurrencyBehavior = ConcurrencyBehavior.IfRowVersionMatches }));
        }

        public Guid CreateCall(ActionRequest request, Guid candidateId)
        {
            var row = new Entity("os_sr_call");
            row["os_sr_call_cand"] = new EntityReference("os_sr_cand", candidateId);
            row["os_sr_call_out"] = new OptionSetValue((int)request.Values["CallOutcome"]!);
            row["os_sr_call_ctat"] = (DateTime)request.Values["ContactedAt"]!;
            row["os_sr_call_ctby"] = new EntityReference("systemuser", request.Actor);
            row["os_sr_call_corid"] = request.Correlation.ToString("D");
            row["ownerid"] = new EntityReference("systemuser", request.Actor);
            if (request.Values.TryGetValue("Notes", out var notes)) row["os_sr_call_nts"] = notes;
            return Create(row, "CC_CREATE_CALL_LOG");
        }

        public Guid CreateHistory(ActionRequest request, Guid candidateId, int previous, int current)
        {
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
            return Create(row, "CC_CREATE_STATUS_HISTORY");
        }

        public void CreateReceipt(ActionRequest request, ActionResult result)
        {
            var row = new Entity("os_sr_oprc");
            row["os_sr_oprc_nm"] = request.Correlation.ToString("D");
            row["os_sr_oprc_corid"] = request.Correlation.ToString("D");
            row["os_sr_oprc_cact"] = request.Action;
            row["os_sr_oprc_hash"] = request.Fingerprint;
            row["os_sr_oprc_ver"] = "1";
            row["os_sr_oprc_cand"] = new EntityReference("os_sr_cand", result.CandidateId);
            row["os_sr_oprc_newstat"] = result.Current;
            row["ownerid"] = new EntityReference("systemuser", request.Actor);
            if (result.Previous.HasValue) row["os_sr_oprc_prevstat"] = result.Previous.Value;
            if (result.CallId.HasValue) row["os_sr_oprc_callref"] = result.CallId.Value.ToString("D");
            if (result.HistoryId.HasValue) row["os_sr_oprc_histref"] = result.HistoryId.Value.ToString("D");
            Create(row, "CC_CREATE_RECEIPT");
        }
    }

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
