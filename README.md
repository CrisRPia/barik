# Why this exists

This is a fork of barik which is not meant to merge, but to include my personal
preferences. It also fixes the massive battery drain that was polling aerospace
every 0.1 seconds by using aerospace callbacks.

# Usage

If you wish to use this, you will have to compile and install it from source.

``` bash
xcodebuild -project Barik.xcodeproj \
  -scheme Barik \
  -configuration Release \
  -derivedDataPath ./build \
  build

cp -R ./build/Build/Products/Release/Barik.app /Applications/
```

This also depends on [a branch of aerospace which is yet to merge](https://github.com/nikitabobko/AeroSpace/pull/1918)

You will have to install it locally for everything to work properly.

Once installed, you can tell this barik to refresh by sending a message
to $TMPDIR/barik.fifo.

For instance:

```toml
on-focus-changed = [
  'exec-and-forget timeout 1 $(printf "refresh" > $TMPDIR/barik.fifo)',
]
exec-on-workspace-change = [
  '/bin/zsh -c "timeout 1 $(printf refresh > $TMPDIR/barik.fifo)"',
]
```

For the lowest possible update latency, you may want to call the callback directly
upon executing a window move command.

```toml
cmd-shift-h = [
  "move left",
  'exec-and-forget /bin/zsh -c "timeout 1 $(printf refresh > $TMPDIR/barik.fifo)"'
]
cmd-shift-j = [
  "move down",
  'exec-and-forget /bin/zsh -c "timeout 1 $(printf refresh > $TMPDIR/barik.fifo)"'
]
cmd-shift-k = [
  "move up",
  'exec-and-forget /bin/zsh -c "timeout 1 $(printf refresh > $TMPDIR/barik.fifo)"'
]
cmd-shift-l = [
  "move right",
  'exec-and-forget /bin/zsh -c "timeout 1 $(printf refresh > $TMPDIR/barik.fifo)"'
]
```

# Example

In this version of barik, the position of window icons in the bar represent their
order in the tree. This is useful to keep track of one's position within an accordion.

https://github.com/user-attachments/assets/d9b8b029-2d65-4cdc-9588-75c55f6225dd
