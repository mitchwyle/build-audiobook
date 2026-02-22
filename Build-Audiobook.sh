#!/bin/bash
set -euo pipefail

# --- Global Variables ---
WorkDir="./M4B-Workspace"
ConcatList="./concat-list.txt"
FinalM4B="./final-audiobook.m4b"
AuthorTag="Unknown-Author"
TitleTag="Unknown-Title"
CoverArt=""

# --- Cleanup & Safety ---

Cleanup() {
    if [[ -d "$WorkDir" ]]; then
        echo "Cleaning up temporary workspace..."
        rm -rf "$WorkDir"
    fi
    [[ -f "$ConcatList" ]] && rm "$ConcatList"
}

# The trap now officially calls the cleanup function on exit or interrupt
trap Cleanup EXIT SIGINT SIGTERM

# --- Functions ---

ShowUsage() {
    cat << EOF
Usage: $(basename "$0") [-a "Author"] [-t "Title"]

Merge multiple audio files into a single M4B audiobook for iPhone.

Options:
  -a, --author "Name"    Set author metadata.
  -t, --title  "Title"   Set book title metadata.
  -h, --help             Show this help.

Policies:
  - Sorting: Natural Sort (10 follows 9, not 1).
  - Audio:   Extracts .mp3, .m4a, .mp4.
  - Covers:  Checks cover.{ext} then {title}.{ext}.
             Exts: jpg, jpeg, png, webp, gif.
  - Output:  AAC 128k, -f ipod.
EOF
    exit 0
}

CheckDependencies() {
    for Tool in ffmpeg sort sed cp; do
        if ! command -v "$Tool" &> /dev/null; then
            echo "Error: Required tool '$Tool' is missing."
            exit 1
        fi
    done
}

FindCoverArt() {
    local Exts=("jpg" "jpeg" "png" "webp" "gif")

    # 1. Primary: cover.{ext}
    for Ext in "${Exts[@]}"; do
        if [[ -f "cover.$Ext" ]]; then
            CoverArt="cover.$Ext"
            echo "Found primary cover: $CoverArt"
            return 0
        fi
    done

    # 2. Secondary: folder.{ext}
    for Ext in "${Exts[@]}"; do
        if [[ -f "folder.$Ext" ]]; then
            CoverArt="folder.$Ext"
            echo "Found folder cover: $CoverArt"
            return 0
        fi
    done

    # 3. Tertiary: {TitleTag}.{ext}
    for Ext in "${Exts[@]}"; do
        if [[ -f "$TitleTag.$Ext" ]]; then
            CoverArt="$TitleTag.$Ext"
            echo "Found title-based cover: $CoverArt"
            return 0
        fi
    done

    # 4. Catch-all: Use the first image file found in the directory
    local Fallback
    Fallback=$(ls *.jpg *.jpeg *.png *.webp *.gif 2>/dev/null | head -n 1) || true
    if [[ -n "$Fallback" ]]; then
        CoverArt="$Fallback"
        echo "Found fallback cover: $CoverArt"
        return 0
    fi

    echo "No image files found. Proceeding without cover art."
}



PrepareAudio() {
    echo "Sanitizing filenames and building list..."
    # Natural sort ensures 09 comes before 10
    local RawFiles
    RawFiles=$(ls *.mp3 *.m4a *.mp4 2>/dev/null | sort -V) || true

    if [[ -z "$RawFiles" ]]; then
        echo "Error: No supported audio files found."
        exit 1
    fi

    mkdir -p "$WorkDir"

    while IFS= read -r File; do
        # Replace spaces with dashes for the workspace copy
        local CleanName="${File// /-}"
        cp "$File" "$WorkDir/$CleanName"
        
        # Escape single quotes for ffmpeg's internal list syntax
        local EscapedName="${CleanName//\'/\'\\\'\'}"
        echo "file '$WorkDir/$EscapedName'" >> "$ConcatList"
    done <<< "$RawFiles"
}

RunFfmpeg() {
    echo "Encoding to M4B..."
    local Args=(-f concat -safe 0 -i "$ConcatList")

    if [[ -n "$CoverArt" ]]; then
        # We add -c:v mjpeg to ensure the image is compatible with the M4B container
        Args+=(
            -i "$CoverArt"
            -map 0:a -map 1
            -c:v mjpeg
            -pix_fmt yuvj420p
            -disposition:v:0 attached_pic
        )
    else
        Args+=(-map 0:a)
    fi

    Args+=(
        -c:a aac -b:a 128k
        -metadata title="$TitleTag"
        -metadata artist="$AuthorTag"
        -f ipod -y "$FinalM4B"
    )

    ffmpeg -hide_banner -loglevel warning "${Args[@]}"
}

# --- Main Execution ---

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--author) AuthorTag="$2"; shift 2 ;;
        -t|--title)  TitleTag="$2";  shift 2 ;;
        -h|--help)   ShowUsage ;;
        *) echo "Unknown option: $1"; ShowUsage ;;
    esac
done

CheckDependencies
FindCoverArt
PrepareAudio
RunFfmpeg

echo "Process Complete."

