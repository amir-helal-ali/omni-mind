#!/usr/bin/env bash
# scripts/install_and_build.sh — Install Zig 0.13.0 and build/test omni-mind
#
# This script handles the full installation and verification process.
# Run with: bash scripts/install_and_build.sh
#
# If the download fails (slow network), the script will retry with
# resume capability until the file is complete.

set -e

ZIG_VERSION="0.13.0"
ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
ZIG_TAR="/tmp/zig-${ZIG_VERSION}.tar.xz"
ZIG_DIR="${HOME}/zig-${ZIG_VERSION}"
ZIG_BIN="${ZIG_DIR}/zig"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)/omni-mind"

echo "═══════════════════════════════════════════════════════════════════════"
echo "  Project Omni-Mind — Installation & Build Script"
echo "  Zig version: ${ZIG_VERSION}"
echo "  Project dir: ${PROJECT_DIR}"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

# ─── Step 1: Check if Zig is already installed ─────────────────────────
if command -v zig >/dev/null 2>&1; then
    EXISTING_VER=$(zig version 2>/dev/null || echo "unknown")
    echo "✓ Zig already installed: $(which zig) (version: ${EXISTING_VER})"
    if [[ "${EXISTING_VER}" == "${ZIG_VERSION}" ]]; then
        ZIG_BIN=$(which zig)
        echo "  Using existing Zig ${ZIG_VERSION}"
    else
        echo "  ⚠ Version mismatch. Will install ${ZIG_VERSION} locally."
    fi
fi

# ─── Step 2: Download Zig (with retry/resume) ──────────────────────────
if [[ ! -x "${ZIG_BIN}" ]]; then
    echo ""
    echo "─── Step 2: Downloading Zig ${ZIG_VERSION} ───"
    echo "URL: ${ZIG_URL}"
    echo "Target: ${ZIG_TAR}"

    # Remove partial if exists and is corrupt
    if [[ -f "${ZIG_TAR}" ]]; then
        EXISTING_SIZE=$(stat -c%s "${ZIG_TAR}" 2>/dev/null || echo 0)
        EXPECTED_SIZE=47082308
        if [[ "${EXISTING_SIZE}" -lt "${EXPECTED_SIZE}" ]]; then
            echo "Existing partial: ${EXISTING_SIZE} / ${EXPECTED_SIZE} bytes — resuming..."
        fi
    fi

    # Try download with up to 5 retries, resuming each time
    MAX_RETRIES=5
    for i in $(seq 1 ${MAX_RETRIES}); do
        echo "Attempt ${i}/${MAX_RETRIES}..."
        if curl -L -C - --max-time 1800 --retry 3 --retry-delay 5 \
                -o "${ZIG_TAR}" "${ZIG_URL}"; then
            ACTUAL_SIZE=$(stat -c%s "${ZIG_TAR}" 2>/dev/null || echo 0)
            if [[ "${ACTUAL_SIZE}" -ge 47082308 ]]; then
                echo "✓ Download complete: ${ACTUAL_SIZE} bytes"
                break
            else
                echo "  Partial download: ${ACTUAL_SIZE} / 47082308 — will retry"
            fi
        else
            echo "  curl exit code: $?"
        fi
        if [[ "${i}" -lt "${MAX_RETRIES}" ]]; then
            echo "  Waiting 10s before retry..."
            sleep 10
        fi
    done

    # Verify download
    ACTUAL_SIZE=$(stat -c%s "${ZIG_TAR}" 2>/dev/null || echo 0)
    if [[ "${ACTUAL_SIZE}" -lt 47082308 ]]; then
        echo ""
        echo "✗ Download incomplete: ${ACTUAL_SIZE} / 47082308 bytes"
        echo "  The ziglang.org server is heavily rate-limited (~25KB/s)."
        echo "  Try downloading from a different network, or use a VPN."
        echo "  Alternative: try the official binary from a mirror."
        exit 1
    fi

    # ─── Step 3: Extract Zig ───────────────────────────────────────────
    echo ""
    echo "─── Step 3: Extracting Zig ───"
    mkdir -p "${ZIG_DIR}"
    tar -xf "${ZIG_TAR}" -C "${HOME}" --strip-components=1
    # Actually let's extract to the versioned directory
    rm -rf "${ZIG_DIR}"
    tar -xf "${ZIG_TAR}" -C "${HOME}"
    ZIG_BIN="${HOME}/zig-linux-x86_64-${ZIG_VERSION}/zig"
    if [[ ! -x "${ZIG_BIN}" ]]; then
        echo "✗ Zig binary not found at ${ZIG_BIN}"
        ls -la "${HOME}/zig-linux-x86_64-${ZIG_VERSION}/" 2>/dev/null
        exit 1
    fi
    echo "✓ Zig extracted to: ${ZIG_BIN}"
    echo "  Version: $(${ZIG_BIN} version)"
fi

# ─── Step 4: Build the project ─────────────────────────────────────────
echo ""
echo "─── Step 4: Building omni-mind ───"
cd "${PROJECT_DIR}"
echo "Running: ${ZIG_BIN} build"
"${ZIG_BIN}" build 2>&1 | tail -20
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "✗ Build failed"
    exit 1
fi
echo "✓ Build succeeded"
echo "  Artifacts in: ${PROJECT_DIR}/zig-out/bin/"

# ─── Step 5: Run unit tests ────────────────────────────────────────────
echo ""
echo "─── Step 5: Running unit tests ───"
"${ZIG_BIN}" build test 2>&1 | tail -30
TEST_STATUS=${PIPESTATUS[0]}
if [[ ${TEST_STATUS} -eq 0 ]]; then
    echo "✓ All unit tests passed"
else
    echo "✗ Some tests failed (exit ${TEST_STATUS})"
    echo "  Continuing to benchmark anyway..."
fi

# ─── Step 6: Run the 1000-question benchmark (native Zig) ─────────────
echo ""
echo "─── Step 6: Native Zig verification (1000 questions) ───"
echo "Running: ${ZIG_BIN} build verify"
"${ZIG_BIN}" build verify 2>&1 | tail -50
VERIFY_STATUS=${PIPESTATUS[0]}

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
if [[ ${VERIFY_STATUS} -eq 0 ]]; then
    echo "  ✓ NATIVE ZIG VERIFICATION PASSED"
    echo ""
    echo "  Expected: 1000/1000 questions passed (100%)"
    echo "  This uses the REAL Zig code paths (not Python simulator)."
else
    echo "  ⚠ Verification reported issues. Check the output above."
fi
echo "═══════════════════════════════════════════════════════════════════════"

# ─── Step 7: Also run the legacy bench for performance comparison ──────
echo ""
echo "─── Step 7: Performance benchmark ───"
"${ZIG_BIN}" build bench 2>&1 | tail -30
BENCH_STATUS=${PIPESTATUS[0]}

# ─── Step 8: Run the REPL ──────────────────────────────────────────────
echo ""
echo "─── Step 8: Interactive REPL ready ───"
echo "To start an interactive session:"
echo "  ${ZIG_BIN} run ${PROJECT_DIR}/src/main.zig"
echo ""
echo "Or run the TCP server:"
echo "  ${PROJECT_DIR}/zig-out/bin/omni-mind"
echo ""
echo "Or query via TCP:"
echo "  echo 'QUERY:0:what is energy?' | nc localhost 19090"
