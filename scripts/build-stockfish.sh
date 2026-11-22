#!/usr/bin/env bash
#
# Builds Stockfish as a static library for iOS (device + simulator).
#
#   ./scripts/build-stockfish.sh            # real build, fails if Stockfish fails
#   ALLOW_STUB=1 ./scripts/build-stockfish.sh   # fall back to a stub library
#
# Output:
#   Build/Stockfish/iphoneos/libstockfish.a
#   Build/Stockfish/iphonesimulator/libstockfish.a
#
# The app links the library through OTHER_LDFLAGS (-lstockfish) and drives the
# engine over the in-process UCI bridge in
# ChessEnginePro/Core/Engine/Bridge/StockfishBridge.mm.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SF_VERSION="${STOCKFISH_VERSION:-17.1}"
SRC_PARENT="$ROOT/Vendor/Stockfish"
SRC="$SRC_PARENT/src"
OUT="$ROOT/Build/Stockfish"
ALLOW_STUB="${ALLOW_STUB:-0}"
MIN_IOS="17.0"
SIM_ARCHS="${SIM_ARCHS:-arm64}"

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "Dieses Skript benötigt macOS mit Xcode."
    exit 1
fi

mkdir -p "$OUT"

# ---------------------------------------------------------------- stub fallback

build_stub() {
    log "Baue Stub-Engine (Stockfish nicht verfügbar)"
    local sdk device_sim
    device_sim="$(xcrun --sdk iphonesimulator --show-sdk-path)"
    sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
    mkdir -p "$OUT/iphoneos" "$OUT/iphonesimulator"

    xcrun --sdk iphoneos clang++ -std=c++17 -O2 -c \
        -target "arm64-apple-ios$MIN_IOS" -isysroot "$sdk" \
        "$ROOT/ChessEnginePro/Core/Engine/Bridge/StockfishStub.cpp" \
        -o "$OUT/iphoneos/StockfishStub.o"
    libtool -static -o "$OUT/iphoneos/libstockfish.a" "$OUT/iphoneos/StockfishStub.o"

    xcrun --sdk iphonesimulator clang++ -std=c++17 -O2 -c \
        -target "arm64-apple-ios$MIN_IOS-simulator" -isysroot "$device_sim" \
        "$ROOT/ChessEnginePro/Core/Engine/Bridge/StockfishStub.cpp" \
        -o "$OUT/iphonesimulator/StockfishStub.o"
    libtool -static -o "$OUT/iphonesimulator/libstockfish.a" "$OUT/iphonesimulator/StockfishStub.o"

    log "Stub-Engine erstellt – die App nutzt die eingebaute Swift-Engine."
}

# ---------------------------------------------------------------- sources

fetch_sources() {
    local need_src=0 need_scripts=0
    [[ -d "$SRC" ]] || need_src=1
    [[ -f "$SRC_PARENT/scripts/net.sh" ]] || need_scripts=1

    if [[ $need_src -eq 0 && $need_scripts -eq 0 ]]; then
        log "Stockfish-Quellen vorhanden ($SF_VERSION)"
        return 0
    fi

    log "Lade Stockfish $SF_VERSION herunter"
    mkdir -p "$SRC_PARENT"
    local tarball="$SRC_PARENT/stockfish-$SF_VERSION.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        curl -fsSL --retry 3 -o "$tarball" \
            "https://github.com/official-stockfish/Stockfish/archive/refs/tags/sf_$SF_VERSION.tar.gz"
    fi
    rm -rf "$SRC_PARENT/tmp"
    mkdir -p "$SRC_PARENT/tmp"
    tar -xzf "$tarball" -C "$SRC_PARENT/tmp"
    local extracted
    extracted="$(find "$SRC_PARENT/tmp" -maxdepth 1 -type d -name 'Stockfish-*' | head -1)"
    if [[ -z "$extracted" ]]; then
        fail "Archiv konnte nicht entpackt werden."
        rm -rf "$SRC_PARENT/tmp"
        return 1
    fi

    if [[ $need_src -eq 1 ]]; then
        mv "$extracted/src" "$SRC"

        # Stockfish's main() must be callable from the bridge: rename the symbol.
        # The UCI loop returns normally on "quit" (it never calls exit()).
        /usr/bin/sed -i '' \
            's/^int main(int argc, char\* argv\[\])/int stockfish_main(int argc, char* argv[])/' \
            "$SRC/main.cpp"
        if ! grep -q "int stockfish_main" "$SRC/main.cpp"; then
            fail "main.cpp konnte nicht angepasst werden."
            rm -rf "$SRC_PARENT/tmp"
            return 1
        fi
    fi

    # The makefile calls ../scripts/net.sh to fetch the NNUE networks.
    if [[ $need_scripts -eq 1 && -d "$extracted/scripts" ]]; then
        rm -rf "$SRC_PARENT/scripts"
        mv "$extracted/scripts" "$SRC_PARENT/scripts"
    fi
    rm -rf "$SRC_PARENT/tmp"
}

# ---------------------------------------------------------------- slices

build_slice() {
    local platform="$1"     # iphoneos | iphonesimulator
    local triple="$2"       # arm64-apple-ios17.0[-simulator]
    local arch="$3"
    local sdk

    if [[ "$platform" == "iphoneos" ]]; then
        sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
    else
        sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
    fi

    log "Kompiliere Stockfish für $platform ($arch)"
    make -C "$SRC" -j"$(sysctl -n hw.ncpu)" analyze \
        ARCH=armv8 \
        COMP=clang \
        KERNEL=IOS \
        optimize=no \
        EXTRACXXFLAGS="-O3 -funroll-loops -DNDEBUG -target $triple -isysroot $sdk -fPIC"

    local objects
    objects="$(find "$SRC" -name '*.o' | sort)"
    if [[ -z "$objects" ]]; then
        fail "Keine Objektdateien erzeugt."
        return 1
    fi

    mkdir -p "$OUT/$platform"
    # shellcheck disable=SC2086
    libtool -static -o "$OUT/$platform/libstockfish.a" $objects
    xcrun strip -x "$OUT/$platform/libstockfish.a" 2>/dev/null || true

    if ! nm -g "$OUT/$platform/libstockfish.a" 2>/dev/null | grep -q "stockfish_main"; then
        fail "stockfish_main fehlt in der Bibliothek."
        return 1
    fi

    make -C "$SRC" objclean >/dev/null 2>&1 || true
}

build_real() {
    fetch_sources
    build_slice "iphoneos" "arm64-apple-ios$MIN_IOS" "arm64"

    local sim_libs=()
    for arch in $SIM_ARCHS; do
        build_slice "iphonesimulator-$arch" "$arch-apple-ios$MIN_IOS-simulator" "$arch"
        sim_libs+=("$OUT/iphonesimulator-$arch/libstockfish.a")
    done

    mkdir -p "$OUT/iphonesimulator"
    lipo -create "${sim_libs[@]}" -output "$OUT/iphonesimulator/libstockfish.a"
    rm -rf "$OUT"/iphonesimulator-*
}

if [[ -f "$OUT/iphoneos/libstockfish.a" && -f "$OUT/iphonesimulator/libstockfish.a" ]]; then
    log "Stockfish-Bibliotheken bereits gebaut"
    nm -g "$OUT/iphoneos/libstockfish.a" | grep -q "stockfish_main" \
        && exit 0 \
        || log "Vorhandene Bibliothek ist ein Stub – baue neu"
fi

if build_real; then
    log "Fertig: $OUT"
    exit 0
fi

if [[ "$ALLOW_STUB" == "1" ]]; then
    build_stub
    exit 0
fi

fail "Stockfish konnte nicht gebaut werden. Siehe Log oben."
exit 1
