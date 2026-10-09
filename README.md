# PILIVE

Standalone split of the original app. Original repository untouched. Version1.0.0 is the split packaging version.

## Dual-mode operation

Run `bash app-store.sh run`. With an active desktop session, the launcher uses the graphical path. Without one it offers a terminal management menu. A desktop installed on disk is not enough: DISPLAY or WAYLAND_DISPLAY must identify an active session. Terminal mode does not emulate the GUI application.

PILIVE offers status/config/start/pause/resume/stop in a real terminal menu, and yad/zenity controls when a display and those tools exist. Broadcasting the screen still requires an active X11 display plus ffmpeg and x11-utils. Wayland alone isn't X11. No desktop on headless OS means no screen to broadcast, not a fake replacement video source.

Security fixes in the split: data-only config parser (old config is no longer executed as shell); configuration/log permissions0600; hidden stream-key prompts; no key printed in log/default prompts; quoted ffmpeg arguments instead of sh -c. Streaming destination may still be visible to the local OS in ffmpeg process arguments. Use a trusted single-user host. Command error output is suppressed rather than logged with the key; check display/dependencies first. Do not leave the stream unattended.

Install only checks syntax. Run doesn't install ffmpeg automatically. Linux packaging and mocked CLI/security checks pass; Raspberry Pi hardware, real broadcasting and non-Linux systems untested. No stream was started during tests.

## Fullscreen Store launch

Version 1.0.1 adds a full-terminal interface when launched through the Store. Python 3 with curses and an interactive terminal are required. The original source remains available directly. Arrow keys select, Enter opens, and Q/Esc returns. Original commands temporarily take over the terminal for their prompts and output, then return to the full-terminal menu. Nested original prompts remain plain; they are not captured or rewritten. Passwords, sudo, confirmations, package changes and original limitations retain their old behavior. No administrative/package/transfer action ran during validation. Linux terminal checks passed; physical Raspberry Pi and non-Linux systems are untested.
