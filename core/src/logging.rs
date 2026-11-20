//! The core's log: stderr (seen when the app runs from a terminal) and,
//! when the app gives a path, a size-capped file that survives a Finder
//! launch, where stderr goes nowhere.

use std::{
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

/// A file grows to this size before it is moved to `<name>.1`, replacing
/// the previous one: at most twice this on disk.
const LIMIT: u64 = 5 << 20;

const DEFAULT_FILTER: &str = "warn,librespot=info,nanyin_core=info";

/// Starts logging once per process; later calls do nothing. `RUST_LOG`
/// overrides the default filter.
pub fn init(path: Option<PathBuf>) {
    let file = path.and_then(|path| match RotatingFile::open(path) {
        Ok(file) => Some(Arc::new(Mutex::new(file))),
        Err(error) => {
            eprintln!("nanyin core: no log file: {error}");
            None
        }
    });
    let started =
        env_logger::Builder::from_env(env_logger::Env::default().default_filter_or(DEFAULT_FILTER))
            .target(env_logger::Target::Pipe(Box::new(Tee { file })))
            .try_init()
            .is_ok();
    if started {
        log_panics();
        log::info!("nanyin core {} started", env!("CARGO_PKG_VERSION"));
    }
}

/// A panic otherwise reaches only stderr, and a panicked player thread
/// leaves playback silent with no other trace.
fn log_panics() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let thread = std::thread::current();
        log::error!(
            "panic on thread {}: {info}\n{}",
            thread.name().unwrap_or("unnamed"),
            std::backtrace::Backtrace::force_capture()
        );
        previous(info);
    }));
}

/// Writes each record to stderr and to the file, if there is one.
struct Tee {
    file: Option<Arc<Mutex<RotatingFile>>>,
}

impl Write for Tee {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let _ = io::stderr().write_all(buf);
        if let Some(file) = &self.file {
            let mut file = file.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            // A full disk or a removed file must never stop playback.
            let _ = file.write_all(buf);
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        if let Some(file) = &self.file {
            let mut file = file.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            let _ = file.flush();
        }
        Ok(())
    }
}

/// Appends to `path`, moving it to `<path>.1` once it reaches `limit`.
/// env_logger writes one whole record per call, so records are never split.
struct RotatingFile {
    path: PathBuf,
    file: File,
    size: u64,
    limit: u64,
}

impl RotatingFile {
    fn open(path: PathBuf) -> io::Result<Self> {
        Self::open_with_limit(path, LIMIT)
    }

    fn open_with_limit(path: PathBuf, limit: u64) -> io::Result<Self> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        let file = append(&path)?;
        let size = file.metadata()?.len();
        Ok(Self {
            path,
            file,
            size,
            limit,
        })
    }

    fn rotate(&mut self) -> io::Result<()> {
        let mut old = self.path.clone().into_os_string();
        old.push(".1");
        fs::rename(&self.path, old)?;
        self.file = append(&self.path)?;
        self.size = 0;
        Ok(())
    }
}

impl Write for RotatingFile {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        if self.size > 0 && self.size + buf.len() as u64 > self.limit {
            self.rotate()?;
        }
        let written = self.file.write(buf)?;
        self.size += written as u64;
        Ok(written)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}

fn append(path: &Path) -> io::Result<File> {
    OpenOptions::new().create(true).append(true).open(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rotates_at_the_limit_and_keeps_one_old_file() {
        let dir = std::env::temp_dir().join(format!("nanyin-log-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let path = dir.join("logs/core.log");
        let mut file = RotatingFile::open_with_limit(path.clone(), 10).unwrap();
        file.write_all(b"first\n").unwrap();
        file.write_all(b"second\n").unwrap();
        file.write_all(b"third\n").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "third\n");
        assert_eq!(
            fs::read_to_string(dir.join("logs/core.log.1")).unwrap(),
            "second\n"
        );

        // A new launch appends to what is there.
        let mut file = RotatingFile::open_with_limit(path.clone(), 100).unwrap();
        file.write_all(b"again\n").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "third\nagain\n");
        fs::remove_dir_all(&dir).unwrap();
    }
}
