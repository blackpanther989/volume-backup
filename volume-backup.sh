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
    zstd -T0 -3 > "$ARCHIVE_PATH"
    
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
    zstd -d -c "$ARCHIVE_PATH" | cpio $CPIO_VERBOSE -idmv
    
    local status=$?
    if [ $status -ne 0 ]; then
        >&2 echo "Restore failed during decompression or extraction!"
        exit $status  # Propagates the exact error code back to the OS
    fi
}

OPERATION=$1
FORCE=""
FIND_EXCLUDES=""
CPIO_VERBOSE=""
EXTENSION=".cpio.zst"

OPTIND=2

while getopts "h?vfe:" OPTION; do
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
