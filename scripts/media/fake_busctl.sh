#!/bin/sh
# Stand-in for busctl in the docs media (see fake_busctl.py): the D-Bus is never touched.
exec python3 "$(dirname "$0")/fake_busctl.py" "$@"
