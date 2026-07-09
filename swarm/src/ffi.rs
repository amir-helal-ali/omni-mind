//! src/ffi.rs — FFI bindings to the Zig core.
//!
//! The Zig core is compiled as a static library (libomni_core.a)
//! and linked into this Rust crate via build.rs. We declare the C ABI here.

#[allow(unused_doc_comments)]
extern "C" {
    fn omni_query(query_ptr: *const u8, out_buf: *mut u8, out_len: u32) -> i32;
    fn omni_inject_axiom(domain: u8, axiom_ptr: *const u8, confidence: f32) -> i32;
    fn omni_stats() -> CoreStats;
    fn omni_bootstrap() -> i32;
    fn omni_shutdown() -> i32;
}

#[repr(C)]
pub struct CoreStats {
    pub bytes_used: usize,
    pub bytes_budget: usize,
    pub node_count: usize,
    pub edge_count: usize,
    pub axiom_count: usize,
}

/// Bootstrap the Zig core.
pub fn bootstrap() -> i32 {
    unsafe { omni_bootstrap() }
}

/// Shutdown the Zig core.
pub fn shutdown() -> i32 {
    unsafe { omni_shutdown() }
}

/// Safe wrapper around omni_query.
pub fn safe_query(q: &str) -> Result<String, i32> {
    let mut buf = [0u8; 8192];
    let q_nul = format!("{}\0", q);
    let n = unsafe {
        omni_query(q_nul.as_ptr(), buf.as_mut_ptr(), buf.len() as u32)
    };
    if n < 0 {
        return Err(n);
    }
    Ok(String::from_utf8_lossy(&buf[..n as usize]).into_owned())
}

/// Safe wrapper around omni_inject_axiom.
pub fn safe_inject_axiom(domain: u8, text: &str, confidence: f32) -> Result<(), i32> {
    let text_nul = format!("{}\0", text);
    let rc = unsafe {
        omni_inject_axiom(domain, text_nul.as_ptr(), confidence)
    };
    if rc < 0 {
        return Err(rc);
    }
    Ok(())
}

/// Get current core stats.
pub fn stats() -> CoreStats {
    // If the lib isn't linked, return zeros (avoids undefined behavior).
    unsafe {
        // Test if the symbol exists by calling; if not linked, this would
        // have failed at link time, so we can call directly.
        omni_stats()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stats_struct_is_correct_size() {
        // 5 usize fields on x86_64 = 40 bytes
        assert_eq!(std::mem::size_of::<CoreStats>(), 40);
    }
}
