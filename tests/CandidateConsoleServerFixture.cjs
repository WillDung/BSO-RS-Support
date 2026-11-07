"use strict";

function sqlLike(value, pattern) {
  let regex = "^";
  for (let index = 0; index < pattern.length; index += 1) {
    const character = pattern[index];
    if (character === "%") regex += ".*";
    else if (character === "_") regex += ".";
    else if (pattern.slice(index, index + 3) === "[[]") {
      regex += "\\[";
      index += 2;
    } else if (pattern.slice(index, index + 3) === "[]]") {
      regex += "\\]";
      index += 2;
    } else if (character === "[") {
      const end = pattern.indexOf("]", index + 1);
      if (end < 0) throw new Error("Unterminated fixture wildcard class");
      regex += pattern.slice(index, end + 1);
      index = end;
    } else {
      regex += character.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
  }
  return new RegExp(`${regex}$`, "i").test(value);
}

function attributeValue(row, path) {
  return path.split("/").reduce((value, part) => value == null ? undefined : value[part], row);
}

function splitTopLevel(expression, operator) {
  const parts = [];
  let start = 0;
  let depth = 0;
  let quoted = false;
  for (let index = 0; index < expression.length; index += 1) {
    const character = expression[index];
    if (character === "'") {
      if (quoted && expression[index + 1] === "'") index += 1;
      else quoted = !quoted;
    } else if (!quoted) {
      if (character === "(") depth += 1;
      else if (character === ")") depth -= 1;
      else if (depth === 0 && expression.slice(index, index + operator.length).toLowerCase() === operator) {
        parts.push(expression.slice(start, index).trim());
        index += operator.length - 1;
        start = index + 1;
      }
    }
  }
  parts.push(expression.slice(start).trim());
  return parts;
}

function matchesFilter(row, filter) {
  if (!filter) return true;
  function evaluate(expression) {
    let part = expression.trim();
    if (part.startsWith("(") && part.endsWith(")") &&
        splitTopLevel(part.slice(1, -1), " or ").length > 1) {
      part = part.slice(1, -1);
    }
    const alternatives = splitTopLevel(part, " or ");
    if (alternatives.length > 1) return alternatives.some(evaluate);
    const conjunction = splitTopLevel(part, " and ");
    if (conjunction.length > 1) return conjunction.every(evaluate);
    const isNull = /^([a-z0-9_/]+) eq null$/i.exec(part);
    if (isNull) return attributeValue(row, isNull[1]) == null;
    const equal = /^([a-z0-9_/]+) eq (\d+)$/i.exec(part);
    if (equal) return attributeValue(row, equal[1]) === Number(equal[2]);
    const equalGuid = /^([a-z0-9_/]+) eq ([0-9a-f-]{36})$/i.exec(part);
    if (equalGuid) {
      return String(attributeValue(row, equalGuid[1]) || "").toLowerCase() === equalGuid[2].toLowerCase();
    }
    const equalString = /^([a-z0-9_/]+) eq '((?:''|[^'])*)'$/i.exec(part);
    if (equalString) {
      const value = attributeValue(row, equalString[1]);
      return typeof value === "string" && value.toLowerCase() === equalString[2].replace(/''/g, "'").toLowerCase();
    }
    const stringFunction = /^(startswith|endswith)\(([a-z0-9_/]+),'((?:''|[^'])*)'\)$/i.exec(part);
    if (stringFunction) {
      const value = attributeValue(row, stringFunction[2]);
      if (typeof value !== "string") return false;
      const pattern = stringFunction[3].replace(/''/g, "'");
      return sqlLike(value, stringFunction[1].toLowerCase() === "startswith"
        ? `${pattern}%` : `%${pattern}`);
    }
    throw new Error(`Unsupported fixture predicate: ${part}`);
  }
  return evaluate(filter);
}

function project(row, select) {
  if (!select) return { ...row };
  const result = {};
  for (const column of select.split(",")) {
    if (Object.hasOwn(row, column)) result[column] = row[column];
    for (const key of Object.keys(row)) {
      if (key.startsWith(`${column}@`)) result[key] = row[key];
    }
  }
  return result;
}

// The optional scope simulates independent server authorization, never browser-provided approval.
function createServer(fixtures, { authorized = () => true, fail, pageSize = 0 } = {}) {
  const requests = [];
  const responses = [];
  const pages = new Map();
  let nextPage = 0;
  const api = {
    async retrieveMultipleRecords(table, query) {
      requests.push({ operation: "retrieveMultipleRecords", table, query });
      if (fail) {
        const error = fail(table, query);
        if (error) throw error;
      }
      let rows;
      let select;
      if (pages.has(query)) {
        const page = pages.get(query);
        if (page.table !== table) throw new Error("Fixture paging table changed");
        ({ rows, select } = page);
      } else {
        if (!query.startsWith("?")) throw new Error("Unexpected fixture continuation link");
        const params = new URLSearchParams(query.slice(1));
        const filter = params.get("$filter");
        select = params.get("$select");
        rows = (fixtures[table] || []).filter((row) => authorized(table, row) && matchesFilter(row, filter));
        const top = Number(params.get("$top"));
        if (top > 0) rows = rows.slice(0, top);
      }
      const count = pageSize || rows.length;
      const entities = rows.slice(0, count).map((row) => project(row, select));
      const result = { entities };
      if (pageSize && rows.length > count) {
        const nextLink = `https://fixture.invalid/continuation/${++nextPage}?token=%2F%2B%3D`;
        pages.set(nextLink, { table, rows: rows.slice(count), select });
        result.nextLink = nextLink;
      }
      responses.push({ table, query, entities, nextLink: result.nextLink });
      return result;
    },
    async retrieveRecord(table, recordId, query) {
      requests.push({ operation: "retrieveRecord", table, recordId, query });
      const entity = (fixtures[table] || []).find((row) =>
        row[`${table}id`] === recordId && authorized(table, row));
      if (!entity) throw new Error("RECORD_NOT_FOUND");
      const select = query ? new URLSearchParams(query.replace(/^\?/, "")).get("$select") : null;
      const response = project(entity, select);
      responses.push({ table, recordId, entity: response });
      return response;
    },
    async createRecord(table, payload) {
      requests.push({ operation: "createRecord", table, payload });
      throw new Error("Unexpected fixture write");
    },
    async updateRecord(table, recordId, payload) {
      requests.push({ operation: "updateRecord", table, recordId, payload });
      throw new Error("Unexpected fixture write");
    }
  };
  return { api, requests, responses };
}

module.exports = { createServer, matchesFilter };
