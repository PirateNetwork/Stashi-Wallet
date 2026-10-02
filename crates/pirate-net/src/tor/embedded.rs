use crate::debug_log::log_debug_event;
use crate::{Error, Result};
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use arti_client::config::pt::TransportConfigBuilder;
use arti_client::config::TorClientConfigBuilder;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use arti_client::config::{BridgeConfigBuilder, CfgPath};
use arti_client::{BootstrapBehavior, StreamPrefs, TorClient as ArtiClient};
use futures_util::StreamExt;
use http_body_util::{BodyExt, Empty};
use hyper::body::Bytes;
use hyper::client::conn::http1;
use hyper::header;
use hyper::Request;
use hyper_util::rt::TokioIo;
use std::env;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use tokio::sync::{oneshot, Mutex};
use tokio_util::sync::CancellationToken;
use tor_rtcompat::{PreferredRuntime, ToplevelBlockOn};
use tracing::{info, warn};

#[cfg(test)]
use super::resolve_tor_dirs;
use super::{tor_base_candidates, TorBridgeConfig, TorBridgeTransport, TorConfig, TorStatus};

fn ensure_tor_dirs(state_dir: &Path, cache_dir: &Path) -> Result<(PathBuf, PathBuf)> {
    if std::fs::create_dir_all(state_dir).is_ok() && std::fs::create_dir_all(cache_dir).is_ok() {
        return Ok((state_dir.to_path_buf(), cache_dir.to_path_buf()));
    }

    let mut last_err: Option<std::io::Error> = None;
    for base in tor_base_candidates() {
        let state = base.join("state");
        let cache = base.join("cache");
        match (
            std::fs::create_dir_all(&state),
            std::fs::create_dir_all(&cache),
        ) {
            (Ok(_), Ok(_)) => {
                log_debug_event(
                    "tor.rs:ensure_tor_dirs",
                    "tor_dir_fallback",
                    &format!(
                        "state_dir={} cache_dir={}",
                        state.display(),
                        cache.display()
                    ),
                );
                return Ok((state, cache));
            }
            (Err(err), _) | (_, Err(err)) => last_err = Some(err),
        }
    }

    Err(Error::Tor(format!(
        "Failed to create Tor state dir: {}",
        last_err
            .map(|err| err.to_string())
            .unwrap_or_else(|| "unknown error".to_string())
    )))
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn transport_binary_filenames(name: &str) -> Vec<String> {
    let mut names = Vec::new();
    if cfg!(windows) {
        let lower = name.to_ascii_lowercase();
        if lower.ends_with(".exe") {
            names.push(name.to_string());
        } else {
            names.push(format!("{}.exe", name));
        }
    } else {
        let arch = env::consts::ARCH;
        names.push(format!("{}-{}", name, arch));
        names.push(name.to_string());
    }
    names
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn find_on_path(file_name: &str) -> Option<PathBuf> {
    let path_var = env::var_os("PATH")?;
    for path in env::split_paths(&path_var) {
        let candidate = path.join(file_name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn tor_browser_candidates(file_name: &str) -> Vec<PathBuf> {
    let mut candidates = Vec::new();

    let browser_path_vars = ["PIRATE_TOR_BROWSER_PATH", "TOR_BROWSER_PATH"];
    for var in browser_path_vars {
        if let Ok(value) = env::var(var) {
            let base = PathBuf::from(value);
            candidates.push(
                base.join("Browser")
                    .join("TorBrowser")
                    .join("Tor")
                    .join("PluggableTransports")
                    .join(file_name),
            );
            candidates.push(
                base.join("TorBrowser")
                    .join("Tor")
                    .join("PluggableTransports")
                    .join(file_name),
            );
            candidates.push(base.join("Tor").join("PluggableTransports").join(file_name));
        }
    }

    #[cfg(windows)]
    {
        if let Ok(local) = env::var("LOCALAPPDATA") {
            let base = PathBuf::from(local)
                .join("Tor Browser")
                .join("Browser")
                .join("TorBrowser")
                .join("Tor")
                .join("PluggableTransports");
            candidates.push(base.join(file_name));
        }
        if let Ok(program) = env::var("PROGRAMFILES") {
            let base = PathBuf::from(program)
                .join("Tor Browser")
                .join("Browser")
                .join("TorBrowser")
                .join("Tor")
                .join("PluggableTransports");
            candidates.push(base.join(file_name));
        }
        if let Ok(program_x86) = env::var("PROGRAMFILES(X86)") {
            let base = PathBuf::from(program_x86)
                .join("Tor Browser")
                .join("Browser")
                .join("TorBrowser")
                .join("Tor")
                .join("PluggableTransports");
            candidates.push(base.join(file_name));
        }
    }

    #[cfg(target_os = "macos")]
    {
        let app_path = PathBuf::from("/Applications")
            .join("Tor Browser.app")
            .join("Contents")
            .join("MacOS")
            .join("Tor")
            .join("PluggableTransports")
            .join(file_name);
        candidates.push(app_path);

        if let Ok(home) = env::var("HOME") {
            let app_path = PathBuf::from(home)
                .join("Applications")
                .join("Tor Browser.app")
                .join("Contents")
                .join("MacOS")
                .join("Tor")
                .join("PluggableTransports")
                .join(file_name);
            candidates.push(app_path);
        }
    }

    #[cfg(target_os = "linux")]
    {
        if let Ok(home) = env::var("HOME") {
            let base = PathBuf::from(home)
                .join(".local")
                .join("share")
                .join("torbrowser")
                .join("tbb")
                .join("x86_64")
                .join("tor-browser")
                .join("Browser")
                .join("TorBrowser")
                .join("Tor")
                .join("PluggableTransports")
                .join(file_name);
            candidates.push(base);
        }
        candidates.push(
            PathBuf::from("/usr/local/share/torbrowser")
                .join("Browser")
                .join("TorBrowser")
                .join("Tor")
                .join("PluggableTransports")
                .join(file_name),
        );
        candidates.push(
            PathBuf::from("/usr/share/torbrowser")
                .join("Browser")
                .join("TorBrowser")
                .join("Tor")
                .join("PluggableTransports")
                .join(file_name),
        );
    }

    candidates
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn bundled_transport_candidates(file_name: &str) -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    let exe = match env::current_exe() {
        Ok(exe) => exe,
        Err(_) => return candidates,
    };
    let exe_dir = match exe.parent() {
        Some(dir) => dir,
        None => return candidates,
    };

    candidates.push(exe_dir.join("tor-pt").join(file_name));
    candidates.push(exe_dir.join("data").join("tor-pt").join(file_name));

    if let Some(parent) = exe_dir.parent() {
        candidates.push(parent.join("tor-pt").join(file_name));
        candidates.push(parent.join("Resources").join("tor-pt").join(file_name));
        candidates.push(parent.join("Frameworks").join("tor-pt").join(file_name));
    }

    candidates
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn find_transport_binary(name: &str) -> Option<PathBuf> {
    let explicit_vars = ["PIRATE_TOR_PT_PATH", "TOR_PT_PATH"];
    for var in explicit_vars {
        if let Ok(value) = env::var(var) {
            let candidate = PathBuf::from(value);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }

    let dir_vars = ["PIRATE_TOR_PT_DIR", "TOR_PT_DIR"];
    for var in dir_vars {
        if let Ok(value) = env::var(var) {
            for file_name in transport_binary_filenames(name) {
                let candidate = PathBuf::from(&value).join(&file_name);
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }
    }

    for file_name in transport_binary_filenames(name) {
        for candidate in bundled_transport_candidates(&file_name) {
            if candidate.is_file() {
                log_debug_event(
                    "tor.rs:find_transport_binary",
                    "tor_pt_bundled",
                    &format!("bin={} path={}", file_name, candidate.display()),
                );
                return Some(candidate);
            }
        }
    }

    for file_name in transport_binary_filenames(name) {
        for candidate in tor_browser_candidates(&file_name) {
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }

    for file_name in transport_binary_filenames(name) {
        if let Some(found) = find_on_path(&file_name) {
            return Some(found);
        }
    }

    None
}

/// Tor client wrapper using Arti
pub struct TorClient {
    config: Arc<Mutex<TorConfig>>,
    state: Arc<Mutex<TorClientState>>,
    bootstrap_lock: Arc<Mutex<()>>,
    stream_prefs: Arc<Mutex<StreamPrefs>>,
}

struct TorClientState {
    client: Option<Arc<ArtiClient<PreferredRuntime>>>,
    status: TorStatus,
    // Arti's connectivity observations can lag a successful directory bootstrap.
    // They are diagnostics, not permission to attempt a Tor connection.
    observed_status: Option<TorStatus>,
    bootstrap_complete: bool,
    generation: u64,
    shutdown_requested: bool,
    cancelled: CancellationToken,
}

impl TorClientState {
    fn new() -> Self {
        Self {
            client: None,
            status: TorStatus::NotStarted,
            observed_status: None,
            bootstrap_complete: false,
            generation: 0,
            shutdown_requested: false,
            cancelled: CancellationToken::new(),
        }
    }

    fn reset(&mut self, shutdown_requested: bool) {
        self.cancelled.cancel();
        self.generation += 1;
        self.shutdown_requested = shutdown_requested;
        self.client = None;
        self.status = TorStatus::NotStarted;
        self.observed_status = None;
        self.bootstrap_complete = false;
    }

    fn check_generation(&self, generation: u64) -> Result<()> {
        if self.shutdown_requested {
            Err(Error::Tor("Tor shutdown requested".to_string()))
        } else if self.generation != generation {
            Err(Error::Tor("Tor bootstrap superseded".to_string()))
        } else {
            Ok(())
        }
    }

    fn start_attempt(&mut self, expected_generation: u64) -> Result<u64> {
        self.check_generation(expected_generation)?;
        self.generation += 1;
        self.cancelled.cancel();
        self.cancelled = CancellationToken::new();
        self.client = None;
        self.bootstrap_complete = false;
        self.observed_status = None;
        self.status = TorStatus::Bootstrapping {
            progress: 0,
            blocked: None,
        };
        Ok(self.generation)
    }

    fn finish_bootstrap(
        &mut self,
        generation: u64,
        result: Result<Arc<ArtiClient<PreferredRuntime>>>,
    ) -> Result<()> {
        self.check_generation(generation)?;
        match result {
            Ok(client) => {
                self.client = Some(client);
                self.bootstrap_complete = true;
                self.status = TorStatus::Ready;
                Ok(())
            }
            Err(error) => {
                self.cancelled.cancel();
                self.client = None;
                self.bootstrap_complete = false;
                self.status = TorStatus::Error(error.to_string());
                Err(error)
            }
        }
    }

    fn observe_status(&mut self, generation: u64, observed: TorStatus) -> bool {
        if self.check_generation(generation).is_err() || matches!(self.status, TorStatus::Error(_))
        {
            return false;
        }
        self.observed_status = Some(observed.clone());
        if !self.bootstrap_complete {
            self.status = match observed {
                // Even an early connectivity event cannot publish a client that
                // bootstrap() has not yet successfully returned.
                TorStatus::Ready => TorStatus::Bootstrapping {
                    progress: 100,
                    blocked: None,
                },
                other => other,
            };
        }
        true
    }
}

impl Drop for TorClientState {
    fn drop(&mut self) {
        self.cancelled.cancel();
    }
}

// Some SDK callers bootstrap on short-lived Tokio runtimes. Arti must outlive
// those callers, and dropping its final owned executor from a Tokio worker
// panics. Retain one lazily created executor for the process, shared by all
// clients and retries. Initialize it on the plain bootstrap thread below.
fn shared_tor_runtime() -> Result<PreferredRuntime> {
    static RUNTIME: OnceLock<std::sync::Mutex<Option<PreferredRuntime>>> = OnceLock::new();
    let mut runtime = RUNTIME
        .get_or_init(|| std::sync::Mutex::new(None))
        .lock()
        .map_err(|_| Error::Tor("Tor runtime initialization lock poisoned".to_string()))?;
    if runtime.is_none() {
        *runtime = Some(
            PreferredRuntime::create()
                .map_err(|e| Error::Tor(format!("Tor runtime init failed: {e}")))?,
        );
    }
    Ok(runtime.as_ref().expect("runtime initialized").clone())
}

fn bootstrap_panic_error(panic: &(dyn std::any::Any + Send)) -> Error {
    let payload = panic
        .downcast_ref::<&str>()
        .copied()
        .or_else(|| panic.downcast_ref::<String>().map(String::as_str))
        .unwrap_or("");
    let diagnostics = pirate_core::debug_log::panic_diagnostics(payload, None, None);
    // This error is also shown in the UI and bootstrap logs. Do not
    // reintroduce the raw payload through that path.
    Error::Tor(format!(
        "Tor bootstrap panic ({})",
        diagnostics.panic_category
    ))
}

#[allow(dead_code)]
fn _assert_tor_client_send_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<TorClient>();
}

impl TorClient {
    /// Create new Tor client
    pub fn new(config: TorConfig) -> Result<Self> {
        info!("Creating Tor client with config: {:?}", config);
        Ok(Self {
            config: Arc::new(Mutex::new(config)),
            state: Arc::new(Mutex::new(TorClientState::new())),
            bootstrap_lock: Arc::new(Mutex::new(())),
            stream_prefs: Arc::new(Mutex::new(StreamPrefs::new())),
        })
    }

    /// Update Tor configuration (clears active client so it can be re-bootstrapped)
    pub async fn update_config(self, config: TorConfig) {
        let mut config_guard = self.config.lock().await;
        let mut state = self.state.lock().await;
        *config_guard = config;
        state.reset(false);
        log_debug_event(
            "tor.rs:TorClient::update_config",
            "tor_update_config",
            "status=not_started",
        );
    }

    /// Bootstrap Tor connection (blocking until ready or error)
    pub async fn bootstrap(self) -> Result<()> {
        let _guard = self.bootstrap_lock.clone().lock_owned().await;
        let (config, mut expected_generation) = {
            let config = self.config.lock().await;
            let state = self.state.lock().await;
            state.check_generation(state.generation)?;
            if !config.enabled {
                return Err(Error::Tor("Tor is disabled".to_string()));
            }
            if state.bootstrap_complete && state.client.is_some() {
                return Ok(());
            }
            (config.clone(), state.generation)
        };

        let mut attempts = Vec::new();
        if config.use_bridges && config.bridges.is_some() {
            attempts.push(true);
        } else {
            attempts.push(false);
            if config.fallback_to_bridges && config.bridges.is_some() {
                attempts.push(true);
            }
        }

        let mut last_error = Error::Tor("Tor bootstrap failed".to_string());
        for use_bridges in attempts {
            let generation = self.state.lock().await.start_attempt(expected_generation)?;
            expected_generation = generation;
            log_debug_event(
                "tor.rs:TorClient::bootstrap",
                "tor_bootstrap_attempt",
                &format!("use_bridges={} gen={}", use_bridges, generation),
            );
            match self
                .clone()
                .bootstrap_with_config(config.clone(), use_bridges, generation)
                .await
            {
                Ok(()) => return Ok(()),
                Err(e) => {
                    warn!(
                        "Tor bootstrap attempt failed (bridges={}): {}",
                        use_bridges, e
                    );
                    last_error = e;
                    if self
                        .state
                        .lock()
                        .await
                        .check_generation(generation)
                        .is_err()
                    {
                        return Err(last_error);
                    }
                }
            }
        }

        Err(last_error)
    }

    /// Get bootstrap status
    pub async fn status(&self) -> TorStatus {
        self.state.lock().await.status.clone()
    }

    /// Get bootstrap status from an owned handle.
    pub async fn status_owned(self) -> TorStatus {
        self.state.lock_owned().await.status.clone()
    }

    /// Check whether a successfully bootstrapped client is available.
    pub async fn is_ready(&self) -> bool {
        let state = self.state.lock().await;
        state.bootstrap_complete && !state.shutdown_requested && state.client.is_some()
    }

    /// Connect to a target host/port using Tor
    pub async fn connect_stream(&self, host: &str, port: u16) -> Result<arti_client::DataStream> {
        let connect_timeout = self.config.lock().await.connect_timeout;
        self.clone().bootstrap().await?;
        let (client, generation) = self.clone().initialized_client().await?;
        let prefs = { self.stream_prefs.lock().await.clone() };
        let target = format!("{}:{}", host, port);
        let stream =
            tokio::time::timeout(connect_timeout, client.connect_with_prefs(target, &prefs))
                .await
                .map_err(|_| {
                    Error::Tor(format!(
                        "Tor connect timed out to {}:{} (port may be blocked by Tor exits)",
                        host, port
                    ))
                })?
                .map_err(|e| Error::Tor(format!("Tor connect failed: {}", e)))?;
        self.state.lock().await.check_generation(generation)?;
        Ok(stream)
    }

    /// Connect to a target using only owned state so the operation can run in
    /// a detached multi-endpoint health task.
    pub async fn connect_stream_owned(
        self,
        host: String,
        port: u16,
    ) -> Result<arti_client::DataStream> {
        let config = Arc::clone(&self.config).lock_owned().await.clone();
        self.clone().bootstrap().await?;
        let (client, generation) = self.clone().initialized_client().await?;
        let prefs = Arc::clone(&self.stream_prefs).lock_owned().await.clone();
        let target = format!("{}:{}", host, port);
        let stream = tokio::time::timeout(
            config.connect_timeout,
            client.connect_with_prefs(target, &prefs),
        )
        .await
        .map_err(|_| {
            Error::Tor(format!(
                "Tor connect timed out to {}:{} (port may be blocked by Tor exits)",
                host, port
            ))
        })?
        .map_err(|e| Error::Tor(format!("Tor connect failed: {}", e)))?;
        Arc::clone(&self.state)
            .lock_owned()
            .await
            .check_generation(generation)?;
        Ok(stream)
    }

    /// Rotate exit circuits by isolating future streams.
    pub async fn rotate_exit(&self) {
        let mut prefs = StreamPrefs::new();
        prefs.new_isolation_group();
        *self.stream_prefs.lock().await = prefs;
        log_debug_event(
            "tor.rs:TorClient::rotate_exit",
            "tor_exit_rotate",
            "isolation=new",
        );
    }

    /// Fetch current Tor exit IP address using an HTTP check over Tor.
    pub async fn fetch_exit_ip(self) -> Result<String> {
        let host = "checkip.amazonaws.com";
        let timeout = Duration::from_secs(20);
        let stream = self.clone().connect_stream(host, 80).await?;
        let io = TokioIo::new(stream);
        let (mut sender, conn) = tokio::time::timeout(timeout, http1::handshake(io))
            .await
            .map_err(|_| Error::Tor("Tor exit IP handshake timed out".to_string()))?
            .map_err(|e| Error::Tor(format!("Tor exit IP handshake failed: {}", e)))?;

        tokio::spawn(async move {
            if let Err(err) = conn.await {
                warn!("Tor exit IP connection error: {}", err);
            }
        });

        let request = Request::builder()
            .method("GET")
            .uri(format!("http://{}/", host))
            .header(header::HOST, host)
            .header(header::USER_AGENT, "PirateWallet-TorExitCheck/1.0")
            .body(Empty::<Bytes>::new())
            .map_err(|e| Error::Tor(format!("Tor exit IP request build failed: {}", e)))?;

        let response = tokio::time::timeout(timeout, sender.send_request(request))
            .await
            .map_err(|_| Error::Tor("Tor exit IP request timed out".to_string()))?
            .map_err(|e| Error::Tor(format!("Tor exit IP request failed: {}", e)))?;

        let status = response.status();
        let body = tokio::time::timeout(timeout, response.into_body().collect())
            .await
            .map_err(|_| Error::Tor("Tor exit IP response timed out".to_string()))?
            .map_err(|e| Error::Tor(format!("Tor exit IP response failed: {}", e)))?
            .to_bytes();
        let body = String::from_utf8_lossy(&body).trim().to_string();

        if !status.is_success() {
            return Err(Error::Tor(format!(
                "Tor exit IP request failed: status={} body={}",
                status, body
            )));
        }
        if body.is_empty() {
            return Err(Error::Tor("Tor exit IP response empty".to_string()));
        }

        Ok(body)
    }

    /// Shutdown Tor client
    pub async fn shutdown(self) {
        info!("Shutting down Tor client...");
        self.state.lock().await.reset(true);
        log_debug_event(
            "tor.rs:TorClient::shutdown",
            "tor_shutdown",
            "status=not_started",
        );
    }

    async fn initialized_client(self) -> Result<(Arc<ArtiClient<PreferredRuntime>>, u64)> {
        let state = self.state.lock_owned().await;
        state.check_generation(state.generation)?;
        if !state.bootstrap_complete {
            return Err(Error::Tor("Tor client not bootstrapped".to_string()));
        }
        let client = state
            .client
            .clone()
            .ok_or_else(|| Error::Tor("Tor client not initialized".to_string()))?;
        Ok((client, state.generation))
    }

    async fn bootstrap_with_config(
        self,
        config: TorConfig,
        use_bridges: bool,
        generation: u64,
    ) -> Result<()> {
        let cancelled = {
            let state = self.state.lock().await;
            state.check_generation(generation)?;
            state.cancelled.clone()
        };
        log_debug_event(
            "tor.rs:TorClient::bootstrap_with_config",
            "tor_bootstrap_start",
            &format!(
                "use_bridges={} timeout_secs={} gen={}",
                use_bridges,
                config.bootstrap_timeout.as_secs(),
                generation
            ),
        );

        let state = Arc::clone(&self.state);
        let (tx, rx) = oneshot::channel();

        std::thread::spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                (|| -> Result<Arc<ArtiClient<PreferredRuntime>>> {
                    let runtime = shared_tor_runtime()?;
                    let runtime_for_client = runtime.clone();

                    runtime.block_on(async move {
                        let arti_config = build_arti_config(&config, use_bridges)?;

                        let client = ArtiClient::with_runtime(runtime_for_client)
                            .config(arti_config)
                            .bootstrap_behavior(BootstrapBehavior::Manual)
                            .create_unbootstrapped()
                            .map_err(|e| {
                                // Arti's Display omits the underlying directory or
                                // permission error. Preserve its source chain so
                                // startup failures can actually be diagnosed.
                                let mut message = format!("Failed to create Tor client: {e}");
                                let mut source = std::error::Error::source(&e);
                                while let Some(cause) = source {
                                    message.push_str(&format!(": {cause}"));
                                    source = cause.source();
                                }
                                Error::Tor(message)
                            })?;

                        spawn_status_watcher(state, &client, generation, cancelled.clone());

                        let bootstrap_client = client.clone();
                        tokio::select! {
                            biased;
                            _ = cancelled.cancelled() => Err(Error::Tor("Tor bootstrap superseded".to_string())),
                            result = tokio::time::timeout(config.bootstrap_timeout, bootstrap_client.bootstrap()) => {
                                match result {
                                    Ok(Ok(())) => Ok(client),
                                    Ok(Err(e)) => Err(Error::Tor(format!("Tor bootstrap failed: {}", e))),
                                    Err(_) => Err(Error::Tor("Tor bootstrap timed out".to_string())),
                                }
                            }
                        }
                    })
                })()
            }));

            let result = match result {
                Ok(inner) => inner,
                Err(panic) => Err(bootstrap_panic_error(panic.as_ref())),
            };

            let _ = tx.send(result);
        });

        let result = match rx.await {
            Ok(result) => result,
            Err(error) => Err(Error::Tor(format!("Tor bootstrap thread error: {error}"))),
        };
        // Validate and publish the client, completion and status together. A
        // shutdown or configuration update cannot race a stale success write.
        let result = self.state.lock().await.finish_bootstrap(generation, result);
        match &result {
            Ok(()) => log_debug_event(
                "tor.rs:TorClient::bootstrap_with_config",
                "tor_bootstrap_ready",
                &format!("status=ready gen={generation}"),
            ),
            Err(error) => log_debug_event(
                "tor.rs:TorClient::bootstrap_with_config",
                "tor_bootstrap_error",
                &format!("error={error} gen={generation}"),
            ),
        }
        result
    }
}

fn spawn_status_watcher(
    state: Arc<Mutex<TorClientState>>,
    client: &ArtiClient<PreferredRuntime>,
    generation: u64,
    cancelled: CancellationToken,
) {
    let mut events = client.bootstrap_events();
    // Do not keep the published Arti client alive through its own observer.
    let state = Arc::downgrade(&state);
    tokio::spawn(async move {
        let mut last_status: Option<TorStatus> = None;
        loop {
            let event = tokio::select! {
                biased;
                _ = cancelled.cancelled() => return,
                event = events.next() => event,
            };
            let Some(event) = event else {
                break;
            };
            let percent = (event.as_frac() * 100.0).round() as u8;
            let blocked = event.blocked().map(|b| b.to_string());
            let new_status = if event.ready_for_traffic() {
                TorStatus::Ready
            } else {
                TorStatus::Bootstrapping {
                    progress: percent,
                    blocked,
                }
            };
            let effective_status = {
                let Some(state) = state.upgrade() else {
                    return;
                };
                let mut state = state.lock().await;
                if !state.observe_status(generation, new_status.clone()) {
                    return;
                }
                state.status.clone()
            };
            if last_status.as_ref() != Some(&new_status) {
                log_debug_event(
                    "tor.rs:spawn_status_watcher",
                    "tor_status_update",
                    &format!(
                        "status={effective_status:?} observed_status={new_status:?} gen={generation}"
                    ),
                );
                last_status = Some(new_status.clone());
            }
        }
        let Some(state) = state.upgrade() else {
            return;
        };
        let active = state.lock().await.check_generation(generation).is_ok();
        if active {
            // The bootstrap operation, not the lifetime of its diagnostic
            // stream, determines success or failure.
            log_debug_event(
                "tor.rs:spawn_status_watcher",
                "tor_status_events_ended",
                &format!("gen={generation}"),
            );
        }
    });
}

impl Clone for TorClient {
    fn clone(&self) -> Self {
        Self {
            config: Arc::clone(&self.config),
            state: Arc::clone(&self.state),
            bootstrap_lock: Arc::clone(&self.bootstrap_lock),
            stream_prefs: Arc::clone(&self.stream_prefs),
        }
    }
}

fn build_arti_config(
    config: &TorConfig,
    use_bridges: bool,
) -> Result<arti_client::TorClientConfig> {
    let (state_dir, cache_dir) = ensure_tor_dirs(&config.state_dir, &config.cache_dir)?;

    let mut builder = TorClientConfigBuilder::from_directories(&state_dir, &cache_dir);

    if use_bridges {
        let bridges = config
            .bridges
            .as_ref()
            .ok_or_else(|| Error::Tor("Bridge config required but missing".to_string()))?;
        apply_bridge_config(&mut builder, bridges)?;
    }

    builder
        .build()
        .map_err(|e| Error::Tor(format!("Tor config build failed: {}", e)))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn apply_bridge_config(
    _builder: &mut TorClientConfigBuilder,
    bridges: &TorBridgeConfig,
) -> Result<()> {
    log_debug_event(
        "tor.rs:apply_bridge_config",
        "tor_pt_unsupported",
        &format!("transport={:?}", bridges.transport),
    );
    Err(Error::Tor(
        "Bridge transports are not supported on mobile builds".to_string(),
    ))
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn apply_bridge_config(
    builder: &mut TorClientConfigBuilder,
    bridges: &TorBridgeConfig,
) -> Result<()> {
    if bridges.bridge_lines.is_empty() {
        return Err(Error::Tor(
            "Bridge mode selected but no bridges provided".to_string(),
        ));
    }

    for line in &bridges.bridge_lines {
        let bridge: BridgeConfigBuilder = line
            .parse()
            .map_err(|e| Error::Tor(format!("Invalid bridge line: {}", e)))?;
        builder.bridges().bridges().push(bridge);
    }

    let (protocol, default_bin) = match &bridges.transport {
        TorBridgeTransport::Obfs4 => ("obfs4", "obfs4proxy"),
        TorBridgeTransport::Snowflake => ("snowflake", "snowflake-client"),
        TorBridgeTransport::Custom(name) => (name.as_str(), name.as_str()),
    };

    let transport_path = if let Some(path) = bridges.transport_path.as_ref() {
        if path.as_os_str().is_empty() {
            None
        } else if path.is_file() {
            Some(CfgPath::new_literal(path))
        } else {
            return Err(Error::Tor(format!(
                "Pluggable transport binary not found at {}",
                path.display()
            )));
        }
    } else if let Some(found) = find_default_bridge_binary(default_bin) {
        log_debug_event(
            "tor.rs:apply_bridge_config",
            "tor_pt_autodetect",
            &format!("transport={} path={}", protocol, found.display()),
        );
        Some(CfgPath::new_literal(found))
    } else {
        log_debug_event(
            "tor.rs:apply_bridge_config",
            "tor_pt_missing",
            &format!("transport={} bin={}", protocol, default_bin),
        );
        None
    }
    .unwrap_or_else(|| CfgPath::new(default_bin.to_string()));

    let mut transport = TransportConfigBuilder::default();
    transport
        .protocols(vec![protocol.parse().map_err(|e| {
            Error::Tor(format!("Invalid transport protocol '{}': {}", protocol, e))
        })?])
        .path(transport_path)
        .run_on_startup(true);
    builder.bridges().transports().push(transport);

    Ok(())
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn find_default_bridge_binary(legacy_name: &str) -> Option<PathBuf> {
    // The official Windows Tor Expert Bundle provides both protocols through
    // Lyrebird. Keep its upstream filename and bytes, with legacy support for
    // existing installations and the other desktop distributions.
    #[cfg(target_os = "windows")]
    if matches!(legacy_name, "obfs4proxy" | "snowflake-client") {
        if let Some(path) = find_transport_binary("lyrebird") {
            return Some(path);
        }
    }
    find_transport_binary(legacy_name)
}

impl Default for TorClient {
    fn default() -> Self {
        Self::new(TorConfig::default()).expect("Failed to create default Tor client")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn caught_bootstrap_panics_do_not_expose_payloads_in_status_or_logs() {
        let payload = String::from(
            "Cannot drop a runtime in a context where blocking is not allowed; private-payload",
        );
        let error = bootstrap_panic_error(&payload).to_string();
        assert!(error.contains("runtime_async_drop"));
        assert!(!error.contains("private-payload"));
        assert!(!error.contains("Cannot drop"));
        assert!(bootstrap_panic_error(&"private-payload")
            .to_string()
            .contains("unknown"));
    }

    fn incomplete_connectivity() -> TorStatus {
        TorStatus::Bootstrapping {
            progress: 85,
            blocked: None,
        }
    }

    fn create_test_arti_client() -> (Arc<ArtiClient<PreferredRuntime>>, PathBuf) {
        let base = env::temp_dir().join(format!("stashi-tor-ready-{}", rand::random::<u64>()));
        let config = TorConfig {
            state_dir: base.join("state"),
            cache_dir: base.join("cache"),
            ..TorConfig::default()
        };
        let runtime = shared_tor_runtime().expect("shared Tor runtime");
        let arti_config = build_arti_config(&config, false).expect("Tor config");
        let client = runtime.block_on(async {
            ArtiClient::with_runtime(runtime.clone())
                .config(arti_config)
                .bootstrap_behavior(BootstrapBehavior::Manual)
                .create_unbootstrapped()
                .expect("unbootstrapped test client")
        });
        (client, base)
    }

    #[test]
    fn test_tor_config_default() {
        let config = TorConfig::default();
        assert!(config.enabled);
        assert!(!config.debug);
    }

    #[test]
    fn tor_client_can_initialize_private_directories() {
        let base = env::temp_dir().join(format!("stashi-tor-init-{}", rand::random::<u64>()));
        let config = TorConfig {
            state_dir: base.join("state"),
            cache_dir: base.join("cache"),
            ..TorConfig::default()
        };
        let runtime = PreferredRuntime::create().expect("Tor runtime");
        let arti_config = build_arti_config(&config, false).expect("Tor config");
        let result = runtime.block_on(async {
            ArtiClient::with_runtime(runtime.clone())
                .config(arti_config)
                .bootstrap_behavior(BootstrapBehavior::Manual)
                .create_unbootstrapped()
        });
        if let Err(error) = &result {
            panic!("Tor initialization failed: {error:#?}");
        }
        drop(result);
        drop(runtime);
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    #[ignore = "Explicit local diagnostic; no network bootstrap"]
    fn diagnose_existing_tor_directories() {
        let base =
            PathBuf::from(env::var("STASHI_DIAGNOSTIC_TOR_DIR").expect("explicit Tor directory"));
        let config = TorConfig {
            state_dir: base.join("state"),
            cache_dir: base.join("cache"),
            ..TorConfig::default()
        };
        let runtime = PreferredRuntime::create().unwrap();
        let config = build_arti_config(&config, false).unwrap();
        runtime.block_on(async {
            let result = ArtiClient::with_runtime(runtime.clone())
                .config(config)
                .bootstrap_behavior(BootstrapBehavior::Manual)
                .create_unbootstrapped();
            if let Err(error) = result {
                panic!("{error:#?}");
            }
        });
    }

    #[test]
    fn host_owned_tor_directories_override_platform_defaults() {
        let fallback = PathBuf::from("fallback");
        let state = PathBuf::from("private").join("state");
        let cache = PathBuf::from("private").join("cache");

        assert_eq!(
            resolve_tor_dirs(fallback, Some(state.clone()), Some(cache.clone())),
            (state, cache)
        );
    }

    #[test]
    fn partial_host_override_keeps_the_other_directory_on_the_fallback() {
        let fallback = PathBuf::from("fallback");
        let state = PathBuf::from("private").join("state");

        assert_eq!(
            resolve_tor_dirs(fallback.clone(), Some(state.clone()), None),
            (state, fallback.join("cache"))
        );
    }

    #[tokio::test]
    async fn test_tor_status() {
        let client = TorClient::new(TorConfig::default()).unwrap();
        assert_eq!(client.status().await, TorStatus::NotStarted);
        assert!(!client.is_ready().await);
    }

    #[tokio::test]
    async fn shutdown_client_cannot_be_restarted_by_a_stale_clone() {
        let client = TorClient::new(TorConfig::default()).expect("client");
        let stale = client.clone();

        client.shutdown().await;

        let error = stale
            .bootstrap()
            .await
            .expect_err("shutdown must remain terminal");
        assert!(error.to_string().contains("Tor shutdown requested"));
    }

    #[tokio::test]
    async fn cached_bootstrap_can_connect_before_observed_channel_ready() {
        // No network is used: inject the result of a successful cached-directory
        // bootstrap, then replay the user's subsequent 85% connectivity event.
        let (arti, base) = tokio::task::spawn_blocking(create_test_arti_client)
            .await
            .expect("client creation task");
        let client = TorClient::new(TorConfig::default()).expect("wrapper");
        let generation = {
            let mut state = client.state.lock().await;
            let generation = state.start_attempt(0).expect("attempt");
            state
                .finish_bootstrap(generation, Ok(arti))
                .expect("cached bootstrap success");
            assert!(state.observe_status(generation, incomplete_connectivity()));
            assert_eq!(state.observed_status, Some(incomplete_connectivity()));
            generation
        };

        assert_eq!(client.status().await, TorStatus::Ready);
        assert!(client.is_ready().await);
        tokio::time::timeout(Duration::from_secs(1), client.clone().bootstrap())
            .await
            .expect("successful bootstrap must not wait for connectivity events")
            .expect("already bootstrapped");
        let (connection_client, connection_generation) = client
            .clone()
            .initialized_client()
            .await
            .expect("an explicit Tor connection is allowed");
        assert_eq!(connection_generation, generation);
        drop(connection_client);
        client.shutdown().await;
        let _ = std::fs::remove_dir_all(base);
    }

    #[tokio::test]
    async fn connectivity_ready_cannot_publish_an_unfinished_client() {
        let client = TorClient::new(TorConfig::default()).expect("wrapper");
        {
            let mut state = client.state.lock().await;
            let generation = state.start_attempt(0).expect("attempt");
            assert!(state.observe_status(generation, TorStatus::Ready));
        }
        assert!(!client.is_ready().await);
        assert_eq!(
            client.status().await,
            TorStatus::Bootstrapping {
                progress: 100,
                blocked: None,
            }
        );
        assert!(client.initialized_client().await.is_err());
    }

    #[test]
    fn late_connectivity_events_cannot_mask_bootstrap_failure() {
        let mut state = TorClientState::new();
        let generation = state.start_attempt(0).expect("attempt");
        state
            .finish_bootstrap(generation, Err(Error::Tor("test failure".to_string())))
            .expect_err("bootstrap fails");
        let failure = state.status.clone();

        assert!(!state.observe_status(generation, incomplete_connectivity()));
        assert!(!state.observe_status(generation, TorStatus::Ready));
        assert_eq!(state.status, failure);
        assert!(!state.bootstrap_complete);
        assert!(state.client.is_none());
    }

    #[tokio::test]
    async fn queued_status_is_rejected_after_retry_and_shutdown() {
        let state = Arc::new(Mutex::new(TorClientState::new()));
        let mut guard = state.lock().await;
        let previous_generation = guard.start_attempt(0).expect("first attempt");
        let observed_state = Arc::clone(&state);
        let (queued_tx, queued_rx) = oneshot::channel();
        let observer = tokio::spawn(async move {
            let _ = queued_tx.send(());
            observed_state
                .lock()
                .await
                .observe_status(previous_generation, TorStatus::Ready)
        });
        queued_rx.await.expect("observer queued behind state lock");
        guard
            .finish_bootstrap(previous_generation, Err(Error::Tor("retry".to_string())))
            .expect_err("first attempt fails");
        let retry_generation = guard
            .start_attempt(previous_generation)
            .expect("retry attempt");
        drop(guard);
        assert!(!observer.await.expect("observer task"));

        let mut guard = state.lock().await;
        let observed_state = Arc::clone(&state);
        let (queued_tx, queued_rx) = oneshot::channel();
        let observer = tokio::spawn(async move {
            let _ = queued_tx.send(());
            observed_state
                .lock()
                .await
                .observe_status(retry_generation, incomplete_connectivity())
        });
        queued_rx.await.expect("observer queued behind state lock");
        guard.reset(true);
        drop(guard);
        assert!(!observer.await.expect("observer task"));
        let state = state.lock().await;
        assert!(state.shutdown_requested);
        assert_eq!(state.status, TorStatus::NotStarted);
        assert!(!state.bootstrap_complete);
    }

    #[tokio::test]
    async fn stale_bootstrap_success_cannot_restore_a_shutdown_client() {
        let (arti, base) = tokio::task::spawn_blocking(create_test_arti_client)
            .await
            .expect("client creation task");
        let client = TorClient::new(TorConfig::default()).expect("wrapper");
        let generation = client.state.lock().await.start_attempt(0).expect("attempt");
        client.clone().shutdown().await;
        client
            .state
            .lock()
            .await
            .finish_bootstrap(generation, Ok(arti))
            .expect_err("stale success must not publish a client");
        assert_eq!(client.status().await, TorStatus::NotStarted);
        assert!(!client.is_ready().await);
        assert!(client.initialized_client().await.is_err());
        let _ = std::fs::remove_dir_all(base);
    }

    #[tokio::test]
    async fn status_observer_does_not_keep_a_dropped_client_alive() {
        let (arti, base) = tokio::task::spawn_blocking(create_test_arti_client)
            .await
            .expect("client creation task");
        let client = TorClient::new(TorConfig::default()).expect("wrapper");
        let generation = {
            let mut state = client.state.lock().await;
            let generation = state.start_attempt(0).expect("attempt");
            state
                .finish_bootstrap(generation, Ok(Arc::clone(&arti)))
                .expect("bootstrap success");
            generation
        };
        let weak_state = Arc::downgrade(&client.state);
        let cancelled = client.state.lock().await.cancelled.clone();
        spawn_status_watcher(Arc::clone(&client.state), &arti, generation, cancelled);
        drop(arti);
        drop(client);
        assert!(weak_state.upgrade().is_none());
        tokio::task::yield_now().await;
        let _ = std::fs::remove_dir_all(base);
    }

    #[test]
    fn shared_runtime_survives_short_lived_caller_runtime() {
        let runtime = std::thread::spawn(|| {
            let tor_runtime = shared_tor_runtime().expect("shared Tor runtime");
            let caller = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("short-lived caller runtime");
            caller.block_on(async { tor_runtime })
        })
        .join()
        .expect("bootstrap caller thread");
        runtime.block_on(async {
            tokio::spawn(async {}).await.expect("Tor worker still runs");
        });
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn shared_runtime_handles_can_be_dropped_on_async_workers() {
        let runtime = tokio::task::spawn_blocking(shared_tor_runtime)
            .await
            .expect("runtime initialization task")
            .expect("shared Tor runtime");
        tokio::spawn(async move { drop(runtime) })
            .await
            .expect("dropping a Tor handle on an async worker must not panic");
    }

    #[tokio::test]
    async fn shutdown_and_retry_cancel_pending_bootstrap_and_observer_work() {
        let client = TorClient::new(TorConfig::default()).expect("wrapper");
        let (generation, first_attempt) = {
            let mut state = client.state.lock().await;
            let generation = state.start_attempt(0).expect("attempt");
            (generation, state.cancelled.clone())
        };
        let first_wait = tokio::spawn(first_attempt.clone().cancelled_owned());
        let second_attempt = {
            let mut state = client.state.lock().await;
            state.start_attempt(generation).expect("retry");
            state.cancelled.clone()
        };
        tokio::time::timeout(Duration::from_secs(1), first_wait)
            .await
            .expect("retry must wake old attempt")
            .expect("old attempt task");
        assert!(first_attempt.is_cancelled());
        assert!(!second_attempt.is_cancelled());

        let bootstrap = tokio::spawn(second_attempt.clone().cancelled_owned());
        let observer = tokio::spawn(second_attempt.clone().cancelled_owned());
        client.shutdown().await;
        tokio::time::timeout(Duration::from_secs(1), async {
            bootstrap.await.expect("bootstrap cancellation");
            observer.await.expect("observer cancellation");
        })
        .await
        .expect("shutdown must wake both background tasks");
        assert!(second_attempt.is_cancelled());
    }
}
