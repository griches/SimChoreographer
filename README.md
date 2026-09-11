# SimChoreographer

A native macOS app that records clicks, holds, drags, and key presses in an Xcode iOS Simulator window and replays named sequences, with a CLI for local AI agents. Requires macOS 13+ and Xcode/Swift 5.9+ to build. No dependencies.

## Build and launch

No Apple Developer membership or signing certificate is required for a local build.

```sh
git clone https://github.com/griches/SimChoreographer.git
cd SimChoreographer
./scripts/build.sh && open build/SimChoreographer.app
```

The app is created only after the build succeeds. The `&&` prevents trying to open a missing app if a build fails. The build also produces `build/simchoreographerctl`. Open `Package.swift` in Xcode to edit the project; launch the bundled app for permission setup rather than the bare Swift executable.

### Signing and macOS permissions

The build script uses your Apple Development certificate if exactly one is available. Otherwise, it automatically creates an **ad hoc local build**. It remembers this choice in `.build/tapper-signing-identity`. Ad hoc builds work locally, but macOS privacy permissions may need reapproval after rebuilding. A consistent development certificate avoids changing the app identity on every build.

To explicitly select a certificate, run `security find-identity -v -p codesigning`, then supply the certificate name or hash:

```sh
TAPPER_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build.sh
```

To force an ad hoc build, use `TAPPER_SIGNING_IDENTITY=- ./scripts/build.sh`. The older `TAPPER_` environment-variable name is retained for compatibility. Signing certificates and the local identity cache are not included in this repository. These are local development builds, not notarized releases.

If changing signing identities leaves an enabled permission unrecognised, follow the targeted reset instructions below. The app’s **Show this copy in Finder** button identifies the correct bundle; permission status refreshes when the app becomes active.

### Compatibility with Tapper

SimChoreographer was previously named Tapper. Its bundle identifier (`com.garyriches.tapper`), internal executable name (`Tapper`), and Application Support folder (`Tapper`) are intentionally retained so existing recordings and privacy permissions carry forward. Swift target names also retain their original names. `build/tapperctl` remains available for existing agent scripts; new scripts can use `build/simchoreographerctl`. The build script makes the old `build/Tapper.app` path an alias for the renamed app.

## If enabled permissions are still rejected

A stale macOS privacy record can retain an old ad hoc build’s code hash even after toggling the permission. If the app remains untrusted after switching to development signing, quit SimChoreographer and reset **only its** records:

```sh
tccutil reset Accessibility com.garyriches.tapper
tccutil reset ListenEvent com.garyriches.tapper
```

Reopen SimChoreographer, request both permissions again, and enable its fresh entries in System Settings. Follow macOS’s Quit & Reopen instruction for Input Monitoring, then Refresh. These commands do not delete recordings or change other apps’ permissions. They revoke SimChoreographer’s existing approvals; the user must grant them again. A tick and a populated Simulator picker verify Accessibility; starting a recording verifies that the input event listener can be created.

## Record and replay

1. Open an iOS device in Xcode Simulator.
2. In SimChoreographer, enable **Accessibility** and **Input Monitoring**. Approve SimChoreographer in System Settings → Privacy & Security. Relaunch if requested by macOS, then click Refresh.
3. Enter a sequence name, select the Simulator window, and click **Record input**.
4. Click, hold, drag, and type through the flow. Press **Command–Shift–Escape** to stop and save. This shortcut also cancels replay or its initial delay.
5. Select the saved sequence in the sidebar and click **Replay**. Set a start delay if needed.

Left-button presses, drag movements, and releases are saved with their timing. This supports clicks, long presses, swipes, drag scrolling, and long-press-and-drag gestures. Keep the entire gesture inside the selected Simulator window; leaving it or moving the window during a gesture stops recording and discards the unfinished gesture. Stopping before release also discards the unfinished gesture while retaining earlier completed input. The first input plays immediately after activation; later inputs retain their recorded intervals. Recording includes the whole Simulator window, including its toolbar; click the device display for iOS interactions.

Coordinates are stored in window-relative macOS points. Moving the window between recording and replay is supported; resizing it is rejected. Keep the same device, orientation, window title, scale, and app layout. Playback requires exactly one matching window title, raises that window, and checks its size, focus, and hit target before each click. During holds, SimChoreographer checks the target every 0.25 seconds. Cancellation, errors, and normal app quit release any synthetic held mouse button at its last playback position. Do not use the mouse during playback. It uses the real Mac pointer.

Keyboard recording supports typing, Return, Tab, arrows, and shortcuts with Command, Shift, Option, or Control. Each captured key-down (including repeat) replays as a complete press and release. Use the same Mac keyboard layout and enable Simulator’s **I/O → Keyboard → Connect Hardware Keyboard** for iOS typing. Simulator/macOS may handle shortcuts themselves. Playback stops if the selected Simulator window loses keyboard focus or opens a modal sheet. Existing tap-only recordings remain compatible; mixed recordings retain the `taps` JSON array with optional `keyCode`, `modifiers`, and `mousePhase` fields. New pointer events use `mousePhase: "down"`, `"drag"`, or `"up"`; absent `mousePhase` retains legacy click behavior. Recordings are limited to 10,000 total input events (each drag sample counts).

## Delete recordings

Select a recording and use **Delete recording** below the sidebar, press Delete while the list has focus, or right-click a recording and choose **Delete recording**. The detail view also has a Delete button. Deletion saves immediately and is disabled during recording/playback. **Undo Delete** restores the most recently deleted recording until another deletion or app quit.

## Agent interface

**Allow local AI agents to run sequences** is enabled by default each launch. The app must remain open. You can turn the toggle off to disable agent access for the current session.

```sh
./build/simchoreographerctl list
./build/simchoreographerctl status
./build/simchoreographerctl run "Login flow"
./build/simchoreographerctl run "Login flow" --delay 3 --timeout 120
./build/simchoreographerctl run <recording-uuid>
./build/simchoreographerctl stop
```

Responses are JSON. `run` waits until playback finishes. Exit codes: `0` success, `1` failure/cancellation, `2` timeout. Duplicate names require a recording UUID. Timeout does **not** cancel playback; issue `stop` to cancel. Commands not picked up within ten seconds expire, preventing an old queued run from starting on a later launch. A run completion means input events were posted, not that the app reached an expected state. Agents should verify results separately using screenshots, accessibility, or XCTest assertions.

## Privacy

- No network service, telemetry, cloud storage, or third-party dependencies.
- Accessibility is used to find Simulator windows, check click targets, and post mouse and keyboard events.
- Input Monitoring listens for mouse down/drag/up and keyboard events only while recording or replaying. Key codes and modifiers are saved only while the selected Simulator window has keyboard focus. The stop shortcut is never saved. These records can reveal typed text; avoid entering passwords or other secrets during recording.
- No screen capture permission is requested and no screenshots are recorded.
- Sequence names, Simulator window titles, coordinates, key codes, modifier flags, and timing are stored in `~/Library/Application Support/Tapper/recordings.json`.
- The same folder holds command/reply files. Directories use mode `700`; files use `600`. Agent control permits programs running under your user account to request playback. It is enabled by default on launch and can be disabled for the current session.
- Delete sequences in the app, or quit SimChoreographer and remove its Application Support folder to erase all saved data. Replies from timed-out clients can remain in `replies/` and may be deleted when the app is closed.

## Validation

```sh
swift test
./scripts/build.sh
```

Automated tests cover coordinate/timing validation, storage round trips, file permissions, and preservation of corrupt storage. Manual validation with macOS permissions granted is required for actual recording and replay:

- Record a tap into a text field, type mixed-case text, press Tab/Return, and stop using the global shortcut while Simulator is active.
- Switch to another Simulator window or app while recording; confirm its typing is excluded.
- Replay a shortcut and cancel during a delay; confirm no modifiers remain held.
- Delete a recording, undo it, then relaunch and verify the saved list.
- Record and replay a swipe, a stationary long press, and a hold followed by dragging.
- Cancel playback during a long hold and verify the mouse button is released.
- Stop recording during a drag and verify only the unfinished gesture is discarded.
- Relaunch SimChoreographer and replay the saved sequence from both UI and CLI.
- Move the Simulator window and repeat; resize it and confirm rejection.
- Cover the tap location or switch focus during a delay and confirm playback stops.
- Cancel during a delay using the shortcut and `simchoreographerctl stop`.

Right-button gestures, multi-touch/pinch gestures, held-key durations, IME/text composition, screenshots, assertions, loops, and an MCP server are not implemented.

## License

MIT. See [LICENSE](LICENSE).
