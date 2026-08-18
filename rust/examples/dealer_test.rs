//! Dealer stability probe: session + Spirc (no audio), idles 5 minutes.
//! Usage: dealer_test <access_token> [device_id]

use std::sync::Arc;

use librespot_connect::{ConnectConfig, Spirc};
use librespot_core::authentication::Credentials;
use librespot_core::config::{DeviceType, SessionConfig};
use librespot_core::session::Session;
use librespot_playback::config::{AudioFormat, PlayerConfig};
use librespot_playback::mixer::softmixer::SoftMixer;
use librespot_playback::mixer::{Mixer, MixerConfig};
use librespot_playback::player::Player;

#[tokio::main]
async fn main() {
    let token = std::env::args().nth(1).expect("usage: dealer_test <token> [device_id]");
    let device_id = std::env::args()
        .nth(2)
        .unwrap_or_else(|| format!("nanyin_probe_{}", std::process::id()));

    let session = Session::new(
        SessionConfig {
            device_id: device_id.clone(),
            ..Default::default()
        },
        None,
    );
    let creds = Credentials::with_access_token(token);

    // NOTE: Spirc::new connects the session itself — connecting here first
    // would hit the NotConnected error (same as the M0 bug).
    println!("[probe] session created, letting spirc connect…");

    let mixer: Arc<SoftMixer> = Arc::new(SoftMixer::open(MixerConfig::default()).unwrap());
    let player = Player::new(
        PlayerConfig::default(),
        session.clone(),
        mixer.get_soft_volume(),
        || {
            // Pipe sink to /dev/null — we never load a track, nothing decodes.
            let build = librespot_playback::audio_backend::BACKENDS
                .iter()
                .find(|(name, _)| *name == "pipe")
                .map(|(_, b)| *b)
                .expect("pipe backend");
            build(Some("/dev/null".into()), AudioFormat::default())
        },
    );

    let (spirc, task) = Spirc::new(
        ConnectConfig {
            name: "nanyin-probe".into(),
            device_type: DeviceType::Computer,
            ..Default::default()
        },
        session.clone(),
        creds,
        player,
        mixer as Arc<dyn Mixer>,
    )
    .await
    .expect("spirc");
    println!("[probe] spirc up — idling 300s, watching dealer");
    tokio::spawn(task);
    let _spirc = spirc; // keep alive

    for i in 1..=30 {
        tokio::time::sleep(std::time::Duration::from_secs(10)).await;
        println!("[probe] t+{}0s session_invalid={}", i, session.is_invalid());
        if session.is_invalid() {
            println!("[probe] SESSION DIED — server ghosting confirmed");
            return;
        }
    }
    println!("[probe] survived 300s — dealer stable");
}
