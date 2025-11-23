#!/bin/bash

# Pi-gen Work Directory Cleanup Script
# Cleans up mounts and allows safe removal of work directories
# Run this when build fails with "target is busy" or "Operation not permitted" errors
#
# Usage:
#   ./cleanup-work.sh              # Clean all mounts in work directory
#   ./cleanup-work.sh stage-kernel # Clean specific stage
#   ./cleanup-work.sh --help       # Show help

set +e  # Don't exit on errors

WORK_DIR="${WORK_DIR:-work}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    cat << EOF
Pi-gen Work Directory Cleanup Script

Usage: $0 [OPTIONS] [STAGE]

Arguments:
  STAGE                  Optional: specific stage to clean (e.g., stage-kernel, stage2, export-image)
                         If not provided, cleans all mounts under work directory

Options:
  -h, --help            Show this help message
  -v, --verbose         Verbose output
  -f, --force           Force cleanup with fuser -km (kills processes)

Examples:
  $0                    # Clean all work directory mounts
  $0 stage-kernel       # Clean only stage-kernel
  $0 export-image       # Clean only export-image
  $0 -f                 # Force cleanup all mounts

EOF
    exit 0
}

# Parse arguments
VERBOSE=0
FORCE=0
TARGET_STAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            TARGET_STAGE="$1"
            shift
            ;;
    esac
done

cd "$BASE_DIR"

echo "=== Pi-gen Work Directory Cleanup Script ==="
echo ""

# Source common functions if available
if [ -f scripts/common ]; then
    source scripts/common
    [ $VERBOSE -eq 1 ] && echo "✓ Loaded pi-gen common functions"
fi

# Determine target directory
if [ -n "$TARGET_STAGE" ]; then
    # Find the specific stage directory
    TARGET_PATTERN="$(realpath ${WORK_DIR}).*/${TARGET_STAGE}"
    echo "Target: ${TARGET_STAGE} stage"
else
    TARGET_PATTERN="$(realpath ${WORK_DIR})"
    echo "Target: All work directories"
fi

# Find all mounts under target directory
echo ""
echo "Scanning for mounts..."
MOUNTS=$(mount | grep "${TARGET_PATTERN}" | awk '{print $3}' | sort -r)

if [ -z "$MOUNTS" ]; then
    echo "  ✓ No mounts found"
    exit 0
fi

echo "Found mounted filesystems:"
echo "$MOUNTS" | sed 's/^/  - /'
echo ""

# Show what's using the mounts if verbose
if [ $VERBOSE -eq 1 ]; then
    echo "Checking for processes using mounts..."
    for mnt in $MOUNTS; do
        USERS=$(fuser -m "$mnt" 2>/dev/null | xargs)
        if [ -n "$USERS" ]; then
            echo "  $mnt: PIDs $USERS"
        fi
    done
    echo ""
fi

# Method 1: Try pi-gen's unmount function first (if available)
if type unmount &>/dev/null; then
    echo "Method 1: Using pi-gen unmount function..."
    for mnt in $MOUNTS; do
        [ $VERBOSE -eq 1 ] && echo "  Unmounting $mnt"
        unmount "$mnt" 2>&1 | grep -v "not mounted" || true
    done
    sleep 1
fi

# Method 2: Try normal unmount
REMAINING=$(mount | grep "${TARGET_PATTERN}" | awk '{print $3}' | sort -r)
if [ -n "$REMAINING" ]; then
    echo "Method 2: Normal unmount..."
    for mnt in $REMAINING; do
        echo "  Unmounting $mnt"
        umount "$mnt" 2>&1 | grep -v "not mounted" || true
    done
    sleep 1
fi

# Check progress
REMAINING=$(mount | grep "${TARGET_PATTERN}" | awk '{print $3}' | sort -r)
if [ -z "$REMAINING" ]; then
    echo ""
    echo "✓ All mounts cleared successfully!"
    echo ""
    if [ -n "$TARGET_STAGE" ]; then
        STAGE_DIR=$(find "$WORK_DIR" -type d -name "$TARGET_STAGE" 2>/dev/null | head -1)
        if [ -n "$STAGE_DIR" ]; then
            echo "You can now safely remove the stage directory:"
            echo "  sudo rm -rf $STAGE_DIR"
        fi
    else
        echo "You can now safely remove work directories:"
        echo "  sudo rm -rf $WORK_DIR"
    fi
    exit 0
fi

# Method 3: Try lazy unmount
echo ""
echo "Method 3: Lazy unmount for remaining mounts..."
for mnt in $REMAINING; do
    echo "  Lazy unmounting $mnt"
    umount -l "$mnt" 2>&1 || true
done
sleep 2

# Method 4: Force cleanup if requested
REMAINING=$(mount | grep "${TARGET_PATTERN}" | awk '{print $3}' | sort -r)
if [ -n "$REMAINING" ] && [ $FORCE -eq 1 ]; then
    echo ""
    echo "Method 4: Force cleanup (killing processes)..."
    for mnt in $REMAINING; do
        echo "  Force unmounting $mnt"
        fuser -km "$mnt" 2>/dev/null || true
        sleep 1
        umount -l "$mnt" 2>&1 || true
    done
    sleep 2
fi

# Final check
FINAL=$(mount | grep "${TARGET_PATTERN}" | awk '{print $3}')

echo ""
if [ -z "$FINAL" ]; then
    echo "✓ All mounts cleared!"
    echo ""
    if [ -n "$TARGET_STAGE" ]; then
        STAGE_DIR=$(find "$WORK_DIR" -type d -name "$TARGET_STAGE" 2>/dev/null | head -1)
        if [ -n "$STAGE_DIR" ]; then
            echo "You can now safely remove the stage directory:"
            echo "  sudo rm -rf $STAGE_DIR"
        fi
    else
        echo "You can now safely remove work directories:"
        echo "  sudo rm -rf $WORK_DIR"
    fi
else
    echo "⚠ Warning: Some mounts could not be cleared:"
    echo "$FINAL" | sed 's/^/  - /'
    echo ""
    echo "Suggestions:"
    echo "  1. Check if your terminal's working directory is inside work/"
    echo "     Run: pwd"
    echo ""
    echo "  2. Find and close processes using the mounts:"
    echo "     sudo lsof +D $(echo $FINAL | head -1 | awk '{print $1}')"
    echo ""
    echo "  3. Force cleanup (will kill processes):"
    echo "     sudo $0 --force $([ -n "$TARGET_STAGE" ] && echo "$TARGET_STAGE")"
    echo ""
    echo "  4. If all else fails, reboot the system"
    exit 1
fi

