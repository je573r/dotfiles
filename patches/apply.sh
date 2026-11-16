#!/bin/bash
# run this after every end4 update, applies everything against ~
cd "$(dirname "$0")" || exit 1
for p in *.patch; do
    echo "== $p"
    patch -p1 -d "$HOME" -N -r - < "$p"
done
echo "done. if something failed the file probably changed upstream, fix by hand (see readme)"
