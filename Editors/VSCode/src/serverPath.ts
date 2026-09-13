import { constants } from "node:fs";
import { access, stat } from "node:fs/promises";
import { delimiter, join } from "node:path";

export const serverExecutableName = "bylaws-lsp";

const homebrewServerPaths = [
  "/opt/homebrew/bin/bylaws-lsp",
  "/usr/local/bin/bylaws-lsp",
  "/home/linuxbrew/.linuxbrew/bin/bylaws-lsp",
];

export type ServerPathResolution =
  | { kind: "found"; path: string }
  | { kind: "configuredPathNotExecutable"; path: string }
  | { kind: "notFound" };

type ExecutableCheck = (path: string) => Promise<boolean>;

export async function resolveServerPath(
  configuredPath: string,
  pathEnvironment: string | undefined,
  isExecutable: ExecutableCheck = checkExecutable,
): Promise<ServerPathResolution> {
  const path = configuredPath.trim();
  if (path.length > 0) {
    return (await isExecutable(path))
      ? { kind: "found", path }
      : { kind: "configuredPathNotExecutable", path };
  }

  const pathCandidates = (pathEnvironment ?? "")
    .split(delimiter)
    .filter((directory) => directory.length > 0)
    .map((directory) => join(directory, serverExecutableName));

  for (const candidate of new Set([...pathCandidates, ...homebrewServerPaths])) {
    if (await isExecutable(candidate)) {
      return { kind: "found", path: candidate };
    }
  }
  return { kind: "notFound" };
}

async function checkExecutable(path: string): Promise<boolean> {
  try {
    await access(path, constants.X_OK);
    return (await stat(path)).isFile();
  } catch {
    return false;
  }
}
