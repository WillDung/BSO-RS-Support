using System;
using System.Linq;
using Microsoft.Crm.Sdk.Messages;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Query;

namespace os_sr_cact
{
    internal static class NormalCreateAuthorization
    {
        private const string ConfigurationName = "os_sr_ncrcfg";
        private const string CandidateCreatePrivilege = "prvCreateos_sr_cand";

        public static void Require(IOrganizationService service, Guid organizationId, Guid actorId)
        {
            var policy = ReadPolicy(service);
            if (policy.OrganizationId != organizationId)
                throw new OperationError("NORMAL_CREATE_ORGANIZATION_REJECTED");
            if (!policy.Enabled)
                throw new OperationError("NORMAL_CREATE_DISABLED");

            var privilegeQuery = new QueryExpression("privilege")
            {
                ColumnSet = new ColumnSet("name"),
                TopCount = 2
            };
            privilegeQuery.Criteria.AddCondition("name", ConditionOperator.Equal, CandidateCreatePrivilege);
            var privileges = service.RetrieveMultiple(privilegeQuery);
            if (privileges.MoreRecords || privileges.Entities.Count != 1 ||
                privileges.Entities[0].Id == Guid.Empty ||
                privileges.Entities[0].GetAttributeValue<string>("name") != CandidateCreatePrivilege)
                throw new OperationError("NORMAL_CREATE_PRIVILEGE_METADATA_REJECTED");

            var effective = (RetrieveUserSetOfPrivilegesByNamesResponse)service.Execute(
                new RetrieveUserSetOfPrivilegesByNamesRequest
                {
                    UserId = actorId,
                    PrivilegeNames = new[] { CandidateCreatePrivilege }
                });
            if (effective.RolePrivileges == null ||
                !effective.RolePrivileges.Any(privilege =>
                    privilege.PrivilegeId == privileges.Entities[0].Id))
                throw new OperationError("NORMAL_CREATE_PRIVILEGE_REQUIRED");
        }

        private static (bool Enabled, Guid OrganizationId) ReadPolicy(IOrganizationService service)
        {
            var definitions = new QueryExpression("environmentvariabledefinition")
            {
                ColumnSet = new ColumnSet("statecode"),
                TopCount = 2
            };
            definitions.Criteria.AddCondition("schemaname", ConditionOperator.Equal, ConfigurationName);
            var definitionResult = service.RetrieveMultiple(definitions);
            if (definitionResult.MoreRecords || definitionResult.Entities.Count != 1 ||
                definitionResult.Entities[0].GetAttributeValue<OptionSetValue>("statecode")?.Value != 0)
                throw new OperationError("NORMAL_CREATE_CONFIGURATION_REJECTED");

            var values = new QueryExpression("environmentvariablevalue")
            {
                ColumnSet = new ColumnSet("value", "statecode"),
                TopCount = 2
            };
            values.Criteria.AddCondition("environmentvariabledefinitionid", ConditionOperator.Equal,
                definitionResult.Entities[0].Id);
            var valueResult = service.RetrieveMultiple(values);
            if (valueResult.MoreRecords || valueResult.Entities.Count != 1 ||
                valueResult.Entities[0].GetAttributeValue<OptionSetValue>("statecode")?.Value != 0)
                throw new OperationError("NORMAL_CREATE_CONFIGURATION_REJECTED");

            var raw = valueResult.Entities[0].GetAttributeValue<string>("value");
            if (raw == null) throw new OperationError("NORMAL_CREATE_CONFIGURATION_REJECTED");
            var fields = raw.Split('|');
            if (fields.Length != 3 || fields[0] != "v1" ||
                !fields[1].StartsWith("enabled=", StringComparison.Ordinal) ||
                !fields[2].StartsWith("organizationId=", StringComparison.Ordinal))
                throw new OperationError("NORMAL_CREATE_CONFIGURATION_REJECTED");

            var enabledValue = fields[1].Substring("enabled=".Length);
            if (enabledValue != "true" && enabledValue != "false")
                throw new OperationError("NORMAL_CREATE_CONFIGURATION_REJECTED");
            var organizationValue = fields[2].Substring("organizationId=".Length);
            if (!Guid.TryParseExact(organizationValue, "D", out var organizationId) ||
                organizationId == Guid.Empty ||
                !string.Equals(organizationValue, organizationId.ToString("D"), StringComparison.OrdinalIgnoreCase))
                throw new OperationError("NORMAL_CREATE_CONFIGURATION_REJECTED");

            return (enabledValue == "true", organizationId);
        }
    }
}
