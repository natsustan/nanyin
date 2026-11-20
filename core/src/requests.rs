//! Questions Swift asks the core and awaits one answer to, unlike commands
//! (fire and forget) and events (pushed). Each carries a number its
//! `Event::Reply` repeats.

use serde::Deserialize;
use serde_json::Value;

use crate::reads::Reads;

#[derive(Debug, Deserialize, PartialEq)]
pub struct Request {
    pub request: u64,
    #[serde(flatten)]
    pub ask: Ask,
}

#[derive(Debug, Deserialize, PartialEq)]
#[serde(tag = "ask", rename_all = "snake_case")]
pub enum Ask {
    /// A page of a playlist's songs, read through the session.
    Playlist { id: String, offset: usize },
    /// An artist's popular songs, read through the session.
    TopTracks { id: String },
}

impl Ask {
    pub async fn answer(self, reads: &Reads) -> Result<Value, String> {
        let answer = match self {
            Self::Playlist { id, offset } => serde_json::to_value(
                reads
                    .playlist(&id, offset)
                    .await
                    .map_err(|e| e.to_string())?,
            ),
            Self::TopTracks { id } => {
                serde_json::to_value(reads.top_tracks(&id).await.map_err(|e| e.to_string())?)
            }
        };
        answer.map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_requests() {
        let request: Request =
            serde_json::from_str(r#"{"request":7,"ask":"playlist","id":"abc","offset":50}"#)
                .unwrap();
        assert_eq!(
            request,
            Request {
                request: 7,
                ask: Ask::Playlist {
                    id: "abc".into(),
                    offset: 50
                }
            }
        );
        let request: Request =
            serde_json::from_str(r#"{"request":8,"ask":"top_tracks","id":"abc"}"#).unwrap();
        assert_eq!(request.ask, Ask::TopTracks { id: "abc".into() });
    }
}
