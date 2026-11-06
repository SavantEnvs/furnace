#!/usr/bin/env bash
# Builds Furnace headless (no GUI/audio/MIDI): a sanitized tree for the fuzz harnesses, and a
# normal-flags Release tree whose `furnace` CLI is the oracle binary for mayhem/test.sh.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
# upstream shifts a 30-bit-flagged macro value left (src/engine/instrument.cpp:4394, left shift of
# 1073741xxx by 8) while loading ordinary .fur files; relax only that check so real modules load.
SANITIZER_FLAGS="$SANITIZER_FLAGS -fno-sanitize=shift-base"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Submodules normally arrive with the checkout; fetch only what the headless build needs if absent.
if [ ! -f extern/fmt/include/fmt/core.h ] || [ ! -f extern/json/include/nlohmann/json.hpp ] \
   || [ ! -d extern/adpcm ] || [ ! -d extern/YM2414-LLE ]; then
  git submodule update --init extern/fmt extern/json extern/adpcm extern/YM2414-LLE
fi

# Upstream omits <cstring>/<climits>/<cstdint>/<cstdlib> in a few headers/sources; force them in
# rather than patching upstream.
INCLUDES="-include cstring -include climits -include cstdint -include cstdlib"
# The compilers come from the CC/CXX environment: passing -DCMAKE_C_COMPILER=clang makes cmake wipe the
# cache on re-run (it caches /usr/bin/clang), dropping every other -D option with it.
CMAKE_OPTS=(-G Ninja
  -DBUILD_GUI=OFF -DWITH_RENDER_SDL=OFF -DWITH_RENDER_OPENGL=OFF -DWITH_RENDER_OPENGL1=OFF
  -DUSE_SDL2=OFF -DWITH_PORTAUDIO=OFF -DUSE_RTMIDI=OFF -DWITH_JACK=OFF -DUSE_BACKWARD=OFF
  -DWITH_LOCALE=OFF -DSYSTEM_FFTW=ON -DSYSTEM_LIBSNDFILE=ON -DSYSTEM_ZLIB=ON
  -DWITH_INSTRUMENTS=OFF -DWITH_WAVETABLES=OFF -DBUILD_TESTING=OFF)

# 1) Sanitized engine objects (everything except src/main.cpp, which the harnesses replace).
cmake -S . -B build "${CMAKE_OPTS[@]}" \
  -DCMAKE_C_FLAGS="-O1 $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
  -DCMAKE_CXX_FLAGS="-O1 $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS $INCLUDES"
ninja -C build -j"$MAYHEM_JOBS" furnace

# 2) Harnesses: fuzzer binary + standalone reproducer, both with leak detection compiled out.
HARNESS_CXXFLAGS="-DHAVE_DIRENT_TYPE -DHAVE_SNDFILE -DWITH_JSON -I$SRC/src -I$SRC/extern/klattsch-cpp/include
  -I$SRC/extern/json/include -isystem $SRC/extern/blip_buf -isystem $SRC/extern/vgsound_emu-modified
  -isystem $SRC/extern/fmt/include -O1 $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS $INCLUDES -std=c++14"
OBJS=$(cd build && ninja -t inputs furnace | grep -E '\.(o|a)$' | grep -v 'src/main\.cpp\.o$' | sed 's#^#build/#')
LIBS="-lfftw3 -lsndfile -lz -ldl"

$CXX $HARNESS_CXXFLAGS -c mayhem/stubs.cc -o build/stubs.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o build/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build/standalone_main.o

for t in fuzz_song fuzz_instrument; do
  $CXX $HARNESS_CXXFLAGS -c "mayhem/$t.cc" -o "build/$t.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "build/$t.o" build/stubs.o build/lsan_off.o $OBJS $LIBS -o "$SRC/$t"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "build/$t.o" build/standalone_main.o build/stubs.o build/lsan_off.o $OBJS $LIBS -o "$SRC/$t-standalone"
done

# 3) Oracle: the normal-flags `furnace` CLI, run by mayhem/test.sh via `furnace -info`.
cmake -S . -B release "${CMAKE_OPTS[@]}" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$INCLUDES $COVERAGE_FLAGS"
ninja -C release -j"$MAYHEM_JOBS" furnace
