# Dictate

Dictate is a very opinionated speech-to-text (STT) script.

It is not configurable, it only integrates several tools.
The philosophy is simple: copy-paste the script and adapt it to your own workflow.
If you want to use `whisper.cpp` or `faster-whisper` instead, you can modify the script.

There is no server, no daemon.

Transcription is done by the OpenAI Whisper model via the remote [Groq API](https://groq.com/) (free tier available).

## How it works

First, the user configures a keyboard shortcut (e.g. `mod+backslash`) in their desktop environment to start and stop the recording, and another one (e.g. `mod+shift+backslash`) to cancel it.

When the shortcut is pressed, recording starts and the user speaks for as long as they want.
The recording can be canceled by running the other shortcut, or the first shortcut can be pressed again to stop the recording and start the transcription.
After processing, the transcribed text is inserted into the active text field (as if the user had typed it).

## Installation

Install the following dependencies:

- arecord (alsa-utils)
- llm: <https://github.com/simonw/llm>
- llm-groq-whisper: <https://github.com/simonw/llm-groq-whisper>
- xclip: <https://github.com/astrand/xclip>
- xdotool: <https://github.com/jordansissel/xdotool>
- dunst (dunstify): <https://github.com/dunst-project/dunst>

Create an account on [Groq](https://groq.com/) and get an API key.

[Install `llm`](https://llm.datasette.io/en/stable/setup.html) and its [`llm-groq-whisper` plugin](https://github.com/simonw/llm-groq-whisper), then configure its API key:

```bash
llm install llm-groq-whisper
llm keys set groq
# Paste key here
```

Copy [`dictate.sh`](./dictate.sh) to `~/.local/bin` (or another directory you prefer).

Configure a keyboard shortcut in your desktop environment to run `./dictate.sh toggle` (and optionally another one for `./dictate.sh cancel`).

For example, I use i3 and added the following lines to `~/.config/i3/config`:

```text
bindsym $mod+backslash exec --no-startup-id ~/.local/bin/dictate.sh toggle
bindsym $mod+Shift+backslash exec --no-startup-id ~/.local/bin/dictate.sh cancel
```

## Usage

```text
Usage: dictate.sh <command>

Commands:
  start   Start recording
  stop    Stop recording and transcribe
  cancel  Cancel recording
  toggle  Start if idle, stop if recording
  status  Show status (idle or working)
```
