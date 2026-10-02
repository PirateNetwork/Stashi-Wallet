//! Simple process-wide debug log writer.
//!
//! We emit JSONL to a single `debug.log` file for field diagnostics. Writes are
//! synchronized and each log entry is written as a single append to prevent
//! interleaving/corruption under concurrency.

use directories::ProjectDirs;
use once_cell::sync::Lazy;
use regex::{Captures, Regex};
use std::env;
use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

const DEFAULT_DEBUG_LOG_MAX_BYTES: u64 = 100 * 1024 * 1024;
const DEFAULT_DEBUG_LOG_BACKUP_COUNT: usize = 2;
const MAX_DEBUG_LOG_BACKUP_COUNT: usize = 10;
const MAX_PANIC_CLASSIFICATION_BYTES: usize = 4_096;

// Keep these values in sync with the Dart export redactor. Neither list may
// contain caller-provided text: panic messages and source paths can hold secrets.
const PANIC_CATEGORIES: &[&str] = &[
    "runtime_async_drop",
    "runtime_missing",
    "runtime_nested_block_on",
    "tor_pending_channel_drop",
    "time_overflow",
    "unknown",
];
const PANIC_SOURCE_FILES: &[&str] = &[
    "api.rs",
    "blocking.rs",
    "client.rs",
    "context.rs",
    "lib.rs",
    "mod.rs",
    "preemptive.rs",
    "runtime.rs",
    "scheduler.rs",
    "shutdown.rs",
    "state.rs",
    "time.rs",
];
const PRIVATE_FIELDS: &[&str] = &[
    "mnemonic",
    "seed",
    "passphrase",
    "password",
    "pin",
    "panic_pin",
    "duress_passphrase",
    "spending_key",
    "sapling_key",
    "orchard_key",
    "ironwood_key",
    "sapling_viewing_key",
    "orchard_viewing_key",
    "ironwood_viewing_key",
    "viewing_key",
    "extsk",
    "ovk",
    "ivk",
    "fvk",
    "private_key",
    "secret",
    "panic",
    "panic_location",
    "backtrace",
    "stack",
];
const CORRELATING_FIELDS: &[&str] = &[
    "wallet_id",
    "account_id",
    "key_id",
    "address",
    "addresses",
    "z_addresses",
    "address_id",
    "txid",
    "txids",
    "spent_txid",
    "pending_txid",
    "recent_txids",
    "last_seen_txids",
    "txid_prefix",
    "nullifier",
    "nullifiers",
    "nf",
    "cmu",
    "cmx",
    "cmx_prefix",
    "commitment",
    "memo",
    "memo_hex",
    "path",
    "cwd",
    "db_path",
    "endpoint",
    "url",
    "host",
    "server",
    "server_name",
    "tls_server_name",
    "tls_pin",
];

/// Bounded, non-sensitive metadata for a panic. Raw payloads and paths are omitted.
#[derive(Debug, Clone, Copy, serde::Serialize)]
pub struct PanicDiagnostics {
    /// A fixed category derived from known panic messages, or `unknown`.
    pub panic_category: &'static str,
    /// An allowlisted source basename, never a directory or arbitrary filename.
    pub panic_source_file: Option<&'static str>,
    /// The compiler-reported source line, when available.
    pub panic_source_line: Option<u32>,
}

/// Classify a panic without returning any part of its payload or source path.
pub fn panic_diagnostics(
    payload: &str,
    source_file: Option<&str>,
    source_line: Option<u32>,
) -> PanicDiagnostics {
    let mut end = payload.len().min(MAX_PANIC_CLASSIFICATION_BYTES);
    while !payload.is_char_boundary(end) {
        end -= 1;
    }
    let payload = &payload[..end];
    let panic_category = if payload
        .contains("Cannot drop a runtime in a context where blocking is not allowed")
    {
        "runtime_async_drop"
    } else if payload.contains("there is no reactor running") {
        "runtime_missing"
    } else if payload.contains("Cannot start a runtime from within a runtime") {
        "runtime_nested_block_on"
    } else if payload.contains("Dropped the 'PendingChannelHandle' without removing the channel") {
        "tor_pending_channel_drop"
    } else if payload.contains("overflow when subtracting duration from instant")
        || payload.contains("overflow when adding duration to instant")
    {
        "time_overflow"
    } else {
        "unknown"
    };
    let panic_source_file = source_file
        .and_then(|path| path.rsplit(['/', '\\']).next())
        .and_then(|file| {
            PANIC_SOURCE_FILES
                .iter()
                .copied()
                .find(|known| *known == file)
        });
    PanicDiagnostics {
        panic_category,
        panic_source_file,
        panic_source_line: source_line.filter(|line| *line > 0),
    }
}

static DEBUG_LOG_PATH: Lazy<PathBuf> = Lazy::new(resolve_debug_log_path);
static DEBUG_LOG_FILE: Lazy<Mutex<Option<File>>> = Lazy::new(|| Mutex::new(None));
static DEBUG_LOG_MAX_BYTES: Lazy<u64> = Lazy::new(resolve_max_debug_log_bytes);
static DEBUG_LOG_BACKUP_COUNT: Lazy<usize> = Lazy::new(resolve_debug_log_backup_count);
static DEBUG_LOG_ENABLED: AtomicBool = AtomicBool::new(false);

static PRIVATE_JSON_FIELD: Lazy<Regex> = Lazy::new(|| {
    Regex::new(&format!(
        r#"(?i)("(?:{})"\s*:\s*)("[^"\\]*(?:\\.[^"\\]*)*"|[^,}}\n]+)"#,
        PRIVATE_FIELDS.join("|")
    ))
    .expect("valid private-field redaction regex")
});

static PANIC_DIAGNOSTIC_JSON_KEY: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r#"(?i)"panic(?:_|\\u005f)(?:category|source(?:_|\\u005f)(?:file|line))"\s*:"#)
        .expect("valid panic metadata key regex")
});

static CORRELATING_JSON_FIELD: Lazy<Regex> = Lazy::new(|| {
    Regex::new(&format!(
        r#"(?i)("(?:{})"\s*:\s*)("[^"\\]*(?:\\.[^"\\]*)*"|[^,}}\n]+)"#,
        CORRELATING_FIELDS.join("|")
    ))
    .expect("valid correlating-field redaction regex")
});

static RAW_SECRET_ASSIGNMENT: Lazy<Regex> = Lazy::new(|| {
    Regex::new(
        r#"(?i)\b(mnemonic|seed|passphrase|password|pin|spending[_ -]?key|viewing[_ -]?key|private[_ -]?key|sapling[_ -]?key|orchard[_ -]?key|ironwood[_ -]?key)\b\s*[:=]\s*("[^"]*"|'[^']*'|\S+)"#,
    )
    .expect("valid secret assignment redaction regex")
});

static PIRATE_ADDRESS: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r#"(?i)\b(?:zs1|ztestsapling1|zregtestsapling1|pirate1|pirate-test1|pirate-regtest1)[a-z0-9_-]{20,}\b"#)
        .expect("valid address redaction regex")
});

static LONG_HEX: Lazy<Regex> =
    Lazy::new(|| Regex::new(r#"(?i)\b(?:0x)?[0-9a-f]{64,}\b"#).expect("valid hex redaction regex"));

static WINDOWS_PATH: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r#"[A-Za-z]:\\[^\s",}]+"#).expect("valid windows path redaction regex")
});

static UNIX_USER_PATH: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r#"/(?:Users|home|var|private|tmp|data|storage)/[^\s",}]+"#)
        .expect("valid unix path redaction regex")
});

fn resolve_debug_log_path() -> PathBuf {
    let path = if let Ok(path) = env::var("PIRATE_DEBUG_LOG_PATH") {
        PathBuf::from(path)
    } else {
        ProjectDirs::from("com", "Pirate", "PirateWallet")
            .map(|dirs| dirs.data_local_dir().join("logs").join("debug.log"))
            .unwrap_or_else(|| {
                env::current_dir()
                    .map(|dir| dir.join(".cursor").join("debug.log"))
                    .unwrap_or_else(|_| PathBuf::from(".cursor").join("debug.log"))
            })
    };

    path
}

fn resolve_max_debug_log_bytes() -> u64 {
    env::var("PIRATE_DEBUG_LOG_MAX_BYTES")
        .ok()
        .and_then(|raw| raw.trim().parse::<u64>().ok())
        .filter(|bytes| *bytes > 0)
        .unwrap_or(DEFAULT_DEBUG_LOG_MAX_BYTES)
}

fn resolve_debug_log_backup_count() -> usize {
    env::var("PIRATE_DEBUG_LOG_BACKUPS")
        .ok()
        .and_then(|raw| raw.trim().parse::<usize>().ok())
        .map(|count| count.min(MAX_DEBUG_LOG_BACKUP_COUNT))
        .unwrap_or(DEFAULT_DEBUG_LOG_BACKUP_COUNT)
}

fn backup_log_path(path: &Path, index: usize) -> PathBuf {
    let mut raw = OsString::from(path.as_os_str());
    raw.push(format!(".{index}"));
    PathBuf::from(raw)
}

fn open_debug_log_file() -> Option<File> {
    if let Some(parent) = DEBUG_LOG_PATH.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(&*DEBUG_LOG_PATH)
        .ok()
}

fn redact_json_field(text: String, regex: &Regex, replacement: &str) -> String {
    regex
        .replace_all(&text, |caps: &Captures<'_>| {
            format!(r#"{}"{}""#, &caps[1], replacement)
        })
        .into_owned()
}

fn redact_secret_assignment(text: String) -> String {
    RAW_SECRET_ASSIGNMENT
        .replace_all(&text, |caps: &Captures<'_>| {
            format!("{}=[REDACTED_SECRET]", &caps[1])
        })
        .into_owned()
}

fn redact_json_value(value: &mut serde_json::Value) {
    use serde_json::Value;
    match value {
        Value::Object(fields) => {
            for (key, value) in fields.iter_mut() {
                let key = key.to_ascii_lowercase();
                match key.as_str() {
                    "panic_category" => {
                        let category = value
                            .as_str()
                            .filter(|category| PANIC_CATEGORIES.contains(category))
                            .unwrap_or("unknown");
                        *value = Value::String(category.to_string());
                    }
                    "panic_source_file" => {
                        *value = value
                            .as_str()
                            .filter(|file| PANIC_SOURCE_FILES.contains(file))
                            .map(|file| Value::String(file.to_string()))
                            .unwrap_or(Value::Null);
                    }
                    "panic_source_line" => {
                        *value = value
                            .as_u64()
                            .filter(|line| *line > 0 && *line <= u32::MAX as u64)
                            .map(|line| Value::Number(line.into()))
                            .unwrap_or(Value::Null);
                    }
                    key if PRIVATE_FIELDS.contains(&key) => {
                        *value = Value::String("[REDACTED_SECRET]".to_string());
                    }
                    key if CORRELATING_FIELDS.contains(&key) => {
                        *value = Value::String("[REDACTED]".to_string());
                    }
                    _ => redact_json_value(value),
                }
            }
        }
        Value::Array(values) => values.iter_mut().for_each(redact_json_value),
        _ => {}
    }
}

fn redact_log_text(text: &str) -> String {
    // Debug logs are JSONL. Consume complete JSON values, including arrays and
    // objects, before the legacy text fallback: regex fragments are not safe
    // substitutes for nested metadata. Discard malformed panic entries entirely.
    let text = text
        .split_inclusive('\n')
        .map(|line| {
            let (body, newline) = line
                .strip_suffix('\n')
                .map_or((line, ""), |body| (body, "\n"));
            match serde_json::from_str::<serde_json::Value>(body) {
                Ok(mut value) => {
                    redact_json_value(&mut value);
                    format!("{}{newline}", value)
                }
                Err(_) if PANIC_DIAGNOSTIC_JSON_KEY.is_match(body) => {
                    format!("[REDACTED_MALFORMED_PANIC_EVENT]{newline}")
                }
                Err(_) => line.to_string(),
            }
        })
        .collect::<String>();
    let text = redact_json_field(text, &PRIVATE_JSON_FIELD, "[REDACTED_SECRET]");
    let text = redact_json_field(text, &CORRELATING_JSON_FIELD, "[REDACTED]");
    let text = redact_secret_assignment(text);
    let text = PIRATE_ADDRESS
        .replace_all(&text, "[REDACTED_ADDRESS]")
        .into_owned();
    let text = LONG_HEX.replace_all(&text, "[REDACTED_HEX]").into_owned();
    let text = WINDOWS_PATH
        .replace_all(&text, "[REDACTED_PATH]")
        .into_owned();
    UNIX_USER_PATH
        .replace_all(&text, "[REDACTED_PATH]")
        .into_owned()
}

fn remove_log_files(path: &Path) {
    let _ = fs::remove_file(path);
    for index in 1..=MAX_DEBUG_LOG_BACKUP_COUNT {
        let _ = fs::remove_file(backup_log_path(path, index));
    }
}

fn current_log_len(guard: &Option<File>) -> u64 {
    guard
        .as_ref()
        .and_then(|file| file.metadata().ok().map(|meta| meta.len()))
        .or_else(|| fs::metadata(&*DEBUG_LOG_PATH).ok().map(|meta| meta.len()))
        .unwrap_or(0)
}

fn rotate_locked(guard: &mut Option<File>) {
    *guard = None;

    // Drop oversized logs instead of archiving giant files.
    if fs::metadata(&*DEBUG_LOG_PATH)
        .ok()
        .map(|meta| meta.len() > *DEBUG_LOG_MAX_BYTES)
        .unwrap_or(false)
    {
        let _ = fs::remove_file(&*DEBUG_LOG_PATH);
        return;
    }

    let backups = *DEBUG_LOG_BACKUP_COUNT;
    if backups == 0 {
        let _ = fs::remove_file(&*DEBUG_LOG_PATH);
        return;
    }

    for index in (1..=backups).rev() {
        let src = if index == 1 {
            (*DEBUG_LOG_PATH).clone()
        } else {
            backup_log_path(&DEBUG_LOG_PATH, index - 1)
        };
        let dst = backup_log_path(&DEBUG_LOG_PATH, index);
        let _ = fs::remove_file(&dst);
        let _ = fs::rename(&src, &dst);
    }
}

fn ensure_file_open(guard: &mut Option<File>) -> bool {
    if guard.is_none() {
        *guard = open_debug_log_file();
    }
    guard.is_some()
}

fn ensure_capacity_for_write(guard: &mut Option<File>, upcoming_bytes: usize) -> bool {
    if !ensure_file_open(guard) {
        return false;
    }

    let current = current_log_len(guard);
    if current.saturating_add(upcoming_bytes as u64) > *DEBUG_LOG_MAX_BYTES {
        rotate_locked(guard);
        if !ensure_file_open(guard) {
            return false;
        }
    }

    true
}

fn enforce_post_write_cap(guard: &mut Option<File>) {
    if current_log_len(guard) > *DEBUG_LOG_MAX_BYTES {
        rotate_locked(guard);
        let _ = ensure_file_open(guard);
    }
}

/// Returns the resolved debug log path.
pub fn debug_log_path() -> PathBuf {
    (*DEBUG_LOG_PATH).clone()
}

/// Enables or disables field diagnostics logging for the current process.
///
/// Logging is disabled by default. Disabling closes the active file handle and
/// removes any existing `debug.log` files so users do not retain stale
/// diagnostics unless they explicitly opt in.
pub fn set_enabled(enabled: bool) {
    DEBUG_LOG_ENABLED.store(enabled, Ordering::Relaxed);
    if !enabled {
        clear_logs();
    }
}

/// Returns whether debug logging is enabled for the current process.
pub fn is_enabled() -> bool {
    DEBUG_LOG_ENABLED.load(Ordering::Relaxed)
}

/// Closes the active debug log handle and removes the active log plus backups.
pub fn clear_logs() {
    let mut guard = DEBUG_LOG_FILE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    *guard = None;
    remove_log_files(&DEBUG_LOG_PATH);
}

/// Appends a single line to `debug.log`.
///
/// The caller should pass a complete line without a trailing newline. This
/// function will add one.
pub fn append_line(line: &str) {
    if !is_enabled() {
        return;
    }

    let mut guard = DEBUG_LOG_FILE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let line = redact_log_text(line);

    // Write as a single buffer so entries can't interleave.
    let mut buf = Vec::with_capacity(line.len() + 1);
    buf.extend_from_slice(line.as_bytes());
    buf.push(b'\n');

    if !ensure_capacity_for_write(&mut guard, buf.len()) {
        return;
    }

    let failed = guard
        .as_mut()
        .and_then(|file| file.write_all(&buf).err())
        .is_some();

    // If the write failed (file moved/locked/etc), drop the handle so we try to
    // reopen on the next log event.
    if failed {
        *guard = None;
        return;
    }

    enforce_post_write_cap(&mut guard);
}

/// Convenience wrapper that formats the line before appending.
pub fn append_line_fmt(args: std::fmt::Arguments<'_>) {
    append_line(&args.to_string());
}

/// Runs `f` with the debug log file locked for the full duration of the call.
///
/// This is mainly useful when you need multiple writes to be serialized as one
/// critical section (for example `writeln!` that may call `write()` multiple
/// times internally).
pub fn with_locked_file<F>(f: F)
where
    F: FnOnce(&mut dyn Write),
{
    if !is_enabled() {
        return;
    }

    let mut guard = DEBUG_LOG_FILE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let mut pending = Vec::new();
    f(&mut pending);
    if pending.is_empty() {
        return;
    }

    let pending = String::from_utf8_lossy(&pending);
    let sanitized = redact_log_text(&pending);
    let buf = sanitized.as_bytes();

    if !ensure_capacity_for_write(&mut guard, buf.len()) {
        return;
    }

    let failed = guard
        .as_mut()
        .and_then(|file| file.write_all(buf).err())
        .is_some();

    if failed {
        *guard = None;
        return;
    }

    enforce_post_write_cap(&mut guard);
}

#[cfg(test)]
mod tests {
    use super::{panic_diagnostics, redact_log_text};

    #[test]
    fn classifies_known_panics_without_exposing_payloads_or_paths() {
        let cases = [
            (
                "Cannot drop a runtime in a context where blocking is not allowed",
                "runtime_async_drop",
            ),
            (
                "there is no reactor running, must be called from the context of a Tokio runtime",
                "runtime_missing",
            ),
            (
                "Cannot start a runtime from within a runtime",
                "runtime_nested_block_on",
            ),
            (
                "Dropped the 'PendingChannelHandle' without removing the channel",
                "tor_pending_channel_drop",
            ),
            (
                "overflow when subtracting duration from instant",
                "time_overflow",
            ),
            ("wallet-1 mnemonic=abandon abandon", "unknown"),
        ];
        for (payload, category) in cases {
            let diagnostics =
                panic_diagnostics(payload, Some("/Users/alice/private/shutdown.rs"), Some(51));
            assert_eq!(diagnostics.panic_category, category);
            assert_eq!(diagnostics.panic_source_file, Some("shutdown.rs"));
            assert_eq!(diagnostics.panic_source_line, Some(51));
            let json = serde_json::to_string(&diagnostics).unwrap();
            assert!(!json.contains("alice"));
            assert!(!json.contains("wallet-1"));
            assert!(!json.contains("abandon"));
        }
        let diagnostics = panic_diagnostics("secret", Some(r"C:\Users\alice\seed-words.rs"), None);
        assert_eq!(diagnostics.panic_source_file, None);
        let diagnostics = panic_diagnostics("secret", Some(r"C:\Users\alice\shutdown.rs"), Some(0));
        assert_eq!(diagnostics.panic_source_file, Some("shutdown.rs"));
        assert_eq!(diagnostics.panic_source_line, None);
    }

    #[test]
    fn panic_classification_is_bounded_and_utf8_safe() {
        let payload = format!(
            "{}Cannot drop a runtime in a context where blocking is not allowed",
            "€".repeat(2_000)
        );
        assert_eq!(
            panic_diagnostics(&payload, None, None).panic_category,
            "unknown"
        );
    }

    #[test]
    fn retains_only_allowlisted_panic_metadata_when_writing_logs() {
        let raw = serde_json::json!({
            "panic": "seed=abandon \"wallet-1\" abandon",
            "panic_location": "/Users/alice/wallet-1/private.rs:51:9",
            "backtrace": "mnemonic=abandon abandon",
            "panic_category": "runtime_async_drop",
            "panic_source_file": "shutdown.rs",
            "panic_source_line": 51,
        })
        .to_string();
        let redacted: serde_json::Value = serde_json::from_str(&redact_log_text(&raw)).unwrap();
        assert_eq!(redacted["panic_category"], "runtime_async_drop");
        assert_eq!(redacted["panic_source_file"], "shutdown.rs");
        assert_eq!(redacted["panic_source_line"], 51);
        for field in ["panic", "panic_location", "backtrace"] {
            assert_eq!(redacted[field], "[REDACTED_SECRET]");
        }
        let exported = redacted.to_string();
        for secret in ["abandon", "alice", "wallet-1"] {
            assert!(!exported.contains(secret));
        }

        let untrusted = serde_json::json!({
            "panic_category": "wallet-1 seed=abandon",
            "panic_source_file": "/Users/alice/shutdown.rs",
            "panic_source_line": "wallet-1",
        })
        .to_string();
        let redacted: serde_json::Value =
            serde_json::from_str(&redact_log_text(&untrusted)).unwrap();
        assert_eq!(redacted["panic_category"], "unknown");
        assert!(redacted["panic_source_file"].is_null());
        assert!(redacted["panic_source_line"].is_null());
    }

    #[test]
    fn panic_source_lines_are_positive_u32_integers() {
        for value in [
            serde_json::json!(0),
            serde_json::json!(-1),
            serde_json::json!(u32::MAX as u64 + 1),
            serde_json::json!(51.5),
            serde_json::json!("51"),
            serde_json::Value::Null,
        ] {
            let raw = serde_json::json!({"panic_source_line": value}).to_string();
            let redacted: serde_json::Value = serde_json::from_str(&redact_log_text(&raw)).unwrap();
            assert!(redacted["panic_source_line"].is_null());
        }
        let raw = serde_json::json!({"panic_source_line": u32::MAX}).to_string();
        let redacted: serde_json::Value = serde_json::from_str(&redact_log_text(&raw)).unwrap();
        assert_eq!(redacted["panic_source_line"], u32::MAX);
    }

    #[test]
    fn redacts_complete_nested_metadata_values_and_escaped_keys() {
        let raw = r#"{"data":[{"panic\u005fcategory":["runtime_async_drop","wallet-1"],"panic_source_file":{"allowed":"shutdown.rs","private":"alice"},"panic_source_line":[51,"abandon"]},{"PANIC_CATEGORY":"runtime_async_drop","panic":["private-payload",{"details":"secret-tail"}],"addresses":["private-address","private-address-tail"]}]}"#;
        let exported = redact_log_text(raw);
        let parsed: serde_json::Value = serde_json::from_str(&exported).unwrap();
        assert_eq!(parsed["data"][0]["panic_category"], "unknown");
        assert!(parsed["data"][0]["panic_source_file"].is_null());
        assert!(parsed["data"][0]["panic_source_line"].is_null());
        assert_eq!(parsed["data"][1]["PANIC_CATEGORY"], "runtime_async_drop");
        assert_eq!(parsed["data"][1]["panic"], "[REDACTED_SECRET]");
        assert_eq!(parsed["data"][1]["addresses"], "[REDACTED]");
        for secret in [
            "wallet-1",
            "alice",
            "abandon",
            "private-payload",
            "secret-tail",
            "private-address",
        ] {
            assert!(!exported.contains(secret));
        }
    }

    #[test]
    fn malformed_panic_entries_fail_closed_and_keep_jsonl_boundaries() {
        let raw = concat!(
            "{\"panic_source_line\":[\"wallet-1\",{\"details\":\"abandon\"}\n",
            "{\"data\":{\"panic_category\":\"runtime_async_drop\"}}\n",
            "{\"panic\\u005fcategory\":{\"secret-tail\":\"alice\"}\n",
        );
        let exported = redact_log_text(raw);
        let lines: Vec<_> = exported.lines().collect();
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0], "[REDACTED_MALFORMED_PANIC_EVENT]");
        assert_eq!(lines[2], "[REDACTED_MALFORMED_PANIC_EVENT]");
        let parsed: serde_json::Value = serde_json::from_str(lines[1]).unwrap();
        assert_eq!(parsed["data"]["panic_category"], "runtime_async_drop");
        assert!(exported.ends_with('\n'));
        for secret in ["wallet-1", "abandon", "alice", "secret-tail"] {
            assert!(!exported.contains(secret));
        }
    }

    #[test]
    fn redacts_private_and_correlating_fields() {
        let raw = r#"{"mnemonic":"abandon abandon","ironwood_key":"secret-ironwood-key","orchard_viewing_key":"legacy-viewing-key","wallet_id":"wallet-1","key_id":42,"address":"zs1qqqqqqqqqqqqqqqqqqqqqqqqqqqq","txid":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","panic":"seed leaked","path":"C:\\Users\\alice\\wallet.db"}"#;
        let redacted = redact_log_text(raw);

        assert!(!redacted.contains("abandon abandon"));
        assert!(!redacted.contains("secret-ironwood-key"));
        assert!(!redacted.contains("legacy-viewing-key"));
        assert!(!redacted.contains("wallet-1"));
        assert!(!redacted.contains("\"key_id\":42"));
        assert!(!redacted.contains("zs1qqqq"));
        assert!(!redacted.contains("0123456789abcdef"));
        assert!(!redacted.contains("seed leaked"));
        assert!(!redacted.contains("alice"));
        assert!(redacted.contains("[REDACTED_SECRET]"));
        assert!(redacted.contains("[REDACTED]"));
    }
}
