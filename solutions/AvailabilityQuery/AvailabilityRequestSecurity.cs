using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;

namespace os_sr_avqg
{
    public sealed class AvailabilityRequestSecurity
    {
        internal static readonly string[] ConfigurationKeys =
        {
            "SecurityVersion", "OrganizationId", "RequesterUserId", "RequesterRoleId", "TaId", "LocationId"
        };

        private AvailabilityRequestSecurity(Guid organization, Guid requester, Guid role, Guid ta, Guid location)
        {
            OrganizationId = organization;
            RequesterUserId = requester;
            RequesterRoleId = role;
            TaId = ta;
            LocationId = location;
        }

        public Guid OrganizationId { get; }
        public Guid RequesterUserId { get; }
        public Guid RequesterRoleId { get; }
        public Guid TaId { get; }
        public Guid LocationId { get; }

        public static AvailabilityRequestSecurity Parse(string? configuration, Guid writer)
        {
            var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var line in (configuration ?? "").Split(new[] { '\r', '\n' },
                         StringSplitOptions.RemoveEmptyEntries))
            {
                var separator = line.IndexOf('=');
                if (separator <= 0) throw Reject("SECURITY_CONFIGURATION");
                var key = line.Substring(0, separator).Trim();
                if (!ConfigurationKeys.Contains(key, StringComparer.OrdinalIgnoreCase)) continue;
                if (values.ContainsKey(key)) throw Reject("SECURITY_CONFIGURATION");
                values.Add(key, line.Substring(separator + 1).Trim());
            }
            if (values.Count != ConfigurationKeys.Length || values["SecurityVersion"] != "2")
                throw Reject("SECURITY_CONFIGURATION");
            Guid Read(string key)
            {
                if (!Guid.TryParseExact(values[key], "D", out var id) || id == Guid.Empty)
                    throw Reject("SECURITY_CONFIGURATION");
                return id;
            }
            var result = new AvailabilityRequestSecurity(Read("OrganizationId"), Read("RequesterUserId"),
                Read("RequesterRoleId"), Read("TaId"), Read("LocationId"));
            if (result.RequesterUserId == writer) throw Reject("SECURITY_CONFIGURATION");
            return result;
        }

        public void ValidateRequester(Guid organization, Guid caller, Guid initiating)
        {
            if (organization != OrganizationId || caller != RequesterUserId || initiating != RequesterUserId)
                throw Reject("REQUESTER");
        }

        internal void ValidateRole(IOrganizationService service)
        {
            var direct = new QueryExpression("role") { ColumnSet = new ColumnSet("roleid"), TopCount = 1 };
            direct.Criteria.AddCondition("roleid", ConditionOperator.Equal, RequesterRoleId);
            direct.AddLink("systemuserroles", "roleid", "roleid").LinkCriteria
                .AddCondition("systemuserid", ConditionOperator.Equal, RequesterUserId);
            if (service.RetrieveMultiple(direct).Entities.Count != 0) return;
            var inherited = new QueryExpression("role") { ColumnSet = new ColumnSet("roleid"), TopCount = 1 };
            inherited.Criteria.AddCondition("roleid", ConditionOperator.Equal, RequesterRoleId);
            inherited.AddLink("teamroles", "roleid", "roleid")
                .AddLink("teammembership", "teamid", "teamid").LinkCriteria
                .AddCondition("systemuserid", ConditionOperator.Equal, RequesterUserId);
            if (service.RetrieveMultiple(inherited).Entities.Count == 0) throw Reject("REQUESTER_ROLE");
        }

        public void ValidateScope(Entity request)
        {
            var ta = request.GetAttributeValue<EntityReference>("os_sr_avq_ta");
            var location = request.GetAttributeValue<EntityReference>("os_sr_avq_loc");
            if (ta == null || ta.LogicalName != "os_sr_ta" || ta.Id != TaId ||
                (location != null && (location.LogicalName != "os_sr_loc" || location.Id != LocationId)) ||
                (request.GetAttributeValue<OptionSetValue>("os_sr_avq_mod")?.Value == (int)InterviewMode.Onsite &&
                 location == null))
                throw Reject("REQUEST_SCOPE");
        }

        public static Guid Correlation(Entity request)
        {
            if (!request.Attributes.TryGetValue("os_sr_avq_corr", out var raw) ||
                !(raw is string value) || !Guid.TryParseExact(value, "D", out var correlation) ||
                correlation == Guid.Empty || request.Id != correlation)
                throw Reject("CORRELATION");
            return correlation;
        }

        public void ValidateOrigin(Entity request)
        {
            foreach (var field in new[] { "ownerid", "createdby" })
            {
                var reference = request.GetAttributeValue<EntityReference>(field);
                if (reference == null || reference.LogicalName != "systemuser" || reference.Id != RequesterUserId)
                    throw Reject("REQUEST_OWNER");
            }
            if (request.GetAttributeValue<EntityReference>("createdonbehalfby") != null)
                throw Reject("REQUEST_OWNER");
            ValidateScope(request);
            Correlation(request);
        }

        public static void ValidateFreshness(DateTime created, DateTime deadline, DateTime now,
            DateTime queried, DateTime expiry, int maximumAgeMinutes)
        {
            if (new[] { created, deadline, now, queried, expiry }.Any(value => value.Kind != DateTimeKind.Utc) ||
                created > now || deadline <= created || now >= deadline ||
                deadline.Ticks - created.Ticks > (long)maximumAgeMinutes * TimeSpan.TicksPerMinute ||
                queried < created || queried > now || expiry <= now || expiry <= queried)
                throw Reject("REQUEST_EXPIRED");
        }

        private static InvalidPluginExecutionException Reject(string category) =>
            new InvalidPluginExecutionException("Availability query rejected: " + category);
    }
}
