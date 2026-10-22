
#[cfg(test)]
mod nanyin_tests {
    use librespot_core::http_client::HttpClient;
    use bytes::Bytes;
    use futures_util::StreamExt;
    use http::{HeaderMap, Request};
    use std::time::{Duration, Instant};

    #[test]
    fn nanyin_retry_after_preserves_long_and_extreme_delays() {
        let mut headers = HeaderMap::new();
        for (header, seconds) in [("86400", 86400), ("-1", 1), ("0", 1)] {
            headers.insert("Retry-After", header.parse().unwrap());
            assert_eq!(HttpClient::get_retry_after(&headers).unwrap().as_secs(), seconds);
        }
        headers.insert("Retry-After", i64::MAX.to_string().parse().unwrap());
        assert!(HttpClient::get_retry_after(&headers).unwrap().as_secs() > 86400);
        headers.insert("Retry-After", u64::MAX.to_string().parse().unwrap());
        assert_eq!(HttpClient::get_retry_after(&headers).unwrap().as_secs(), u64::MAX);
        headers.insert("Retry-After", "Thu, 01 Jan 2099 00:00:00 GMT".parse().unwrap());
        assert!(HttpClient::get_retry_after(&headers).unwrap().as_secs() > 86400);
        headers.insert("X-RateLimit-Next", "invalid".parse().unwrap());
        headers.insert("Retry-After", "86400".parse().unwrap());
        assert_eq!(HttpClient::get_retry_after(&headers).unwrap().as_secs(), 86400);
        headers.insert("X-RateLimit-Next", "2000-01-01T00:00:00Z".parse().unwrap());
        assert_eq!(HttpClient::get_retry_after(&headers).unwrap().as_secs(), 86400);
        headers.remove("X-RateLimit-Next");
        headers.insert("Retry-After", "invalid".parse().unwrap());
        assert!(HttpClient::get_retry_after(&headers).is_none());
    }

    #[tokio::test]
    async fn nanyin_http_failures_are_not_replayed_and_429_blocks_new_clients() {
        use std::{io::{Read, Write}, net::TcpListener, sync::atomic::{AtomicUsize, Ordering}};
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let calls = std::sync::Arc::new(AtomicUsize::new(0));
        let server_calls = calls.clone();
        let server = std::thread::spawn(move || {
            for status in [500, 200, 206, 429] {
                let (mut socket, _) = listener.accept().unwrap();
                socket.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
                let mut data = [0; 4096];
                socket.read(&mut data).unwrap();
                server_calls.fetch_add(1, Ordering::SeqCst);
                if status == 200 || status == 206 {
                    // Headers arrive normally, but the body never completes.
                    write!(socket, "HTTP/1.1 {status} OK\r\nContent-Length: 2\r\n\r\nx").unwrap();
                    std::thread::sleep(librespot_core::http_client::REQUEST_TIMEOUT + Duration::from_secs(1));
                    continue;
                }
                write!(socket, "HTTP/1.1 {status} Test\r\nContent-Length: 0\r\nRetry-After: 86400\r\nConnection: close\r\n\r\n").unwrap();
            }
        });
        let request = || Request::builder().method("PUT")
            .uri(format!("http://{address}/connect-state"))
            .body(Bytes::from_static(b"offline fixture")).unwrap();
        let client = HttpClient::new(None);
        assert!(client.request_body(request()).await.is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        let started = Instant::now();
        let error = client.request_body(request()).await.unwrap_err();
        assert_eq!(error.kind, librespot_core::error::ErrorKind::DeadlineExceeded);
        assert!(started.elapsed() < Duration::from_secs(16));
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        let mut progressing = client.request_stream(request()).unwrap();
        let body = progressing.next().await.unwrap().unwrap().into_body();
        let error = HttpClient::collect_stream_body(body).await.unwrap_err();
        assert_eq!(error.kind, librespot_core::error::ErrorKind::DeadlineExceeded);
        assert_eq!(calls.load(Ordering::SeqCst), 3);
        let saved = std::env::temp_dir().join(format!("nanyin-cooldown-test-{}", std::process::id()));
        let _ = std::fs::remove_file(&saved);
        extern "C" fn persist(seconds: u64) -> i32 {
            let path = std::env::temp_dir().join(format!("nanyin-cooldown-test-{}", std::process::id()));
            if std::fs::write(path, seconds.to_string()).is_ok() { 0 } else { -1 }
        }
        crate::nanyin_register_rate_limit_callback(persist);
        let mut queued_before_cooldown = client.request_stream(request()).unwrap();
        let mut cdn = client.request_stream(request()).unwrap();
        assert!(cdn.next().await.unwrap().is_err());
        assert_eq!(std::fs::read_to_string(&saved).unwrap(), "86400", "429 must be persisted before returning to the caller");
        std::fs::remove_file(saved).unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 4);
        assert!(HttpClient::rate_limit_remaining().as_secs() >= 86398);
        let queued_error = queued_before_cooldown.next().await.unwrap().unwrap_err();
        assert_eq!(queued_error.kind, librespot_core::error::ErrorKind::ResourceExhausted,
            "a previously constructed CDN request must recheck cooldown when polled");
        // No fifth connection can be made, including through the stream path.
        let replacement = HttpClient::new(None);
        assert!(replacement.request_body(request()).await.is_err());
        assert!(replacement.request_stream(request()).is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 4);
        server.join().unwrap();
        // A protocol-level 429 inside HTTP 200 uses exactly the same gate and
        // synchronous persistence, including when it extends an HTTP hold.
        HttpClient::record_rate_limit(Duration::from_secs(172800)).unwrap();
        let saved = std::env::temp_dir().join(format!("nanyin-cooldown-test-{}", std::process::id()));
        assert_eq!(std::fs::read_to_string(&saved).unwrap(), "172800");
        assert!(HttpClient::rate_limit_remaining().as_secs() >= 172799);
        assert!(replacement.request_body(request()).await.is_err());
        std::fs::remove_file(saved).unwrap();
    }
}
