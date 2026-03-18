# AGENTS.md

Minimal voice dictation tool for Linux (speech-to-text, STT).

## Use case

- the user configures a keyboard shortcut (e.g. `mod+backspace`) in their desktop environment to run `./dictate.sh toggle`
- when the shortcut is pressed, the notification "🎤 Recording..." appears
- the user speaks for as long as they want
- the recording can be canceled by running `./dictate.sh cancel` (e.g. bound to another shortcut or run manually)
- when the same shortcut is pressed again: recording stops, the notification "⏳ Transcribing..." appears and stays visible for the whole transcription
- after processing, the transcribed text is inserted into the active text field (as if the user had typed it)
- the notification "⏳ Transcribing..." disappears

## Specs

### Functional specs

- the user starts dictation by running the script and stops it by running it again
- the user can configure a keyboard shortcut if they want (outside the script scope)
- the transcribed text is inserted into the active field without sending an equivalent "Enter" keypress
- the user can cancel an ongoing recording
- status notifications replace each other (only one visible notification at a time)

### Technical specs

- audio recording via `arecord` (S16_LE, 16 kHz, mono, WAV)
- transcription via `llm groq-whisper`
- keyboard result injection: copy text to **CLIPBOARD and PRIMARY** (`xclip -selection clipboard` and `xclip -selection primary`) followed by `xdotool key Shift-Insert`
  - CLIPBOARD for modern applications (VS Code, browsers)
  - PRIMARY for classic Unix applications (terminals, xterm, vim)
- notifications via `dunstify`
  - use notification IDs to replace and close the current notification (tags don't work for closing notifications)
- implemented in bash for simplicity, no persistent state, no daemonization
- use a subdirectory of the user XDG directory to store temporary files

## Docs

dunst:

- <https://dunst-project.org/documentation/>
- <https://dunst-project.org/documentation/dunst/>
- <https://dunst-project.org/documentation/guides/>
- <https://dunst-project.org/documentation/dunstify/>
- <https://dunst-project.org/documentation/faq/>
- <https://wiki.archlinux.org/title/Dunst>
