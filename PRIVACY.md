# Privacy / 隐私说明

- The widget starts the local Codex `app-server --stdio` and asks for account and rate-limit data. The Codex process may contact OpenAI under the user's existing account. No separate telemetry endpoint is present in this widget's source.
- Email, plan, timestamps and quota snapshots are saved through macOS UserDefaults. UI masking does not encrypt the stored email. No password input or account switching is implemented.
- Project statistics read JSONL files under the default local Codex session directories. The parser reads file bytes and parses JSON lines, which can contain conversation content, but selects only project paths and token counters for statistics. Do not describe this as never reading files containing chats.
- Preferences use `io.github.a262668008-prog.codexquota`, separate from the original personal app. Removing the app does not automatically erase preferences.
- Public source contains no intended user logs, account histories, authentication files or private notes. Do not publish screenshots showing real emails or project names without checking them.
- Source inspection is not a network traffic audit or an independent security certification.
