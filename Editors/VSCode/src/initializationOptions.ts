export interface ConfigurationReader {
  get<Value>(section: string, defaultValue: Value): Value;
}

export interface InitializationOptions {
  baseline?: string;
  only?: string[];
  refreshDelayMilliseconds?: number;
  rules?: string[];
  skip?: string[];
}

export function readInitializationOptions(
  configuration: ConfigurationReader,
): InitializationOptions {
  const options: InitializationOptions = {};

  const baseline = readString(configuration, "baseline");
  if (baseline.length > 0) {
    options.baseline = baseline;
  }

  const only = readStrings(configuration, "only");
  if (only.length > 0) {
    options.only = only;
  }

  const delay = readDelay(configuration, "refreshDelayMilliseconds");
  if (delay > 0) {
    options.refreshDelayMilliseconds = delay;
  }

  const rules = readStrings(configuration, "rules");
  if (rules.length > 0) {
    options.rules = rules;
  }

  const skip = readStrings(configuration, "skip");
  if (skip.length > 0) {
    options.skip = skip;
  }

  return options;
}

function readString(
  configuration: ConfigurationReader,
  section: string,
): string {
  const value = configuration.get<unknown>(section, "");
  return typeof value === "string" ? value.trim() : "";
}

function readStrings(
  configuration: ConfigurationReader,
  section: string,
): string[] {
  const values = configuration.get<unknown>(section, []);
  if (!Array.isArray(values)) {
    return [];
  }
  return values
    .filter((value): value is string => typeof value === "string")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
}

function readDelay(
  configuration: ConfigurationReader,
  section: string,
): number {
  const value = configuration.get<unknown>(section, 0);
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    return 0;
  }
  return value > 0 ? value : 0;
}
