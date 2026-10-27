//! Shared test helpers: fixture loading and a tiny HTTP/1.1 mock server.
#![allow(dead_code)]

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;

/// `../spec/<rel>` relative to the crate root. Tests only: the published
/// crate never reads these files.
pub fn spec_path(rel: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../spec")
        .join(rel)
}

pub fn fixture(name: &str) -> String {
    std::fs::read_to_string(spec_path(&format!("fixtures/{name}")))
        .unwrap_or_else(|e| panic!("fixture {name}: {e}"))
}

pub fn golden(name: &str) -> String {
    std::fs::read_to_string(spec_path(&format!("golden/{name}")))
        .unwrap_or_else(|e| panic!("golden {name}: {e}"))
}

/// A canned HTTP response.
#[derive(Clone, Debug)]
pub struct Reply {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: String,
}

impl Reply {
    pub fn json(status: u16, body: impl Into<String>) -> Self {
        Reply {
            status,
            headers: vec![("Content-Type".into(), "application/json".into())],
            body: body.into(),
        }
    }

    pub fn ok(body: impl Into<String>) -> Self {
        Reply::json(200, body)
    }

    pub fn header(mut self, k: &str, v: &str) -> Self {
        self.headers.push((k.into(), v.into()));
        self
    }
}

/// A request the mock server received.
#[derive(Clone, Debug)]
pub struct Seen {
    /// Path and query, e.g. `/v1/properties?page=1`.
    pub target: String,
    /// Header names lower-cased.
    pub headers: Vec<(String, String)>,
}

impl Seen {
    pub fn path(&self) -> &str {
        self.target.split('?').next().unwrap()
    }

    pub fn query(&self, key: &str) -> Option<String> {
        let q = self.target.split_once('?')?.1;
        q.split('&').find_map(|kv| {
            let (k, v) = kv.split_once('=').unwrap_or((kv, ""));
            (k == key).then(|| v.replace("%2C", ",").replace('+', " "))
        })
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
    }
}

/// Serves `replies` in order, one per request, then answers 599 to anything
/// else. Each connection is closed after one response.
pub struct MockServer {
    pub url: String,
    seen: Arc<Mutex<Vec<Seen>>>,
}

impl MockServer {
    pub fn start(replies: Vec<Reply>) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let url = format!("http://{}", listener.local_addr().unwrap());
        let seen = Arc::new(Mutex::new(Vec::new()));
        let seen2 = Arc::clone(&seen);
        thread::spawn(move || {
            let mut queue = replies.into_iter();
            for stream in listener.incoming() {
                let Ok(stream) = stream else { continue };
                let Some(req) = read_request(&stream) else {
                    continue;
                };
                seen2.lock().unwrap().push(req);
                let reply = queue.next().unwrap_or_else(|| {
                    Reply::json(
                        599,
                        r#"{"title":"Unexpected request","status":599,"code":"UNEXPECTED_REQUEST"}"#,
                    )
                });
                write_reply(stream, &reply);
            }
        });
        MockServer { url, seen }
    }

    pub fn requests(&self) -> Vec<Seen> {
        self.seen.lock().unwrap().clone()
    }
}

fn read_request(stream: &TcpStream) -> Option<Seen> {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).ok()?;
    let target = line.split_whitespace().nth(1)?.to_string();
    let mut headers = Vec::new();
    loop {
        let mut h = String::new();
        if reader.read_line(&mut h).ok()? == 0 {
            break;
        }
        let h = h.trim_end();
        if h.is_empty() {
            break;
        }
        if let Some((k, v)) = h.split_once(':') {
            headers.push((k.trim().to_ascii_lowercase(), v.trim().to_string()));
        }
    }
    Some(Seen { target, headers })
}

fn write_reply(mut stream: TcpStream, r: &Reply) {
    let mut head = format!("HTTP/1.1 {} Mock\r\n", r.status);
    for (k, v) in &r.headers {
        head.push_str(&format!("{k}: {v}\r\n"));
    }
    head.push_str(&format!(
        "Content-Length: {}\r\nConnection: close\r\n\r\n",
        r.body.len()
    ));
    let _ = stream.write_all(head.as_bytes());
    let _ = stream.write_all(r.body.as_bytes());
    let _ = stream.flush();
}

/// A `/v1/properties` page with `n` copies of the first Berlin card.
pub fn spaces_page(page: u64, n: usize, page_count: u64, seed: u64) -> String {
    let base: serde_json::Value = serde_json::from_str(&fixture("properties_berlin.json")).unwrap();
    let card = base["data"][0].clone();
    let data: Vec<_> = (0..n)
        .map(|i| {
            let mut c = card.clone();
            c["slug"] = format!("space-p{page}-{i}").into();
            c
        })
        .collect();
    let mut meta = base["meta"].clone();
    meta["pagination"] = serde_json::json!({
        "page": page, "pageSize": 50, "total": page_count * 50, "pageCount": page_count
    });
    meta["seed"] = seed.into();
    serde_json::json!({ "data": data, "meta": meta }).to_string()
}
