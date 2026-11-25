//! Read-only Pathfinder queries: followed artists' new releases
//! (`queryWhatsNewFeed`), personalized Home shelves (`homeSection` for Made
//! for you and Your top mixes), and artist page metadata (`queryArtistOverview`
//! for monthly listeners, followers and popular track play counts, plus
//! `queryArtistRelated` for Fans also like).
//!
//! These are the same private queries Spotify's own clients make, sent with
//! the playback session's Login5 bearer token and spclient client token.
//! Spotify can change persisted query hashes without notice, so failures are
//! reported cleanly and callers leave the affected section out rather than
//! breaking the page. Results are cached briefly and any 429 pauses further
//! Pathfinder reads until the cooldown passes.

use std::{
    collections::{HashMap, HashSet},
    sync::Mutex as SyncMutex,
    time::{Duration, Instant},
};

use bytes::Bytes;
use http::{Method, Request};
use librespot_core::{Error, Session, error::ErrorKind};
use serde::Serialize;
use serde_json::Value;
use tokio::sync::Mutex;

const ENDPOINT: &str = "https://api-partner.spotify.com/pathfinder/v2/query";
const WHATS_NEW_HASH: &str = "d889c8c936ab192af8ced595427f5ba2acdf63478fdc0a181c8d477f8322630e";
const HOME_SECTION_HASH: &str = "eb3fba2d388cf4fc4d696b1757a58584e9538a3b515ea742e9cc9465807340be";
const ARTIST_OVERVIEW_HASH: &str =
    "4bc52527bb77a5f8bbb9afe491e9aa725698d29ab73bff58d49169ee29800167";
const ARTIST_RELATED_HASH: &str =
    "3d031d6cb22a2aa7c8d203d49b49df731f58b1e2799cc38d9876d58771aa66f3";

const MADE_FOR_YOU_SECTION: &str = "spotify:section:0JQ5DAUnp4wcj0bCb3wh3S";
const TOP_MIXES_SECTION: &str = "spotify:section:0JQ5DAnM3wGh0gz1MXnu89";
/// Spotify DJ is a special context librespot cannot play as a playlist.
const UNSUPPORTED_DJ_URI: &str = "spotify:playlist:37i9dQZF1EYkqdzj48dyYq";

const NEW_RELEASES_LIMIT: usize = 50;
const HOME_PAGE_SIZE: usize = 20;
const HOME_MAX_PAGES: usize = 2;
const ARTIST_CACHE_LIMIT: usize = 32;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const CACHE_AGE: Duration = Duration::from_secs(600);
const RATE_LIMIT_COOLDOWN: Duration = Duration::from_secs(60);

/// Shaped like `NanyinKit.SpotifyImage`.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct Image {
    pub url: String,
    pub width: Option<u32>,
}

/// Shaped like `NanyinKit.ArtistRef`.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct ArtistRef {
    pub id: Option<String>,
    pub name: String,
    pub uri: Option<String>,
}

/// Shaped like `NanyinKit.AlbumSummary`.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct ReleaseAlbum {
    pub id: String,
    pub name: String,
    pub uri: String,
    pub album_type: Option<String>,
    pub images: Vec<Image>,
    pub artists: Vec<ArtistRef>,
    pub release_date: Option<String>,
}

/// Shaped like `NanyinKit.PlaylistOwner`.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct PlaylistOwner {
    pub id: String,
    pub display_name: Option<String>,
}

/// Shaped like `NanyinKit.Playlist`.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct ShelfPlaylist {
    pub id: String,
    pub name: String,
    pub uri: String,
    pub description: Option<String>,
    pub images: Vec<Image>,
    pub owner: PlaylistOwner,
    pub collaborative: Option<bool>,
}

#[derive(Clone, Debug, Default, Serialize, PartialEq, Eq)]
pub struct HomeShelves {
    pub made_for_you: Vec<ShelfPlaylist>,
    pub top_mixes: Vec<ShelfPlaylist>,
}

/// Monthly listeners, follower count and popular-track play counts from
/// `queryArtistOverview`.
#[derive(Clone, Debug, Default, Serialize, PartialEq, Eq)]
pub struct ArtistOverview {
    pub monthly_listeners: Option<u64>,
    pub followers: Option<u64>,
    pub play_counts: HashMap<String, u64>,
}

/// Shaped like `NanyinKit.Artist`.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct RelatedArtist {
    pub id: String,
    pub name: String,
    pub uri: String,
    pub images: Vec<Image>,
}

pub struct Pathfinder {
    session: Session,
    /// Separate locks let New Releases and Made for You load concurrently
    /// while still coalescing duplicate reads of the same shelf.
    new_releases: Mutex<Option<(Instant, Vec<ReleaseAlbum>)>>,
    home_shelves: Mutex<Option<(Instant, HomeShelves)>>,
    artist_overviews: SyncMutex<HashMap<String, (Instant, ArtistOverview)>>,
    related_artists: SyncMutex<HashMap<String, (Instant, Vec<RelatedArtist>)>>,
    cooldown_until: SyncMutex<Option<Instant>>,
}

impl Pathfinder {
    pub fn new(session: Session) -> Self {
        Self {
            session,
            new_releases: Mutex::default(),
            home_shelves: Mutex::default(),
            artist_overviews: SyncMutex::default(),
            related_artists: SyncMutex::default(),
            cooldown_until: SyncMutex::default(),
        }
    }

    fn cooling_down(&self) -> bool {
        self.cooldown_until
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .is_some_and(|until| Instant::now() < until)
    }

    fn note_rate_limit(&self) {
        *self
            .cooldown_until
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) =
            Some(Instant::now() + RATE_LIMIT_COOLDOWN);
    }

    /// The account's feed of new releases from followed artists, newest first.
    /// Read-only: never marks items as seen.
    pub async fn new_releases(&self, force: bool) -> Result<Vec<ReleaseAlbum>, Error> {
        let mut cached = self.new_releases.lock().await;
        if !force
            && let Some((at, albums)) = cached.as_ref()
            && at.elapsed() < CACHE_AGE
        {
            return Ok(albums.clone());
        }
        let body = self.post_checked(&whats_new_query()).await?;
        let albums = parse_new_releases(&body)?;
        *cached = Some((Instant::now(), albums.clone()));
        Ok(albums)
    }

    /// Personalized Home shelves (`Made for you` and `Your top mixes`).
    pub async fn made_for_you(&self, timezone: &str, force: bool) -> Result<HomeShelves, Error> {
        let mut cached = self.home_shelves.lock().await;
        if !force
            && let Some((at, shelves)) = cached.as_ref()
            && at.elapsed() < CACHE_AGE
        {
            return Ok(shelves.clone());
        }
        if self.cooling_down() {
            return Err(Error::resource_exhausted("pathfinder rate limited"));
        }
        let country = self.session.country();
        let (made_for_you, top_mixes) = tokio::join!(
            self.read_home_section(MADE_FOR_YOU_SECTION, &country, timezone),
            self.read_home_section(TOP_MIXES_SECTION, &country, timezone),
        );
        if [&made_for_you, &top_mixes]
            .iter()
            .any(|res| matches!(res, Err(e) if e.kind == ErrorKind::ResourceExhausted))
        {
            self.note_rate_limit();
        }
        let (shelves, complete) = match (made_for_you, top_mixes) {
            (Ok(made_for_you), Ok(top_mixes)) => (
                HomeShelves {
                    made_for_you,
                    top_mixes,
                },
                true,
            ),
            (Ok(made_for_you), Err(error)) => {
                log::warn!("pathfinder top mixes failed: {error}");
                (
                    HomeShelves {
                        made_for_you,
                        top_mixes: Vec::new(),
                    },
                    false,
                )
            }
            (Err(error), Ok(top_mixes)) => {
                log::warn!("pathfinder made for you failed: {error}");
                (
                    HomeShelves {
                        made_for_you: Vec::new(),
                        top_mixes,
                    },
                    false,
                )
            }
            (Err(error), Err(_)) => return Err(error),
        };
        if complete {
            *cached = Some((Instant::now(), shelves.clone()));
        }
        Ok(shelves)
    }

    async fn read_home_section(
        &self,
        section: &str,
        country: &str,
        timezone: &str,
    ) -> Result<Vec<ShelfPlaylist>, Error> {
        let mut playlists = Vec::new();
        let mut seen = HashSet::new();
        let sp_t = self.session.device_id();
        for page in 0..HOME_MAX_PAGES {
            let offset = page * HOME_PAGE_SIZE;
            let body = self
                .post(&home_section_query(
                    section, country, timezone, sp_t, offset,
                ))
                .await?;
            let parsed = parse_home_section_page(&body)?;
            let more = parsed.more(offset);
            let mut added = 0;
            for playlist in parsed.playlists {
                if seen.insert(playlist.id.clone()) {
                    playlists.push(playlist);
                    added += 1;
                }
            }
            if !more || added == 0 {
                break;
            }
        }
        Ok(playlists)
    }

    /// Monthly listeners, follower count and popular-track play counts for one
    /// artist (`queryArtistOverview`).
    pub async fn artist_overview(&self, id: &str) -> Result<ArtistOverview, Error> {
        if !valid_id(id) {
            return Err(Error::invalid_argument("artist id"));
        }
        if let Some(cached) = cache_get(&self.artist_overviews, id) {
            return Ok(cached);
        }
        let body = self.post_checked(&artist_overview_query(id)).await?;
        let overview = parse_artist_overview(&body)?;
        cache_put(&self.artist_overviews, id, overview.clone());
        Ok(overview)
    }

    /// Related artist cards ("Fans also like") from `queryArtistRelated`.
    pub async fn related_artists(&self, id: &str) -> Result<Vec<RelatedArtist>, Error> {
        if !valid_id(id) {
            return Err(Error::invalid_argument("artist id"));
        }
        if let Some(cached) = cache_get(&self.related_artists, id) {
            return Ok(cached);
        }
        let body = self.post_checked(&artist_related_query(id)).await?;
        let artists = parse_related_artists(&body)?;
        cache_put(&self.related_artists, id, artists.clone());
        Ok(artists)
    }

    async fn post_checked(&self, payload: &Value) -> Result<Value, Error> {
        if self.cooling_down() {
            return Err(Error::resource_exhausted("pathfinder rate limited"));
        }
        match self.post(payload).await {
            Ok(body) => Ok(body),
            Err(error) => {
                if error.kind == ErrorKind::ResourceExhausted {
                    self.note_rate_limit();
                }
                Err(error)
            }
        }
    }

    async fn post(&self, payload: &Value) -> Result<Value, Error> {
        let token = self.session.login5().auth_token().await?;
        let client_token = self.session.spclient().client_token().await?;
        let bytes = serde_json::to_vec(payload)?;
        let req = Request::builder()
            .method(Method::POST)
            .uri(ENDPOINT)
            .header("authorization", format!("Bearer {}", token.access_token))
            .header("client-token", client_token)
            .header("content-type", "application/json")
            .body(Bytes::from(bytes))
            .map_err(Error::invalid_argument)?;
        let response = tokio::time::timeout(
            REQUEST_TIMEOUT,
            self.session.http_client().request_body(req),
        )
        .await
        .map_err(|_| Error::deadline_exceeded("pathfinder request timed out"))??;
        Ok(serde_json::from_slice(&response)?)
    }
}

fn whats_new_query() -> Value {
    serde_json::json!({
        "operationName": "queryWhatsNewFeed",
        "variables": {
            "offset": 0,
            "limit": NEW_RELEASES_LIMIT,
            "onlyUnPlayedItems": false,
            "includedContentTypes": ["ALBUM"],
            "includeEpisodeContentRatingsV2": false
        },
        "extensions": {
            "persistedQuery": {
                "version": 1,
                "sha256Hash": WHATS_NEW_HASH
            }
        }
    })
}

fn home_section_query(
    section: &str,
    country: &str,
    timezone: &str,
    context_token: &str,
    offset: usize,
) -> Value {
    serde_json::json!({
        "operationName": "homeSection",
        "variables": {
            "uri": section,
            "country": country,
            "timeZone": timezone,
            "sp_t": context_token,
            "sectionItemsLimit": HOME_PAGE_SIZE,
            "sectionItemsOffset": offset
        },
        "extensions": {
            "persistedQuery": {
                "version": 1,
                "sha256Hash": HOME_SECTION_HASH
            }
        }
    })
}

fn has_graphql_errors(body: &Value) -> bool {
    body.get("errors").is_some_and(|errors| {
        !errors.is_null() && errors.as_array().is_none_or(|list| !list.is_empty())
    })
}

fn valid_id(id: &str) -> bool {
    id.len() == 22 && id.bytes().all(|b| b.is_ascii_alphanumeric())
}

fn parse_images(sources: Option<&Value>) -> Vec<Image> {
    sources
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|source| {
            let url = source.get("url")?.as_str()?;
            if !url.starts_with("https://") {
                return None;
            }
            let width = source
                .get("width")
                .and_then(Value::as_u64)
                .and_then(|w| u32::try_from(w).ok());
            Some(Image {
                url: url.to_owned(),
                width,
            })
        })
        .collect()
}

fn parse_new_releases(body: &Value) -> Result<Vec<ReleaseAlbum>, Error> {
    if has_graphql_errors(body) {
        return Err(Error::unavailable("Spotify refused the What's New feed"));
    }
    let items = body
        .pointer("/data/whatsNewFeedItems/items")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::unavailable("What's New feed missing in response"))?;

    let mut albums = Vec::new();
    let mut seen = HashSet::new();
    for item in items {
        if item.pointer("/content/__typename").and_then(Value::as_str)
            != Some("AlbumResponseWrapper")
        {
            continue;
        }
        let Some(data) = item.pointer("/content/data") else {
            continue;
        };
        if let Some(album) = parse_release_album(data)
            && seen.insert(album.uri.clone())
        {
            albums.push(album);
        }
    }
    albums.sort_by(|a, b| b.release_date.cmp(&a.release_date));
    albums.truncate(NEW_RELEASES_LIMIT);
    Ok(albums)
}

fn parse_release_album(data: &Value) -> Option<ReleaseAlbum> {
    if data.get("__typename").and_then(Value::as_str) != Some("Album") {
        return None;
    }
    let uri = data.get("uri")?.as_str()?;
    let id = uri
        .strip_prefix("spotify:album:")
        .filter(|id| valid_id(id))?;
    let name = data.get("name")?.as_str()?;
    let album_type = data
        .get("albumType")
        .and_then(Value::as_str)
        .map(str::to_ascii_lowercase);
    let release_date = data
        .pointer("/date/isoString")
        .and_then(Value::as_str)
        .map(|iso| format_release_date(iso, data.pointer("/date/precision")));
    let artists = data
        .pointer("/artists/items")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|artist| {
            let name = artist.pointer("/profile/name")?.as_str()?;
            let uri = artist.get("uri").and_then(Value::as_str);
            Some(ArtistRef {
                id: uri
                    .and_then(|u| u.strip_prefix("spotify:artist:"))
                    .map(str::to_owned),
                name: name.to_owned(),
                uri: uri.map(str::to_owned),
            })
        })
        .collect();
    let images = parse_images(data.pointer("/coverArt/sources"));
    Some(ReleaseAlbum {
        id: id.to_owned(),
        name: name.to_owned(),
        uri: uri.to_owned(),
        album_type,
        images,
        artists,
        release_date,
    })
}

fn format_release_date(iso: &str, precision: Option<&Value>) -> String {
    let day = iso.get(..10).unwrap_or(iso);
    match precision.and_then(Value::as_str) {
        Some("YEAR") => day.get(..4).unwrap_or(day).to_owned(),
        Some("MONTH") => day.get(..7).unwrap_or(day).to_owned(),
        _ => day.to_owned(),
    }
}

struct HomePage {
    playlists: Vec<ShelfPlaylist>,
    count: usize,
    total: Option<usize>,
}

impl HomePage {
    fn more(&self, offset: usize) -> bool {
        self.count > 0
            && self.total.map_or(self.count == HOME_PAGE_SIZE, |total| {
                offset.saturating_add(self.count) < total
            })
    }
}

fn parse_home_section_page(body: &Value) -> Result<HomePage, Error> {
    if has_graphql_errors(body) {
        return Err(Error::unavailable("Spotify refused the Home section"));
    }
    let sections = body
        .pointer("/data/homeSections/sections")
        .and_then(Value::as_array)
        .filter(|sections| !sections.is_empty())
        .ok_or_else(|| Error::unavailable("Home sections missing in response"))?;

    let mut playlists = Vec::new();
    let mut count = 0usize;
    let mut total = Some(0usize);
    for section in sections {
        let items = section
            .pointer("/sectionItems/items")
            .and_then(Value::as_array)
            .ok_or_else(|| Error::unavailable("Home section items missing"))?;
        count += items.len();
        let section_total = section
            .pointer("/sectionItems/totalCount")
            .and_then(Value::as_u64)
            .and_then(|n| usize::try_from(n).ok());
        total = total.and_then(|sum| section_total.map(|n| sum + n));
        for item in items {
            let Some(data) = item.pointer("/content/data") else {
                continue;
            };
            if let Some(playlist) = parse_shelf_playlist(data) {
                playlists.push(playlist);
            }
        }
    }
    Ok(HomePage {
        playlists,
        count,
        total,
    })
}

fn parse_shelf_playlist(data: &Value) -> Option<ShelfPlaylist> {
    if data.get("__typename").and_then(Value::as_str) != Some("Playlist") {
        return None;
    }
    let uri = data.get("uri")?.as_str()?;
    if uri == UNSUPPORTED_DJ_URI {
        return None;
    }
    let id = uri
        .strip_prefix("spotify:playlist:")
        .filter(|id| valid_id(id))?;
    let name = data.get("name")?.as_str()?;
    let description = data
        .get("description")
        .and_then(Value::as_str)
        .filter(|d| !d.is_empty())
        .map(str::to_owned);
    let images = data
        .pointer("/images/items")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .flat_map(|item| parse_images(item.get("sources")))
        .collect();
    let owner = data.pointer("/ownerV2/data");
    let owner_id = owner
        .and_then(|o| o.get("uri"))
        .and_then(Value::as_str)
        .and_then(|u| u.strip_prefix("spotify:user:"))
        .unwrap_or("spotify")
        .to_owned();
    let owner_name = owner
        .and_then(|o| o.get("name"))
        .and_then(Value::as_str)
        .map(str::to_owned);
    Some(ShelfPlaylist {
        id: id.to_owned(),
        name: name.to_owned(),
        uri: uri.to_owned(),
        description,
        images,
        owner: PlaylistOwner {
            id: owner_id,
            display_name: owner_name,
        },
        collaborative: Some(false),
    })
}

fn artist_overview_query(id: &str) -> Value {
    serde_json::json!({
        "operationName": "queryArtistOverview",
        "variables": {
            "uri": format!("spotify:artist:{id}"),
            "locale": "",
            "includePrerelease": false
        },
        "extensions": {
            "persistedQuery": {
                "version": 1,
                "sha256Hash": ARTIST_OVERVIEW_HASH
            }
        }
    })
}

fn artist_related_query(id: &str) -> Value {
    serde_json::json!({
        "operationName": "queryArtistRelated",
        "variables": {
            "uri": format!("spotify:artist:{id}")
        },
        "extensions": {
            "persistedQuery": {
                "version": 1,
                "sha256Hash": ARTIST_RELATED_HASH
            }
        }
    })
}

fn cache_get<T: Clone>(cache: &SyncMutex<HashMap<String, (Instant, T)>>, key: &str) -> Option<T> {
    let guard = cache
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    guard
        .get(key)
        .filter(|(at, _)| at.elapsed() < CACHE_AGE)
        .map(|(_, value)| value.clone())
}

fn cache_put<T>(cache: &SyncMutex<HashMap<String, (Instant, T)>>, key: &str, value: T) {
    let mut guard = cache
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    guard.retain(|_, (at, _)| at.elapsed() < CACHE_AGE);
    if guard.len() >= ARTIST_CACHE_LIMIT
        && !guard.contains_key(key)
        && let Some(oldest) = guard
            .iter()
            .min_by_key(|(_, (at, _))| *at)
            .map(|(k, _)| k.clone())
    {
        guard.remove(&oldest);
    }
    guard.insert(key.to_owned(), (Instant::now(), value));
}

fn parse_count(value: &Value) -> Option<u64> {
    match value {
        Value::String(text) => text.parse::<u64>().ok(),
        other => other.as_u64(),
    }
}

fn parse_artist_overview(body: &Value) -> Result<ArtistOverview, Error> {
    if has_graphql_errors(body) {
        return Err(Error::unavailable("Spotify refused the artist overview"));
    }
    let artist = body
        .pointer("/data/artistUnion")
        .filter(|value| value.is_object())
        .ok_or_else(|| Error::unavailable("Artist overview missing in response"))?;
    if artist.get("__typename").and_then(Value::as_str) == Some("NotFound") {
        return Err(Error::not_found("Artist overview not found"));
    }
    let monthly_listeners = artist
        .pointer("/stats/monthlyListeners")
        .and_then(parse_count);
    let followers = artist.pointer("/stats/followers").and_then(parse_count);
    let mut play_counts = HashMap::new();
    if let Some(items) = artist
        .pointer("/discography/topTracks/items")
        .and_then(Value::as_array)
    {
        for row in items {
            let Some(track) = row.get("track") else {
                continue;
            };
            let Some(count) = track.get("playcount").and_then(parse_count) else {
                continue;
            };
            if let Some(uri) = track
                .get("uri")
                .and_then(Value::as_str)
                .filter(|uri| uri.starts_with("spotify:track:"))
            {
                play_counts.insert(uri.to_owned(), count);
            }
            if let Some(linked) = track
                .pointer("/relinkingInformation/linkedTrack/uri")
                .and_then(Value::as_str)
                .filter(|uri| uri.starts_with("spotify:track:"))
            {
                play_counts.insert(linked.to_owned(), count);
            }
        }
    }
    Ok(ArtistOverview {
        monthly_listeners,
        followers,
        play_counts,
    })
}

fn parse_related_artists(body: &Value) -> Result<Vec<RelatedArtist>, Error> {
    if has_graphql_errors(body) {
        return Err(Error::unavailable("Spotify refused related artists"));
    }
    let items = body
        .pointer("/data/artistUnion/relatedContent/relatedArtists/items")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::unavailable("Related artists missing in response"))?;
    let mut artists = Vec::new();
    let mut seen = HashSet::new();
    for entry in items {
        let Some(uri) = entry.get("uri").and_then(Value::as_str) else {
            continue;
        };
        let Some(id) = uri
            .strip_prefix("spotify:artist:")
            .filter(|id| valid_id(id))
        else {
            continue;
        };
        let Some(name) = entry
            .pointer("/profile/name")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|name| !name.is_empty())
        else {
            continue;
        };
        if !seen.insert(id.to_owned()) {
            continue;
        }
        let images = parse_images(entry.pointer("/visuals/avatarImage/sources"));
        artists.push(RelatedArtist {
            id: id.to_owned(),
            name: name.to_owned(),
            uri: uri.to_owned(),
            images,
        });
    }
    if !items.is_empty() && artists.is_empty() {
        return Err(Error::unavailable("Related artists could not be decoded"));
    }
    Ok(artists)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn release_item(uri: &str, name: &str, kind: &str, date: &str) -> Value {
        json!({
            "content": {
                "__typename": "AlbumResponseWrapper",
                "data": {
                    "__typename": "Album",
                    "uri": uri,
                    "name": name,
                    "albumType": kind,
                    "date": {"isoString": date, "precision": "DAY"},
                    "artists": {"items": [{"uri": "spotify:artist:0000000000000000000001", "profile": {"name": "Artist"}}]},
                    "coverArt": {"sources": [{"url": "https://i.scdn.co/image/a", "width": 300}]}
                }
            }
        })
    }

    #[test]
    fn parses_new_releases_newest_first_and_skips_non_albums() {
        let body = json!({
            "data": {
                "whatsNewFeedItems": {
                    "items": [
                        release_item("spotify:album:1111111111111111111111", "Older", "ALBUM", "2026-10-02T00:00:00Z"),
                        release_item("spotify:album:2222222222222222222222", "Newest", "SINGLE", "2026-10-16T00:00:00Z"),
                        {"content": {"__typename": "EpisodeOrChapterResponseWrapper", "data": {"__typename": "Episode"}}},
                        release_item("spotify:album:2222222222222222222222", "Newest", "SINGLE", "2026-10-16T00:00:00Z"),
                        release_item("spotify:album:short", "Bad", "ALBUM", "2026-10-20T00:00:00Z"),
                    ]
                }
            }
        });
        let albums = parse_new_releases(&body).unwrap();
        let names: Vec<_> = albums.iter().map(|a| a.name.as_str()).collect();
        assert_eq!(names, ["Newest", "Older"]);
        assert_eq!(albums[0].album_type.as_deref(), Some("single"));
        assert_eq!(albums[0].release_date.as_deref(), Some("2026-10-16"));
        assert_eq!(albums[0].images[0].width, Some(300));
    }

    #[test]
    fn rejects_graphql_errors_and_missing_feeds() {
        assert!(
            parse_new_releases(&json!({"errors": [{"message": "PersistedQueryNotFound"}]}))
                .is_err()
        );
        assert!(parse_new_releases(&json!({"data": null})).is_err());
        assert!(
            parse_new_releases(&json!({"data": {"whatsNewFeedItems": {"items": []}}}))
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn parses_home_section_and_skips_dj() {
        let body = json!({
            "data": {
                "homeSections": {
                    "sections": [{
                        "sectionItems": {
                            "totalCount": 3,
                            "items": [
                                {"content": {"data": {"__typename": "Playlist", "uri": UNSUPPORTED_DJ_URI, "name": "DJ"}}},
                                {"content": {"data": {
                                    "__typename": "Playlist",
                                    "uri": "spotify:playlist:1234567890123456789012",
                                    "name": "Discover Weekly",
                                    "description": "Your weekly mixtape",
                                    "ownerV2": {"data": {"uri": "spotify:user:spotify", "name": "Spotify"}},
                                    "images": {"items": [{"sources": [{"url": "https://i.scdn.co/image/b", "width": 300}]}]}
                                }}},
                                {"content": {"data": {"__typename": "NotFound"}}}
                            ]
                        }
                    }]
                }
            }
        });
        let page = parse_home_section_page(&body).unwrap();
        assert_eq!(page.count, 3);
        assert!(!page.more(0));
        assert_eq!(page.playlists.len(), 1);
        assert_eq!(page.playlists[0].name, "Discover Weekly");
        assert_eq!(page.playlists[0].owner.id, "spotify");
        assert_eq!(page.playlists[0].images[0].width, Some(300));
    }

    #[test]
    fn whats_new_query_is_read_only() {
        let query = whats_new_query();
        assert_eq!(query["operationName"], "queryWhatsNewFeed");
        assert_eq!(query["variables"]["includedContentTypes"], json!(["ALBUM"]));
        assert!(!query.to_string().contains("SetItemsStateInWhatsNewFeed"));
    }

    #[test]
    fn parses_artist_overview_stats_and_play_counts() {
        let body = json!({
            "data": {
                "artistUnion": {
                    "stats": {
                        "monthlyListeners": 8123456,
                        "followers": "1200450"
                    },
                    "discography": {
                        "topTracks": {
                            "items": [
                                {"track": {
                                    "uri": "spotify:track:1111111111111111111111",
                                    "playcount": "987654321",
                                    "relinkingInformation": {"linkedTrack": {"uri": "spotify:track:9999999999999999999999"}}
                                }},
                                {"track": {"uri": "spotify:track:2222222222222222222222", "playcount": 42000}},
                                {"track": {"uri": "spotify:episode:3333333333333333333333", "playcount": "10"}}
                            ]
                        }
                    }
                }
            }
        });
        let overview = parse_artist_overview(&body).unwrap();
        assert_eq!(overview.monthly_listeners, Some(8_123_456));
        assert_eq!(overview.followers, Some(1_200_450));
        assert_eq!(overview.play_counts.len(), 3);
        assert_eq!(
            overview
                .play_counts
                .get("spotify:track:1111111111111111111111"),
            Some(&987_654_321)
        );
        assert_eq!(
            overview
                .play_counts
                .get("spotify:track:9999999999999999999999"),
            Some(&987_654_321)
        );
        assert_eq!(
            overview
                .play_counts
                .get("spotify:track:2222222222222222222222"),
            Some(&42_000)
        );
        assert!(parse_artist_overview(&json!({"errors": [{"message": "fail"}]})).is_err());
        assert!(parse_artist_overview(&json!({"data": null})).is_err());
        assert!(
            parse_artist_overview(&json!({"data": {"artistUnion": {"__typename": "NotFound"}}}))
                .is_err()
        );
    }

    #[test]
    fn parses_related_artists_and_deduplicates() {
        let body = json!({
            "data": {
                "artistUnion": {
                    "relatedContent": {
                        "relatedArtists": {
                            "items": [
                                {
                                    "uri": "spotify:artist:1111111111111111111111",
                                    "profile": {"name": "Alpha"},
                                    "visuals": {"avatarImage": {"sources": [
                                        {"url": "https://i.scdn.co/image/a", "width": 640}
                                    ]}}
                                },
                                {
                                    "uri": "spotify:artist:1111111111111111111111",
                                    "profile": {"name": "Alpha Duplicate"}
                                },
                                {
                                    "uri": "spotify:artist:bad",
                                    "profile": {"name": "Invalid"}
                                },
                                {
                                    "uri": "spotify:artist:2222222222222222222222",
                                    "profile": {"name": "   "}
                                }
                            ]
                        }
                    }
                }
            }
        });
        let related = parse_related_artists(&body).unwrap();
        assert_eq!(related.len(), 1);
        assert_eq!(related[0].id, "1111111111111111111111");
        assert_eq!(related[0].name, "Alpha");
        assert_eq!(related[0].images[0].width, Some(640));
        assert!(parse_related_artists(&json!({"errors": [{"message": "fail"}]})).is_err());
    }
}
