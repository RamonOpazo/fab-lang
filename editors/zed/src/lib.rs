//! Starts fAB's language server, `fab lsp`, for Zed. The server is fAB's own
//! binary, found on the PATH; nothing is downloaded.

use zed_extension_api as zed;

struct Fab;

impl zed::Extension for Fab {
    fn new() -> Self {
        Fab
    }

    fn language_server_command(
        &mut self,
        _id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> zed::Result<zed::Command> {
        let command = worktree
            .which("fab")
            .ok_or("`fab` is not on the PATH: run `make install OPTIMIZE=Debug` in fab-lang")?;
        Ok(zed::Command {
            command,
            args: vec!["lsp".into()],
            env: worktree.shell_env(),
        })
    }
}

zed::register_extension!(Fab);
