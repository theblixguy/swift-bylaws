import assert from "node:assert/strict";
import { delimiter, join } from "node:path";
import { mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import test from "node:test";
import { resolveServerPath, serverExecutableName } from "./serverPath.js";

function executableCheck(paths: string[]): (path: string) => Promise<boolean> {
  const executablePaths = new Set(paths);
  return async (path) => executablePaths.has(path);
}

test("uses the configured executable", async () => {
  const configuredPath = "/Applications/Bylaws/bin/bylaws-lsp";
  const resolution = await resolveServerPath(
    configuredPath,
    "/usr/bin",
    executableCheck([configuredPath]),
  );

  assert.deepEqual(resolution, { kind: "found", path: configuredPath });
});

test("reports a configured path that cannot run", async () => {
  const resolution = await resolveServerPath(
    "/missing/bylaws-lsp",
    "/working/bin",
    executableCheck([join("/working/bin", serverExecutableName)]),
  );

  assert.deepEqual(resolution, {
    kind: "configuredPathNotExecutable",
    path: "/missing/bylaws-lsp",
  });
});

test("rejects a directory as the configured executable", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "bylaws-server-path-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  assert.deepEqual(await resolveServerPath(directory, undefined), {
    kind: "configuredPathNotExecutable",
    path: directory,
  });
});

test("uses a symlink to an executable", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "bylaws-server-path-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, "server");
  await symlink(process.execPath, path);
  assert.deepEqual(await resolveServerPath(path, undefined), { kind: "found", path });
});

test("uses the first executable on PATH", async () => {
  const first = join("/first/bin", serverExecutableName);
  const second = join("/second/bin", serverExecutableName);
  const resolution = await resolveServerPath(
    "",
    ["/first/bin", "/second/bin"].join(delimiter),
    executableCheck([first, second]),
  );

  assert.deepEqual(resolution, { kind: "found", path: first });
});

for (const homebrewPath of [
  "/opt/homebrew/bin/bylaws-lsp",
  "/usr/local/bin/bylaws-lsp",
  "/home/linuxbrew/.linuxbrew/bin/bylaws-lsp",
]) {
  test(`Homebrew executable found at ${homebrewPath}`, async () => {
    const resolution = await resolveServerPath(
      "",
      undefined,
      executableCheck([homebrewPath]),
    );

    assert.deepEqual(resolution, { kind: "found", path: homebrewPath });
  });
}

test("reports when no executable is available", async () => {
  const resolution = await resolveServerPath(
    "",
    "/usr/bin",
    executableCheck([]),
  );

  assert.deepEqual(resolution, { kind: "notFound" });
});
