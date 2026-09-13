import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { runInNewContext } from "node:vm";
import { build } from "esbuild";
import type { LanguageClientOptions } from "vscode-languageclient/node";

for (const folderCount of [0, 1, 2]) {
  test(`Server settings match client folder scope (folder count: ${folderCount})`, async () => {
    const folders = Array.from({ length: folderCount }, (_, index) => ({
      index,
      name: `Project${index}`,
      uri: { fsPath: `/projects/project${index}` },
    }));
    const configurationScopes: unknown[] = [];
    let clientOptions: LanguageClientOptions | undefined;
    let started = false;
    const module = { exports: {} as { activate(): Promise<void> } };
    const result = await build({
      entryPoints: [path.resolve(__dirname, "../src/extension.ts")],
      bundle: true,
      format: "cjs",
      platform: "node",
      write: false,
      plugins: [{
        name: "editor-mocks",
        setup(build) {
          build.onResolve({ filter: /^(vscode|vscode-languageclient\/node|\.\/serverPath\.js)$/ }, (args) => ({
            path: args.path,
            namespace: "editor-mocks",
          }));
          build.onLoad({ filter: /.*/, namespace: "editor-mocks" }, (args) => ({
            contents: args.path === "vscode"
              ? "module.exports = mocks.vscode;"
              : args.path === "./serverPath.js"
                ? "module.exports = mocks.serverPath;"
                : "module.exports = mocks.languageClient;",
          }));
        },
      }],
    });
    const output = result.outputFiles[0];
    assert.ok(output);
    runInNewContext(output.text, {
      module,
      exports: module.exports,
      process,
      mocks: {
        vscode: {
          workspace: {
            workspaceFolders: folders.length > 0 ? folders : undefined,
            getConfiguration(section: string, scope: unknown) {
              assert.equal(section, "bylaws");
              configurationScopes.push(scope);
              return {
                get(key: string, defaultValue: unknown) {
                  if (key === "only") {
                    return scope && scope === folders[0]?.uri ? ["folder-rule"] : ["workspace-rule"];
                  }
                  return defaultValue;
                },
              };
            },
          },
        },
        serverPath: {
          resolveServerPath: async () => ({ kind: "found", path: "/tools/bylaws-lsp" }),
        },
        languageClient: {
          LanguageClient: class {
            constructor(_id: string, _name: string, _server: unknown, options: LanguageClientOptions) {
              clientOptions = options;
            }
            async start() {
              started = true;
            }
          },
        },
      },
    });

    await module.exports.activate();

    assert.deepEqual(configurationScopes, [folders[0]?.uri]);
    assert.equal(clientOptions?.workspaceFolder, folders[0]);
    assert.equal(
      clientOptions?.initializationOptions.only[0],
      folderCount > 0 ? "folder-rule" : "workspace-rule",
    );
    assert.equal(started, true);
  });
}
