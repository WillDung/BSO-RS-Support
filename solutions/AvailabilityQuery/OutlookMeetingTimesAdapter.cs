using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Mail;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Web.Script.Serialization;
using System.Xml;
using System.Xml.Linq;

namespace os_sr_avqg
{
    public sealed class OutlookMeetingTimesRequest
    {
        internal OutlookMeetingTimesRequest(AvailabilityQuery query, AvailabilitySettings settings)
        {
            RequiredAttendees = query.TaEmail!.Trim().ToLowerInvariant();
            ResourceAttendees = query.Mode == InterviewMode.Onsite
                ? query.RoomEmail!.Trim().ToLowerInvariant() : "";
            MeetingDuration = query.DurationMinutes;
            Start = query.StartUtc;
            End = query.EndUtc;
            MaxCandidates = settings.MaximumCandidates;
        }

        public string RequiredAttendees { get; }
        public string ResourceAttendees { get; }
        public int MeetingDuration { get; }
        public DateTime Start { get; }
        public DateTime End { get; }
        public int MaxCandidates { get; }
        public string MinimumAttendeePercentage => "100";
        public bool IsOrganizerOptional => true;
        public string ActivityDomain => "Work";
    }

    public static class OutlookMeetingTimesAdapter
    {
        private const int MaximumResponseLength = 1048576;
        private static readonly string[] TimestampFormats =
        {
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'"
        };
        private static readonly string[] AttendeeTypes = { "required", "optional", "resource" };
        private static readonly string[] AvailabilityValues =
        {
            "free", "tentative", "busy", "oof", "workingElsewhere", "unknown"
        };

        public static OutlookMeetingTimesRequest CreateRequest(
            AvailabilityQuery query, AvailabilitySettings settings, DateTime nowUtc)
        {
            var failure = AvailabilityRules.ValidateQuery(query, settings, nowUtc);
            if (failure != null) throw new AvailabilityFailure(failure);
            return new OutlookMeetingTimesRequest(query, settings);
        }

        internal static AvailabilityResult Evaluate(AvailabilityQuery query, string? providerResponse,
            AvailabilitySettings settings, DateTime nowUtc)
        {
            try
            {
                var root = ReadObject(ReadJson(providerResponse),
                    new[] { "emptySuggestionsReason", "meetingTimeSuggestions" },
                    new[] { "emptySuggestionsReason", "meetingTimeSuggestions" });
                ReadString(root["emptySuggestionsReason"]);
                var suggestions = ReadArray(root["meetingTimeSuggestions"]);
                if (suggestions.Count > settings.MaximumCandidates) throw InvalidResponse();

                var slots = new SortedDictionary<DateTime, AvailableSlot>();
                var observations = new Dictionary<Tuple<DateTime, DateTime>, bool>();
                foreach (var item in suggestions)
                {
                    var suggestion = ReadObject(item,
                        new[] { "confidence", "organizerAvailability", "suggestionReason",
                            "meetingTimeSlot", "attendeeAvailability", "locations" },
                        new[] { "meetingTimeSlot", "attendeeAvailability" });
                    ValidateOptionalFields(suggestion);
                    var timeSlot = ReadObject(suggestion["meetingTimeSlot"],
                        new[] { "start", "end" }, new[] { "start", "end" });
                    var start = ReadUtc(timeSlot["start"]);
                    var end = ReadUtc(timeSlot["end"]);
                    if (end <= start) throw InvalidResponse();
                    var slot = new AvailableSlot(start, end);
                    var available = RequiredAttendeesAreFree(
                        suggestion["attendeeAvailability"], query);
                    var key = Tuple.Create(start, end);
                    if (observations.TryGetValue(key, out var previous) && previous != available)
                        throw InvalidResponse();
                    observations[key] = available;
                    if (available && AvailabilityRules.IsEligibleSlot(slot, query, settings, nowUtc))
                        slots[start] = slot;
                }

                if (slots.Count == 0) return AvailabilityResult.NoSlots("NO_COMMON_SLOT");
                var result = slots.Values.ToArray();
                SlotResultJson.Serialize(result, settings.MaximumSlotCount, settings.MaximumPayloadLength);
                return AvailabilityResult.Available(result);
            }
            catch (AvailabilityFailure failure)
            {
                return AvailabilityResult.Failed(failure.Category);
            }
        }

        private static XElement ReadJson(string? json)
        {
            if (string.IsNullOrWhiteSpace(json) || json!.Length > MaximumResponseLength)
                throw InvalidResponse();
            try
            {
                var serializer = new JavaScriptSerializer
                {
                    MaxJsonLength = MaximumResponseLength,
                    RecursionLimit = 32
                };
                serializer.DeserializeObject(json);
                var quotas = new XmlDictionaryReaderQuotas
                {
                    MaxDepth = 32,
                    MaxStringContentLength = MaximumResponseLength,
                    MaxArrayLength = MaximumResponseLength,
                    MaxBytesPerRead = 4096,
                    MaxNameTableCharCount = MaximumResponseLength
                };
                using (var reader = JsonReaderWriterFactory.CreateJsonReader(
                    Encoding.UTF8.GetBytes(json), quotas))
                {
                    var root = XElement.Load(reader);
                    if (reader.Read()) throw InvalidResponse();
                    return root;
                }
            }
            catch (XmlException)
            {
                throw InvalidResponse();
            }
            catch (SerializationException)
            {
                throw InvalidResponse();
            }
            catch (ArgumentException)
            {
                throw InvalidResponse();
            }
            catch (InvalidOperationException)
            {
                throw InvalidResponse();
            }
        }

        private static Dictionary<string, XElement> ReadObject(
            XElement value, IEnumerable<string> allowed, IEnumerable<string> required)
        {
            RequireType(value, "object");
            var allowedNames = new HashSet<string>(allowed, StringComparer.Ordinal);
            var properties = new Dictionary<string, XElement>(StringComparer.Ordinal);
            foreach (var child in value.Elements())
            {
                var name = child.Name.LocalName;
                if (child.Name.Namespace != XNamespace.None || !allowedNames.Contains(name) ||
                    properties.ContainsKey(name))
                    throw InvalidResponse();
                properties.Add(name, child);
            }
            if (required.Any(name => !properties.ContainsKey(name))) throw InvalidResponse();
            return properties;
        }

        private static IReadOnlyList<XElement> ReadArray(XElement value)
        {
            RequireType(value, "array");
            var items = value.Elements().ToArray();
            if (items.Any(item => item.Name != "item")) throw InvalidResponse();
            return items;
        }

        private static void RequireType(XElement value, string type)
        {
            if ((string?)value.Attribute("type") != type ||
                value.Attributes().Any(attribute => attribute.Name != "type"))
                throw InvalidResponse();
        }

        private static string ReadString(XElement value)
        {
            RequireType(value, "string");
            if (value.HasElements) throw InvalidResponse();
            return value.Value;
        }

        private static void ValidateOptionalFields(Dictionary<string, XElement> suggestion)
        {
            if (suggestion.TryGetValue("confidence", out var confidence))
            {
                RequireType(confidence, "number");
                if (confidence.HasElements ||
                    !decimal.TryParse(confidence.Value, NumberStyles.Float, CultureInfo.InvariantCulture,
                        out var number) || number < 0 || number > 100)
                    throw InvalidResponse();
            }
            foreach (var name in new[] { "organizerAvailability", "suggestionReason" })
                if (suggestion.TryGetValue(name, out var value)) ReadString(value);
            if (!suggestion.TryGetValue("locations", out var locations)) return;
            foreach (var item in ReadArray(locations))
            {
                var location = ReadObject(item,
                    new[] { "displayName", "locationEmailAddress", "address" }, Array.Empty<string>());
                foreach (var name in new[] { "displayName", "locationEmailAddress" })
                    if (location.TryGetValue(name, out var value)) ReadString(value);
                if (!location.TryGetValue("address", out var address)) continue;
                var fields = ReadObject(address,
                    new[] { "street", "city", "state", "countryOrRegion", "postalCode" },
                    Array.Empty<string>());
                foreach (var value in fields.Values) ReadString(value);
            }
        }

        private static DateTime ReadUtc(XElement value)
        {
            var fields = ReadObject(value, new[] { "dateTime", "timeZone" },
                new[] { "dateTime", "timeZone" });
            var timeZone = ReadString(fields["timeZone"]);
            if (!string.Equals(timeZone, "UTC", StringComparison.Ordinal))
                throw new AvailabilityFailure("PROVIDER_TIMEZONE_UNSUPPORTED");
            if (!DateTime.TryParseExact(ReadString(fields["dateTime"]), TimestampFormats,
                    CultureInfo.InvariantCulture, DateTimeStyles.None, out var timestamp))
                throw InvalidResponse();
            return DateTime.SpecifyKind(timestamp, DateTimeKind.Utc);
        }

        private static bool RequiredAttendeesAreFree(XElement value, AvailabilityQuery query)
        {
            var taAddress = query.TaEmail!.Trim().ToLowerInvariant();
            var roomAddress = query.Mode == InterviewMode.Onsite
                ? query.RoomEmail!.Trim().ToLowerInvariant() : "";
            var taCount = 0;
            var roomCount = 0;
            var taFree = false;
            var roomFree = false;
            foreach (var item in ReadArray(value))
            {
                var entry = ReadObject(item, new[] { "attendee", "availability" },
                    new[] { "attendee", "availability" });
                var attendee = ReadObject(entry["attendee"], new[] { "type", "emailAddress" },
                    new[] { "type", "emailAddress" });
                var email = ReadObject(attendee["emailAddress"], new[] { "address", "name" },
                    new[] { "address" });
                if (email.TryGetValue("name", out var name)) ReadString(name);
                var address = NormalizeAddress(ReadString(email["address"]));
                var type = ReadString(attendee["type"]);
                var availability = ReadString(entry["availability"]);
                if (!AttendeeTypes.Contains(type, StringComparer.Ordinal) ||
                    !AvailabilityValues.Contains(availability, StringComparer.Ordinal))
                    throw InvalidResponse();

                if (address == taAddress)
                {
                    taCount++;
                    taFree = type == "required" && availability == "free";
                }
                if (query.Mode == InterviewMode.Onsite && address == roomAddress)
                {
                    roomCount++;
                    roomFree = type == "resource" && availability == "free";
                }
            }
            return taCount == 1 && taFree &&
                (query.Mode == InterviewMode.Online || (roomCount == 1 && roomFree));
        }

        private static string NormalizeAddress(string value)
        {
            var address = value.Trim();
            try
            {
                var parsed = new MailAddress(address);
                if (!string.Equals(parsed.Address, address, StringComparison.OrdinalIgnoreCase) ||
                    parsed.Address.Count(character => character == '@') != 1)
                    throw InvalidResponse();
                return address.ToLowerInvariant();
            }
            catch (FormatException)
            {
                throw InvalidResponse();
            }
        }

        private static AvailabilityFailure InvalidResponse() =>
            new AvailabilityFailure("PROVIDER_RESPONSE_INVALID");
    }
}
