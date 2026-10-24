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
                if (context.MessageName != "os_sr_cact" || context.Stage != 30 || context.Mode != 0 ||
                    !context.IsInTransaction || context.UserId != context.InitiatingUserId || context.Depth != 1)
                    throw new OperationError("UNSUPPORTED_EXECUTION_CONTEXT");
                var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
                var service = factory.CreateOrganizationService(context.InitiatingUserId);
                var input = context.InputParameters.ToDictionary(pair => pair.Key, pair => (object?)pair.Value, StringComparer.Ordinal);
                var request = new ActionRequest(context.InitiatingUserId, input, DateTime.UtcNow);
                var result = CandidateOperation.Execute(request, new DataverseStore(service, context));
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
                throw new InvalidPluginExecutionException(error.Message);
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

    internal sealed class DataverseStore : IOperationStore
    {
        private readonly IOrganizationService service;
        private readonly IPluginExecutionContext context;
        public DataverseStore(IOrganizationService service, IPluginExecutionContext context)
        {
            this.service = service;
            this.context = context;
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
            var rows = service.RetrieveMultiple(query).Entities;
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
            var row = service.Retrieve("os_sr_cand", id, new ColumnSet("os_sr_cand_stat", "versionnumber"));
            if (!row.Contains("os_sr_cand_stat")) throw new OperationError("CANDIDATE_INTEGRITY_FAILURE");
            int status = row.GetAttributeValue<OptionSetValue>("os_sr_cand_stat").Value;
            if (status < ActionRequest.NeedCall || status > ActionRequest.Failed) throw new OperationError("INVALID_CANDIDATE_STATUS");
            return new CandidateState { Id = id, Status = status, RowVersion = row.RowVersion };
        }

        private Guid Create(Entity row)
        {
            if (row.Id == Guid.Empty) row.Id = Guid.NewGuid();
            Authorize("Create", row);
            try { return service.Create(row); }
            finally { context.SharedVariables.Remove(ProtectCandidateCore.IntentKey); }
        }

        private void Authorize(string message, Entity row)
        {
            context.SharedVariables[ProtectCandidateCore.IntentKey] = ProtectCandidateCore.Intent(message, row);
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
            return Create(row);
        }

        public void UpdateCandidate(ActionRequest request, CandidateState candidate, int status)
        {
            var row = new Entity("os_sr_cand", candidate.Id) { RowVersion = candidate.RowVersion };
            if (request.Action == "UpdateCandidate") SetProfile(row, request);
            else row["os_sr_cand_stat"] = new OptionSetValue(status);
            Authorize("Update", row);
            try { service.Execute(new UpdateRequest { Target = row, ConcurrencyBehavior = ConcurrencyBehavior.IfRowVersionMatches }); }
            finally { context.SharedVariables.Remove(ProtectCandidateCore.IntentKey); }
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
            return Create(row);
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
            return Create(row);
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
            Create(row);
        }
    }

    public sealed class ProtectCandidateCore : IPlugin
    {
        internal const string IntentKey = "os_sr_cact.validated_intent";
        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            if (context.MessageName == "Associate" || context.MessageName == "Disassociate")
            {
                var projectTables = new[] { "os_sr_cand", "os_sr_call", "os_sr_csh", "os_sr_oprc" };
                var projectRelationships = new[] { "os_sr_pos_cand", "os_sr_csrc_cand", "os_sr_ta_cand",
                    "os_sr_cand_call", "os_sr_cand_csh", "os_sr_usr_call_ctby", "os_sr_usr_csh_actr", "os_sr_cand_oprc" };
                var relationship = context.InputParameters.Contains("Relationship") ? context.InputParameters["Relationship"] as Relationship : null;
                var targetReference = context.InputParameters.Contains("Target") ? context.InputParameters["Target"] as EntityReference : null;
                var related = context.InputParameters.Contains("RelatedEntities") ? context.InputParameters["RelatedEntities"] as EntityReferenceCollection : null;
                if (relationship != null && projectRelationships.Contains(relationship.SchemaName, StringComparer.OrdinalIgnoreCase) ||
                    targetReference != null && projectTables.Contains(targetReference.LogicalName, StringComparer.OrdinalIgnoreCase) ||
                    related != null && related.Any(reference => projectTables.Contains(reference.LogicalName, StringComparer.OrdinalIgnoreCase)))
                    throw new InvalidPluginExecutionException("DIRECT_CANDIDATE_CORE_WRITE_BLOCKED");
                return;
            }
            var parent = context.ParentContext;
            if (context.Stage != 10 || context.Mode != 0 || parent == null || parent.MessageName != "os_sr_cact" ||
                parent.Stage != 30 || !parent.IsInTransaction || !context.IsInTransaction ||
                context.UserId != context.InitiatingUserId || parent.UserId != context.UserId ||
                parent.InitiatingUserId != context.InitiatingUserId ||
                !new[] { "os_sr_cand", "os_sr_call", "os_sr_csh", "os_sr_oprc" }.Contains(context.PrimaryEntityName) ||
                (context.MessageName != "Create" && context.MessageName != "Update") ||
                (context.MessageName == "Update" && context.PrimaryEntityName != "os_sr_cand") ||
                !context.InputParameters.Contains("Target") || !(context.InputParameters["Target"] is Entity target) ||
                !parent.SharedVariables.Contains(IntentKey) ||
                !(parent.SharedVariables[IntentKey] is string expected) ||
                expected != Intent(context.MessageName, target))
                throw new InvalidPluginExecutionException("DIRECT_CANDIDATE_CORE_WRITE_BLOCKED");
        }

        internal static string Intent(string message, Entity target)
        {
            var builder = new StringBuilder(message).Append('|').Append(target.LogicalName).Append('|')
                .Append(target.Id.ToString("D"));
            foreach (var attribute in target.Attributes.OrderBy(pair => pair.Key, StringComparer.Ordinal))
            {
                // Dataverse can materialize the primary ID in Target.Attributes during Create.
                if (attribute.Key == target.LogicalName + "id" && attribute.Value is Guid primary && primary == target.Id) continue;
                string value;
                if (attribute.Value == null) value = "null";
                else if (attribute.Value is EntityReference reference) value = "r:" + reference.LogicalName + ":" + reference.Id.ToString("D");
                else if (attribute.Value is OptionSetValue option) value = "o:" + option.Value.ToString(CultureInfo.InvariantCulture);
                else if (attribute.Value is DateTime date) value = "d:" + date.ToString("O", CultureInfo.InvariantCulture);
                else if (attribute.Value is string text) value = "s:" + text;
                else if (attribute.Value is int integer) value = "i:" + integer.ToString(CultureInfo.InvariantCulture);
                else throw new InvalidPluginExecutionException("UNSUPPORTED_MUTATION_VALUE");
                builder.Append('|').Append(attribute.Key.Length).Append(':').Append(attribute.Key)
                    .Append('|').Append(value.Length).Append(':').Append(value);
            }
            using (var hash = SHA256.Create())
                return BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(builder.ToString()))).Replace("-", "");
        }
    }
}
