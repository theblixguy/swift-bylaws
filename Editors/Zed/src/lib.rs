use zed_extension_api::settings::LspSettings;
use zed_extension_api::{self as zed, LanguageServerId, Worktree};

const SERVER_EXECUTABLE: &str = "bylaws-lsp";

struct BylawsExtension;

impl zed::Extension for BylawsExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> zed::Result<zed::Command> {
        let settings = LspSettings::for_worktree(language_server_id.as_ref(), worktree)?;
        let command = settings
            .binary
            .as_ref()
            .and_then(|binary| binary.path.clone())
            .or_else(|| worktree.which(SERVER_EXECUTABLE))
            .ok_or_else(|| {
                "Bylaws Language Server was not found. Install Bylaws with Homebrew or set lsp.bylaws.binary.path."
                    .to_owned()
            })?;
        let args = settings
            .binary
            .as_ref()
            .and_then(|binary| binary.arguments.clone())
            .unwrap_or_default();
        let env = settings
            .binary
            .and_then(|binary| binary.env)
            .map(|environment| environment.into_iter().collect())
            .unwrap_or_else(|| worktree.shell_env());
        Ok(zed::Command { command, args, env })
    }
}

zed::register_extension!(BylawsExtension);
