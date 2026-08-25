#!/bin/bash
set -o pipefail  # <-- CRITICAL: Forces pipelines to fail if ANY command in them fails

backup() {
    if [ -z "$FORCE" ] && [ -z "$(ls -A /volume)" ]; then
        >&2 echo "Volume is empty or missing, check if you specified a correct name"
        exit 1
    fi

    if ! [ "$ARCHIVE" == "-" ]; then
        mkdir -p "$(dirname "/backup/$ARCHIVE")"
    fi

    cd /volume || exit 1
    
    # If find, cpio, or zstd fails, the pipeline returns a non-zero code
    find . $FIND_EXCLUDES -print0 | \
    cpio $CPIO_VERBOSE --null -ov -H newc 2>/dev/null | \
    zstd -T$ZSTD_THREADS -$ZSTD_LEVEL > "$ARCHIVE_PATH"
    
    # Capture the pipeline's exit status
    local status=$?
    if [ $status -ne 0 ]; then
        >&2 echo "Backup failed during archiving or compression!"
        exit $status  # Propagates the exact error code back to the OS
    fi
}

restore() {
    if ! [ "$ARCHIVE" == "-" ]; then
        if ! [ -e "$ARCHIVE_PATH" ]; then
            >&2 echo "Archive file $ARCHIVE does not exist"
            exit 1
        fi
    fi

    if ! [ -z "$(ls -A /volume)" -o -n "$FORCE" ]; then
        >&2 echo "Target volume is not empty, aborting; use -f to override"
        exit 1
    fi

    rm -rf /volume/* /volume/..?* /volume/.[!.]*
    cd /volume || exit 1

    # If zstd or cpio fails, the pipeline returns a non-zero code
    zstd -d -c -T$ZSTD_THREADS "$ARCHIVE_PATH" | cpio $CPIO_VERBOSE -idmv
    
    local status=$?
    if [ $status -ne 0 ]; then
        >&2 echo "Restore failed during decompression or extraction!"
        exit $status  # Propagates the exact error code back to the OS
    fi
}

usage() {
    cat >&2 << EOF
Usage: $0 <operation> [options] [archive]

Operations:
  backup    Create a backup of /volume
  restore   Restore /volume from an archive

Options:
  -h        Show this help message
  -v        Verbose output
  -f        Force operation (backup: ignore empty volume; restore: overwrite non-empty volume)
  -e GLOB   Exclude files matching GLOB from backup (can be used multiple times)
  -c LEVEL  Compression level (1-22, default: 1)
  -t THREADS Number of threads for zstd (default: 1; 0 = auto)

Archive:
  If not specified or "-", use stdout/stdin
  Otherwise, archive is saved to /backup/<name>.cpio.zst

Examples:
  $0 backup -c 10 -t 4 my-backup
  $0 restore -t 4 my-backup
  $0 backup -e '*.log' -e '*.tmp' -c 19 full-backup
EOF
}

OPERATION=$1
FORCE=""
FIND_EXCLUDES=""
CPIO_VERBOSE=""
EXTENSION=".cpio.zst"
ZSTD_LEVEL=1
ZSTD_THREADS=1

OPTIND=2

while getopts "h?vfe:c:t:" OPTION; do
    case "$OPTION" in
    h|\?)
        usage
        exit 0
        ;;
    e)  
        if [ -z "$OPTARG" ] || [ "$OPERATION" != "backup" ]; then
          usage
          exit 1
        fi
        # Convert glob to find exclusion logic
        FIND_EXCLUDES="$FIND_EXCLUDES -not -path */$OPTARG*"
        ;;
    f)
        FORCE=1
        ;;
    v)
        CPIO_VERBOSE="-v"
        ;;
    c)
        ZSTD_LEVEL="$OPTARG"
        # Validate compression level
        if ! [[ "$ZSTD_LEVEL" =~ ^[0-9]+$ ]] || [ "$ZSTD_LEVEL" -lt 1 ] || [ "$ZSTD_LEVEL" -gt 22 ]; then
            >&2 echo "Error: Compression level must be between 1 and 22"
            usage
            exit 1
        fi
        ;;
    t)
        ZSTD_THREADS="$OPTARG"
        # Validate thread count (allow 0 for zstd auto-detection)
        if ! [[ "$ZSTD_THREADS" =~ ^[0-9]+$ ]] || [ "$ZSTD_THREADS" -lt 0 ]; then
            >&2 echo "Error: Thread count must be a non-negative integer (0 = auto)"
            usage
            exit 1
        fi
        ;;
    *)
        usage
        exit 1
        ;;
    esac
done

shift $((OPTIND - 1))

if [ -z "$1" ] || [ "$1" == "-" ]; then
    ARCHIVE="-"
    ARCHIVE_PATH="/dev/stdout"
else
    ARCHIVE=${1%%$EXTENSION}$EXTENSION
    ARCHIVE_PATH=/backup/$ARCHIVE
fi

case "$OPERATION" in
"backup" )
backup
;;
"restore" )
restore
;;
* )
usage
;;
esac
