#!/bin/bash
# Builds the install website into site/: the universal app zip and the status line script next to index.html and install.sh.
# Deploy the site/ folder to Vercel.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/make-app.sh --universal
rm -f site/TokenCoach.zip
ditto -c -k --keepParent .build/TokenCoach.app site/TokenCoach.zip
cp scripts/statusline.sh site/statusline.sh
echo "Site ready in site/ ($(du -h site/TokenCoach.zip | cut -f1) zip)"
