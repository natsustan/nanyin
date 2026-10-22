//! Bounded library reads over an already verified playback session.
//! Range and batch shapes follow crmne/spotifast session_reads.rs and its pinned
//! librespot fork (669e004e); no session creation, token refresh or Connect load.
use std::{collections::{BTreeSet, HashMap}, ffi::{c_char, CStr, CString},
    future::Future, sync::{atomic::{AtomicU64, Ordering}, Mutex}, time::Duration};
use librespot_core::{error::ErrorKind, http_client::HttpClient, Session, SpotifyUri, spotify_id::SpotifyId};
use librespot_protocol::{extended_metadata::{BatchedEntityRequest, BatchedExtensionResponse, EntityRequest, ExtensionQuery},
    extension_kind::ExtensionKind, metadata::Track, playlist4_external::SelectedListContent};
use once_cell::sync::Lazy;
use protobuf::Message;
use serde_json::{json, Value};
use tokio::sync::{watch, Semaphore};

const PAGE_LIMIT: usize = 50;
const MAX_PENDING: usize = 8;
const READ_TIMEOUT: Duration = Duration::from_secs(15);
static NEXT_REQUEST: AtomicU64 = AtomicU64::new(1);
static REQUESTS: Lazy<Mutex<HashMap<u64, watch::Sender<bool>>>> = Lazy::new(|| Mutex::new(HashMap::new()));
static READ_GATE: Semaphore = Semaphore::const_new(1);

#[derive(Debug)]
struct ReadError { code: &'static str, message: String }
type ReadResult<T> = Result<T, ReadError>;
fn failure(code: &'static str, message: impl Into<String>) -> ReadError {
    ReadError { code, message: message.into() }
}
fn invalid(message: &str) -> ReadError { failure("invalid_response", message) }
fn cancelled() -> ReadError { failure("cancelled", "Playlist read was cancelled") }
impl From<librespot_core::Error> for ReadError {
    fn from(error: librespot_core::Error) -> Self {
        let code = match error.kind {
            ErrorKind::Cancelled => "cancelled",
            ErrorKind::NotFound => "not_found",
            ErrorKind::PermissionDenied => "forbidden",
            ErrorKind::ResourceExhausted => "rate_limited",
            ErrorKind::DeadlineExceeded => "timeout",
            _ => "unavailable",
        };
        failure(code, format!("Playlist read failed: {error}"))
    }
}

/// Allocate before dispatch so cancellation cannot race request registration.
#[no_mangle]
pub extern "C" fn nanyin_library_request_new() -> u64 {
    let mut requests = REQUESTS.lock().unwrap();
    if requests.len() >= MAX_PENDING { return 0; }
    let id = NEXT_REQUEST.fetch_add(1, Ordering::Relaxed);
    let (sender, _) = watch::channel(false);
    requests.insert(id, sender);
    id
}
#[no_mangle]
pub extern "C" fn nanyin_library_request_cancel(id: u64) {
    if let Some(sender) = REQUESTS.lock().unwrap().get(&id) { sender.send_replace(true); }
}
pub(crate) fn cancel_all() {
    for sender in REQUESTS.lock().unwrap().values() { sender.send_replace(true); }
}
struct Registration(u64);
impl Drop for Registration {
    fn drop(&mut self) { REQUESTS.lock().unwrap().remove(&self.0); }
}
async fn cancellable<T>(mut cancel: watch::Receiver<bool>, duration: Duration,
    operation: impl Future<Output = ReadResult<T>>) -> ReadResult<T> {
    if *cancel.borrow() { return Err(cancelled()); }
    tokio::select! {
        biased;
        _ = cancel.changed() => Err(cancelled()),
        result = tokio::time::timeout(duration, operation) => result
            .unwrap_or_else(|_| Err(failure("timeout", "Playlist read timed out"))),
    }
}

struct ReadSession { session: Session, generation: u64, callback: u64, account: String }
impl ReadSession {
    fn capture(account: &str, callback: u64) -> ReadResult<Self> {
        let _lifecycle = crate::PLAYER_LIFECYCLE.lock().unwrap();
        let generation = crate::PLAYER_GENERATION.load(Ordering::SeqCst);
        if crate::SHUTTING_DOWN.load(Ordering::SeqCst)
            || crate::AUTHORIZED_PLAYER_GENERATION.load(Ordering::SeqCst) != generation
            || crate::CALLBACK_GENERATION.load(Ordering::SeqCst) != callback
            || crate::SPIRC.lock().unwrap().is_none() {
            return Err(failure("unavailable", "No verified playback session is available"));
        }
        let session = crate::SESSION.lock().unwrap().clone()
            .ok_or_else(|| failure("unavailable", "No playback session"))?;
        if session.is_invalid() { return Err(failure("unavailable", "Playback session ended")); }
        if account.is_empty() || session.username() != account {
            return Err(failure("account_mismatch", "Library and playback accounts do not match"));
        }
        Ok(Self { session, generation, callback, account: account.to_owned() })
    }
    fn check(&self) -> ReadResult<()> {
        let current = Self::capture(&self.account, self.callback)?;
        if current.generation != self.generation { return Err(cancelled()); }
        if !HttpClient::rate_limit_remaining().is_zero() {
            return Err(failure("rate_limited", "Playback service is cooling down"));
        }
        Ok(())
    }
}

fn endpoint(id: &str, offset: u32, limit: u32) -> ReadResult<String> {
    if id.len() != 22 || !id.bytes().all(|b| b.is_ascii_alphanumeric())
        || SpotifyId::from_base62(id).is_err() || limit == 0 || limit as usize > PAGE_LIMIT
        || offset > i32::MAX as u32 {
        return Err(failure("invalid_argument", "Invalid playlist range"));
    }
    Ok(format!("/playlist/v2/playlist/{id}?decorate=revision,length,attributes,owner&from={offset}&length={limit}"))
}

/// Bounds and raw slots, even when the server responds with an expanded range.
fn window(list: &SelectedListContent, offset: u32, limit: u32) -> ReadResult<Vec<String>> {
    let contents = list.contents.get_or_default();
    let total = usize::try_from(list.length()).map_err(|_| invalid("Negative playlist size"))?;
    let start = usize::try_from(contents.pos()).map_err(|_| invalid("Negative playlist offset"))?;
    let offset = offset as usize;
    if offset > total || start > offset { return Err(invalid("Unexpected playlist range")); }
    let count = (total - offset).min(limit as usize);
    let from = offset - start;
    let end = from.checked_add(count).ok_or_else(|| invalid("Invalid playlist range"))?;
    if end > contents.items.len() { return Err(invalid("Incomplete playlist range")); }
    Ok(contents.items[from..end].iter().map(|item| item.uri().to_owned()).collect())
}
fn batch(rows: &[String]) -> (BatchedEntityRequest, BTreeSet<String>) {
    let asked: BTreeSet<_> = rows.iter().filter(|uri| matches!(
        SpotifyUri::from_uri(uri), Ok(SpotifyUri::Track { .. })
    )).cloned().collect();
    let request = BatchedEntityRequest {
        entity_request: asked.iter().map(|uri| EntityRequest {
            entity_uri: uri.clone(),
            query: vec![ExtensionQuery { extension_kind: ExtensionKind::TRACK_V4.into(), ..Default::default() }],
            ..Default::default()
        }).collect(), ..Default::default()
    };
    (request, asked)
}
fn status(code: i32) -> ReadResult<bool> {
    match code {
        0 | 200 => Ok(true),
        404 | 451 => Ok(false),
        429 => Err(failure("rate_limited", "Spotify limited the metadata request")),
        401 | 403 => Err(failure("forbidden", "Spotify refused the metadata request")),
        _ => Err(invalid("Spotify could not return complete track metadata")),
    }
}
fn track_json(bytes: &[u8], requested: &str) -> ReadResult<Value> {
    let track = Track::parse_from_bytes(bytes).map_err(|_| invalid("Unreadable track metadata"))?;
    let id = SpotifyId::from_raw(track.gid()).map_err(|_| invalid("Track has no valid id"))?.to_base62();
    if format!("spotify:track:{id}") != requested { return Err(invalid("Track metadata identity mismatch")); }
    let album = track.album.get_or_default();
    let album_id = SpotifyId::from_raw(album.gid()).ok().map(|id| id.to_base62());
    let artists: Vec<_> = track.artist.iter().map(|artist| json!({
        "id": SpotifyId::from_raw(artist.gid()).ok().map(|id| id.to_base62()), "name": artist.name()
    })).collect();
    let images: Vec<_> = album.cover_group.get_or_default().image.iter().chain(album.cover.iter())
        .filter(|image| image.file_id().len() == 20).map(|image| {
            let hex: String = image.file_id().iter().map(|b| format!("{b:02x}")).collect();
            json!({"url": format!("https://i.scdn.co/image/{hex}")})
        }).collect();
    Ok(json!({"id": id, "uri": requested, "name": track.name(), "duration_ms": track.duration().max(0),
        "artists": artists, "album": {"id": album_id, "name": album.name(), "images": images}}))
}
fn metadata_rate_limited(response: &BatchedExtensionResponse) -> bool {
    response.extended_metadata.iter().any(|group| group.header.provider_error_status == 429
        || group.extension_data.iter().any(|data| data.header.status_code == 429))
}
fn answers(asked: &BTreeSet<String>, response: BatchedExtensionResponse) -> ReadResult<HashMap<String, Value>> {
    let mut remaining = asked.clone();
    let mut tracks = HashMap::new();
    for group in response.extended_metadata {
        // Provider errors are not individual missing songs.
        if !status(group.header.provider_error_status)? { return Err(invalid("Metadata provider refused the batch")); }
        if group.extension_kind.enum_value().ok() != Some(ExtensionKind::TRACK_V4) { continue; }
        for data in group.extension_data {
            if !asked.contains(&data.entity_uri) { continue; }
            if !remaining.remove(&data.entity_uri) { return Err(invalid("Duplicate metadata response")); }
            if !status(data.header.status_code)? { continue; }
            let bytes = data.extension_data.as_ref().ok_or_else(|| invalid("Missing track metadata"))?;
            tracks.insert(data.entity_uri.clone(), track_json(&bytes.value, &data.entity_uri)?);
        }
    }
    if !remaining.is_empty() { return Err(invalid("Incomplete track metadata response")); }
    Ok(tracks)
}
fn page_json(list: &SelectedListContent, rows: &[String], tracks: &HashMap<String, Value>, offset: u32) -> ReadResult<Value> {
    if list.revision().is_empty() { return Err(invalid("Playlist has no revision")); }
    let revision: String = list.revision().iter().map(|byte| format!("{byte:02x}")).collect();
    let items: Vec<_> = rows.iter().map(|uri| json!({"item": tracks.get(uri)})).collect();
    let next = (offset as usize + rows.len() < list.length() as usize).then_some("next");
    Ok(json!({"offset": offset, "total": list.length(), "next": next, "snapshot_id": revision, "items": items}))
}
trait PageTransport {
    fn check(&self) -> ReadResult<()>;
    async fn playlist(&self, endpoint: &str) -> ReadResult<Vec<u8>>;
    async fn metadata(&self, request: BatchedEntityRequest) -> ReadResult<BatchedExtensionResponse>;
}
impl PageTransport for ReadSession {
    fn check(&self) -> ReadResult<()> { ReadSession::check(self) }
    async fn playlist(&self, endpoint: &str) -> ReadResult<Vec<u8>> {
        Ok(self.session.spclient().request(&http::Method::GET, endpoint, None, None).await?.to_vec())
    }
    async fn metadata(&self, request: BatchedEntityRequest) -> ReadResult<BatchedExtensionResponse> {
        let response = self.session.spclient().get_extended_metadata(request).await?;
        // Persist an embedded 429 before the completed future can race caller
        // cancellation. No Retry-After is available inside this envelope.
        if metadata_rate_limited(&response) {
            HttpClient::record_rate_limit(Duration::from_secs(30))?;
            return Err(failure("rate_limited", "Spotify limited the metadata request"));
        }
        Ok(response)
    }
}
async fn read_with_transport(transport: &impl PageTransport, endpoint: &str, offset: u32, limit: u32) -> ReadResult<Value> {
    tokio::time::sleep(Duration::from_millis(150)).await;
    transport.check()?;
    let bytes = transport.playlist(endpoint).await?;
    let list = SelectedListContent::parse_from_bytes(&bytes).map_err(|_| invalid("Unreadable playlist response"))?;
    let rows = window(&list, offset, limit)?;
    let (request, asked) = batch(&rows);
    let tracks = if asked.is_empty() { HashMap::new() } else {
        tokio::time::sleep(Duration::from_millis(150)).await;
        transport.check()?;
        answers(&asked, transport.metadata(request).await?)?
    };
    transport.check()?;
    page_json(&list, &rows, &tracks, offset)
}
async fn read_page(account: &str, callback: u64, endpoint: &str, offset: u32, limit: u32) -> ReadResult<Value> {
    let _permit = READ_GATE.acquire().await.map_err(|_| cancelled())?;
    let context = ReadSession::capture(account, callback)?;
    read_with_transport(&context, endpoint, offset, limit).await
}

/// Blocking only on Swift's dedicated library worker. Cancellation includes
/// waiting for the read permit. Always returns owned JSON, freed by Swift.
#[no_mangle]
pub extern "C" fn nanyin_playlist_page(request: u64, expected_account: *const c_char,
    callback_generation: u64, playlist_id: *const c_char, offset: u32, limit: u32) -> *mut c_char {
    let _registration = Registration(request);
    let result = (|| -> ReadResult<Value> {
        let cancel = REQUESTS.lock().unwrap().get(&request).map(|sender| sender.subscribe())
            .ok_or_else(cancelled)?;
        if expected_account.is_null() || playlist_id.is_null() { return Err(failure("invalid_argument", "Missing playlist or account")); }
        let account = unsafe { CStr::from_ptr(expected_account) }.to_str().map_err(|_| invalid("Invalid account"))?;
        let id = unsafe { CStr::from_ptr(playlist_id) }.to_str().map_err(|_| invalid("Invalid playlist id"))?;
        let endpoint = endpoint(id, offset, limit)?;
        crate::RUNTIME.block_on(cancellable(cancel, READ_TIMEOUT, read_page(account, callback_generation, &endpoint, offset, limit)))
    })();
    let json = match result {
        Ok(page) => page,
        Err(error) => {
            // An embedded metadata 429 has no Retry-After header. Preserve an
            // existing HTTP hold; otherwise install the same 30s fallback.
            if error.code == "rate_limited" && HttpClient::rate_limit_remaining().is_zero() {
                let _ = HttpClient::record_rate_limit(Duration::from_secs(30));
            }
            json!({"error": {"code": error.code, "message": error.message}})
        }
    };
    CString::new(json.to_string()).unwrap().into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;
    use librespot_protocol::{entity_extension_data::{EntityExtensionData, EntityExtensionDataHeader},
        extended_metadata::EntityExtensionDataArray, playlist4_external::{Item, ListItems}};
    use std::sync::atomic::AtomicUsize;
    const ID: &str = "37i9dQZF1DXbIbVYph0Zr5";
    fn uri(n: u128) -> String { format!("spotify:track:{}", SpotifyId::from_raw(&n.to_be_bytes()).unwrap().to_base62()) }
    fn list(rows: &[String], offset: i32, total: i32) -> SelectedListContent {
        SelectedListContent { revision: Some(vec![1,2,3]), length: Some(total),
            contents: Some(ListItems { pos: Some(offset), truncated: Some(false),
                items: rows.iter().map(|uri| Item { uri: Some(uri.clone()), ..Default::default() }).collect(),
                ..Default::default() }).into(), ..Default::default() }
    }
    fn metadata(rows: &[String], code: i32) -> BatchedExtensionResponse {
        let data = rows.iter().map(|uri| {
            let id = SpotifyId::from_base62(uri.strip_prefix("spotify:track:").unwrap()).unwrap();
            let track = Track { gid: Some(id.to_raw().to_vec()), name: Some("Fixture song".into()),
                duration: Some(123_000), ..Default::default() };
            EntityExtensionData { entity_uri: uri.clone(),
                header: Some(EntityExtensionDataHeader { status_code: code, ..Default::default() }).into(),
                extension_data: Some(protobuf::well_known_types::any::Any {
                    value: track.write_to_bytes().unwrap(), ..Default::default()
                }).into(), ..Default::default() }
        }).collect();
        BatchedExtensionResponse { extended_metadata: vec![EntityExtensionDataArray {
            extension_kind: ExtensionKind::TRACK_V4.into(), extension_data: data, ..Default::default()
        }], ..Default::default() }
    }
    struct Fixture {
        bytes: Vec<u8>, response: BatchedExtensionResponse,
        reads: AtomicUsize, batches: AtomicUsize, checks: AtomicUsize,
        fail_check: usize, hang: bool, refuse: bool,
    }
    impl PageTransport for Fixture {
        fn check(&self) -> ReadResult<()> {
            if self.checks.fetch_add(1, Ordering::SeqCst) + 1 == self.fail_check { Err(cancelled()) } else { Ok(()) }
        }
        async fn playlist(&self, endpoint: &str) -> ReadResult<Vec<u8>> {
            assert!(endpoint.contains("&from=0&length=50"));
            self.reads.fetch_add(1, Ordering::SeqCst);
            if self.hang { std::future::pending::<()>().await; }
            if self.refuse { return Err(failure("forbidden", "fixture refusal")); }
            Ok(self.bytes.clone())
        }
        async fn metadata(&self, request: BatchedEntityRequest) -> ReadResult<BatchedExtensionResponse> {
            assert_eq!(request.entity_request.len(), 2, "duplicates and non-track rows do not multiply requests");
            self.batches.fetch_add(1, Ordering::SeqCst);
            Ok(self.response.clone())
        }
    }
    fn fixture() -> Fixture {
        let rows = vec![uri(1), "".into(), "spotify:local:artist:album:song:10".into(), uri(1), uri(2)];
        Fixture { bytes: list(&rows, 0, 5).write_to_bytes().unwrap(),
            response: metadata(&[uri(1), uri(2)], 200), reads: 0.into(), batches: 0.into(), checks: 0.into(),
            fail_check: 0, hang: false, refuse: false }
    }
    #[test]
    fn range_arguments_and_windows_are_bounded() {
        assert_eq!(endpoint(ID, 100, 50).unwrap(), format!("/playlist/v2/playlist/{ID}?decorate=revision,length,attributes,owner&from=100&length=50"));
        for (id, offset, limit) in [("bad",0,50),(ID,u32::MAX,50),(ID,0,0),(ID,0,51)] {
            assert!(endpoint(id, offset, limit).is_err());
        }
        let rows = vec![uri(1), uri(2), uri(3)];
        assert_eq!(window(&list(&rows, 0, 3), 1, 2).unwrap(), rows[1..]);
        assert!(window(&list(&rows, 3, 6), 0, 3).is_err());
        assert!(window(&list(&rows, 0, 10), 0, 50).is_err());
        assert!(window(&list(&rows, -1, 3), 0, 3).is_err());
        assert!(window(&list(&[], 0, 0), 0, 50).unwrap().is_empty());
    }
    #[test]
    fn metadata_missing_and_refused_rows_are_not_confused() {
        let asked = BTreeSet::from([uri(1), uri(2)]);
        assert!(metadata_rate_limited(&metadata(&[uri(1)], 429)));
        assert!(!metadata_rate_limited(&metadata(&[uri(1)], 403)));
        assert_eq!(answers(&asked, metadata(&[uri(1),uri(2)], 404)).unwrap().len(), 0);
        assert_eq!(answers(&asked, metadata(&[uri(1),uri(2)], 451)).unwrap().len(), 0);
        assert!(answers(&asked, metadata(&[uri(1)], 200)).is_err());
        assert!(answers(&asked, metadata(&[uri(1),uri(1),uri(2)], 200)).is_err());
        for (code, kind) in [(403,"forbidden"),(429,"rate_limited"),(500,"invalid_response")] {
            assert_eq!(answers(&asked, metadata(&[uri(1),uri(2)], code)).unwrap_err().code, kind);
        }
        let mut corrupt = metadata(&[uri(1),uri(2)], 200);
        corrupt.extended_metadata[0].extension_data[0].extension_data.as_mut().unwrap().value = vec![255];
        assert!(answers(&asked, corrupt).is_err());
        let mut wrong = metadata(&[uri(1),uri(2)], 200);
        wrong.extended_metadata[0].extension_data[0].extension_data = wrong.extended_metadata[0].extension_data[1].extension_data.clone();
        assert!(answers(&asked, wrong).is_err());
    }
    #[tokio::test]
    async fn real_decoder_and_reader_preserve_slots_and_never_replay() {
        let endpoint = endpoint(ID, 0, 50).unwrap();
        let fake = fixture();
        let page = read_with_transport(&fake, &endpoint, 0, 50).await.unwrap();
        assert_eq!(fake.reads.load(Ordering::SeqCst), 1);
        assert_eq!(fake.batches.load(Ordering::SeqCst), 1);
        assert_eq!(page["items"].as_array().unwrap().len(), 5);
        assert_eq!(page["items"][0], page["items"][3]);
        assert!(page["items"][1]["item"].is_null());
        assert!(page["items"][2]["item"].is_null());
        assert!(page["next"].is_null());
        assert_eq!(page["snapshot_id"], "010203");
        let mut fake = fixture(); fake.refuse = true;
        assert_eq!(read_with_transport(&fake, &endpoint, 0, 50).await.unwrap_err().code, "forbidden");
        assert_eq!(fake.reads.load(Ordering::SeqCst), 1);
        assert_eq!(fake.batches.load(Ordering::SeqCst), 0);
        let mut fake = fixture(); fake.fail_check = 2; // replaced after the first response
        assert_eq!(read_with_transport(&fake, &endpoint, 0, 50).await.unwrap_err().code, "cancelled");
        assert_eq!(fake.batches.load(Ordering::SeqCst), 0);
        let mut fake = fixture(); fake.fail_check = 3; // replaced while metadata arrives
        assert!(read_with_transport(&fake, &endpoint, 0, 50).await.is_err());
        assert_eq!(fake.batches.load(Ordering::SeqCst), 1);
    }
    #[tokio::test]
    async fn cancellation_and_timeout_stop_the_actual_read_future() {
        let endpoint = endpoint(ID,0,50).unwrap();
        let mut fake = fixture(); fake.hang = true;
        let (sender, cancel) = watch::channel(false);
        let read = cancellable(cancel, Duration::from_secs(2), read_with_transport(&fake, &endpoint,0,50));
        let cancel = async { tokio::time::sleep(Duration::from_millis(250)).await; sender.send_replace(true); };
        let (result, _) = tokio::join!(read, cancel);
        assert_eq!(result.unwrap_err().code, "cancelled");
        assert_eq!(fake.reads.load(Ordering::SeqCst), 1);
        assert_eq!(fake.batches.load(Ordering::SeqCst), 0);
        let (_sender, cancel) = watch::channel(false);
        let fake = Fixture { hang: true, ..fixture() };
        assert_eq!(cancellable(cancel, Duration::from_millis(200), read_with_transport(&fake, &endpoint,0,50)).await.unwrap_err().code, "timeout");
        assert_eq!(fake.batches.load(Ordering::SeqCst), 0);
        // The deadline covers a reader waiting behind another page, too.
        let _permit = READ_GATE.acquire().await.unwrap();
        let (_sender, cancel) = watch::channel(false);
        let result = cancellable(cancel, Duration::from_millis(20), read_page("offline", 0, &endpoint, 0, 50)).await;
        assert_eq!(result.unwrap_err().code, "timeout");
    }
    #[test]
    fn ffi_cancellation_before_dispatch_consumes_bounded_reservations() {
        let requests: Vec<_> = (0..MAX_PENDING).map(|_| nanyin_library_request_new()).collect();
        assert!(requests.iter().all(|id| *id != 0));
        assert_eq!(nanyin_library_request_new(), 0);
        cancel_all();
        let account = CString::new("offline").unwrap(); let id = CString::new(ID).unwrap();
        for request in requests {
            let pointer = nanyin_playlist_page(request, account.as_ptr(), 123, id.as_ptr(), 0, 50);
            let value: Value = serde_json::from_str(unsafe { CStr::from_ptr(pointer) }.to_str().unwrap()).unwrap();
            crate::nanyin_free_string(pointer);
            assert_eq!(value["error"]["code"], "cancelled");
        }
        assert!(REQUESTS.lock().unwrap().is_empty());
        assert_eq!(ReadSession::capture("offline", u64::MAX).err().unwrap().code, "unavailable");
    }
}
