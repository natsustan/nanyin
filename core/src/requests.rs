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
    /// A song's credits, read through the session.
    Credits { id: String },
    /// A song's lyrics from Spotify's `color-lyrics` service, read through the session.
    Lyrics {
        id: String,
        #[serde(default)]
        cover_file_id: Option<String>,
    },
    /// New releases from followed artists, read through Pathfinder.
    NewReleases {
        #[serde(default)]
        force: bool,
    },
    /// Personalized Home shelves (Made for you and Your top mixes).
    MadeForYou {
        timezone: String,
        #[serde(default)]
        force: bool,
    },
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
            Self::Credits { id } => {
                serde_json::to_value(reads.credits(&id).await.map_err(|e| e.to_string())?)
            }
            Self::Lyrics { id, cover_file_id } => serde_json::to_value(
                reads
                    .lyrics(&id, cover_file_id.as_deref())
                    .await
                    .map_err(|e| e.to_string())?,
            ),
            Self::NewReleases { force } => {
                serde_json::to_value(reads.new_releases(force).await.map_err(|e| e.to_string())?)
            }
            Self::MadeForYou { timezone, force } => serde_json::to_value(
                reads
                    .made_for_you(&timezone, force)
                    .await
                    .map_err(|e| e.to_string())?,
            ),
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
        let request: Request =
            serde_json::from_str(r#"{"request":9,"ask":"credits","id":"abc"}"#).unwrap();
        assert_eq!(request.ask, Ask::Credits { id: "abc".into() });
        let request: Request = serde_json::from_str(
            r#"{"request":12,"ask":"lyrics","id":"abc","cover_file_id":"ab12"}"#,
        )
        .unwrap();
        assert_eq!(
            request.ask,
            Ask::Lyrics {
                id: "abc".into(),
                cover_file_id: Some("ab12".into()),
            }
        );
        let request: Request =
            serde_json::from_str(r#"{"request":10,"ask":"new_releases","force":true}"#).unwrap();
        assert_eq!(request.ask, Ask::NewReleases { force: true });
        let request: Request = serde_json::from_str(
            r#"{"request":11,"ask":"made_for_you","timezone":"Asia/Shanghai"}"#,
        )
        .unwrap();
        assert_eq!(
            request.ask,
            Ask::MadeForYou {
                timezone: "Asia/Shanghai".into(),
                force: false
            }
        );
    }
}
