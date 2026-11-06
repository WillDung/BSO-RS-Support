"use strict";

const fs = require("node:fs");
const path = require("node:path");

const definition = JSON.parse(fs.readFileSync(path.join(
  __dirname, "..", "..", "solutions", "AvailabilityQuery", "os_sr_avchk.clientdata.json"
), "utf8")).properties.definition;

const IDS = Object.freeze({
  query: "33333333-3333-4333-8333-333333333333",
  ta: "11111111-1111-4111-8111-111111111111",
  location: "22222222-2222-4222-8222-222222222222"
});

function buildFixture(now = new Date()) {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 2));
  while ([0, 6].includes(start.getUTCDay())) start.setUTCDate(start.getUTCDate() + 1);
  const end = new Date(start.getTime() + 3 * 3600000);
  const slotEnd = new Date(start.getTime() + 3600000);
  const hours = Object.fromEntries(["monday", "tuesday", "wednesday", "thursday", "friday"]
    .map((day) => [day, { opens: "09:00", closes: "17:00" }]));
  const settings = {
    os_sr_avq_bhrs: JSON.stringify(hours),
    os_sr_avq_durs: "30,60",
    os_sr_avq_lead: "15",
    os_sr_avq_hzn: "7",
    os_sr_avq_exp: "10",
    os_sr_avq_dom: "example.invalid",
    os_sr_avq_maxc: "10"
  };
  const parameters = {};
  for (const [name, parameter] of Object.entries(definition.parameters)) {
    const schema = parameter.metadata && parameter.metadata.schemaName;
    if (schema) {
      if (!Object.hasOwn(settings, schema)) throw new Error("Unmapped Flow environment parameter");
      parameters[name] = parameter.type === "Float" ? Number(settings[schema]) : settings[schema];
    }
  }
  const references = {
    ta: { id: IDS.ta, statecode: 0, email: "ta@example.invalid" },
    location: { id: IDS.location, statecode: 0, roomEmail: "room@example.invalid" }
  };
  const canonicalTime = (date) => date.toISOString().replace(".000Z", "Z");
  return {
    now: now.toISOString(), start, end, slotEnd, settings, parameters, references,
    localStart: start.toISOString().slice(0, 10) + "T09:00",
    localEnd: end.toISOString().slice(0, 10) + "T12:00",
    canonicalSlots: JSON.stringify([{ startUtc: canonicalTime(start), endUtc: canonicalTime(slotEnd) }])
  };
}

function providerResult(fixture, { onsite = false, roomBusy = false, empty = false } = {}) {
  const attendee = (address, type, availability) => ({
    attendee: { emailAddress: { address }, type }, availability
  });
  const attendees = [attendee(fixture.references.ta.email, "required", "free")];
  if (onsite) attendees.push(attendee(fixture.references.location.roomEmail, "resource",
    roomBusy ? "busy" : "free"));
  return {
    emptySuggestionsReason: empty ? "SYNTHETIC_PROVIDER_REASON_NOT_FOR_PERSISTENCE" : "",
    meetingTimeSuggestions: empty ? [] : [{
      meetingTimeSlot: {
        start: { dateTime: fixture.start.toISOString().slice(0, 19), timeZone: "UTC" },
        end: { dateTime: fixture.slotEnd.toISOString().slice(0, 19), timeZone: "UTC" }
      },
      attendeeAvailability: attendees
    }]
  };
}

module.exports = { IDS, buildFixture, providerResult };
