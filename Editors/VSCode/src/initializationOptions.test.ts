import assert from "node:assert/strict";
import test from "node:test";
import {
  type ConfigurationReader,
  readInitializationOptions,
} from "./initializationOptions.js";

function configuration(
  values: Record<string, unknown>,
): ConfigurationReader {
  return {
    get<Value>(section: string, defaultValue: Value): Value {
      const value = values[section];
      return value === undefined ? defaultValue : (value as Value);
    },
  };
}

test("Missing settings return empty options", () => {
  const options = readInitializationOptions(configuration({}));

  assert.deepEqual(options, {});
});

test("Workspace settings set server options", () => {
  const options = readInitializationOptions(
    configuration({
      baseline: "Bylaws.baseline.swift",
      only: ["final-classes"],
      refreshDelayMilliseconds: 300,
      rules: ["Rules/Bylaws.swift"],
      skip: ["public-classes"],
    }),
  );

  assert.deepEqual(options, {
    baseline: "Bylaws.baseline.swift",
    only: ["final-classes"],
    refreshDelayMilliseconds: 300,
    rules: ["Rules/Bylaws.swift"],
    skip: ["public-classes"],
  });
});

test("Server options exclude blank paths", () => {
  const options = readInitializationOptions(
    configuration({ baseline: "  ", rules: ["", " ", "Bylaws.swift"] }),
  );

  assert.deepEqual(options, { rules: ["Bylaws.swift"] });
});

test("Server options exclude negative refresh delay", () => {
  const options = readInitializationOptions(
    configuration({ refreshDelayMilliseconds: -300 }),
  );

  assert.deepEqual(options, {});
});

test("Server options exclude values with wrong types", () => {
  const options = readInitializationOptions(
    configuration({
      baseline: 7,
      only: "final-classes",
      refreshDelayMilliseconds: "300",
      rules: [1, "Bylaws.swift", null],
    }),
  );

  assert.deepEqual(options, { rules: ["Bylaws.swift"] });
});
