#!/bin/bash
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:`pwd`/flutter/bin"
flutter config --enable-web
flutter build web --release --no-tree-shake-icons
