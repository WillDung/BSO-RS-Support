using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Xrm.Sdk;
using os_sr_avqg;

internal static partial class Program
{
    private static readonly Guid SecurityOrganization = Guid.Parse("55555555-6666-7777-8888-999999999999");
    private static readonly Guid SecurityRole = Guid.Parse("66666666-7777-8888-9999-aaaaaaaaaaaa");
    private static readonly Guid SecurityLocation = Guid.Parse("33333333-4444-5555-6666-777777777777");

    private static string SecurityConfiguration() =>
        AvailabilityConfigurationRenderer.Render(ConfigurationSource(), IntegrationUser) +
        "\nSecurityVersion=2\nOrganizationId=" + SecurityOrganization.ToString("D") +
        "\nRequesterUserId=" + BsoUser.ToString("D") +
        "\nRequesterRoleId=" + SecurityRole.ToString("D") +
        "\nTaId=" + BsoUser.ToString("D") + "\nLocationId=" + SecurityLocation.ToString("D");

    private static void TestRequestSecurity()
    {
        var bindings = new Dictionary<string, string>
        {
            ["SecurityVersion"] = "2", ["OrganizationId"] = SecurityOrganization.ToString("D"),
            ["RequesterUserId"] = BsoUser.ToString("D"), ["RequesterRoleId"] = SecurityRole.ToString("D"),
            ["TaId"] = BsoUser.ToString("D"), ["LocationId"] = SecurityLocation.ToString("D")
        };
        Equal(SecurityConfiguration(), AvailabilityConfigurationRenderer.RenderSecured(
            ConfigurationSource(), IntegrationUser, bindings), "Secured renderer produces canonical binding bytes.");
        void InvalidBindings(IEnumerable<KeyValuePair<string, string>> values)
        {
            assertions++;
            try
            {
                AvailabilityConfigurationRenderer.RenderSecured(ConfigurationSource(), IntegrationUser, values);
            }
            catch (InvalidPluginExecutionException) { return; }
            throw new InvalidOperationException("Invalid security renderer bindings must fail closed.");
        }
        InvalidBindings(bindings.Where(pair => pair.Key != "RequesterRoleId"));
        InvalidBindings(bindings.Concat(new[] { new KeyValuePair<string, string>("RequesterUserId", BsoUser.ToString()) }));
        InvalidBindings(bindings.Concat(new[] { new KeyValuePair<string, string>("Unexpected", "value") }));
        InvalidBindings(bindings.Select(pair => pair.Key == "RequesterUserId"
            ? new KeyValuePair<string, string>(pair.Key, IntegrationUser.ToString("D")) : pair));
        var binding = AvailabilityRequestSecurity.Parse(SecurityConfiguration(), IntegrationUser);
        binding.ValidateRequester(SecurityOrganization, BsoUser, BsoUser);
        Equal(BsoUser, binding.RequesterUserId, "Exact configured requester is admitted.");
        SecurityRejects(() => binding.ValidateRequester(SecurityOrganization, IntegrationUser, IntegrationUser),
            "REQUESTER", "Writer cannot become requester.");
        SecurityRejects(() => binding.ValidateRequester(SecurityOrganization, Guid.NewGuid(), Guid.NewGuid()),
            "REQUESTER", "Unbound requester is rejected.");
        SecurityRejects(() => binding.ValidateRequester(Guid.NewGuid(), BsoUser, BsoUser),
            "REQUESTER", "Wrong organization is rejected.");
        SecurityRejects(() => binding.ValidateRequester(SecurityOrganization, BsoUser, IntegrationUser),
            "REQUESTER", "Impersonated requester is rejected.");
        foreach (var configuration in new[] { "", SecurityConfiguration().Replace("SecurityVersion=2", "SecurityVersion=1"),
                     SecurityConfiguration() + "\nRequesterUserId=" + BsoUser })
            SecurityRejects(() => AvailabilityRequestSecurity.Parse(configuration, IntegrationUser),
                "SECURITY_CONFIGURATION", "Missing/versioned/duplicate configuration fails closed.");

        GuardHost Host(QueryState state = QueryState.NoSlots) =>
            new GuardHost("Update", IntegrationUser, IntegrationUser, ResultTarget(state));
        var host = Host();
        host.Execute();
        Equal(true, host.QueryColumns.Contains("ownerid"), "Original owner is retrieved.");
        Equal(true, host.QueryColumns.Contains("os_sr_avq_dead"), "Server deadline is retrieved.");
        host = Host();
        host.QueryRow["ownerid"] = new EntityReference("systemuser", IntegrationUser);
        host.QueryRow["createdby"] = new EntityReference("systemuser", IntegrationUser);
        host.QueryRow["os_sr_avq_cat"] = Now.AddMonths(-10);
        host.QueryRow["os_sr_avq_dead"] = Now.AddMonths(-10).AddMinutes(12);
        GuardRejects(host, "REQUEST_OWNER", "Original stale writer-owned/writer-created NoSlots counterexample rejects.");
        foreach (var field in new[] { "ownerid", "createdby" })
        {
            host = Host();
            host.QueryRow[field] = new EntityReference("systemuser", IntegrationUser);
            GuardRejects(host, "REQUEST_OWNER", "Known writer-owned stale NoSlots counterexample is rejected.");
        }
        host = Host();
        host.QueryRow["createdonbehalfby"] = new EntityReference("systemuser", IntegrationUser);
        GuardRejects(host, "REQUEST_OWNER", "Impersonated origin is rejected.");
        host = Host();
        host.AuthorizedRole = false;
        GuardRejects(host, "REQUESTER_ROLE", "Revoked requester role rejects completion.");
        host = Host();
        host.QueryRow["os_sr_avq_ta"] = new EntityReference("os_sr_ta", Guid.NewGuid());
        GuardRejects(host, "REQUEST_SCOPE", "Wrong scope rejects even NoSlots.");

        foreach (var correlation in new object?[] { null, "", "not-a-guid", Guid.Empty.ToString(), Guid.NewGuid().ToString() })
        {
            var target = ResultTarget(QueryState.NoSlots);
            target["os_sr_avq_corr"] = correlation;
            GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, target),
                "CORRELATION", "Missing/malformed/mismatched terminal correlation fails closed.");
        }
        host = Host();
        host.QueryRow["os_sr_avq_corr"] = Guid.NewGuid().ToString();
        GuardRejects(host, "CORRELATION", "Stored correlation cannot bind another request.");
        host = Host();
        host.QueryRow["os_sr_avq_dead"] = Now;
        GuardRejects(host, "REQUEST_EXPIRED", "Deadline equality rejects stale NoSlots.");
        host = Host();
        host.QueryRow["os_sr_avq_cat"] = Now.AddDays(-1);
        host.QueryRow["os_sr_avq_dead"] = Now.AddDays(-1).AddMinutes(12);
        GuardRejects(host, "REQUEST_EXPIRED", "Old Pending request cannot complete.");
        host = Host();
        host.QueryRow.Attributes.Remove("os_sr_avq_dead");
        GuardRejects(host, "INVALID_REQUEST", "Legacy rows without a deadline fail closed.");
        host = Host();
        host.ServerNow = Now.AddMinutes(11).AddTicks(-1);
        var fresh = ResultTarget(QueryState.NoSlots);
        fresh["os_sr_avq_qat"] = Now.AddMinutes(10);
        fresh["os_sr_avq_exp"] = Now.AddMinutes(20);
        host = new GuardHost("Update", IntegrationUser, IntegrationUser, fresh)
            { ServerNow = Now.AddMinutes(11).AddTicks(-1) };
        host.Execute();
        assertions++;
        host.ServerNow = Now.AddMinutes(11);
        GuardRejects(host, "REQUEST_EXPIRED", "Exact deadline boundary rejects deterministically.");
        var future = ResultTarget(QueryState.NoSlots);
        future["os_sr_avq_qat"] = Now.AddTicks(1);
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, future),
            "REQUEST_EXPIRED", "Future provider timestamp is rejected.");
        host = Host();
        host.QueryRow["os_sr_avq_stat"] = new OptionSetValue((int)QueryState.NoSlots);
        GuardRejects(host, "TERMINAL_STATE", "Duplicate terminal result is rejected.");
        host = Host();
        host.Inputs.Remove("ConcurrencyBehavior");
        GuardRejects(host, "CONCURRENCY_REQUIRED", "Unconditional update fails closed.");
        host = Host();
        host.Inputs["ConcurrencyBehavior"] = ConcurrencyBehavior.Default;
        GuardRejects(host, "CONCURRENCY_REQUIRED", "Default update behavior is not conditional concurrency.");
        host = Host();
        host.QueryRow.RowVersion = "2";
        GuardRejects(host, "CONCURRENCY_MISMATCH", "Concurrent version change fails closed.");
        var noVersion = ResultTarget(QueryState.NoSlots);
        noVersion.RowVersion = null;
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, noVersion),
            "CONCURRENCY_REQUIRED", "Missing expected version fails closed.");
        var malformed = ResultTarget(QueryState.Available);
        malformed["os_sr_avq_slts"] = null;
        GuardRejects(new GuardHost("Update", IntegrationUser, IntegrationUser, malformed),
            "RESULT_INVALID", "Missing canonical provider result fails closed.");
        foreach (var message in new[] { "Assign", "Delete" })
            GuardRejects(new GuardHost(message, BsoUser, BsoUser, ResultTarget(QueryState.NoSlots)),
                "IMMUTABLE_REQUEST", "Ownership and correlation-replay deletion are blocked.");

        var id = Guid.NewGuid();
        Entity Create() => new Entity("os_sr_avq", id)
        {
            ["os_sr_avqid"] = id, ["os_sr_avq_corr"] = id.ToString("D"),
            ["os_sr_avq_ta"] = new EntityReference("os_sr_ta", BsoUser),
            ["os_sr_avq_mod"] = new OptionSetValue((int)InterviewMode.Online),
            ["os_sr_avq_strt"] = Now.AddDays(1).AddHours(2),
            ["os_sr_avq_end"] = Now.AddDays(1).AddHours(10), ["os_sr_avq_dur"] = 30
        };
        var request = Create();
        host = new GuardHost("Create", BsoUser, BsoUser, request);
        host.Execute();
        Equal(BsoUser, request.GetAttributeValue<EntityReference>("ownerid").Id, "Owner is server-bound.");
        Equal(Now, request.GetAttributeValue<DateTime>("os_sr_avq_cat"), "Server stamps creation clock.");
        Equal(Now.AddMinutes(12), request.GetAttributeValue<DateTime>("os_sr_avq_dead"),
            "Server stamps immutable deadline.");
        request = Create();
        host = new GuardHost("Create", BsoUser, BsoUser, request) { AuthorizedRole = false };
        GuardRejects(host, "REQUESTER_ROLE", "Requester without exact effective role is rejected.");
        request = Create();
        request.Attributes.Remove("os_sr_avq_corr");
        GuardRejects(new GuardHost("Create", BsoUser, BsoUser, request),
            "CORRELATION", "Create requires caller correlation.");
        request = Create();
        request["ownerid"] = new EntityReference("systemuser", BsoUser);
        GuardRejects(new GuardHost("Create", BsoUser, BsoUser, request),
            "UNEXPECTED_ATTRIBUTE", "Even matching caller-supplied ownership is rejected.");
    }

    private static void SecurityRejects(Action action, string category, string description)
    {
        assertions++;
        try { action(); }
        catch (InvalidPluginExecutionException exception)
        {
            if (exception.Message == "Availability query rejected: " + category) return;
            throw;
        }
        throw new InvalidOperationException(description);
    }
}
