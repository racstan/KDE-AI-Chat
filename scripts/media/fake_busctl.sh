#!/bin/sh
# Stand-in for busctl in the docs media: the D-Bus is never touched. Speech Note's State is
# "idle" (ready); every other call fails.
case "$*" in
    *get-property*State) echo '{"type":"u","data":3}' ;;
    *) exit 1 ;;
esac
