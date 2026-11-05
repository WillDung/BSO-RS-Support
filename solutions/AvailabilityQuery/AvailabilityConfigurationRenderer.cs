using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Web.Script.Serialization;
using System.Xml;
using System.Xml.Linq;
using Microsoft.Xrm.Sdk;

namespace os_sr_avqg
{
    public static class AvailabilityConfigurationRenderer
    {
        private static readonly string[] EnvironmentNames =
        {
            "os_sr_avq_bhrs", "os_sr_avq_durs", "os_sr_avq_lead",
            "os_sr_avq_hzn", "os_sr_avq_exp", "os_sr_avq_dom"
        };

        public static string Render(IEnumerable<KeyValuePair<string, string>> environmentValues,
            Guid integrationApplicationUserId)
        {
            var source = new Dictionary<string, string>(StringComparer.Ordinal);
            if (environmentValues == null) throw InvalidConfiguration();
            foreach (var pair in environmentValues)
            {
                if (!EnvironmentNames.Contains(pair.Key, StringComparer.Ordinal) ||
                    source.ContainsKey(pair.Key) || string.IsNullOrWhiteSpace(pair.Value))
                    throw InvalidConfiguration();
                source.Add(pair.Key, pair.Value);
            }
            if (source.Count != EnvironmentNames.Length) throw InvalidConfiguration();

            var hours = ReadBusinessHours(source["os_sr_avq_bhrs"]);
            var durations = source["os_sr_avq_durs"].Split(',').Select(ReadInteger).ToArray();
            var domains = source["os_sr_avq_dom"].Split(',').Select(value => value.Trim()).ToArray();
            if (durations.Distinct().Count() != durations.Length ||
                domains.Distinct(StringComparer.Ordinal).Count() != domains.Length ||
                domains.Any(domain => domain != domain.ToLowerInvariant() ||
                    Uri.CheckHostName(domain) != UriHostNameType.Dns))
                throw InvalidConfiguration();

            AvailabilitySettings expected;
            try
            {
                expected = new AvailabilitySettings(domains, durations, hours,
                    ReadInteger(source["os_sr_avq_lead"]), ReadInteger(source["os_sr_avq_hzn"]),
                    ReadInteger(source["os_sr_avq_exp"]), integrationApplicationUserId);
            }
            catch (AvailabilityFailure)
            {
                throw InvalidConfiguration();
            }
            if (!expected.AllowedEmailDomains.SequenceEqual(domains, StringComparer.Ordinal))
                throw InvalidConfiguration();

            var lines = new List<string>
            {
                "IntegrationApplicationUserId=" + integrationApplicationUserId.ToString("D"),
                "AllowedEmailDomains=" + string.Join(",", domains),
                "AllowedDurationsMinutes=" + string.Join(",", durations.Select(FormatInteger)),
                "MaximumHorizonDays=" + FormatInteger(expected.MaximumHorizonDays),
                "MinimumLeadTimeMinutes=" + FormatInteger(expected.MinimumLeadTimeMinutes),
                "ResultExpiryMinutes=" + FormatInteger(expected.ResultExpiryMinutes)
            };
            foreach (var pair in hours.OrderBy(pair => pair.Key))
                lines.Add("BusinessHours." + pair.Key + "=" +
                    pair.Value.Opens.ToString(@"hh\:mm", CultureInfo.InvariantCulture) + "-" +
                    pair.Value.Closes.ToString(@"hh\:mm", CultureInfo.InvariantCulture));

            var rendered = string.Join("\n", lines);
            var parsed = PluginConfiguration.Parse(rendered);
            if (parsed.IntegrationApplicationUserId != expected.IntegrationApplicationUserId ||
                parsed.MaximumHorizonDays != expected.MaximumHorizonDays ||
                parsed.MinimumLeadTimeMinutes != expected.MinimumLeadTimeMinutes ||
                parsed.ResultExpiryMinutes != expected.ResultExpiryMinutes ||
                !parsed.AllowedDurationsMinutes.SequenceEqual(durations) ||
                !parsed.AllowedEmailDomains.SequenceEqual(domains, StringComparer.Ordinal) ||
                parsed.BusinessHours.Count != hours.Count ||
                hours.Any(pair => !parsed.BusinessHours.TryGetValue(pair.Key, out var actual) ||
                    actual.Opens != pair.Value.Opens || actual.Closes != pair.Value.Closes))
                throw InvalidConfiguration();
            return rendered;
        }

        private static Dictionary<DayOfWeek, DailyBusinessHours> ReadBusinessHours(string json)
        {
            XElement root;
            try
            {
                // The XML-mapped JSON reader preserves duplicate properties but can ignore trailing JSON.
                new JavaScriptSerializer().DeserializeObject(json);
                using (var reader = JsonReaderWriterFactory.CreateJsonReader(
                    Encoding.UTF8.GetBytes(json), XmlDictionaryReaderQuotas.Max))
                {
                    root = XElement.Load(reader);
                    if (reader.Read()) throw InvalidConfiguration();
                }
            }
            catch (XmlException)
            {
                throw InvalidConfiguration();
            }
            catch (ArgumentException)
            {
                throw InvalidConfiguration();
            }
            catch (InvalidOperationException)
            {
                throw InvalidConfiguration();
            }
            if ((string?)root.Attribute("type") != "object" ||
                root.Attributes().Any(attribute => attribute.Name != "type"))
                throw InvalidConfiguration();
            var hours = new Dictionary<DayOfWeek, DailyBusinessHours>();
            foreach (var day in root.Elements())
            {
                if (!Enum.GetNames(typeof(DayOfWeek)).Any(name =>
                        string.Equals(name, day.Name.LocalName, StringComparison.OrdinalIgnoreCase)) ||
                    !Enum.TryParse(day.Name.LocalName, true, out DayOfWeek weekday) ||
                    hours.ContainsKey(weekday) || (string?)day.Attribute("type") != "object" ||
                    day.Attributes().Any(attribute => attribute.Name != "type"))
                    throw InvalidConfiguration();
                var bounds = day.Elements().ToArray();
                if (bounds.Length != 2 || bounds.Count(item => item.Name.LocalName == "opens") != 1 ||
                    bounds.Count(item => item.Name.LocalName == "closes") != 1 ||
                    bounds.Any(item => (string?)item.Attribute("type") != "string" || item.HasElements ||
                        item.Attributes().Any(attribute => attribute.Name != "type")))
                    throw InvalidConfiguration();
                if (!TimeSpan.TryParseExact(bounds.Single(item => item.Name.LocalName == "opens").Value,
                        @"hh\:mm", CultureInfo.InvariantCulture, out var opens) ||
                    !TimeSpan.TryParseExact(bounds.Single(item => item.Name.LocalName == "closes").Value,
                        @"hh\:mm", CultureInfo.InvariantCulture, out var closes))
                    throw InvalidConfiguration();
                try
                {
                    hours.Add(weekday, new DailyBusinessHours(opens, closes));
                }
                catch (AvailabilityFailure)
                {
                    throw InvalidConfiguration();
                }
            }
            return hours;
        }

        private static int ReadInteger(string value)
        {
            if (!int.TryParse(value.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out var number))
                throw InvalidConfiguration();
            return number;
        }

        private static string FormatInteger(int value) => value.ToString(CultureInfo.InvariantCulture);

        private static InvalidPluginExecutionException InvalidConfiguration() =>
            new InvalidPluginExecutionException("Availability query configuration is invalid.");
    }
}
