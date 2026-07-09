// swarm/build.rs — Build script.
// Links the Zig static library (libomni_core.a) into the Rust swarm crate.
//
// This requires the Zig core to be built first: `zig build` in the project root.

use std::path::PathBuf;

fn main() {
    // Locate libomni_core.a relative to this Cargo.toml.
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let lib_dir = manifest_dir.join("../zig-out/lib");
    let lib_path = lib_dir.join("libomni_core.a");

    if !lib_path.exists() {
        println!("cargo:warning=libomni_core.a not found at {}. Run 'zig build' in the project root first.", lib_path.display());
        println!("cargo:warning=FFI calls will fail to link. Building swarm without Zig core linkage.");
        return;
    }

    // Tell cargo to link the static lib.
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=omni_core");
    println!("cargo:rustc-link-lib=dylib=c");

    // Re-run if the lib changes.
    println!("cargo:rerun-if-changed={}", lib_path.display());
    println!("cargo:rerun-if-changed=../build.zig");
}
