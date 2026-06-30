#!/bin/bash
# 建置 whisper.cpp 為 macOS arm64 靜態庫（Metal embedded），供 WhisperCppEngine 連結。
# 產物落在 vendor/whisper/{lib,include}（已 gitignore）。Phase 4 整合成本的一部分。
set -euo pipefail

WHISPER_TAG="v1.9.1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
SRC="$VENDOR/whisper.cpp"
OUT="$VENDOR/whisper"

mkdir -p "$VENDOR"
if [ ! -d "$SRC" ]; then
    echo "• Cloning whisper.cpp $WHISPER_TAG"
    git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp "$SRC"
fi

echo "• Configuring (Metal embedded, static, arm64)"
cmake -S "$SRC" -B "$SRC/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_BLAS=ON \
    -DGGML_NATIVE=ON \
    -DGGML_OPENMP=OFF

echo "• Building"
cmake --build "$SRC/build" --config Release -j"$(sysctl -n hw.ncpu)"

echo "• Collecting libs + headers into $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/lib" "$OUT/include"
find "$SRC/build" -name 'lib*.a' -exec cp {} "$OUT/lib/" \;
cp "$SRC/include/whisper.h" "$OUT/include/"
cp "$SRC/ggml/include/"*.h "$OUT/include/" 2>/dev/null || true

echo "• Done. Libs:"
ls -1 "$OUT/lib"
