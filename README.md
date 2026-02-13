# Why this exists

This is a fork of barik which is not meant to merge, but to include my personal
preferences. It also fixes the massive battery drain that was polling aerospace
every 0.1 seconds by using aerospace callbacks.

# Usage

If you wish to use this, you will have to compile and install it from source.

``` bash
> xcodebuild -project Barik.xcodeproj \
  -scheme Barik \
  -configuration Release \
  -derivedDataPath ./build \
  build
> cp -R ./build/Build/Products/Release/Barik.app /Applications/
```

This also depends on [a branch of aerospace which is yet to merge](https://github.com/nikitabobko/AeroSpace/pull/1918)

You will have to install it locally for everything to work properly.
