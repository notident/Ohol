#!/bin/bash
# Builds OneLife (client + built-in single-player server) for the browser.
#
# No Asyncify.  The two blocking loops were refactored into per-frame steps:
#   - client: ScreenGL::frameStep() driven by emscripten_set_main_loop
#   - server: serverStep() called from the client's frame
# Client and server talk through in-memory sockets, so no threads, no
# SharedArrayBuffer and no special HTTP headers are needed.
#
# Layout (the workflow creates it):  $WORK/OneLife  $WORK/minorGems  $WORK/OneLifeData7

set -euo pipefail

WORK="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="$WORK/OneLife"
MG="$WORK/minorGems"
DATA="$WORK/OneLifeData7"
SITE="$REPO/wasm/site"
OBJ="$REPO/wasm/obj"
LOGDIR="$REPO/wasm/logs"

command -v em++ >/dev/null || { echo "em++ not found: activate emsdk first"; exit 1; }
mkdir -p "$OBJ" "$SITE" "$LOGDIR"

# 1. which files to build
python3 "$REPO/wasm/gen_sources.py" "$WORK" > "$LOGDIR/sources.txt"
echo "$(wc -l < "$LOGDIR/sources.txt") source files"

# 2. compile each file (parallel).  -DONELIFE_EMBEDDED_SERVER drops the
#    server's own main() and its headless stubs; client versions are used.
FLAGS="-O2 -fexceptions -DLINUX -DONELIFE_EMBEDDED_SERVER -I$WORK -w"

# client/ and server/ both have fitnessScore.cpp and lifeTokens.cpp with the
# same function names.  Rename the server's so both can live in one binary.
SERVER_RENAME="-DinitFitnessScore=svInitFitnessScore -DfreeFitnessScore=svFreeFitnessScore -DinitLifeTokens=svInitLifeTokens -DfreeLifeTokens=svFreeLifeTokens"

compile_one() {
    src="$1"
    extra=""
    case "$src" in
        "$REPO"/server/*) extra="$SERVER_RENAME" ;;
    esac
    name=$(echo "$src" | md5sum | cut -c1-12)_$(basename "$src" .cpp)
    if ! em++ $FLAGS $extra -c "$src" -o "$OBJ/$name.o" 2> "$LOGDIR/$name.err"; then
        echo "FAILED: $src" >> "$LOGDIR/failed.txt"
        sed 's/^/    /' "$LOGDIR/$name.err" | head -25 >> "$LOGDIR/failed.txt"
        return 1
    fi
}
export -f compile_one
export FLAGS OBJ LOGDIR SERVER_RENAME REPO

rm -f "$LOGDIR/failed.txt"
xargs -P "$(nproc)" -I{} bash -c 'compile_one {}' < "$LOGDIR/sources.txt" || true

if [ -f "$LOGDIR/failed.txt" ]; then
    echo "==== compile errors ===="
    cat "$LOGDIR/failed.txt"
    exit 1
fi

# 3. game data and settings go into the browser's virtual file system
PRELOAD=()
for d in "$DATA"/*/; do
    name=$(basename "$d")
    [ "$name" = ".git" ] && continue
    PRELOAD+=(--preload-file "$d@/$name")
done
PRELOAD+=(--preload-file "$REPO/gameSource/graphics@/graphics")

# settings: server defaults first, then the single-player overrides
SET="$REPO/wasm/settings_merged"
rm -rf "$SET"; mkdir -p "$SET"
cp -r "$REPO/server/settings/." "$SET/" 2>/dev/null || true
cp -r "$REPO/gameSource/settings/." "$SET/" 2>/dev/null || true
cp -r "$REPO/wasm/settings_overrides/." "$SET/"
PRELOAD+=(--preload-file "$SET@/settings")
for f in dataVersionNumber.txt; do
    [ -f "$DATA/$f" ] && PRELOAD+=(--preload-file "$DATA/$f@/$f")
done
for f in curseWordList.txt; do
    [ -f "$REPO/server/$f" ] && PRELOAD+=(--preload-file "$REPO/server/$f@/$f")
done
for f in language.txt liveTriggers.txt eqImpulseResponse.aiff reverbImpulseResponse.aiff us_english_60.txt wordList.txt; do
    PRELOAD+=(--preload-file "$REPO/gameSource/$f@/$f")
done
PRELOAD+=(--preload-file "$REPO/gameSource/languages@/languages")
PRELOAD+=(--preload-file "$REPO/gameSource/otherSounds@/otherSounds")

# 4. link.  Emscripten's built-in SDL 1.2 matches the code (<SDL/SDL.h>);
#    no -sUSE_SDL, no Asyncify.
em++ -O2 -fexceptions "$OBJ"/*.o \
    -o "$SITE/index.html" \
    -sLEGACY_GL_EMULATION=1 \
    -sALLOW_MEMORY_GROWTH=1 \
    -sMAXIMUM_MEMORY=2GB \
    -sSTACK_SIZE=4MB \
    -sEXIT_RUNTIME=0 \
    -sFORCE_FILESYSTEM=1 \
    --shell-file "$REPO/wasm/shell.html" \
    "${PRELOAD[@]}" \
    > "$LOGDIR/link.log" 2>&1 || { echo "==== link errors ===="; head -80 "$LOGDIR/link.log"; exit 1; }

ls -la "$SITE"
echo "Build finished: $SITE"
