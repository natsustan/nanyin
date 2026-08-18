//! Raw dealer websocket experiment (M2.3 queue debugging).
//! Connects DIRECTLY to the dealer endpoint, sends candidate SUBSCRIBE
//! frames, and prints every inbound frame — isolating the frame format
//! question from librespot's dealer implementation.
//!
//! Usage: ws_probe <access_token> [format=a|b|c] [hold_secs=15]
//!   a: {"type":"SUBSCRIBE","uri":"hm://connect-state/v1/cluster"}
//!   b: {"type":"SUBSCRIBE","uris":["hm://connect-state/v1/cluster"]}
//!   c: {"method":"SUBSCRIBE","uri":"hm://connect-state/v1/cluster"}

use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::tungstenite::Message as WsMessage;

#[tokio::main]
async fn main() {
    let token = std::env::args().nth(1).expect("usage: ws_probe <token> [a|b|c] [hold_secs]");
    let format = std::env::args().nth(2).unwrap_or_else(|| "a".into());
    let hold: u64 = std::env::args().nth(3).unwrap_or_else(|| "15".into()).parse().unwrap();

    // Resolve dealer host via the public apresolve endpoint.
    let resp = reqwest::get("https://apresolve.spotify.com/?type=dealer")
        .await
        .expect("apresolve");
    let body: serde_json::Value = resp.json().await.expect("apresolve json");
    let host = body["dealer"]
        .as_array()
        .and_then(|a| a.first())
        .and_then(|h| h.as_str())
        .expect("dealer host")
        .to_string();
    let url = format!("wss://{host}/?access_token={token}");
    println!("[ws_probe] connecting to wss://{host}/…");

    let (mut ws, _resp) = tokio_tungstenite::connect_async(&url).await.expect("ws connect");
    println!("[ws_probe] connected (format {format}, holding {hold}s)");

    let frame = match format.as_str() {
        "a" => r#"{"type":"SUBSCRIBE","uri":"hm://connect-state/v1/cluster"}"#.to_string(),
        "b" => r#"{"type":"SUBSCRIBE","uris":["hm://connect-state/v1/cluster"]}"#.to_string(),
        "c" => r#"{"method":"SUBSCRIBE","uri":"hm://connect-state/v1/cluster"}"#.to_string(),
        other => panic!("unknown format {other}"),
    };
    println!("[ws_probe] sending: {frame}");
    ws.send(WsMessage::Text(frame.into())).await.expect("send subscribe");

    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(hold);
    loop {
        let next = tokio::time::timeout_at(deadline, ws.next()).await;
        match next {
            Err(_) => {
                println!("[ws_probe] held {hold}s without closing — SUBSCRIBE ACCEPTED?");
                break;
            }
            Ok(None) => {
                println!("[ws_probe] server closed the connection cleanly");
                break;
            }
            Ok(Some(Err(e))) => {
                println!("[ws_probe] ws error: {e}");
                break;
            }
            Ok(Some(Ok(msg))) => match msg {
                WsMessage::Text(t) => {
                    let preview: String = t.chars().take(400).collect();
                    println!("[ws_probe] TEXT: {preview}");
                }
                WsMessage::Binary(b) => println!("[ws_probe] BINARY: {} bytes", b.len()),
                WsMessage::Ping(_) => println!("[ws_probe] ping"),
                WsMessage::Pong(_) => println!("[ws_probe] pong"),
                WsMessage::Close(c) => println!("[ws_probe] CLOSE: {c:?}"),
                _ => {}
            },
        }
    }
}
