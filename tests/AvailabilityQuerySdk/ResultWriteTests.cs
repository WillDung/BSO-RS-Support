using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Xrm.Sdk;
using os_sr_avqg;

internal static partial class Program
{
    private static ParameterCollection ResultInputs()
    {
        var target = ResultTarget(QueryState.NoSlots);
        return new ParameterCollection
        {
            ["QueryId"] = target.Id, ["ExpectedRowVersion"] = "W/\"1\"",
            ["CorrelationId"] = target.Id, ["TerminalStatus"] = (int)QueryState.NoSlots,
            ["SlotsJson"] = "[]", ["ReasonCode"] = "NO_COMMON_SLOT", ["ErrorCode"] = "",
            ["QueriedAt"] = Now.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"),
            ["ExpiresAt"] = Now.AddMinutes(10).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        };
    }

    private static void TestResultWrite()
    {
        GuardHost Host(Guid? caller = null) =>
            new GuardHost("Update", caller ?? IntegrationUser, caller ?? IntegrationUser,
                ResultTarget(QueryState.NoSlots));
        void Reject(GuardHost host, ParameterCollection input, string category)
        {
            SecurityRejects(() => host.ExecuteResult(input), category, "Result operation must reject.");
            Equal(0, host.ConditionalWrites, "Rejected operation cannot persist.");
        }
        var host = Host();
        host.ExecuteResult(ResultInputs());
        Equal(1, host.ConditionalWrites, "Valid result uses exactly one conditional write.");
        Equal("Applied", host.Outputs["ResultCode"], "Success is explicit after the write.");
        Equal("2", host.QueryRow.RowVersion, "Conditional engine advances the row version.");
        var stale = ResultInputs();
        stale["ExpectedRowVersion"] = "2";
        Reject(Host(), stale, "CONCURRENCY_MISMATCH");
        foreach (var version in new[] { "*", "W/\"*\"", "", "0", "01", "-1", "W/\"", "W/\"\"", "W/\"1\"garbage" })
        {
            var input = ResultInputs();
            input["ExpectedRowVersion"] = version;
            Reject(Host(), input, "CONCURRENCY_REQUIRED");
        }
        var wrongCorrelation = ResultInputs();
        wrongCorrelation["CorrelationId"] = Guid.NewGuid();
        Reject(Host(), wrongCorrelation, "INVALID_REQUEST");
        host = Host();
        host.QueryRow["ownerid"] = new EntityReference("systemuser", IntegrationUser);
        Reject(host, ResultInputs(), "REQUEST_OWNER");
        host = Host();
        host.QueryRow["os_sr_avq_dead"] = Now;
        Reject(host, ResultInputs(), "REQUEST_EXPIRED");
        host = Host();
        host.QueryRow["os_sr_avq_stat"] = new OptionSetValue((int)QueryState.NoSlots);
        Reject(host, ResultInputs(), "TERMINAL_STATE");
        var extra = ResultInputs();
        extra["ownerid"] = IntegrationUser;
        Reject(Host(), extra, "INVALID_REQUEST");
        Reject(Host(BsoUser), ResultInputs(), "UPDATE_CALLER");
        host = Host();
        host.DenyWritePrivilege = true;
        Reject(host, ResultInputs(), "RESULT_WRITE_FAILED");
        host = Host();
        host.AuthorizedRole = false;
        Reject(host, ResultInputs(), "REQUESTER_ROLE");

        var first = Host();
        var second = Host();
        second.QueryRow = first.QueryRow;
        using (var barrier = new Barrier(2))
        {
            first.BeforeConditionalWrite = second.BeforeConditionalWrite = () =>
            {
                if (!barrier.SignalAndWait(TimeSpan.FromSeconds(10)))
                    throw new InvalidOperationException("Synthetic write race did not synchronize.");
            };
            string Run(GuardHost contender)
            {
                try { contender.ExecuteResult(ResultInputs()); return "Applied"; }
                catch (InvalidPluginExecutionException exception) { return exception.Message; }
            }
            var competing = new[] { Task.Run(() => Run(first)), Task.Run(() => Run(second)) };
            Task.WaitAll(competing);
            Equal(1, competing.Count(task => task.Result == "Applied"), "Exactly one competing write succeeds.");
            Equal(1, competing.Count(task => task.Result.EndsWith("CONCURRENCY_MISMATCH",
                StringComparison.Ordinal)), "The other competing write fails closed.");
            Equal(1, first.ConditionalWrites + second.ConditionalWrites, "No unconditional lost-update write.");
        }
    }
}
