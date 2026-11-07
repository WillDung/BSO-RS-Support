"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { isDeepStrictEqual } = require("node:util");

class Unsupported extends Error {}
class EvaluationError extends Error {}
const fail = (message) => { throw new EvaluationError(message); };
const clone = (value) => structuredClone(value);
const numericEqual = (a, b) => typeof a === "bigint" || typeof b === "bigint"
  ? (["bigint", "number"].includes(typeof a) && ["bigint", "number"].includes(typeof b) &&
    Number.isInteger(Number(a)) && Number.isInteger(Number(b)) && BigInt(a) === BigInt(b))
  : isDeepStrictEqual(a, b);

function parseExpression(text) {
  let position = 0;
  const whitespace = () => { while (/\s/.test(text[position] || "") && position < text.length) position++; };
  function value() {
    whitespace();
    let node;
    if (text[position] === "'") {
      position++;
      let string = "";
      let closed = false;
      while (position < text.length) {
        if (text[position] === "'") {
          position++;
          if (text[position] === "'") { string += "'"; position++; }
          else { closed = true; break; }
        } else string += text[position++];
      }
      if (!closed) throw new Unsupported("Unterminated WDL string");
      node = { literal: string };
    } else {
      const number = /^-?\d+(?:\.\d+)?/.exec(text.slice(position));
      const identifier = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(text.slice(position));
      if (number) {
        position += number[0].length;
        node = { literal: Number(number[0]) };
      } else if (identifier) {
        const name = identifier[0];
        position += name.length;
        whitespace();
        if (text[position] === "(") {
          position++;
          const args = [];
          whitespace();
          if (text[position] !== ")") {
            for (;;) {
              args.push(value());
              whitespace();
              if (text[position] !== ",") break;
              position++;
            }
          }
          if (text[position++] !== ")") throw new Unsupported("Invalid WDL call");
          node = { name, args };
        } else if (["true", "false", "null"].includes(name)) {
          node = { literal: JSON.parse(name) };
        } else throw new Unsupported("Unsupported WDL identifier: " + name);
      } else throw new Unsupported("Unsupported WDL token");
    }
    for (;;) {
      whitespace();
      const optional = text[position] === "?";
      if (optional) position++;
      if (text[position] !== "[") {
        if (optional) throw new Unsupported("Unsupported optional WDL access");
        break;
      }
      position++;
      const key = value();
      whitespace();
      if (text[position++] !== "]") throw new Unsupported("Invalid WDL property access");
      node = { target: node, key, optional };
    }
    return node;
  }
  const result = value();
  whitespace();
  if (position !== text.length) throw new Unsupported("Unconsumed WDL expression");
  return result;
}

function validateSchema(value, schema) {
  const supported = new Set(["type", "properties", "required", "additionalProperties", "items",
    "enum", "not", "pattern", "minimum", "maximum", "multipleOf", "minItems", "maxItems",
    "uniqueItems", "minProperties", "maxLength"]);
  for (const key of Object.keys(schema)) {
    if (!supported.has(key)) throw new Unsupported("Unsupported fixture JSON Schema keyword: " + key);
  }
  if ((schema.additionalProperties !== undefined && typeof schema.additionalProperties !== "boolean") ||
      Array.isArray(schema.items)) {
    throw new Unsupported("Unsupported fixture JSON Schema form");
  }
  const isType = (type) => ({
    null: value === null,
    string: typeof value === "string",
    integer: typeof value === "number" && Number.isInteger(value),
    number: typeof value === "number" && Number.isFinite(value),
    boolean: typeof value === "boolean",
    object: value !== null && typeof value === "object" && !Array.isArray(value),
    array: Array.isArray(value)
  })[type] ?? (() => { throw new Unsupported("Unsupported JSON Schema type"); })();
  if (schema.type && !(Array.isArray(schema.type) ? schema.type : [schema.type]).some(isType)) {
    fail("JSON Schema type mismatch");
  }
  if (schema.enum && !schema.enum.some((item) => numericEqual(item, value))) fail("JSON Schema enum");
  if (schema.not) {
    let matches = true;
    try { validateSchema(value, schema.not); } catch (error) {
      if (!(error instanceof EvaluationError)) throw error;
      matches = false;
    }
    if (matches) fail("JSON Schema not");
  }
  if (typeof value === "string") {
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) fail("JSON Schema pattern");
    if (schema.maxLength !== undefined && [...value].length > schema.maxLength) fail("JSON Schema length");
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) fail("JSON Schema minimum");
    if (schema.maximum !== undefined && value > schema.maximum) fail("JSON Schema maximum");
    if (schema.multipleOf !== undefined && value % schema.multipleOf !== 0) fail("JSON Schema multiple");
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) fail("JSON Schema minItems");
    if (schema.maxItems !== undefined && value.length > schema.maxItems) fail("JSON Schema maxItems");
    if (schema.uniqueItems && value.some((entry, index) =>
      value.slice(0, index).some((other) => isDeepStrictEqual(entry, other)))) fail("JSON Schema uniqueItems");
    if (schema.items) for (const item of value) validateSchema(item, schema.items);
  } else if (value !== null && typeof value === "object") {
    if (schema.minProperties !== undefined && Object.keys(value).length < schema.minProperties) {
      fail("JSON Schema minProperties");
    }
    for (const key of schema.required || []) if (!Object.hasOwn(value, key)) fail("JSON Schema required");
    for (const [key, entry] of Object.entries(value)) {
      if (Object.hasOwn(schema.properties || {}, key)) validateSchema(entry, schema.properties[key]);
      else if (schema.additionalProperties === false) fail("JSON Schema extra property");
    }
  }
}

function dateValue(value) {
  if (typeof value !== "string" ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,7})?Z?$/.test(value)) {
    return fail("Invalid fixture UTC timestamp");
  }
  const normalized = value.endsWith("Z") ? value : value + "Z";
  const date = new Date(normalized);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 19) !== value.slice(0, 19)) {
    return fail("Invalid calendar timestamp");
  }
  return date;
}

function formatTime(value, format, offset = 0) {
  const date = new Date(dateValue(value).getTime() + offset * 60000);
  const iso = date.toISOString();
  const formats = {
    "yyyy-MM-dd": iso.slice(0, 10),
    "HH:mm": iso.slice(11, 16),
    dddd: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][date.getUTCDay()],
    "yyyy-MM-ddTHH:mm:ssZ": iso.slice(0, 19) + "Z",
    "yyyy-MM-ddTHH:mm:ss.fffffffZ": iso.slice(0, 19) + "." +
      ((/\.(\d+)/.exec(value) || [null, ""])[1]).padEnd(7, "0") + "Z"
  };
  if (!Object.hasOwn(formats, format)) throw new Unsupported("Unsupported fixture date format: " + format);
  return formats[format];
}

class FlowFixture {
  constructor(options) {
    this.options = options;
    this.records = {};
    this.variables = {};
    this.items = [];
    this.loops = {};
    this.calls = [];
    this.cache = new Map();
    this.terminated = false;
  }

  evaluate(value) {
    if (Array.isArray(value)) return value.map((item) => this.evaluate(item));
    if (value && typeof value === "object") {
      return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, this.evaluate(item)]));
    }
    if (typeof value !== "string" || !value.startsWith("@")) return value;
    if (value.startsWith("@@")) return value.slice(1);
    if (value.startsWith("@{")) throw new Unsupported("Fixture interpolation is not implemented");
    if (!this.cache.has(value)) this.cache.set(value, parseExpression(value.slice(1)));
    return this.node(this.cache.get(value));
  }

  node(node) {
    if (Object.hasOwn(node, "literal")) return node.literal;
    if (node.target) {
      let target = this.node(node.target);
      const key = this.node(node.key);
      const keys = target !== null && typeof target === "object" && Object.hasOwn(target, key)
        ? [key] : String(key).split("/");
      for (const part of keys) {
        if (target === null || target === undefined || !Object.hasOwn(Object(target), part)) {
          if (node.optional) return null;
          return fail("Missing WDL property");
        }
        target = target[part];
      }
      return target;
    }
    if (node.name.toLowerCase() === "if") {
      const condition = this.node(node.args[0]);
      if (typeof condition !== "boolean") return fail("WDL if requires a boolean");
      return this.node(node.args[condition ? 1 : 2]);
    }
    return this.call(node.name, node.args.map((arg) => this.node(arg)));
  }

  call(name, args) {
    const [a, b, c] = args;
    const text = (value) => {
      if (typeof value !== "string") return fail("WDL string argument required");
      return value;
    };
    const numberPair = (operation) => {
      if (![a, b].every((v) => ["number", "bigint"].includes(typeof v))) return fail("WDL numeric arguments required");
      return typeof a === "bigint" || typeof b === "bigint"
        ? operation(BigInt(a), BigInt(b)) : operation(a, b);
    };
    switch (name.toLowerCase()) {
      case "variables":
        if (!Object.hasOwn(this.variables, a)) return fail("Missing WDL variable");
        return this.variables[a];
      case "parameters":
        if (!Object.hasOwn(this.options.parameters, a)) return fail("Missing WDL parameter");
        return this.options.parameters[a];
      case "triggeroutputs": return { body: this.options.query };
      case "body": return this.records[a]?.outputs?.body ?? null;
      case "outputs": return this.records[a]?.outputs ?? null;
      case "actions": return this.records[a] ?? null;
      case "item":
        if (!this.items.length) return fail("No WDL item context");
        return this.items[this.items.length - 1];
      case "items":
        if (!Object.hasOwn(this.loops, a)) return fail("No WDL loop context");
        return this.loops[a];
      case "utcnow": return this.options.now;
      case "coalesce": return args.find((v) => v !== null && v !== undefined) ?? null;
      case "equals": return numericEqual(a, b);
      case "and":
      case "or":
        if (!args.every((v) => typeof v === "boolean")) return fail("WDL boolean arguments required");
        return name.toLowerCase() === "and" ? args.every(Boolean) : args.some(Boolean);
      case "not":
        if (typeof a !== "boolean") return fail("WDL boolean argument required");
        return !a;
      case "greater": return numberPair((x, y) => x > y);
      case "greaterorequals": return numberPair((x, y) => x >= y);
      case "less": return numberPair((x, y) => x < y);
      case "lessorequals": return numberPair((x, y) => x <= y);
      case "add": return numberPair((x, y) => x + y);
      case "sub": return numberPair((x, y) => x - y);
      case "mul": return numberPair((x, y) => x * y);
      case "mod":
        if (b === 0 || b === 0n) return fail("WDL division by zero");
        return numberPair((x, y) => x % y);
      case "min": return args.reduce((x, y) => x < y ? x : y);
      case "int":
        if (!/^[+-]?\d+$/.test(String(a)) || !Number.isSafeInteger(Number(a))) return fail("Invalid WDL integer");
        return Number(a);
      case "string":
        return a === null || a === undefined ? "" : typeof a === "object" ? JSON.stringify(a) : String(a);
      case "json":
        try { return JSON.parse(text(a)); } catch (error) {
          if (error instanceof SyntaxError) return fail("Invalid WDL JSON");
          throw error;
        }
      case "concat": return args.map(text).join("");
      case "tolower": return text(a).toLowerCase();
      case "trim": return text(a).trim();
      case "uricomponent":
        try { return encodeURIComponent(text(a)); } catch (error) {
          if (error instanceof URIError) return fail("Invalid WDL URI component");
          throw error;
        }
      case "split": return text(a).split(text(b));
      case "startswith": return text(a).startsWith(text(b));
      case "endswith": return text(a).endsWith(text(b));
      case "substring":
        if (!Number.isInteger(b) || b < 0 || b > text(a).length ||
            (c !== undefined && (!Number.isInteger(c) || c < 0 || b + c > a.length))) {
          return fail("Invalid WDL substring");
        }
        return a.substring(b, c === undefined ? undefined : b + c);
      case "length":
        if (typeof a !== "string" && !Array.isArray(a)) return fail("Invalid WDL length");
        return a.length;
      case "empty":
        if (a === null || a === undefined) return true;
        if (typeof a === "string" || Array.isArray(a)) return a.length === 0;
        if (typeof a === "object") return Object.keys(a).length === 0;
        return fail("Invalid WDL empty");
      case "contains":
        if (typeof a === "string") return a.includes(text(b));
        if (Array.isArray(a)) return a.some((value) => numericEqual(value, b));
        if (a && typeof a === "object") return Object.hasOwn(a, b);
        return fail("Invalid WDL contains");
      case "first":
      case "last":
        if ((!Array.isArray(a) && typeof a !== "string") || !a.length) return fail("Invalid WDL first/last");
        return a[name.toLowerCase() === "first" ? 0 : a.length - 1];
      case "createarray": return args;
      case "union":
        if (!args.every(Array.isArray)) return fail("Fixture union requires arrays");
        return args.flat().filter((entry, index, entries) =>
          entries.findIndex((other) => isDeepStrictEqual(entry, other)) === index);
      case "sort":
        if (!Array.isArray(a)) return fail("WDL sort requires an array");
        return [...a].sort((x, y) => {
          const left = b === undefined ? x : x[b];
          const right = b === undefined ? y : y[b];
          return left < right ? -1 : left > right ? 1 : 0;
        });
      case "ticks": {
        const milliseconds = dateValue(a).getTime();
        const fraction = ((/\.(\d+)/.exec(a) || [null, ""])[1]).padEnd(7, "0");
        return 621355968000000000n + BigInt(milliseconds) * 10000n + BigInt(fraction.slice(3));
      }
      case "addminutes":
      case "adddays": {
        if (typeof b !== "number" || !Number.isFinite(b)) return fail("Invalid WDL date offset");
        const milliseconds = dateValue(a).getTime() + b * (name.toLowerCase() === "adddays" ? 86400000 : 60000);
        const date = new Date(milliseconds);
        if (!Number.isFinite(date.getTime())) return fail("WDL date overflow");
        return date.toISOString();
      }
      case "formatdatetime": return formatTime(a, b);
      case "convertfromutc":
        if (b !== "SE Asia Standard Time") throw new Unsupported("Unsupported fixture timezone");
        return formatTime(a, c, 420);
      case "xml": return { fixtureXml: a };
      case "xpath":
        if (b !== "count(/r/*)" || !a?.fixtureXml?.r || typeof a.fixtureXml.r !== "object") {
          throw new Unsupported("Unsupported fixture XML/XPath shape");
        }
        return Object.keys(a.fixtureXml.r).length;
      default: throw new Unsupported("Unsupported WDL function: " + name);
    }
  }

  skip(name, action) {
    this.records[name] = { status: "Skipped" };
    for (const [child, definition] of Object.entries(action.actions || {})) this.skip(child, definition);
    for (const [child, definition] of Object.entries(action.else?.actions || {})) this.skip(child, definition);
  }

  async sequence(actions) {
    const pending = new Set(Object.keys(actions));
    const completed = new Set();
    for (const name of pending) this.records[name] = { status: "NotStarted" };
    while (pending.size && !this.terminated) {
      let progress = false;
      for (const name of [...pending]) {
        if (this.terminated) break;
        const action = actions[name];
        const dependencies = Object.entries(action.runAfter || {});
        if (!dependencies.every(([dependency]) => !pending.has(dependency) &&
            (completed.has(dependency) || this.records[dependency]))) continue;
        pending.delete(name);
        completed.add(name);
        progress = true;
        if (!dependencies.every(([dependency, statuses]) => statuses.includes(this.records[dependency].status))) {
          this.skip(name, action);
          continue;
        }
        await this.action(name, action);
      }
      if (!progress) throw new Unsupported("Unresolved Flow runAfter dependency");
    }
    if (this.terminated) for (const name of pending) this.skip(name, actions[name]);
    return [...completed].some((name) => ["Failed", "TimedOut"].includes(this.records[name].status))
      ? "Failed" : "Succeeded";
  }

  async action(name, action) {
    const record = this.records[name] = { status: "Running" };
    try {
      switch (action.type) {
        case "InitializeVariable":
          for (const variable of action.inputs.variables) this.variables[variable.name] = this.evaluate(variable.value);
          break;
        case "SetVariable": this.variables[action.inputs.name] = this.evaluate(action.inputs.value); break;
        case "AppendToArrayVariable":
          if (!Array.isArray(this.variables[action.inputs.name])) fail("Expected array variable");
          this.variables[action.inputs.name].push(this.evaluate(action.inputs.value));
          break;
        case "Compose": record.outputs = this.evaluate(action.inputs); break;
        case "ParseJson": {
          const content = this.evaluate(action.inputs.content);
          let parsed = content;
          if (typeof content === "string") {
            try { parsed = JSON.parse(content); } catch { fail("ParseJson invalid JSON"); }
          }
          validateSchema(parsed, action.inputs.schema);
          record.outputs = { body: clone(parsed) };
          break;
        }
        case "Select":
        case "Query": {
          const source = this.evaluate(action.inputs.from);
          if (!Array.isArray(source)) fail("Data operation requires an array");
          const result = [];
          for (const item of source) {
            this.items.push(item);
            try {
              if (action.type === "Select") result.push(this.evaluate(action.inputs.select));
              else {
                const keep = this.evaluate(action.inputs.where);
                if (typeof keep !== "boolean") fail("Query requires boolean predicate");
                if (keep) result.push(item);
              }
            } finally { this.items.pop(); }
          }
          record.outputs = { body: result };
          break;
        }
        case "Scope": record.status = await this.sequence(action.actions || {}); break;
        case "If": {
          const condition = this.evaluate(action.expression);
          if (typeof condition !== "boolean") fail("If action requires a boolean");
          const selected = condition ? action.actions || {} : action.else?.actions || {};
          const excluded = condition ? action.else?.actions || {} : action.actions || {};
          for (const [child, definition] of Object.entries(excluded)) this.skip(child, definition);
          record.status = await this.sequence(selected);
          break;
        }
        case "Foreach": {
          const source = this.evaluate(action.foreach);
          if (!Array.isArray(source)) fail("Foreach requires an array");
          for (const item of source) {
            this.loops[name] = item;
            this.items.push(item);
            try {
              if (await this.sequence(action.actions || {}) === "Failed") {
                record.status = "Failed";
                break;
              }
            } finally { this.items.pop(); }
          }
          delete this.loops[name];
          if (!source.length) {
            for (const [child, definition] of Object.entries(action.actions || {})) this.skip(child, definition);
          }
          break;
        }
        case "Terminate":
          this.terminated = true;
          this.runStatus = action.inputs.runStatus;
          break;
        case "OpenApiConnection": await this.connector(name, action, record); break;
        default: throw new Unsupported("Unsupported Flow action: " + action.type);
      }
      if (record.status === "Running") record.status = "Succeeded";
    } catch (error) {
      if (!(error instanceof EvaluationError)) throw error;
      record.status = "Failed";
      record.error = { code: "FixtureEvaluationFailed", message: error.message };
      for (const [child, definition] of Object.entries(action.actions || {})) this.skip(child, definition);
      for (const [child, definition] of Object.entries(action.else?.actions || {})) this.skip(child, definition);
    }
  }

  async connector(name, action, record) {
    const inputs = this.evaluate(action.inputs);
    if (inputs.retryPolicy?.type !== "none") throw new Unsupported("Fixture connectors require explicit no-retry");
    const operation = inputs.host.operationId;
    const callbacks = {
      GetItem: this.options.getItem,
      UpdateOnlyRecord: this.options.updateItem,
      FindMeetingTimes_V2: this.options.outlook
    };
    if (!Object.hasOwn(callbacks, operation) || typeof callbacks[operation] !== "function") {
      throw new Unsupported("Unstubbed connector operation: " + operation);
    }
    this.calls.push({ name, operation, parameters: clone(inputs.parameters) });
    try {
      record.outputs = { body: await callbacks[operation](inputs.parameters, name), statusCode: 200 };
    } catch (error) {
      if (error instanceof Unsupported || error.name === "AssertionError") throw error;
      record.status = error.status === "TimedOut" ? "TimedOut" : "Failed";
      record.outputs = {
        statusCode: error.statusCode ?? null,
        body: error.body ?? { error: { code: "SyntheticConnectorFailure" } }
      };
    }
  }
}

async function runFlow(options) {
  const source = options.definition || JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..",
    "solutions", "AvailabilityQuery", "os_sr_avchk.clientdata.json"), "utf8")).properties.definition;
  if (!options.query || !options.parameters || !options.now) throw new Unsupported("Missing Flow fixture inputs");
  const defaults = Object.fromEntries(Object.entries(source.parameters || {})
    .filter(([, parameter]) => Object.hasOwn(parameter, "defaultValue"))
    .map(([name, parameter]) => [name, clone(parameter.defaultValue)]));
  const runner = new FlowFixture({ ...options, parameters: { ...defaults, ...options.parameters } });
  const status = await runner.sequence(source.actions);
  return {
    status: runner.runStatus || status,
    variables: runner.variables,
    outputs: Object.fromEntries(Object.entries(runner.records).map(([key, value]) => [key, value.outputs])),
    statuses: Object.fromEntries(Object.entries(runner.records).map(([key, value]) => [key, value.status])),
    errors: Object.fromEntries(Object.entries(runner.records)
      .filter(([, value]) => value.error).map(([key, value]) => [key, value.error])),
    calls: runner.calls
  };
}

module.exports = { runFlow, parseExpression, validateSchema, EvaluationError, Unsupported };
