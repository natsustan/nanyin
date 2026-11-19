//! One playback engine: a librespot session, its player and its Spotify
//! Connect device. The FFI layer in `lib.rs` keeps at most one alive.

use std::{path::PathBuf, sync::Arc, time::Duration};

use librespot_connect::{ConnectConfig, Spirc};
use librespot_core::{
    Error, Session, SessionConfig, authentication::Credentials, cache::Cache, config::DeviceType,
    error::ErrorKind,
};
use librespot_playback::{
    audio_backend,
    config::{AudioFormat, Bitrate, PlayerConfig, VolumeCtrl},
    mixer::{self, MixerConfig},
    player::Player,
};
use serde::Deserialize;

use crate::events::{Event, FailureReason};

/// How long the access-point handshake and Connect registration may take
/// before the attempt is abandoned. Never retried here: Swift decides.
pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Debug, Deserialize)]
pub struct Config {
    /// Stable per install. A new id per launch registers a new Connect device
    /// every time, which piles up ghost devices on the account.
    pub device_id: String,
    pub device_name: String,
    pub initial_volume: u16,
    pub credentials: CredentialsInput,
    /// The account the Web API grant belongs to. The session must sign in as
    /// the same account, or it is closed before it plays anything.
    pub expected_username: Option<String>,
    pub audio_cache_dir: Option<PathBuf>,
    pub audio_cache_limit: Option<u64>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum CredentialsInput {
    /// A fresh playback OAuth token, used once to obtain a reusable credential.
    AccessToken { token: String },
    /// librespot's reusable credential, exactly as `Event::Connected` gave it.
    Stored { json: String },
}

impl CredentialsInput {
    fn into_credentials(self) -> Result<Credentials, Error> {
        match self {
            Self::AccessToken { token } => Ok(Credentials::with_access_token(token)),
            Self::Stored { json } => {
                serde_json::from_str(&json).map_err(|e| Error::invalid_argument(e.to_string()))
            }
        }
    }
}

pub struct Engine {
    pub spirc: Spirc,
    pub session: Session,
}

pub struct Failure {
    pub reason: FailureReason,
    pub message: String,
}

impl From<Error> for Failure {
    fn from(error: Error) -> Self {
        Self {
            reason: classify(&error),
            message: error.to_string(),
        }
    }
}

/// Only an access point's explicit login refusal counts as a rejected
/// credential. Other permission errors (a client-token 403, say) are not a
/// reason to throw the grant away.
fn classify(error: &Error) -> FailureReason {
    let message = error.error.to_string();
    if error.kind == ErrorKind::PermissionDenied && message.starts_with("Login failed") {
        FailureReason::AuthRejected
    } else if error.kind == ErrorKind::DeadlineExceeded {
        FailureReason::Timeout
    } else {
        FailureReason::Other
    }
}

impl Engine {
    /// Connects, registers the Connect device and returns the Spirc task for
    /// the caller to run. `emit` receives player events from now on.
    pub async fn start(
        config: Config,
        emit: impl Fn(Event) + Send + Sync + 'static,
    ) -> Result<(Self, impl Future<Output = ()> + Send + 'static), Failure> {
        let credentials = config.credentials.into_credentials()?;
        let session_config = SessionConfig {
            device_id: config.device_id,
            ..SessionConfig::default()
        };
        // Credentials stay in memory: Swift persists them in the Keychain.
        let cache = Cache::new(
            None,
            None,
            config.audio_cache_dir.as_deref(),
            config.audio_cache_limit,
        )?
        .with_memory_credentials();
        let session = Session::new(session_config, Some(cache));

        let mixer = mixer::find(Some("softvol")).ok_or_else(|| Failure {
            reason: FailureReason::Other,
            message: "soft volume mixer missing".into(),
        })?(MixerConfig {
            // librespot's default log curve puts every useful level in the
            // slider's top quarter; cubic spreads it out.
            volume_ctrl: VolumeCtrl::Cubic(VolumeCtrl::DEFAULT_DB_RANGE),
            ..MixerConfig::default()
        })?;
        let backend = audio_backend::find(None).ok_or_else(|| Failure {
            reason: FailureReason::Other,
            message: "audio backend missing".into(),
        })?;
        let player = Player::new(
            PlayerConfig {
                bitrate: Bitrate::Bitrate320,
                ..PlayerConfig::default()
            },
            session.clone(),
            mixer.get_soft_volume(),
            move || backend(None, AudioFormat::default()),
        );

        let mut events = player.get_player_event_channel();
        let emit = Arc::new(emit);
        tokio::spawn(async move {
            while let Some(event) = events.recv().await {
                if let Some(event) = Event::from_player(event) {
                    emit(event);
                }
            }
        });

        let connect_config = ConnectConfig {
            name: config.device_name,
            device_type: DeviceType::Computer,
            initial_volume: config.initial_volume,
            ..ConnectConfig::default()
        };
        let (spirc, task) =
            Spirc::new(connect_config, session.clone(), credentials, player, mixer).await?;

        if let Some(expected) = config.expected_username
            && !session.username().eq_ignore_ascii_case(&expected)
        {
            let _ = spirc.shutdown();
            task.await;
            return Err(Failure {
                reason: FailureReason::AccountMismatch,
                message: format!(
                    "playback signed in as {}, expected {expected}",
                    session.username()
                ),
            });
        }
        Ok((Self { spirc, session }, task))
    }

    /// The reusable credential to persist, as JSON.
    pub fn credentials_json(&self) -> Option<String> {
        let credentials = self.session.cache()?.credentials()?;
        serde_json::to_string(&credentials).ok()
    }

    pub fn shutdown(&self) {
        let _ = self.spirc.shutdown();
    }
}
