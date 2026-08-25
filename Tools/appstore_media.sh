#!/bin/bash
#
# appstore_media.sh — regenerates every screenshot and App Preview in AppStore/.
#
#     Tools/appstore_media.sh                 # screenshots + previews
#     Tools/appstore_media.sh screenshots     # screenshots only
#     Tools/appstore_media.sh video           # previews only
#
# Needs Xcode, the simulators named below and ImageMagick (`brew install
# imagemagick`) for the lossless PNG squeeze. Everything is driven by the `-shot`
# launch argument handled in solitaire/Support/ScreenshotScenes.swift, which is
# `#if DEBUG` only — so this builds Debug, and none of it exists in the build
# that goes to the App Store.
#
# Output goes to AppStore/screenshots/<locale>/<device>/ and
# AppStore/preview/<locale>/<device>.mp4, where <device> is iphone-6.5 or
# ipad-13. Override the root with OUT_ROOT=… to try things out without touching
# the set you are about to upload.
#
set -euo pipefail

MODE="${1:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="${OUT_ROOT:-$ROOT/AppStore}"
WORK="${WORK:-$(mktemp -d -t solitaire-appstore)}"
BID=cz.rob.solitaire

# Both devices record their App Store slot size natively, so nothing here is
# scaled or cropped:
#   iPhone 11 Pro Max → 1242 × 2688, one of the two sizes Connect takes for 6.5"
#   iPad Pro 13" (M5) → 2064 × 2752, one of the two it takes for iPad 13"
#
# **6.5" is the iPhone slot this listing uses.** Apple derives every smaller
# size from the one you upload, but only within a slot: a listing sitting on the
# 6.5" slot refuses a 6.9" file outright, and the other way round. Shooting one
# iPhone size rather than two halves the run; if the 6.9" slot is ever wanted as
# well, add "iPhone 17 Pro Max" 1320 × 2868 back alongside this one — the shoot
# function already takes the device and the expected size as arguments.
IPHONE_NAME="iPhone 11 Pro Max"
IPAD_NAME="iPad Pro 13-inch (M5)"
IPHONE_SHOT_SIZE=(1242 2688)
IPAD_SHOT_SIZE=(2064 2752)

# Xcode ships the iPhone 11 Pro Max device *type* but does not always leave a
# ready-made device for it, so the 6.5" one is created on demand (see
# ensure_device). iOS 26 still runs on that hardware, which is why the current
# runtime pairs with it at all.
IPHONE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max

# App Preview render sizes — the only two App Store Connect takes for these
# devices, and *not* the devices' own resolutions. See AppStore/screenshots.md
# before changing either.
IPHONE_VIDEO_SIZE=(886 1920)
IPAD_VIDEO_SIZE=(1200 1600)

# Previews must carry stereo AAC at 256 kbps and silence does not satisfy the
# check, so a bed is synthesised — the app itself ships no audio at all.
PREVIEW_MUSIC="${PREVIEW_MUSIC-$WORK/bed.wav}"
PREVIEW_GAIN="${PREVIEW_GAIN:-0.5}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

udid_for() {
    # Device lines are indented four spaces and read "<name> (<udid>) (<state>)".
    # Matched as a fixed string, because names like "iPad Pro 13-inch (M5)" carry
    # brackets of their own; the trailing " (" keeps "iPhone 11" from matching
    # "iPhone 11 Pro Max".
    xcrun simctl list devices available \
        | grep -F "    $1 (" \
        | grep -oE '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' \
        | head -n 1 || true
}

ensure_device() { # ensure_device <name> <device-type-id> -> udid on stdout
    local udid; udid="$(udid_for "$1")"
    if [ -z "$udid" ]; then
        # Newest installed runtime. simctl refuses a pairing the runtime does
        # not support, so a device type that has aged out fails here rather than
        # producing something that never boots. Messages go to stderr, because
        # the caller reads this function's stdout.
        local rt
        rt="$(xcrun simctl list runtimes available \
              | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' \
              | tail -n 1)"
        [ -n "$rt" ] || { echo "no iOS simulator runtime installed" >&2; return 1; }
        echo "  creating simulator '$1' on ${rt##*.}" >&2
        xcrun simctl create "$1" "$2" "$rt" >/dev/null || return 1
        udid="$(udid_for "$1")"
    fi
    printf '%s' "$udid"
}

boot_and_install() {
    local udid="$1"
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    # A pose writes settings, statistics and a saved game like any other play
    # would, so each run starts from a clean install rather than from whatever
    # the last one left behind.
    xcrun simctl uninstall "$udid" "$BID" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP"
    # The board hides the status bar, but pin it anyway: a sheet that ever stops
    # hiding it should photograph 9:41 and a full battery, not a real clock.
    xcrun simctl status_bar "$udid" override --time "9:41" \
        --batteryState charged --batteryLevel 100 --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true
}

locale_args() {
    case "$1" in
        cs)    printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(cs)" -AppleLocale cs_CZ ;;
        en-US) printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(en-US)" -AppleLocale en_US ;;
    esac
}

launch() { # launch <udid> <locale> <args...>
    local udid="$1" loc="$2"; shift 2
    local largs=()
    while IFS= read -r -d '' a; do largs+=("$a"); done < <(locale_args "$loc")
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BID" "${largs[@]}" "$@" >/dev/null
}

# A pose is built before the first frame is drawn, but the animations it starts
# are not: a sheet takes half a second to present, the wand springs in, the
# victory cascade flies. The app drops a marker file once those have had time to
# land (Shots.markReady), so nothing here has to sleep for a guess.
container_for() { xcrun simctl get_app_container "$1" "$BID" data; }

clear_ready() { rm -f "$(container_for "$1")/Documents/shot-ready" 2>/dev/null || true; }

wait_ready() { # wait_ready <udid> <timeout-seconds>
    local marker="$(container_for "$1")/Documents/shot-ready"
    local waited=0
    while [ ! -f "$marker" ] && [ "$waited" -lt "$2" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    # stderr, because the caller reads this function's stdout.
    [ -f "$marker" ] || { echo "  !! pose never became ready (${2}s)" >&2; return 1; }
    printf '%s' "$waited"
}

# ---------------------------------------------------------------- build

say "Building Debug for the simulator"
xcodebuild -project "$ROOT/solitaire.xcodeproj" -scheme solitaire \
    -configuration Debug -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$IPAD_NAME" \
    -derivedDataPath "$WORK/dd" build >/dev/null
APP="$WORK/dd/Build/Products/Debug-iphonesimulator/solitaire.app"

IPHONE_UDID="$(ensure_device "$IPHONE_NAME" "$IPHONE_TYPE" || true)"
IPAD_UDID="$(udid_for "$IPAD_NAME")"
[ -n "$IPHONE_UDID" ] \
    || { echo "no simulator named '$IPHONE_NAME', and creating one failed"; exit 1; }
[ -n "$IPAD_UDID" ] || { echo "no simulator named '$IPAD_NAME'"; exit 1; }

# ---------------------------------------------------------------- screenshots

# name|extra launch arguments. The pose itself lives in the shot catalogue in
# ScreenshotScenes.swift; the two sheet flags are ContentView's own business,
# because opening a sheet is a view-level thing rather than a board.
SHOTS=(
    "01-board|"
    "02-autofinish|"
    "03-stuck|"
    "04-hint|"
    "05-vegas|"
    "06-win|"
    "07-stats|-open-stats"
    "08-settings|-open-settings"
)

shoot() { # shoot <udid> <locale> <device-dir> <W> <H>
    local udid="$1" loc="$2" dev="$3" w="$4" h="$5"
    local dir="$OUT_ROOT/screenshots/$loc/$dev"
    mkdir -p "$dir"
    for entry in "${SHOTS[@]}"; do
        local name="${entry%%|*}" extra="${entry#*|}"
        clear_ready "$udid"
        # shellcheck disable=SC2086
        launch "$udid" "$loc" -shot "$name" $extra
        local waited
        waited="$(wait_ready "$udid" 60)" || exit 1
        xcrun simctl io "$udid" screenshot "$dir/$name.png" >/dev/null 2>&1
        local size
        size="$(magick identify -format '%wx%h' "$dir/$name.png")"
        printf '  %-14s %-10s ready in %2ss\n' "$name" "$size" "$waited"
        # Both devices record their slot size, so a mismatch means the simulator
        # is not the one this script expects rather than something to paper over.
        if [ "$size" != "${w}x${h}" ]; then
            echo "     !! expected ${w}x${h} — wrong simulator or a changed runtime"
            exit 1
        fi
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

if [ "$MODE" = all ] || [ "$MODE" = screenshots ]; then
    command -v magick >/dev/null \
        || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }
    boot_and_install "$IPHONE_UDID"
    boot_and_install "$IPAD_UDID"
    for loc in cs en-US; do
        say "Screenshots — iPhone 6.5\" / $loc"
        shoot "$IPHONE_UDID" "$loc" iphone-6.5 "${IPHONE_SHOT_SIZE[@]}"
        say "Screenshots — iPad 13\" / $loc"
        shoot "$IPAD_UDID" "$loc" ipad-13 "${IPAD_SHOT_SIZE[@]}"
    done

    # The simulator writes RGBA even though every pixel is opaque, and App Store
    # Connect wants screenshots without transparency. Dropping the channel leaves
    # the picture untouched and saves about a third of the size — verified rather
    # than assumed, and anything that is not identical is left alone.
    say "Squeezing PNGs (lossless)"
    while IFS= read -r f; do
        magick "$f" -alpha off -depth 8 -strip \
                    -define png:compression-level=9 \
                    -define png:compression-filter=5 "$f.opt"
        if [ "$(magick compare -metric AE "$f" "$f.opt" null: 2>&1 | awk '{print $1}')" = "0" ]; then
            mv "$f.opt" "$f"
        else
            rm -f "$f.opt"
            echo "  left as-is (not identical): $f"
        fi
    done < <(find "$OUT_ROOT/screenshots" -name '*.png')
    du -sh "$OUT_ROOT/screenshots"
fi

# ---------------------------------------------------------------- previews

# name|seconds|launch arguments. Recording starts the moment the app is launched,
# so the clip covers the app's own launch animation too — the cut points below
# are measured from there.
#
# Both clips play themselves and need no touch input. `preview-play` deals
# number 27122 with the dealing animation on and hands it to the advisor bot
# (`-autoplay`), which takes the top suggestion once every 200 ms — about the
# pace of somebody who knows what they are doing. That deal was chosen because
# it keeps going: the bot stops the moment a board repeats, and most deals stall
# inside a minute, whereas this one plays 120 moves before the win is even
# certain. `preview-finish` is deal 6477 at the point where the wand appears,
# and the pose taps it two seconds in — so the clip opens on a board and
# everything after that is the cascade and the confetti.
CLIPS=(
    "p1-play|22|-shot preview-play -autoplay"
    "p2-finish|14|-shot preview-finish"
)

# Cut points, in seconds into each recording. Every window is chosen to hold
# something *moving* from its first frame to its last: cards being dealt, a run
# sliding across, the cascade, the confetti. The deal is numbered and the bot is
# deterministic, so the timeline is the same on every run — but the iPad reaches
# each state a little sooner than the iPhone, which is why the two have their own
# points.
#
# Two things bound the windows, and both were learned the hard way on the sister
# projects:
#
#   * The confetti window is short on purpose. It flies for about two seconds and
#     then the results panel just sits there, so a five-second window spends
#     three of them on a still picture.
#   * Nothing may reach past about 21 s into a recording. The files report their
#     full length but the tail is not reliably decodable — a range that crosses
#     it is clamped and the finished preview holds one frame for the difference,
#     while every step reports success.
#
# After any change to the pacing, the poses or the animations, look at the frames
# either side of each cut before uploading — Tools/appstore_frames.swift pulls
# them out. Nothing here fails loudly: a stale window just goes still.
IPHONE_CUTS=(p1-play:0.4:5.6 p1-play:6.6:12.8 p1-play:13.8:19.4
             p2-finish:2.8:7.6 p2-finish:8.2:11.4)
IPAD_CUTS=(p1-play:0.3:5.5 p1-play:6.5:12.7 p1-play:13.7:19.3
           p2-finish:2.6:7.4 p2-finish:8.0:11.2)

record() { # record <udid> <locale> <clipdir>
    local udid="$1" loc="$2" dir="$3"
    mkdir -p "$dir"
    for entry in "${CLIPS[@]}"; do
        IFS='|' read -r name secs args <<<"$entry"
        clear_ready "$udid"
        # shellcheck disable=SC2086
        launch "$udid" "$loc" $args
        xcrun simctl io "$udid" recordVideo --codec h264 --force "$dir/$name.mp4" >/dev/null 2>&1 &
        local pid=$!
        sleep "$secs"
        kill -INT $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
        sleep 1
        printf '  %-10s %s\n' "$name" "$(avmediainfo "$dir/$name.mp4" | awk '/^Duration:/{print $2 "s"}')"
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

assemble() { # assemble <clipdir> <out.mp4> <W> <H> <cut...>
    local dir="$1" out="$2" w="$3" h="$4"; shift 4
    mkdir -p "$(dirname "$out")"
    local specs=()
    for cut in "$@"; do specs+=("$dir/${cut%%:*}.mp4:${cut#*:}"); done
    swift "$ROOT/Tools/appstore_video.swift" "$out" "$w" "$h" "${specs[@]}"
    # What comes out of the cut is the right size and the wrong everything else
    # for App Store Connect — too high a profile, too fast a bit rate and no
    # audio at all. This pins the lot to Apple's table.
    swift "$ROOT/Tools/appstore_conform.swift" "$out" "$w" "$h" \
        ${PREVIEW_MUSIC:+"$PREVIEW_MUSIC"} "$PREVIEW_GAIN"
}

if [ "$MODE" = all ] || [ "$MODE" = video ]; then
    boot_and_install "$IPHONE_UDID"
    boot_and_install "$IPAD_UDID"
    if [ -n "$PREVIEW_MUSIC" ] && [ ! -f "$PREVIEW_MUSIC" ]; then
        say "Synthesising the music bed"
        python3 "$ROOT/Tools/gen_preview_music.py" "$PREVIEW_MUSIC" 30
    fi
    for loc in cs en-US; do
        say "Preview — iPhone 6.5\" / $loc"
        record "$IPHONE_UDID" "$loc" "$WORK/clips/iphone-$loc"
        assemble "$WORK/clips/iphone-$loc" "$OUT_ROOT/preview/$loc/iphone-6.5.mp4" \
            "${IPHONE_VIDEO_SIZE[@]}" "${IPHONE_CUTS[@]}"

        say "Preview — iPad 13\" / $loc"
        record "$IPAD_UDID" "$loc" "$WORK/clips/ipad-$loc"
        assemble "$WORK/clips/ipad-$loc" "$OUT_ROOT/preview/$loc/ipad-13.mp4" \
            "${IPAD_VIDEO_SIZE[@]}" "${IPAD_CUTS[@]}"
    done
fi

say "Done. Working files in $WORK"
