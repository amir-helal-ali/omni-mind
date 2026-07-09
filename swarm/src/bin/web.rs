//! src/bin/web.rs — Web server binary for Omni-Mind.
//!
//! Run with: cargo run --bin omni-web -- --port 8080
//! Then open: http://localhost:8080

use omni_swarm::{init, web, ffi};
use std::thread;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    log::info!("Starting Omni-Mind Web Server");

    init().expect("swarm init failed");

    // Bootstrap the Zig core on a large-stack thread.
    let core_thread = thread::Builder::new()
        .name("omni-core".into())
        .stack_size(64 * 1024 * 1024)
        .spawn(|| {
            let rc = ffi::bootstrap();
            if rc != 0 {
                log::error!("Failed to bootstrap Zig core (rc={})", rc);
                return;
            }
            log::info!("Zig core bootstrapped via FFI");

            let s = ffi::stats();
            log::info!("Core: {} nodes, {} axioms, {}/{} bytes ({:.1}%)",
                s.node_count, s.axiom_count, s.bytes_used, s.bytes_budget,
                (s.bytes_used as f64 / s.bytes_budget as f64) * 100.0);
        })
        .expect("failed to spawn core thread");

    core_thread.join().ok();

    // Parse port from args.
    let args: Vec<String> = std::env::args().collect();
    let port: u16 = parse_arg(&args, "--port", 8080);

    // Start the web server (blocks forever).
    web::run(port);
}

fn parse_arg<T: std::str::FromStr>(args: &[String], flag: &str, default: T) -> T {
    for (i, a) in args.iter().enumerate() {
        if a == flag {
            if let Some(val) = args.get(i + 1) {
                if let Ok(v) = val.parse::<T>() {
                    return v;
                }
            }
        }
    }
    default
}
