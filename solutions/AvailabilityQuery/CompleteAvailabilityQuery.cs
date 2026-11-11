using System;
using System.Globalization;
using System.Linq;
using System.ServiceModel;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;

namespace os_sr_avqg
{
    public sealed class CompleteAvailabilityQuery : IPlugin
    {
        public const string MessageName = "os_sr_avq_complete";
        private readonly string? configuration;
        private readonly Func<DateTime> utcNow;

        public CompleteAvailabilityQuery(string? unsecureConfiguration, string? secureConfiguration)
            : this(unsecureConfiguration, () => DateTime.UtcNow) { }

        internal CompleteAvailabilityQuery(string? configuration, Func<DateTime> utcNow)
        {
            this.configuration = configuration;
            this.utcNow = utcNow;
        }

        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var trace = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
            if (context.MessageName != MessageName || context.Stage != 20 || context.Mode != 0 ||
                !context.IsInTransaction || context.Depth != 1)
                throw Reject("UNSUPPORTED_OPERATION");
            var settings = PluginConfiguration.Parse(configuration);
            var security = AvailabilityRequestSecurity.Parse(configuration, settings.ResultWriterUserId);
            if (context.OrganizationId != security.OrganizationId ||
                !AvailabilityMutationPolicy.IsResultUpdateCaller(context.UserId, context.InitiatingUserId,
                    settings.ResultWriterUserId))
                throw Reject("UPDATE_CALLER");
            var target = CreateTarget(context.InputParameters);
            var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
            var service = factory.CreateOrganizationService(context.UserId);
            ProtectAvailabilityQuery.ValidateResult(service, settings, security, trace, utcNow(), target);
            try
            {
                service.Execute(new UpdateRequest
                {
                    Target = target,
                    ConcurrencyBehavior = ConcurrencyBehavior.IfRowVersionMatches
                });
            }
            catch (FaultException<OrganizationServiceFault> fault)
            {
                trace.Trace("AVQ_RESULT_WRITE_REJECTED code={0}", fault.Detail.ErrorCode);
                throw Reject(fault.Detail.ErrorCode == -2147088254
                    ? "CONCURRENCY_MISMATCH" : "RESULT_WRITE_FAILED");
            }
            context.OutputParameters["ResultCode"] = "Applied";
            trace.Trace("AVQ_RESULT_WRITE_APPLIED");
        }

        internal static Entity CreateTarget(ParameterCollection inputs)
        {
            var names = new[]
            {
                "QueryId", "ExpectedRowVersion", "CorrelationId", "TerminalStatus",
                "SlotsJson", "ReasonCode", "ErrorCode", "QueriedAt", "ExpiresAt"
            };
            if (inputs.Keys.Any(key => !names.Contains(key, StringComparer.Ordinal)) ||
                !inputs.TryGetValue("QueryId", out var rawId) || !(rawId is Guid id) || id == Guid.Empty ||
                !inputs.TryGetValue("CorrelationId", out var rawCorrelation) ||
                !(rawCorrelation is Guid correlation) || correlation != id ||
                !inputs.TryGetValue("TerminalStatus", out var rawStatus) || !(rawStatus is int status))
                throw Reject("INVALID_REQUEST");
            string Text(string name)
            {
                if (!inputs.TryGetValue(name, out var value) || !(value is string text))
                    throw Reject("INVALID_REQUEST");
                return text;
            }
            string? Optional(string name)
            {
                if (!inputs.TryGetValue(name, out var value) || value == null || Equals(value, "")) return null;
                if (!(value is string text)) throw Reject("INVALID_REQUEST");
                return text;
            }
            DateTime Time(string name)
            {
                var text = Text(name);
                if (!DateTime.TryParseExact(text,
                        new[] { "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'" },
                        CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                        out var time))
                    throw Reject("INVALID_REQUEST");
                return time;
            }
            return new Entity("os_sr_avq", id)
            {
                RowVersion = ParseRowVersion(Text("ExpectedRowVersion")),
                ["os_sr_avq_corr"] = correlation.ToString("D"),
                ["os_sr_avq_stat"] = new OptionSetValue(status),
                ["os_sr_avq_slts"] = Text("SlotsJson"),
                ["os_sr_avq_rsn"] = Optional("ReasonCode"),
                ["os_sr_avq_err"] = Optional("ErrorCode"),
                ["os_sr_avq_qat"] = Time("QueriedAt"),
                ["os_sr_avq_exp"] = Time("ExpiresAt")
            };
        }

        internal static string ParseRowVersion(string value)
        {
            var text = value.Length >= 4 && value.StartsWith("W/\"", StringComparison.Ordinal) &&
                       value.EndsWith("\"", StringComparison.Ordinal)
                ? value.Substring(3, value.Length - 4) : value;
            if (!long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var version) ||
                version <= 0 || version.ToString(CultureInfo.InvariantCulture) != text)
                throw Reject("CONCURRENCY_REQUIRED");
            return text;
        }

        private static InvalidPluginExecutionException Reject(string code) =>
            new InvalidPluginExecutionException("Availability query rejected: " + code);
    }
}
