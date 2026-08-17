//! Standalone session-connect test: init_test <access_token>
//! Prints whether a librespot session accepts the OAuth token (login5 path).

use librespot_core::authentication::Credentials;
use librespot_core::cache::Cache;
use librespot_core::config::SessionConfig;
use librespot_core::session::Session;

#[tokio::main]
async fn main() {
    let token = std::env::args().nth(1).expect("usage: init_test <access_token>");
    let cfg = SessionConfig {
        device_id: format!("nanyin_test_{}", std::process::id()),
        ..Default::default()
    };
    let cache = Cache::new(None::<std::path::PathBuf>, None, None, None).ok();
    let session = Session::new(cfg, cache);
    let creds = Credentials::with_access_token(token);

    println!("connecting…");
    match session.connect(creds, true).await {
        Ok(()) => {
            println!("SESSION OK — username: {:?}", session.username());
            println!("spclient base: {:?}", session.spclient().base_url().await);
            println!("country: {}", session.country());
        }
        Err(e) => {
            println!("SESSION FAILED: {e:?}");
            std::process::exit(1);
        }
    }
}
