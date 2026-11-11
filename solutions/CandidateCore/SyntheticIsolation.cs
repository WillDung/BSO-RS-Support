using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Xml;
using System.Xml.Linq;
using Microsoft.Crm.Sdk.Messages;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using Microsoft.Xrm.Sdk.Messages;

namespace os_sr_cact
{
    // The value is deployment-controlled, never a request parameter or an environment-variable default.
    public sealed class SyntheticIsolation
    {
        public const string ConfigurationName = "os_sr_siso";
        public const string VerifyAction = "VerifySyntheticIsolation";
        public static readonly string[] Tables =
        {
            "os_sr_cand", "os_sr_call", "os_sr_csh", "os_sr_intv", "os_sr_oprc",
            "os_sr_pos", "os_sr_csrc", "os_sr_ta", "os_sr_loc"
        };
        public static readonly string[] WriteMessages =
        {
            "Create", "Update", "Delete", "Upsert", "SetState", "SetStateDynamicEntity",
            "Assign", "Merge", "CreateMultiple", "UpdateMultiple", "UpsertMultiple", "DeleteMultiple"
        };
        public static bool IsProtectedTable(string? name) => Tables.Contains(name, StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, Guid> references;
        public Guid OrganizationId { get; }
        public Guid EnvironmentId { get; }
        public Guid ActorId { get; }
        public Guid ScopeId { get; }
        public DateTime? ExpiresUtc { get; }
        public bool Enabled { get; }
        public bool PersistentDev { get; }
        public string CandidateName => "[SYNTHETIC-E2E] Playwright " + ScopeId.ToString("D");
        public string CandidateEmail => "pw-" + ScopeId.ToString("D") + "@example.invalid";

        private SyntheticIsolation(XElement root)
        {
            OrganizationId = ReadGuid(root, "organizationId");
            EnvironmentId = ReadGuid(root, "environmentId");
            ActorId = ReadGuid(root, "actorId");
            ScopeId = ReadGuid(root, "scopeId");
            PersistentDev = (string?)root.Attribute("profileVersion") == "2";
            if (PersistentDev)
            {
                if ((string?)root.Attribute("lifetime") != "PersistentDev" ||
                    OrganizationId != DevCandidateSlice.DevelopmentOrganizationId ||
                    !new[] { "true", "false" }.Contains((string?)root.Attribute("enabled")))
                    throw new OperationError("SYNTHETIC_CONFIGURATION_INVALID");
                Enabled = (string?)root.Attribute("enabled") == "true";
            }
            else
            {
                if (!DateTime.TryParseExact((string?)root.Attribute("expiresUtc"), "yyyy-MM-dd'T'HH:mm:ss'Z'",
                    CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out var expiry))
                    throw new OperationError("SYNTHETIC_CONFIGURATION_INVALID");
                ExpiresUtc = expiry;
                Enabled = true;
            }
            references = new Dictionary<string, Guid>(StringComparer.Ordinal)
            {
                ["os_sr_pos"] = ReadGuid(root, "positionId"),
                ["os_sr_csrc"] = ReadGuid(root, "sourceId"),
                ["os_sr_ta"] = ReadGuid(root, "taId"),
                ["os_sr_loc"] = ReadGuid(root, "locationId")
            };
        }

        public static SyntheticIsolation Parse(string value)
        {
            if (string.IsNullOrWhiteSpace(value) || value.Length > 4096)
                throw new OperationError("SYNTHETIC_CONFIGURATION_INVALID");
            using (var reader = XmlReader.Create(new StringReader(value), new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null
            }))
            {
                var root = XElement.Load(reader);
                var bindings = new[] { "organizationId", "environmentId", "actorId", "scopeId",
                    "positionId", "sourceId", "taId", "locationId" };
                var attributes = bindings.Concat((string?)root.Attribute("profileVersion") == "2"
                    ? new[] { "profileVersion", "lifetime", "enabled" } : new[] { "expiresUtc" }).ToArray();
                if (root.Name != "syntheticIsolation" || root.HasElements ||
                    root.Attributes().Count() != attributes.Length ||
                    root.Attributes().Any(attribute => !attributes.Contains(attribute.Name.ToString())))
                    throw new OperationError("SYNTHETIC_CONFIGURATION_INVALID");
                return new SyntheticIsolation(root);
            }
        }

        private static Guid ReadGuid(XElement root, string name)
        {
            if (!Guid.TryParseExact((string?)root.Attribute(name), "D", out var id) || id == Guid.Empty)
                throw new OperationError("SYNTHETIC_CONFIGURATION_INVALID");
            return id;
        }

        public static SyntheticIsolation Load(IOrganizationService service, IPluginExecutionContext context)
        {
            var policy = ReadProfile(service);
            policy.ValidateContext(context.OrganizationId, context.InitiatingUserId, DateTime.UtcNow);
            return policy;
        }

        public static SyntheticIsolation? LoadForGuard(IOrganizationService service, IPluginExecutionContext context)
        {
            var policy = ReadProfile(service);
            if (context.OrganizationId != DevCandidateSlice.DevelopmentOrganizationId ||
                context.OrganizationId != policy.OrganizationId)
                throw new OperationError("SYNTHETIC_ORGANIZATION_REJECTED");
            if (context.InitiatingUserId != policy.ActorId) return null;
            policy.ValidateContext(context.OrganizationId, context.InitiatingUserId, DateTime.UtcNow);
            return policy;
        }

        private static SyntheticIsolation ReadProfile(IOrganizationService service)
        {
            var definitions = new QueryExpression("environmentvariabledefinition")
            {
                ColumnSet = new ColumnSet("statecode"), TopCount = 2
            };
            definitions.Criteria.AddCondition("schemaname", ConditionOperator.Equal, ConfigurationName);
            var definitionResult = service.RetrieveMultiple(definitions);
            var definitionRows = definitionResult.Entities;
            if (definitionResult.MoreRecords || definitionRows.Count != 1 ||
                definitionRows[0].GetAttributeValue<OptionSetValue>("statecode")?.Value != 0)
                throw new OperationError("SYNTHETIC_CONFIGURATION_MISSING");
            var values = new QueryExpression("environmentvariablevalue")
            {
                ColumnSet = new ColumnSet("value", "statecode"), TopCount = 2
            };
            values.Criteria.AddCondition("environmentvariabledefinitionid", ConditionOperator.Equal, definitionRows[0].Id);
            var valueResult = service.RetrieveMultiple(values);
            var rows = valueResult.Entities;
            if (valueResult.MoreRecords || rows.Count != 1 || rows[0].GetAttributeValue<OptionSetValue>("statecode")?.Value != 0)
                throw new OperationError("SYNTHETIC_CONFIGURATION_MISSING");
            return Parse(rows[0].GetAttributeValue<string>("value"));
        }

        public void ValidateContext(Guid organization, Guid actor, DateTime now)
        {
            if (organization != DevCandidateSlice.DevelopmentOrganizationId || organization != OrganizationId)
                throw new OperationError("SYNTHETIC_ORGANIZATION_REJECTED");
            if (actor != ActorId) throw new OperationError("SYNTHETIC_ACTOR_REJECTED");
            if (!Enabled) throw new OperationError("SYNTHETIC_PROFILE_DISABLED");
            if (now.Kind != DateTimeKind.Utc || ExpiresUtc.HasValue && now >= ExpiresUtc.Value)
                throw new OperationError("SYNTHETIC_SCOPE_EXPIRED");
        }

        public void ValidateRequest(ActionRequest request, IOrganizationService service)
        {
            if (!request.Values.TryGetValue("SyntheticScopeId", out var scope) ||
                !(scope is Guid id) || id != ScopeId)
                throw new OperationError("SYNTHETIC_SCOPE_REQUIRED");
            if (request.Actor != ActorId || request.CandidateId.HasValue && request.CandidateId != ScopeId)
                throw new OperationError("SYNTHETIC_CANDIDATE_REJECTED");
            if (request.Action != "CreateCandidate")
                ValidateRow(service.Retrieve("os_sr_cand", ScopeId, new ColumnSet(VerificationColumns("os_sr_cand"))));
            foreach (var field in new[] { "CandidateName", "CandidateEmail" })
                if (request.Values.TryGetValue(field, out var value) &&
                    !Equals(value, field == "CandidateName" ? CandidateName : CandidateEmail))
                    throw new OperationError("SYNTHETIC_PROFILE_REJECTED");
            foreach (var pair in new[]
            {
                (Input: "PositionId", Table: "os_sr_pos"), (Input: "CandidateSourceId", Table: "os_sr_csrc"),
                (Input: "AssignedTaId", Table: "os_sr_ta"), (Input: "InterviewerId", Table: "os_sr_ta"),
                (Input: "LocationId", Table: "os_sr_loc")
            })
                if (request.Values.TryGetValue(pair.Input, out var value) && value != null &&
                    (!(value is Guid reference) || reference != references[pair.Table]))
                    throw new OperationError("SYNTHETIC_REFERENCE_REJECTED");
            ValidateReferences(service);
        }

        public void ValidateReferences(IOrganizationService service)
        {
            foreach (var reference in references)
                ValidateRow(service.Retrieve(reference.Key, reference.Value, new ColumnSet(VerificationColumns(reference.Key))));
        }

        public void VerifyApiScope(IOrganizationService control, IOrganizationService caller, IPluginExecutionContext context)
        {
            ValidateContext(context.OrganizationId, context.InitiatingUserId, DateTime.UtcNow);
            var user = control.Retrieve("systemuser", ActorId, new ColumnSet("isdisabled", "islicensed", "accessmode"));
            if (!user.Contains("isdisabled") || user.GetAttributeValue<bool>("isdisabled") ||
                !user.GetAttributeValue<bool>("islicensed") || user.GetAttributeValue<OptionSetValue>("accessmode")?.Value != 0)
                throw new OperationError("SYNTHETIC_CALLER_INELIGIBLE");
            RequireApiCallerPrivileges(control);
            RequireApiContract(control);
            ValidateReferences(caller);
            foreach (var table in new[] { "os_sr_cand", "os_sr_call", "os_sr_csh", "os_sr_intv" })
            {
                var query = new QueryExpression(table)
                {
                    ColumnSet = new ColumnSet(VerificationColumns(table)), TopCount = 101
                };
                query.Criteria.AddCondition(table == "os_sr_cand" ? "os_sr_candid" : CandidateColumn(table),
                    ConditionOperator.Equal, ScopeId);
                var rows = control.RetrieveMultiple(query);
                if (rows.MoreRecords || rows.Entities.Count > 100)
                    throw new OperationError("SYNTHETIC_READBACK_LIMIT");
                foreach (var row in rows.Entities)
                {
                    ValidateRow(row);
                    ValidateRow(caller.Retrieve(table, row.Id, new ColumnSet(VerificationColumns(table))));
                }
            }
        }

        private void RequireApiCallerPrivileges(IOrganizationService service)
        {
            var required = new HashSet<string>(Tables.Where(table => table != "os_sr_oprc")
                .Select(table => "prvRead" + table), StringComparer.Ordinal);
            var denied = new HashSet<string>(StringComparer.Ordinal)
            {
                "prvBypassCustomPlugins", "prvBypassCustomBusinessLogic", "prvActOnBehalfOfAnotherUser",
                "prvImportCustomization", "prvPublishCustomization", "prvReados_sr_oprc"
            };
            foreach (var table in Tables.Concat(new[] { "Role", "Team", "User", "SystemUser", "BusinessUnit",
                "EnvironmentVariableDefinition", "EnvironmentVariableValue", "PluginPackage", "PluginAssembly",
                "PluginType", "SdkMessageProcessingStep", "CustomAPI", "CustomAPIRequestParameter",
                "CustomAPIResponseProperty", "Privilege", "Organization", "Workflow", "WebResource",
                "SdkMessage", "SdkMessageProcessingStepImage", "Solution" }))
                foreach (var verb in new[] { "Create", "Write", "Delete", "Assign", "Share" })
                    denied.Add("prv" + verb + table);
            var query = new QueryExpression("privilege") { ColumnSet = new ColumnSet("name"), TopCount = 501 };
            query.Criteria.AddCondition("name", ConditionOperator.In, required.Concat(denied).Cast<object>().ToArray());
            var catalog = service.RetrieveMultiple(query);
            if (catalog.MoreRecords || catalog.Entities.Count > 500 ||
                catalog.Entities.Any(row => row.Id == Guid.Empty || string.IsNullOrEmpty(row.GetAttributeValue<string>("name"))))
                throw new OperationError("SYNTHETIC_PRIVILEGE_METADATA_MISSING");
            var names = catalog.Entities.ToDictionary(row => row.Id, row => row.GetAttributeValue<string>("name"));
            if (!required.IsSubsetOf(names.Values) ||
                !new[] { "prvBypassCustomPlugins", "prvBypassCustomBusinessLogic", "prvActOnBehalfOfAnotherUser" }
                    .All(name => names.Values.Contains(name)))
                throw new OperationError("SYNTHETIC_PRIVILEGE_METADATA_MISSING");
            // This message includes team-derived grants; direct-role enumeration is not sufficient.
            var response = (RetrieveUserSetOfPrivilegesByNamesResponse)service.Execute(
                new RetrieveUserSetOfPrivilegesByNamesRequest
                { UserId = ActorId, PrivilegeNames = names.Values.ToArray() });
            if (response.RolePrivileges == null ||
                response.RolePrivileges.Any(privilege => !names.ContainsKey(privilege.PrivilegeId) ||
                    new[] { "prvReados_sr_cand", "prvReados_sr_call", "prvReados_sr_csh", "prvReados_sr_intv" }
                        .Contains(names[privilege.PrivilegeId]) && privilege.Depth != PrivilegeDepth.Basic))
                throw new OperationError("SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
            var effective = new HashSet<string>(response.RolePrivileges.Select(privilege => names[privilege.PrivilegeId]),
                StringComparer.Ordinal);
            if (!required.IsSubsetOf(effective) || effective.Overlaps(denied))
                throw new OperationError("SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        }

        private static void RequireApiContract(IOrganizationService service)
        {
            var query = new QueryExpression("customapi")
            {
                ColumnSet = new ColumnSet("plugintypeid", "executeprivilegename", "isprivate", "isfunction",
                    "allowedcustomprocessingsteptype"), TopCount = 2
            };
            query.Criteria.AddCondition("uniquename", ConditionOperator.Equal, "os_sr_cact");
            var result = service.RetrieveMultiple(query);
            if (result.MoreRecords || result.Entities.Count != 1)
                throw new OperationError("SYNTHETIC_API_CONTRACT_REJECTED");
            var api = result.Entities[0];
            var handler = api.GetAttributeValue<EntityReference>("plugintypeid");
            if (handler == null || api.GetAttributeValue<string>("executeprivilegename") != "prvReados_sr_cand" ||
                !api.GetAttributeValue<bool>("isprivate") || !api.Contains("isfunction") ||
                api.GetAttributeValue<bool>("isfunction") ||
                api.GetAttributeValue<OptionSetValue>("allowedcustomprocessingsteptype")?.Value != 0)
                throw new OperationError("SYNTHETIC_API_CONTRACT_REJECTED");
            var type = service.Retrieve("plugintype", handler.Id, new ColumnSet("typename", "pluginassemblyid"));
            var assemblyId = type.GetAttributeValue<EntityReference>("pluginassemblyid");
            if (type.GetAttributeValue<string>("typename") != typeof(ApplyCandidateAction).FullName || assemblyId == null)
                throw new OperationError("SYNTHETIC_API_CONTRACT_REJECTED");
            var assembly = service.Retrieve("pluginassembly", assemblyId.Id,
                new ColumnSet("name", "version", "isolationmode", "sourcetype", "packageid"));
            var executing = typeof(ApplyCandidateAction).Assembly.GetName();
            if (assembly.GetAttributeValue<string>("name") != executing.Name ||
                assembly.GetAttributeValue<string>("version") != executing.Version.ToString() ||
                assembly.GetAttributeValue<OptionSetValue>("isolationmode")?.Value != 2 ||
                assembly.GetAttributeValue<OptionSetValue>("sourcetype")?.Value != 4 ||
                assembly.GetAttributeValue<EntityReference>("packageid") == null)
                throw new OperationError("SYNTHETIC_API_CONTRACT_REJECTED");
            foreach (var metadata in new[] {
                (Table: "customapirequestparameter", Name: "SyntheticScopeId", Type: 12),
                (Table: "customapiresponseproperty", Name: "IsolationContract", Type: 10) })
            {
                var parameter = new QueryExpression(metadata.Table)
                { ColumnSet = new ColumnSet("type", "isoptional"), TopCount = 2 };
                if (metadata.Table != "customapirequestparameter")
                    parameter.ColumnSet = new ColumnSet("type");
                parameter.Criteria.AddCondition("customapiid", ConditionOperator.Equal, api.Id);
                parameter.Criteria.AddCondition("uniquename", ConditionOperator.Equal, metadata.Name);
                var rows = service.RetrieveMultiple(parameter);
                if (rows.MoreRecords || rows.Entities.Count != 1 ||
                    rows.Entities[0].GetAttributeValue<OptionSetValue>("type")?.Value != metadata.Type ||
                    metadata.Table == "customapirequestparameter" && !rows.Entities[0].GetAttributeValue<bool>("isoptional"))
                    throw new OperationError("SYNTHETIC_API_CONTRACT_REJECTED");
            }
        }

        public void ValidateRow(Entity row)
        {
            if (!Tables.Contains(row.LogicalName) || row.Id == Guid.Empty ||
                row.Attributes.Values.Any(value => value is AliasedValue))
                throw new OperationError("SYNTHETIC_ROW_REJECTED");
            if (references.TryGetValue(row.LogicalName, out var reference))
            {
                var label = row.LogicalName == "os_sr_pos" ? "[DEV] Software Engineer" :
                    row.LogicalName == "os_sr_csrc" ? "[DEV] Internal Test Source" :
                    row.LogicalName == "os_sr_ta" ? "[DEV] Synthetic Interviewer" : "[DEV] Test Location";
                if (row.Id != reference || row.GetAttributeValue<OptionSetValue>("statecode")?.Value != 0 ||
                    row.GetAttributeValue<string>(NameColumn(row.LogicalName)) != label)
                    throw new OperationError("SYNTHETIC_REFERENCE_REJECTED");
                return;
            }
            if (row.LogicalName == "os_sr_cand")
            {
                if (row.Id != ScopeId || row.GetAttributeValue<string>("os_sr_cand_nm") != CandidateName ||
                    row.GetAttributeValue<string>("os_sr_cand_eml") != CandidateEmail ||
                    row.GetAttributeValue<EntityReference>("ownerid")?.LogicalName != "systemuser" ||
                    row.GetAttributeValue<EntityReference>("ownerid")?.Id != ActorId)
                    throw new OperationError("SYNTHETIC_PROFILE_REJECTED");
                foreach (var pair in new[] { ("os_sr_cand_pos", "os_sr_pos"), ("os_sr_cand_csrc", "os_sr_csrc"),
                    ("os_sr_cand_ta", "os_sr_ta") })
                    ValidateLookup(row, pair.Item1, pair.Item2, false);
                return;
            }
            var candidate = row.GetAttributeValue<EntityReference>(CandidateColumn(row.LogicalName));
            if (candidate == null || candidate.LogicalName != "os_sr_cand" || candidate.Id != ScopeId)
                throw new OperationError("SYNTHETIC_CANDIDATE_REJECTED");
            if (row.LogicalName == "os_sr_intv")
            {
                ValidateLookup(row, "os_sr_intv_ta", "os_sr_ta", true);
                ValidateLookup(row, "os_sr_intv_loc", "os_sr_loc", true);
            }
        }

        private void ValidateLookup(Entity row, string column, string table, bool required)
        {
            var value = row.GetAttributeValue<EntityReference>(column);
            if (value == null ? required : value.LogicalName != table || value.Id != references[table])
                throw new OperationError("SYNTHETIC_REFERENCE_REJECTED");
        }

        private static string NameColumn(string table) => table == "os_sr_pos" ? "os_sr_pos_ttl" : table + "_nm";
        private static string CandidateColumn(string table) => table + "_cand";
        internal string[] VerificationColumns(string table)
        {
            table = table.ToLowerInvariant();
            if (references.ContainsKey(table)) return new[] { NameColumn(table), "statecode" };
            if (table == "os_sr_cand") return new[] { "os_sr_cand_nm", "os_sr_cand_eml", "ownerid",
                "os_sr_cand_pos", "os_sr_cand_csrc", "os_sr_cand_ta" };
            if (table == "os_sr_intv") return new[] { "os_sr_intv_cand", "os_sr_intv_ta", "os_sr_intv_loc" };
            if (!Tables.Contains(table)) throw new OperationError("SYNTHETIC_QUERY_REJECTED");
            return new[] { CandidateColumn(table) };
        }

        public FilterExpression ScopeFilter(string table)
        {
            table = table.ToLowerInvariant();
            if (!Tables.Contains(table)) throw new OperationError("SYNTHETIC_QUERY_REJECTED");
            var filter = new FilterExpression(LogicalOperator.And);
            filter.AddCondition(table == "os_sr_cand" || references.ContainsKey(table) ? table + "id" :
                CandidateColumn(table), ConditionOperator.Equal,
                references.TryGetValue(table, out var id) ? id : ScopeId);
            if (table == "os_sr_cand")
            {
                filter.AddCondition("os_sr_cand_nm", ConditionOperator.Equal, CandidateName);
                filter.AddCondition("os_sr_cand_eml", ConditionOperator.Equal, CandidateEmail);
                filter.AddCondition("ownerid", ConditionOperator.Equal, ActorId);
                foreach (var pair in new[] { ("os_sr_cand_pos", "os_sr_pos"), ("os_sr_cand_csrc", "os_sr_csrc"),
                    ("os_sr_cand_ta", "os_sr_ta") })
                {
                    var optional = new FilterExpression(LogicalOperator.Or);
                    optional.AddCondition(pair.Item1, ConditionOperator.Null);
                    optional.AddCondition(pair.Item1, ConditionOperator.Equal, references[pair.Item2]);
                    filter.AddFilter(optional);
                }
            }
            if (references.ContainsKey(table))
            {
                filter.AddCondition("statecode", ConditionOperator.Equal, 0);
                filter.AddCondition(NameColumn(table), ConditionOperator.Equal, table == "os_sr_pos" ? "[DEV] Software Engineer" :
                    table == "os_sr_csrc" ? "[DEV] Internal Test Source" :
                    table == "os_sr_ta" ? "[DEV] Synthetic Interviewer" : "[DEV] Test Location");
            }
            if (table == "os_sr_intv")
            {
                filter.AddCondition("os_sr_intv_ta", ConditionOperator.Equal, references["os_sr_ta"]);
                filter.AddCondition("os_sr_intv_loc", ConditionOperator.Equal, references["os_sr_loc"]);
            }
            return filter;
        }

        public void ScopeQuery(QueryBase query)
        {
            if (query is QueryExpression expression)
            {
                var root = new FilterExpression(LogicalOperator.And);
                root.AddFilter(expression.Criteria);
                root.AddFilter(ScopeFilter(expression.EntityName));
                expression.Criteria = root;
                expression.ColumnSet.AddColumns(VerificationColumns(expression.EntityName));
                ScopeLinks(expression.LinkEntities);
                BindCandidate(expression.EntityName, expression.LinkEntities);
                return;
            }
            if (query is FetchExpression fetch)
            {
                using (var reader = XmlReader.Create(new StringReader(fetch.Query),
                    new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null }))
                {
                    var xml = XElement.Load(reader);
                    if (xml.Name != "fetch" || xml.Attribute("aggregate") != null ||
                        xml.Descendants("attribute").Any(attribute => attribute.Attribute("aggregate") != null ||
                            attribute.Attribute("groupby") != null))
                        throw new OperationError("SYNTHETIC_QUERY_REJECTED");
                    var entity = xml.Element("entity") ?? throw new OperationError("SYNTHETIC_QUERY_REJECTED");
                    ScopeFetch(entity);
                    foreach (var column in VerificationColumns((string?)entity.Attribute("name") ?? ""))
                        if (!entity.Elements("attribute").Any(attribute =>
                            (string?)attribute.Attribute("name") == column && attribute.Attribute("alias") == null))
                            entity.Add(new XElement("attribute", new XAttribute("name", column)));
                    fetch.Query = xml.ToString(SaveOptions.DisableFormatting);
                }
                return;
            }
            throw new OperationError("SYNTHETIC_QUERY_REJECTED");
        }

        private void ScopeLinks(IEnumerable<LinkEntity> links)
        {
            foreach (var link in links)
            {
                var root = new FilterExpression(LogicalOperator.And);
                root.AddFilter(link.LinkCriteria);
                root.AddFilter(ScopeFilter(link.LinkToEntityName));
                link.LinkCriteria = root;
                ScopeLinks(link.LinkEntities);
                BindCandidate(link.LinkToEntityName, link.LinkEntities);
            }
        }

        private void BindCandidate(string table, ICollection<LinkEntity> links)
        {
            table = table.ToLowerInvariant();
            if (table == "os_sr_cand" || references.ContainsKey(table)) return;
            links.Add(new LinkEntity(table, "os_sr_cand", CandidateColumn(table), "os_sr_candid", JoinOperator.Inner)
            {
                Columns = new ColumnSet(false), LinkCriteria = ScopeFilter("os_sr_cand")
            });
        }

        private static XElement FetchFilter(FilterExpression scope)
        {
            var filter = new XElement("filter", new XAttribute("type", scope.FilterOperator == LogicalOperator.And ? "and" : "or"));
            foreach (var condition in scope.Conditions)
            {
                var element = new XElement("condition", new XAttribute("attribute", condition.AttributeName),
                    new XAttribute("operator", condition.Operator == ConditionOperator.Null ? "null" : "eq"));
                if (condition.Operator != ConditionOperator.Null)
                    element.Add(new XAttribute("value", Convert.ToString(condition.Values[0], CultureInfo.InvariantCulture) ?? ""));
                filter.Add(element);
            }
            foreach (var child in scope.Filters) filter.Add(FetchFilter(child));
            return filter;
        }

        private void ScopeFetch(XElement entity)
        {
            var table = ((string?)entity.Attribute("name") ?? "").ToLowerInvariant();
            // Separate sibling filters are ANDed; never append constraints to an existing OR.
            entity.Add(FetchFilter(ScopeFilter(table)));
            foreach (var link in entity.Elements("link-entity")) ScopeFetch(link);
            if (table != "os_sr_cand" && !references.ContainsKey(table))
                entity.Add(new XElement("link-entity", new XAttribute("name", "os_sr_cand"),
                    new XAttribute("from", "os_sr_candid"), new XAttribute("to", CandidateColumn(table)),
                    new XAttribute("link-type", "inner"), FetchFilter(ScopeFilter("os_sr_cand"))));
        }

        public static void RequireRestrictedCaller(IOrganizationService service, IPluginExecutionContext context)
        {
            // TDS does not execute these row/query plug-ins. It must not be a second read path.
            var organization = service.Retrieve("organization", context.OrganizationId,
                new ColumnSet("enabletdsendpoint", "enablerelevancesearch"));
            if (!organization.Contains("enabletdsendpoint") || organization.GetAttributeValue<bool>("enabletdsendpoint"))
                throw new OperationError("SYNTHETIC_TDS_NOT_DISABLED");
            if (!organization.Contains("enablerelevancesearch") || organization.GetAttributeValue<bool>("enablerelevancesearch"))
                throw new OperationError("SYNTHETIC_SEARCH_NOT_DISABLED");
            var privileges = (RetrieveUserPrivilegesResponse)service.Execute(
                new RetrieveUserPrivilegesRequest { UserId = context.InitiatingUserId });
            var granted = new HashSet<Guid>(privileges.RolePrivileges.Select(privilege => privilege.PrivilegeId));
            foreach (var table in Tables)
            {
                var metadata = (RetrieveEntityResponse)service.Execute(new RetrieveEntityRequest
                {
                    LogicalName = table, EntityFilters = Microsoft.Xrm.Sdk.Metadata.EntityFilters.Entity |
                        Microsoft.Xrm.Sdk.Metadata.EntityFilters.Privileges,
                    RetrieveAsIfPublished = false
                });
                if (metadata.EntityMetadata.ChangeTrackingEnabled != false)
                    throw new OperationError("SYNTHETIC_CHANGE_TRACKING_NOT_DISABLED");
                var read = metadata.EntityMetadata.Privileges?
                    .Where(privilege => privilege.PrivilegeType == Microsoft.Xrm.Sdk.Metadata.PrivilegeType.Read).ToArray();
                if (read == null || read.Length != 1)
                    throw new OperationError("SYNTHETIC_PRIVILEGE_METADATA_MISSING");
                if (table != "os_sr_oprc" && !granted.Contains(read[0].PrivilegeId))
                    throw new OperationError("SYNTHETIC_OWNER_REFERENCE_READ_REQUIRED");
                if (table == "os_sr_oprc" && granted.Contains(read[0].PrivilegeId))
                    throw new OperationError("SYNTHETIC_RECEIPT_READ_REJECTED");
            }
            if (granted.Count == 0 || granted.Count > 500) throw new OperationError("SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
            var query = new QueryExpression("privilege") { ColumnSet = new ColumnSet("name"), TopCount = 501 };
            query.Criteria.AddCondition("privilegeid", ConditionOperator.In, granted.Cast<object>().ToArray());
            var allowed = new HashSet<string>(new[]
            {
                "prvReados_sr_cand", "prvReados_sr_call", "prvReados_sr_csh", "prvReados_sr_intv",
                "prvReados_sr_pos", "prvReados_sr_csrc", "prvReados_sr_ta", "prvReados_sr_loc",
                "prvReadAppModule", "prvReadAppModuleRoles", "prvReadEntity", "prvReadAttribute",
                "prvReadRelationship", "prvReadWebResource", "prvReadCustomization", "prvReadSystemForm",
                "prvReadSavedQuery", "prvReadSavedQueryVisualizations", "prvReadOptionSet",
                "prvReadCustomControl", "prvReadCustomControlDefaultConfig", "prvReadCustomControlResource",
                "prvReadEntityKey", "prvReadEntityMap", "prvReadAttributeMap", "prvReadUser",
                "prvReadTeam", "prvReadRole", "prvReadBusinessUnit", "prvReadOrganization", "prvReadUserSettings"
            }, StringComparer.Ordinal);
            var effective = service.RetrieveMultiple(query);
            if (effective.MoreRecords || effective.Entities.Count != granted.Count ||
                !granted.SetEquals(effective.Entities.Select(privilege => privilege.Id)) ||
                effective.Entities.Any(privilege => !allowed.Contains(privilege.GetAttributeValue<string>("name"))))
                throw new OperationError("SYNTHETIC_CALLER_PRIVILEGES_REJECTED");
        }

        public string Contract()
        {
            var now = DateTime.UtcNow;
            ValidateContext(OrganizationId, ActorId, now);
            var until = ExpiresUtc.HasValue && ExpiresUtc.Value < now.AddMinutes(2)
                ? ExpiresUtc.Value : now.AddMinutes(2);
            return string.Format(CultureInfo.InvariantCulture,
                "{{\"version\":2,\"boundary\":\"ScopedCandidateCoreApi\",\"nativeWritesDenied\":true," +
                "\"readback\":\"CallerOwnedScope\",\"organizationId\":\"{0:D}\",\"environmentId\":\"{1:D}\"," +
                "\"actorId\":\"{2:D}\",\"scopeId\":\"{3:D}\",\"candidateId\":\"{3:D}\"," +
                "\"positionId\":\"{4:D}\",\"sourceId\":\"{5:D}\",\"taId\":\"{6:D}\"," +
                "\"locationId\":\"{7:D}\",\"validUntil\":\"{8:yyyy-MM-ddTHH:mm:ssZ}\",\"calendarEnabled\":false}}",
                OrganizationId, EnvironmentId, ActorId, ScopeId, references["os_sr_pos"],
                references["os_sr_csrc"], references["os_sr_ta"], references["os_sr_loc"], until);
        }

        public static void RequireGuardCoverage(IOrganizationService service)
        {
            // Only registrations from this executing package version count. Filters must be unfiltered,
            // synchronous, caller-context and active. Unknown/unguardable supported messages fail closed.
            var steps = new QueryExpression("sdkmessageprocessingstep")
            {
                ColumnSet = new ColumnSet("stage", "mode", "statecode", "filteringattributes", "impersonatinguserid")
            };
            steps.Criteria.AddCondition("statecode", ConditionOperator.Equal, 0);
            var type = steps.AddLink("plugintype", "eventhandler", "plugintypeid");
            type.LinkCriteria.AddCondition("typename", ConditionOperator.In, new object[]
                { typeof(SyntheticIsolationGuard).FullName!, typeof(SyntheticIsolationReadGuard).FullName! });
            type.EntityAlias = "handler";
            type.Columns.AddColumn("typename");
            var assembly = type.AddLink("pluginassembly", "pluginassemblyid", "pluginassemblyid");
            assembly.LinkCriteria.AddCondition("name", ConditionOperator.Equal, "os_sr_cact");
            assembly.LinkCriteria.AddCondition("version", ConditionOperator.Equal,
                typeof(SyntheticIsolation).Assembly.GetName().Version!.ToString());
            var package = assembly.AddLink("pluginpackage", "packageid", "pluginpackageid");
            package.LinkCriteria.AddCondition("uniquename", ConditionOperator.Equal, "os_sr_cact_pkg");
            var message = steps.AddLink("sdkmessage", "sdkmessageid", "sdkmessageid");
            message.EntityAlias = "message";
            message.Columns.AddColumn("name");
            var filter = steps.AddLink("sdkmessagefilter", "sdkmessagefilterid", "sdkmessagefilterid", JoinOperator.LeftOuter);
            filter.EntityAlias = "filter";
            filter.Columns.AddColumn("primaryobjecttypecode");
            var registered = service.RetrieveMultiple(steps);
            if (registered.MoreRecords) throw new OperationError("SYNTHETIC_COVERAGE_INCOMPLETE");
            var registrations = registered.Entities;
            if (registrations.Any(row =>
                row.GetAttributeValue<AliasedValue>("handler.typename")?.Value as string == typeof(SyntheticIsolationGuard).FullName &&
                (row.GetAttributeValue<AliasedValue>("message.name")?.Value as string == "RetrieveMultiple" ||
                 row.GetAttributeValue<AliasedValue>("message.name")?.Value as string == "Retrieve")))
                throw new OperationError("SYNTHETIC_GUARD_COVERAGE_REDUNDANT");
            var support = new QueryExpression("sdkmessagefilter")
            {
                ColumnSet = new ColumnSet("primaryobjecttypecode", "iscustomprocessingstepallowed")
            };
            support.Criteria.AddCondition("primaryobjecttypecode", ConditionOperator.In, Tables.Cast<object>().ToArray());
            var supportedMessage = support.AddLink("sdkmessage", "sdkmessageid", "sdkmessageid");
            supportedMessage.EntityAlias = "message";
            supportedMessage.Columns.AddColumn("name");
            var supported = service.RetrieveMultiple(support);
            if (supported.MoreRecords) throw new OperationError("SYNTHETIC_COVERAGE_INCOMPLETE");
            foreach (var table in Tables)
            {
                foreach (var required in new[] { "Create", "Update", "Delete" })
                    RequireStep(registrations, table, required, 20);
                foreach (var row in supported.Entities.Where(row =>
                    row.GetAttributeValue<string>("primaryobjecttypecode") == table))
                {
                    var name = row.GetAttributeValue<AliasedValue>("message.name")?.Value as string;
                    if (name == null || !WriteMessages.Contains(name)) continue;
                    if (!row.GetAttributeValue<bool>("iscustomprocessingstepallowed"))
                        throw new OperationError("SYNTHETIC_UNGUARDABLE_MESSAGE");
                    RequireStep(registrations, table, name, 20);
                }
            }
            RequireStep(registrations, null, "Associate", 20);
            RequireStep(registrations, null, "Disassociate", 20);
            RequireStep(registrations, null, "RetrieveMultiple", 20, true);
            RequireStep(registrations, null, "RetrieveMultiple", 40, true);
            RequireStep(registrations, null, "Retrieve", 40, true);
        }

        private static void RequireStep(IEnumerable<Entity> rows, string? table, string message, int stage, bool readGuard = false)
        {
            if (rows.Count(row =>
                (row.GetAttributeValue<AliasedValue>("handler.typename")?.Value as string) ==
                    (readGuard ? typeof(SyntheticIsolationReadGuard).FullName : typeof(SyntheticIsolationGuard).FullName) &&
                (row.GetAttributeValue<AliasedValue>("filter.primaryobjecttypecode")?.Value as string) == table &&
                (row.GetAttributeValue<AliasedValue>("message.name")?.Value as string) == message &&
                row.GetAttributeValue<OptionSetValue>("stage")?.Value == stage &&
                row.GetAttributeValue<OptionSetValue>("mode")?.Value == 0 &&
                string.IsNullOrEmpty(row.GetAttributeValue<string>("filteringattributes")) &&
                row.GetAttributeValue<EntityReference>("impersonatinguserid") == null) != 1)
                throw new OperationError("SYNTHETIC_GUARD_COVERAGE_MISSING");
        }
    }

    // Per-table RetrieveMultiple steps do not run for a different root table joined to Candidate.
    public sealed class SyntheticIsolationReadGuard : IPlugin
    {
        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            if (context.OrganizationId != DevCandidateSlice.DevelopmentOrganizationId)
                throw new InvalidPluginExecutionException("SYNTHETIC_ORGANIZATION_REJECTED");
            try
            {
                if (context.Mode != 0) throw new OperationError("SYNTHETIC_CONTEXT_REJECTED");
                if (context.MessageName == "RetrieveMultiple" && context.Stage == 20)
                {
                    var query = context.InputParameters["Query"];
                    if (query is QueryExpression protectedQuery && SyntheticIsolation.IsProtectedTable(protectedQuery.EntityName))
                    {
                        PolicyForCaller(serviceProvider, context)?.ScopeQuery(protectedQuery);
                        return;
                    }
                    if (query is QueryExpression expression && !SyntheticIsolation.IsProtectedTable(expression.EntityName) &&
                        HasProtectedLink(expression.LinkEntities))
                    {
                        if (PolicyForCaller(serviceProvider, context) != null)
                            throw new OperationError("SYNTHETIC_CROSS_ROOT_QUERY_REJECTED");
                        return;
                    }
                    if (query is FetchExpression fetch)
                    {
                        using (var reader = XmlReader.Create(new StringReader(fetch.Query),
                            new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null }))
                        {
                            var xml = XElement.Load(reader);
                            var root = (string?)xml.Elements().FirstOrDefault(element => element.Name.LocalName == "entity")?.Attribute("name");
                            if (SyntheticIsolation.IsProtectedTable(root))
                            {
                                PolicyForCaller(serviceProvider, context)?.ScopeQuery(fetch);
                                return;
                            }
                            if (!SyntheticIsolation.IsProtectedTable(root) && xml.Descendants()
                                .Where(element => element.Name.LocalName == "link-entity")
                                .Any(link => SyntheticIsolation.IsProtectedTable((string?)link.Attribute("name"))))
                            {
                                if (PolicyForCaller(serviceProvider, context) != null)
                                    throw new OperationError("SYNTHETIC_CROSS_ROOT_QUERY_REJECTED");
                                return;
                            }
                        }
                    }
                    if (!(query is QueryExpression) && !(query is FetchExpression) &&
                        PolicyForCaller(serviceProvider, context) != null)
                        throw new OperationError("SYNTHETIC_QUERY_REJECTED");
                    return;
                }
                if (context.Stage != 40) throw new OperationError("SYNTHETIC_CONTEXT_REJECTED");
                IEnumerable<Entity> rows;
                if (context.MessageName == "Retrieve" &&
                    context.OutputParameters.TryGetValue("BusinessEntity", out var entity) && entity is Entity record)
                    rows = new[] { record };
                else if (context.MessageName == "RetrieveMultiple" &&
                    context.OutputParameters.TryGetValue("BusinessEntityCollection", out var collection) && collection is EntityCollection result)
                    rows = result.Entities;
                else throw new OperationError("SYNTHETIC_ROW_REJECTED");
                SyntheticIsolation? policy = null;
                var loaded = false;
                foreach (var row in rows)
                {
                    var protectedRow = SyntheticIsolation.IsProtectedTable(row.LogicalName);
                    var relevant = protectedRow || ContainsProtectedExpansion(row);
                    if (!relevant) continue;
                    if (!loaded)
                    {
                        policy = PolicyForCaller(serviceProvider, context);
                        loaded = true;
                        if (policy == null) return;
                    }
                    if (protectedRow && context.MessageName == "Retrieve")
                    {
                        var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
                        var system = factory.CreateOrganizationService(null);
                        var query = new QueryExpression(row.LogicalName) { ColumnSet = new ColumnSet(false), TopCount = 2 };
                        query.Criteria.AddCondition(row.LogicalName + "id", ConditionOperator.Equal, row.Id);
                        policy!.ScopeQuery(query);
                        var full = system.RetrieveMultiple(query).Entities;
                        if (full.Count != 1) throw new OperationError("SYNTHETIC_ROW_REJECTED");
                        policy.ValidateRow(full[0]);
                        if (row.RelatedEntities.Count != 0)
                            throw new OperationError("SYNTHETIC_EXPANSION_REJECTED");
                    }
                    else if (protectedRow) policy!.ValidateRow(row);
                    else
                        throw new OperationError("SYNTHETIC_EXPANSION_REJECTED");
                }
            }
            catch (OperationError error)
            {
                var trace = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
                trace.Trace("os_sr_siso rejected code={0}", error.Message);
                throw new InvalidPluginExecutionException(error.Message);
            }
        }

        private static SyntheticIsolation? PolicyForCaller(IServiceProvider provider, IPluginExecutionContext context)
        {
            var factory = (IOrganizationServiceFactory)provider.GetService(typeof(IOrganizationServiceFactory));
            return SyntheticIsolation.LoadForGuard(factory.CreateOrganizationService(null), context);
        }

        private static bool HasProtectedLink(IEnumerable<LinkEntity> links) =>
            links.Any(link => SyntheticIsolation.IsProtectedTable(link.LinkToEntityName) || HasProtectedLink(link.LinkEntities));

        private static bool ContainsProtectedExpansion(Entity row) =>
            row.Attributes.Values.OfType<EntityReference>().Any(reference => SyntheticIsolation.IsProtectedTable(reference.LogicalName)) ||
            row.Attributes.Values.OfType<AliasedValue>().Any(value => SyntheticIsolation.IsProtectedTable(value.EntityLogicalName) ||
                value.Value is EntityReference reference && SyntheticIsolation.IsProtectedTable(reference.LogicalName)) ||
            row.RelatedEntities.Values.Any(rows => rows.Entities.Any(entity =>
                SyntheticIsolation.IsProtectedTable(entity.LogicalName) || ContainsProtectedExpansion(entity))) ||
            row.Attributes.Values.OfType<Entity>().Any(entity =>
                SyntheticIsolation.IsProtectedTable(entity.LogicalName) || ContainsProtectedExpansion(entity)) ||
            row.Attributes.Values.OfType<EntityCollection>().Any(rows => rows.Entities.Any(entity =>
                SyntheticIsolation.IsProtectedTable(entity.LogicalName) || ContainsProtectedExpansion(entity)));
    }

    public sealed class SyntheticIsolationGuard : IPlugin
    {
        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            if (context.OrganizationId != DevCandidateSlice.DevelopmentOrganizationId)
                throw new InvalidPluginExecutionException("SYNTHETIC_ORGANIZATION_REJECTED");
            var trace = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
            try
            {
                if (context.Mode != 0) throw new OperationError("SYNTHETIC_CONTEXT_REJECTED");
                if (context.MessageName == "Associate" || context.MessageName == "Disassociate")
                {
                    var target = context.InputParameters.Contains("Target") ? context.InputParameters["Target"] as EntityReference : null;
                    var related = context.InputParameters.Contains("RelatedEntities") ?
                        context.InputParameters["RelatedEntities"] as EntityReferenceCollection : null;
                    if (target != null && SyntheticIsolation.IsProtectedTable(target.LogicalName) ||
                        related != null && related.Any(row => SyntheticIsolation.IsProtectedTable(row.LogicalName)))
                    {
                        var associationFactory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
                        if (SyntheticIsolation.LoadForGuard(associationFactory.CreateOrganizationService(null), context) != null)
                            throw new OperationError("SYNTHETIC_DIRECT_WRITE_REJECTED");
                    }
                    return;
                }
                var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
                var system = factory.CreateOrganizationService(null);
                var policy = SyntheticIsolation.LoadForGuard(system, context);
                if (policy == null) return;
                if (context.Stage != 20 || !context.IsInTransaction ||
                    !(context.MessageName == "Create" || context.MessageName == "Update"))
                    throw new OperationError("SYNTHETIC_DIRECT_WRITE_REJECTED");
                var parent = context.ParentContext;
                var searched = 0;
                while (parent != null && parent.Depth > 1 && searched++ < 8) parent = parent.ParentContext;
                if (parent == null || parent.MessageName != "os_sr_cact" || parent.Stage != 30 ||
                    parent.Mode != 0 || !parent.IsInTransaction || parent.Depth != 1 ||
                    parent.UserId != policy.ActorId || parent.InitiatingUserId != policy.ActorId ||
                    parent.OrganizationId != context.OrganizationId ||
                    !parent.InputParameters.TryGetValue("SyntheticScopeId", out var scope) ||
                    !(scope is Guid scopeId) || scopeId != policy.ScopeId)
                    throw new OperationError("SYNTHETIC_DIRECT_WRITE_REJECTED");
                var request = CandidateActionInputAdapter.Create(policy.ActorId, parent.InputParameters, DateTime.UtcNow);
                var targetRow = context.InputParameters["Target"] as Entity ??
                    throw new OperationError("SYNTHETIC_ROW_REJECTED");
                var table = targetRow.LogicalName;
                var create = context.MessageName == "Create";
                var mutation = table == "os_sr_cand" ? (create ? "CANDIDATE_CREATE" : "CANDIDATE_UPDATE") :
                    table == "os_sr_intv" ? (create ? "INTERVIEW_SCHEDULE_CREATE" : "INTERVIEW_SCHEDULE_UPDATE") :
                    create && table == "os_sr_call" ? "CALL_LOG_CREATE" :
                    create && table == "os_sr_csh" ? "STATUS_HISTORY_CREATE" :
                    create && table == "os_sr_oprc" ? "RECEIPT_CREATE" : null;
                if (table == "os_sr_cand" && targetRow.Id != policy.ScopeId || mutation == null ||
                    !CandidateOperation.MutationMatrix.TryGetValue(request.Action, out var allowed) || !allowed.Contains(mutation))
                    throw new OperationError("SYNTHETIC_DIRECT_WRITE_REJECTED");
                if (context.MessageName == "Update")
                {
                    var existing = system.Retrieve(table, targetRow.Id, new ColumnSet(policy.VerificationColumns(table)));
                    policy.ValidateRow(existing);
                    foreach (var attribute in targetRow.Attributes) existing[attribute.Key] = attribute.Value;
                    policy.ValidateRow(existing);
                }
                else policy.ValidateRow(targetRow);
                if (request.Action != "CreateCandidate" && request.CandidateId != policy.ScopeId)
                    throw new OperationError("SYNTHETIC_CANDIDATE_REJECTED");
            }
            catch (OperationError error)
            {
                trace.Trace("os_sr_siso rejected code={0}", error.Message);
                throw new InvalidPluginExecutionException(error.Message);
            }
        }
    }
}
