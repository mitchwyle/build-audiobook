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

# Trap ensures Cleanup is called on exit or interruption
trap Cleanup EXIT SIGINT SIGTERM

# --- Functions ---

ShowUsage() {
    cat << EOF
Usage: $(basename "$0") [-a "Author"] [-t "Title"]

Merge multiple audio files in the current directory into a single M4B audiobook for iPhone.

Options:
  -a, --author "Name"    Set author metadata.
  -t, --title  "Title"   Set book title metadata.
  -h, --help             Show this help.

Policies:
  - Sorting: Natural Sort (10 follows 9, not 1).
  - Audio:   Extracts .mp3, .m4a, .mp4 from current directory.
  - Covers:  Searches current directory for: 
             1. cover.{ext} | 2. folder.{ext} | 3. {title}.{ext} | 4. First image found.
             Exts: jpg, jpeg, png, webp, gif.
  - Output:  AAC 128k, MJPEG cover stream, -f ipod.
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
    
    # Priority 1-3: Specific naming conventions
    for Ext in "${Exts[@]}"; do
        for Name in "cover" "folder" "$TitleTag"; do
            if [[ -f "$Name.$Ext" ]]; then
                CoverArt="$Name.$Ext"
                echo "Found cover art: $CoverArt"
                return 0
            fi
        done
    done

    # Priority 4: Catch-all fallback - Use the first image file found
    local Fallback
    Fallback=$(ls *.jpg *.jpeg *.png *.webp *.gif 2>/dev/null | head -n 1) || true
    if [[ -n "$Fallback" ]]; then
        CoverArt="$Fallback"
        echo "Using fallback image: $CoverArt"
        return 0
    fi

    echo "No cover art found. Proceeding without an image."
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
        # Replace spaces with dashes for the workspace copy to be bulletproof
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
    
    # Map the cover art if found, using MJPEG for M4B/iPod compatibility
    if [[ -n "$CoverArt" ]]; then
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

    # Final audio and container settings
    Args+=(
        -c:a aac 
        -b:a 128k 
        -metadata title="$TitleTag" 
        -metadata album="$TitleTag" 
        -metadata artist="$AuthorTag" 
        -metadata album_artist="$AuthorTag" 
        -metadata genre="Audiobook" 
        -f ipod -y "$FinalM4B"
    )

    ffmpeg -hide_banner -loglevel warning "${Args[@]}"
}

# --- Main Execution ---

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

echo "---"
echo "Process Complete: $FinalM4B"
