#!/bin/bash
set -e

# default command to run is queue (can provide options)
if [ $# = 0 -o "$1" = "-h" -o "$1" = "--help" ]; then
    exec queue "$@"
else 
    exec "$@"
fi
