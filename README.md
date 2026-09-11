# SimChoreographer

**Record the route once. Give your AI agent a quick way back to the screen it needs to inspect.**

SimChoreographer is a native macOS utility for closing the visual feedback loop in AI-assisted iOS development. Record the taps, typing, holds, and drags needed to reach a screen in Xcode Simulator, save the sequence with a name, and let your agent replay it from the command line after the next build.

The agent changes the app, builds and launches it, runs the saved route, then uses its screenshot tool to inspect the result and decide what to change next. SimChoreographer handles the repetitive navigation between launching the app and taking that next screenshot.

## Why we built it

Getting an AI agent to edit and build an app is only part of an iteration. To review the result, it often needs to reach a particular page, open a sheet, scroll to a section, or reproduce a gesture. Repeating that navigation by hand interrupts the feedback loop.

We built SimChoreographer to turn a demonstrated interaction into a named command an agent can reuse. It is useful for short development tasks where the route stays consistent while the screen under review changes: adjusting spacing, tuning a component, checking a populated form, or reviewing a screen reached through several steps.

- **Record by doing.** Navigate in Simulator as usual; no flow file to write before the first replay.
- **Use your existing app build.** No SDK, app instrumentation, or accessibility identifiers need adding to the iOS app.
- **Include the interaction that matters.** Record typing, scrolling by dragging, long presses, and hold-and-drag paths alongside taps.
- **Follow controls as they move.** Ordinary taps prefer a unique accessibility identifier or label/type match; strict mode stops when a target cannot be resolved.
- **Call it from an agent.** The CLI waits for playback to finish and returns JSON with a success or failure exit code.
- **Keep the workflow local.** No account, hosted service, or third-party runtime dependency. Recordings remain on your Mac.

## The development loop

1. **Record a route** such as “Open checkout preview” from a known starting screen.
2. **Ask the agent to make a change**, build the app, and launch it in the same Simulator.
3. **Replay the route** with `simchoreographerctl run "Open checkout preview"`.
4. **Take the next screenshot** using the agent’s existing capture tool, once the target screen is ready.
5. **Inspect and iterate.** The agent reviews the image, adjusts the app, and runs the route again.

For example, an instruction to your development agent could be:

> After each successful build, launch the app and wait for its home screen. Run `./build/simchoreographerctl run "Open checkout preview" --timeout 120` from the SimChoreographer folder. If playback succeeds, wait for the preview to finish loading, take a screenshot with your screenshot tool, and inspect the layout. If playback fails, inspect the current screen before continuing.

The CLI path above is relative to this repository; use its absolute path when your agent is working in a different project.

SimChoreographer replays input. Your agent or test tooling handles building, app setup, screenshots, and checking the outcome. A successful replay means the input sequence finished; it does not assert that the expected page appeared.

## Build and launch

Requires macOS 13+ and Xcode with Swift 5.9 or later. No Apple Developer membership or signing certificate is required for a local build.

```sh
git clone https://github.com/griches/SimChoreographer.git
cd SimChoreographer
./scripts/build.sh && open build/SimChoreographer.app
```

The build produces the app and `build/simchoreographerctl`. Launch the bundled app and grant its Accessibility and Input Monitoring permissions. See [Signing and macOS permissions](#signing-and-macos-permissions) if you need help with setup.

## Record and replay

1. Open an iOS device in Xcode Simulator.
2. In SimChoreographer, enable **Accessibility** and **Input Monitoring**. Approve SimChoreographer in System Settings → Privacy & Security. Relaunch if requested by macOS, then click Refresh.
3. Enter a sequence name, select the Simulator window, and click **Record input**.
4. Click, hold, drag, and type through the flow. Press **Command–Shift–Escape** to stop and save. This shortcut also cancels replay or its initial delay.
5. Select the saved sequence in the sidebar and click **Replay**. Set a start delay if needed.

Left-button presses, drag movements, and releases are saved with their timing. This supports clicks, long presses, swipes, drag scrolling, and long-press-and-drag gestures. Keep the entire gesture inside the selected Simulator window; leaving it or moving the window during a gesture stops recording and discards the unfinished gesture. Stopping before release also discards the unfinished gesture while retaining earlier completed input. The first input plays immediately after activation; later inputs retain their recorded intervals. Recording includes the whole Simulator window, including its toolbar; click the device display for iOS interactions.

Coordinates are stored in window-relative macOS points. Moving the window between recording and replay is supported; resizing it is rejected. Keep the same device, orientation, window title, scale, and app layout. Playback requires exactly one matching window title, raises that window, and checks its size, focus, and hit target before each click. During holds, SimChoreographer checks the target every 0.25 seconds. Cancellation, errors, and normal app quit release any synthetic held mouse button at its last playback position. Do not use the mouse during playback. It uses the real Mac pointer.

Keyboard recording supports typing, Return, Tab, arrows, and shortcuts with Command, Shift, Option, or Control. Each captured key-down (including repeat) replays as a complete press and release. Use the same Mac keyboard layout and enable Simulator’s **I/O → Keyboard → Connect Hardware Keyboard** for iOS typing. Simulator/macOS may handle shortcuts themselves. Playback stops if the selected Simulator window loses keyboard focus or opens a modal sheet. Existing tap-only recordings remain compatible; mixed recordings retain the `taps` JSON array with optional `keyCode`, `modifiers`, and `mousePhase` fields. New pointer events use `mousePhase: "down"`, `"drag"`, or `"up"`; absent `mousePhase` retains legacy click behavior. Recordings are limited to 10,000 total input events (each drag sample counts).

## Accessibility action map

While recording, **Last tapped element** shows the best-effort label, accessibility identifier and control type of the element under your last press. Select a saved sequence and expand **Recorded action map** to review its presses and key events. Details are captured on mouse-down, before a tap normally navigates away; drag samples do not trigger repeated inspection.

If the hit element has no label or identifier, SimChoreographer checks up to four enclosing elements within the same window. Such results are marked as coming from an enclosing element. Inspection has a short time budget; unavailable details do not stop recording. Custom views or incomplete Simulator accessibility trees may expose only a type or no useful details. Older recordings remain playable but have no captured metadata; record a new sequence to add it.

`simchoreographerctl list` includes optional `element` objects on recorded mouse-down events, with `label`, `identifier`, `role`, and `ancestorDepth` fields. This gives an agent context for the recorded route. It is a snapshot of the elements you pressed, not a complete live screen tree, and ordinary taps now prefer a unique accessibility match before falling back to coordinates. No changes to the iOS app are required; descriptive accessibility labels and stable identifiers improve the results.

### Element-first playback

For ordinary taps, replay searches the selected Simulator window for the recorded identifier first, then a unique exact label + control type. It taps the matched element’s current centre, keeping press and release at the same point. Duplicate identifiers are treated as ambiguous; an incomplete or timed-out search never counts as a unique match. Off-screen, disabled or covered targets are rejected. There is no automatic scrolling.

By default, a missing or ambiguous target falls back to the recorded coordinates. Enable **Strict element targeting for taps** beside Replay, or pass `--strict-elements` to the CLI, to stop instead. Strict mode also stops on ordinary taps without metadata, including old recordings. Metadata borrowed from enclosing elements is descriptive only and cannot relocate a tap. Completion replies report element targets and coordinate fallbacks.

Holds, drags, and presses containing keyboard input retain their original coordinates and paths, including in strict mode. Device/window size checks still apply. Lookup may add time between actions; screenshot or assertion checks remain the agent’s responsibility.

## Agent interface

**Allow local AI agents to run sequences** is enabled by default each launch. The app must remain open. You can turn the toggle off to disable agent access for the current session.

```sh
./build/simchoreographerctl list
./build/simchoreographerctl status
./build/simchoreographerctl run "Login flow"
./build/simchoreographerctl run "Login flow" --delay 3 --timeout 120
./build/simchoreographerctl run "Login flow" --strict-elements
./build/simchoreographerctl run <recording-uuid>
./build/simchoreographerctl key return
./build/simchoreographerctl key cmd+a
./build/simchoreographerctl text "Hello, world!"
./build/simchoreographerctl stop
```

Responses are JSON. `run` waits until playback finishes. Exit codes: `0` success, `1` failure/cancellation, `2` timeout. Duplicate names require a recording UUID. Timeout does **not** cancel playback; issue `stop` to cancel. Commands not picked up within ten seconds expire, preventing an old queued run from starting on a later launch. A run completion means input events were posted, not that the app reached an expected state. Agents should verify results separately using screenshots, accessibility, or XCTest assertions.

### Send a key without recording

An AI agent can send a single key or shortcut directly through SimChoreographer:

```sh
./build/simchoreographerctl key return
./build/simchoreographerctl key shift+tab
./build/simchoreographerctl key cmd+a
./build/simchoreographerctl key escape --window "iPhone 17 – iOS 27.0"
```

The app activates the Simulator, checks keyboard focus, sends the press and release (including modifier releases), and returns JSON. Nothing is added to saved recordings. Exactly one Simulator window must match; with multiple windows, supply its exact title using `--window`. Requests are rejected while recording or playback is active, when agent control is off, or if permissions/focus checks fail. `stop` or Command–Shift–Escape can cancel before delivery.

Use **I/O → Keyboard → Connect Hardware Keyboard** in Simulator for iOS typing. Supported keys include letters, digits, Return/Enter, Tab, Escape, Space, Backspace/Delete, ForwardDelete, arrows, Home/End, PageUp/PageDown, F1–F12 and named punctuation; see `--help` for the full list. Modifiers are `cmd`/`command`, `ctrl`/`control`, `option`/`alt`, `shift` and `fn`. Names are case-insensitive: use `shift+a` to hold Shift, rather than uppercase `A`. Letter and punctuation names refer to physical US keyboard positions; the active keyboard layout determines the resulting character. This is a key press, not arbitrary text entry or a held-key duration. Simulator or macOS may handle shortcuts themselves.

Both app permissions are required, and **Allow local AI agents to run sequences** also controls direct key requests. Success means the events were sent, not that the app handled them; the agent should verify the result. `--timeout` and JSON exit codes work as for `run`. The file command schema adds optional `key` and `windowTitle` fields for `action: "key"`.

### Send a string

```sh
./build/simchoreographerctl text 'Hello, world!'
./build/simchoreographerctl text 'Café ☕️' --window 'iPhone 17 – iOS 27.0'
```

Focus the intended text field first, then call `text`. SimChoreographer sends Unicode keyboard events in small batches, preserving spaces, case, punctuation and Unicode characters without using the clipboard. The command waits for completion and returns JSON with the usual exit codes. Unicode handling depends on the receiving app; verify the resulting field rather than treating event delivery as confirmation that the text was accepted. Newlines and tabs are passed through as text, but a field may handle them as submission or navigation; use `key return` or `key tab` for explicit key actions.

The same agent toggle, permissions, single-window selection and busy-state checks apply as for `key`. Focus is checked between batches. `stop` or Command–Shift–Escape cancels the remaining text; text already entered is not undone, and the reply reports how many UTF-16 units were sent. Input is limited to 1–10,000 UTF-16 units; empty strings and NUL characters are rejected. `--timeout` does not cancel an in-progress request.

Use shell quoting appropriate to your string, or pass the string as a single argument through an agent's subprocess API. Text is not added to saved recordings or echoed into the app status/reply, but it is present in the local command file until consumed (and may be visible in shell history/process arguments). The command schema adds optional `text` for `action: "text"`; `windowTitle` remains optional. No new permissions are required.

## Delete recordings

Select a recording and use **Delete recording** below the sidebar, press Delete while the list has focus, or right-click a recording and choose **Delete recording**. The detail view also has a Delete button. Deletion saves immediately and is disabled during recording/playback. **Undo Delete** restores the most recently deleted recording until another deletion or app quit.

## Getting repeatable results

Use the same Simulator device, orientation, scale, window size, and keyboard layout. Start each run on the same page with the same test data and login state. Moving the Simulator window between runs is supported; resizing it requires a new recording.

Ordinary taps prefer accessibility targets; coordinate fallback and gestures use window-relative coordinates. If a control moves and has no reliable accessibility match, record the route again. Allow time for loading and animations, and have the agent verify the target page before judging its screenshot. This makes the tool best suited to short, stable routes during local development.

The Simulator must be available in the foreground during playback, which uses the Mac’s actual pointer and keyboard input. Avoid interacting with the Mac while a sequence runs. **Command–Shift–Escape** stops playback, including a pending delay or held gesture.

Right-button gestures, multi-touch/pinch gestures, held-key durations, and IME/text composition are not supported. Screenshot capture, assertions, automatic build orchestration, and the outer iteration loop belong to the agent or other tooling; SimChoreographer does not provide them. The agent interface is a CLI, with no MCP server required or included.

## Privacy

- No network service, telemetry, cloud storage, or third-party dependencies.
- Accessibility is used to find Simulator windows, check click targets, read their labels/identifiers/types, and post mouse and keyboard events.
- Input Monitoring listens for mouse down/drag/up and keyboard events only while recording or replaying. Key codes and modifiers are saved only while the selected Simulator window has keyboard focus. The stop shortcut is never saved. These records can reveal typed text; avoid entering passwords or other secrets during recording.
- Accessibility labels and identifiers can contain app content and are included in agent list replies. The inspector does not read element values such as text-field contents.
- No screen capture permission is requested and no screenshots are recorded.
- Sequence names, Simulator window titles, coordinates, key codes, modifier flags, timing, and captured accessibility metadata are stored in `~/Library/Application Support/Tapper/recordings.json`.
- The same folder holds command/reply files. Directories use mode `700`; files use `600`. Agent control permits programs running under your user account to request playback or direct key/text input. It is enabled by default on launch and can be disabled for the current session.
- Delete sequences in the app, or quit SimChoreographer and remove its Application Support folder to erase all saved data. Replies from timed-out clients can remain in `replies/` and may be deleted when the app is closed.

## Signing and macOS permissions

The build script uses your Apple Development certificate if exactly one is available. Otherwise, it automatically creates an **ad hoc local build**. It remembers this choice in `.build/tapper-signing-identity`. Ad hoc builds work locally, but macOS privacy permissions may need reapproval after rebuilding. A consistent development certificate avoids changing the app identity on every build.

To explicitly select a certificate, run `security find-identity -v -p codesigning`, then supply the certificate name or hash:

```sh
TAPPER_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build.sh
```

To force an ad hoc build, use `TAPPER_SIGNING_IDENTITY=- ./scripts/build.sh`. The older `TAPPER_` environment-variable name is retained for compatibility. Signing certificates and the local identity cache are not included in this repository. These are local development builds, not notarized releases.

If changing signing identities leaves an enabled permission unrecognised, follow the targeted reset instructions below. The app’s **Show this copy in Finder** button identifies the correct bundle; permission status refreshes when the app becomes active.

### If enabled permissions are still rejected

A stale macOS privacy record can retain an old ad hoc build’s code hash even after toggling the permission. If the app remains untrusted after switching to development signing, quit SimChoreographer and reset **only its** records:

```sh
tccutil reset Accessibility com.garyriches.tapper
tccutil reset ListenEvent com.garyriches.tapper
```

Reopen SimChoreographer, request both permissions again, and enable its fresh entries in System Settings. Follow macOS’s Quit & Reopen instruction for Input Monitoring, then Refresh. These commands do not delete recordings or change other apps’ permissions. They revoke SimChoreographer’s existing approvals; the user must grant them again. A tick and a populated Simulator picker verify Accessibility; starting a recording verifies that the input event listener can be created.

### Compatibility with Tapper

SimChoreographer was previously named Tapper. Its bundle identifier (`com.garyriches.tapper`), internal executable name (`Tapper`), and Application Support folder (`Tapper`) are intentionally retained so existing recordings and privacy permissions carry forward. Swift target names also retain their original names. `build/tapperctl` remains available for existing agent scripts; new scripts can use `build/simchoreographerctl`. The build script makes the old `build/Tapper.app` path an alias for the renamed app.

## Validation

```sh
swift test
./scripts/build.sh
```

Automated tests cover coordinate/timing validation, storage round trips, file permissions, preservation of corrupt storage, accessibility metadata compatibility, identifier/label matching, ambiguous and incomplete searches, ordinary-tap classification, and strict-mode command compatibility. Manual validation with macOS permissions granted is required for actual recording and replay:

- Record taps on labelled buttons and an unlabelled area; check **Last tapped element**, the saved **Recorded action map**, and `simchoreographerctl list`. Enclosing-element fallbacks should be marked.
- Record a tap into a text field, type mixed-case text, press Tab/Return, and stop using the global shortcut while Simulator is active.
- Switch to another Simulator window or app while recording; confirm its typing is excluded.
- Replay a shortcut and cancel during a delay; confirm no modifiers remain held.
- Delete a recording, undo it, then relaunch and verify the saved list.
- Record and replay a swipe, a stationary long press, and a hold followed by dragging.
- Cancel playback during a long hold and verify the mouse button is released.
- Stop recording during a drag and verify only the unfinished gesture is discarded.
- Move a labelled control within the same-sized app window and replay: verify the tap follows it. Test duplicate/missing labels with strict mode (stop) and default mode (coordinate fallback).
- Relaunch SimChoreographer and replay the saved sequence from both UI and CLI.
- Move the Simulator window and repeat; resize it and confirm rejection.
- Cover the tap location or switch focus during a delay and confirm playback stops.
- Cancel during a delay using the shortcut and `simchoreographerctl stop`.

## License

MIT. See [LICENSE](LICENSE).
