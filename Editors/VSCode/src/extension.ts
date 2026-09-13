import * as vscode from "vscode";
import {
  LanguageClient,
  type LanguageClientOptions,
  type ServerOptions,
} from "vscode-languageclient/node";
import {
  type InitializationOptions,
  readInitializationOptions,
} from "./initializationOptions.js";
import { resolveServerPath } from "./serverPath.js";

const configurationSection = "bylaws";
const serverPathSetting = "serverPath";
const openSettingsAction = "Open Settings";

let client: LanguageClient | undefined;

export async function activate(): Promise<void> {
  const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
  const configuration = vscode.workspace.getConfiguration(
    configurationSection,
    workspaceFolder?.uri,
  );
  const configuredPath = configuration.get<string>(serverPathSetting, "");
  const resolution = await resolveServerPath(configuredPath, process.env.PATH);

  switch (resolution.kind) {
    case "found":
      await startClient(
        resolution.path,
        readInitializationOptions(configuration),
        workspaceFolder,
      );
      return;
    case "configuredPathNotExecutable":
      await showServerPathError(
        `Bylaws Language Server cannot run at '${resolution.path}'. Set Bylaws: Server Path to an executable file.`,
      );
      return;
    case "notFound":
      await showServerPathError(
        "Bylaws Language Server was not found. Install Bylaws for macOS or Linux and set Bylaws: Server Path if the editor cannot find it.",
      );
      return;
    default:
      resolution satisfies never;
  }
}

export async function deactivate(): Promise<void> {
  await client?.stop();
  client = undefined;
}

async function startClient(
  serverPath: string,
  initializationOptions: InitializationOptions,
  workspaceFolder: vscode.WorkspaceFolder | undefined,
): Promise<void> {
  const serverOptions: ServerOptions = {
    command: serverPath,
  };
  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ language: "swift", scheme: "file" }],
    initializationOptions,
  };
  if (workspaceFolder !== undefined) {
    clientOptions.workspaceFolder = workspaceFolder;
  }
  client = new LanguageClient(
    "bylaws",
    "Bylaws",
    serverOptions,
    clientOptions,
  );
  await client.start();
}

async function showServerPathError(message: string): Promise<void> {
  const action = await vscode.window.showErrorMessage(
    message,
    openSettingsAction,
  );
  if (action === openSettingsAction) {
    await vscode.commands.executeCommand(
      "workbench.action.openSettings",
      `${configurationSection}.${serverPathSetting}`,
    );
  }
}
