#!/usr/bin/env python3
# /// script
# requires-python = ">=3.14"
# dependencies = [
#     "PySide6>=6.8.0",
# ]
# ///
"""llm-text-transform-qt - LLM text transform with a Qt/QML prompt picker."""

import fcntl
import os
import pathlib
import shutil
import subprocess
import sys
import threading
import time

from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication, QWindow
from PySide6.QtQml import QQmlApplicationEngine

APP_NAME = "llm-text-transform"


class Notifier:
    def __init__(self, id_file: pathlib.Path) -> None:
        self.id_file = id_file

    def notify(self, message: str, timeout: int = 0) -> None:
        args = ["dunstify", "--printid", f"--app-name={APP_NAME}", "-t", str(timeout)]
        if self.id_file.exists():
            args.append(f"--replace-id={self.id_file.read_text().strip()}")
        result = subprocess.run(
            args + [APP_NAME, message], capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            self.id_file.write_text(result.stdout.strip())

    def close(self) -> None:
        if self.id_file.exists():
            notify_id = self.id_file.read_text().strip()
            subprocess.run(["dunstify", f"--close={notify_id}"], capture_output=True)
            self.id_file.unlink(missing_ok=True)


def get_state_dir() -> pathlib.Path:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    state_home = os.environ.get(
        "XDG_STATE_HOME", str(pathlib.Path.home() / ".local" / "state")
    )
    state_dir = pathlib.Path(runtime_dir or state_home) / APP_NAME
    state_dir.mkdir(parents=True, exist_ok=True)
    return state_dir


def detect_clipboard_tool() -> str | None:
    for tool_name in ("xclip", "xsel"):
        if shutil.which(tool_name):
            return tool_name
    return None


def read_primary_clipboard(clipboard_tool: str) -> str:
    if clipboard_tool == "xclip":
        command = ["xclip", "-o", "-selection", "primary"]
    else:
        command = ["xsel", "--output", "--primary"]
    result = subprocess.run(command, capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else ""


def write_both_clipboards(clipboard_tool: str, value: str) -> None:
    if clipboard_tool == "xclip":
        commands = [
            ["xclip", "-in", "-selection", "clipboard"],
            ["xclip", "-in", "-selection", "primary"],
        ]
    else:
        commands = [
            ["xsel", "--input", "--clipboard"],
            ["xsel", "--input", "--primary"],
        ]
    for command in commands:
        subprocess.run(command, input=value, text=True)


def paste_via_shift_insert(clipboard_tool: str, value: str) -> None:
    write_both_clipboards(clipboard_tool, value)
    hold_delay_seconds = float(
        os.environ.get("LLM_SHIFT_INSERT_HOLD_DELAY_SEC", "0.04")
    )
    subprocess.run(["xdotool", "keydown", "Shift"])
    time.sleep(hold_delay_seconds)
    subprocess.run(["xdotool", "key", "Insert"])
    time.sleep(hold_delay_seconds)
    subprocess.run(["xdotool", "keyup", "Shift"])


def list_prompt_names(prompt_dir: pathlib.Path) -> list[str]:
    return sorted(
        str(path.relative_to(prompt_dir)).removesuffix(".prompt.md")
        for path in prompt_dir.rglob("*.prompt.md")
    )


class PromptSelectorBackend(QObject):
    filteredPromptNamesChanged = Signal()
    previewTextChanged = Signal()
    selectedPromptChanged = Signal()
    finished = Signal()

    def __init__(self, prompt_dir: pathlib.Path) -> None:
        super().__init__()
        self.prompt_dir = prompt_dir
        self.all_prompt_names = list_prompt_names(prompt_dir)
        self.filtered_prompt_names = list(self.all_prompt_names)
        self.preview_text_value = "Select a prompt to preview."
        self.selected_prompt_value = ""

    @Property(list, notify=filteredPromptNamesChanged)
    def filteredPromptNames(self) -> list[str]:
        return self.filtered_prompt_names

    @Property(str, notify=previewTextChanged)
    def previewText(self) -> str:
        return self.preview_text_value

    @Property(str, notify=selectedPromptChanged)
    def selectedPrompt(self) -> str:
        return self.selected_prompt_value

    @Slot(str)
    def updateFilter(self, search_text: str) -> None:
        normalized = search_text.lower().strip()
        if not normalized:
            self.filtered_prompt_names = list(self.all_prompt_names)
        else:
            self.filtered_prompt_names = [
                prompt_name
                for prompt_name in self.all_prompt_names
                if normalized in prompt_name.lower()
            ]
        self.filteredPromptNamesChanged.emit()

    @Slot(str)
    def showPreview(self, prompt_name: str) -> None:
        prompt_file = self.prompt_dir / f"{prompt_name}.prompt.md"
        if prompt_file.exists():
            self.preview_text_value = prompt_file.read_text()
        else:
            self.preview_text_value = ""
        self.previewTextChanged.emit()

    @Slot(str)
    def setSelectedPrompt(self, prompt_name: str) -> None:
        self.selected_prompt_value = prompt_name
        self.selectedPromptChanged.emit()
        self.showPreview(prompt_name)

    @Slot()
    def acceptSelection(self) -> None:
        if self.selected_prompt_value:
            self.finished.emit()

    @Slot()
    def cancelSelection(self) -> None:
        self.selected_prompt_value = ""
        self.selectedPromptChanged.emit()
        self.finished.emit()


def run_qml_selector(prompt_dir: pathlib.Path) -> str:
    qml_file = pathlib.Path(__file__).with_name("llm-text-transform.qml")
    if not qml_file.exists():
        raise FileNotFoundError(f"Missing QML file: {qml_file}")

    application = QGuiApplication.instance()
    owns_application = application is None
    if application is None:
        application = QGuiApplication(sys.argv)

    backend = PromptSelectorBackend(prompt_dir)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("promptBackend", backend)
    engine.load(str(qml_file))

    if not engine.rootObjects():
        raise RuntimeError(f"Could not load QML UI from {qml_file}")

    root_object = engine.rootObjects()[0]
    if not isinstance(root_object, QWindow):
        raise RuntimeError("QML root object is not a QWindow")
    root_window = root_object
    backend.finished.connect(root_window.close)

    if owns_application:
        application.exec()
    else:
        # In this project we do not expect embedding in an existing event loop,
        # but keep the branch explicit for clarity.
        application.exec()

    return backend.selected_prompt_value


def run_processing(
    notifier: Notifier,
    clipboard_tool: str,
    prompt_name: str,
    system_prompt: str,
    input_text: str,
) -> None:
    spinner_frames = ("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
    stop_event = threading.Event()
    label = f'⏳ Processing "{prompt_name}"'

    def spinner_loop() -> None:
        index = 0
        while not stop_event.wait(0.15):
            notifier.notify(f"{label} {spinner_frames[index]}")
            index = (index + 1) % len(spinner_frames)

    spinner_thread = threading.Thread(target=spinner_loop, daemon=True)
    spinner_thread.start()

    try:
        result = subprocess.run(
            ["llm", "--system", system_prompt, f"<text>\n{input_text}\n</text>"],
            capture_output=True,
            text=True,
        )
    finally:
        stop_event.set()
        spinner_thread.join()

    if result.returncode == 0:
        paste_via_shift_insert(clipboard_tool, result.stdout)
        notifier.notify("✅ Result pasted", 1500)
        time.sleep(1.5)
        notifier.close()
    else:
        notifier.notify("❌ LLM processing failed", 5000)
        time.sleep(5)
        notifier.close()


def run_main() -> int:
    state_dir = get_state_dir()
    notifier = Notifier(state_dir / "notification.id")

    required_commands = ["llm", "dunstify", "xdotool"]
    missing_commands = [
        command for command in required_commands if not shutil.which(command)
    ]
    if missing_commands:
        notifier.notify(f"❌ Missing dependencies: {', '.join(missing_commands)}", 5000)
        print(
            f"Error: missing commands: {', '.join(missing_commands)}", file=sys.stderr
        )
        return 1

    clipboard_tool = detect_clipboard_tool()
    if clipboard_tool is None:
        notifier.notify("❌ Missing dependencies: xclip or xsel", 5000)
        print("Error: no clipboard tool found. Install xclip or xsel.", file=sys.stderr)
        return 1

    lock_file = open(state_dir / f"{APP_NAME}.lock", "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_file.close()
        return 0

    prompt_name = ""
    system_prompt = ""
    input_text = ""

    try:
        prompt_dir = pathlib.Path(
            os.environ.get(
                "LLM_FZF_PROMPT_DIR",
                str(pathlib.Path.home() / ".agents" / "prompts" / "desktop"),
            )
        )
        if not prompt_dir.is_dir():
            notifier.notify("❌ Prompt directory not found", 5000)
            print(
                f"Error: prompt directory does not exist: {prompt_dir}", file=sys.stderr
            )
            return 1

        input_text = read_primary_clipboard(clipboard_tool)
        if not input_text.strip():
            notifier.notify("❌ Primary clipboard is empty", 5000)
            print("Error: primary clipboard is empty.", file=sys.stderr)
            return 1

        prompt_name = run_qml_selector(prompt_dir)
        if not prompt_name:
            return 0

        prompt_file = prompt_dir / f"{prompt_name}.prompt.md"
        system_prompt = prompt_file.read_text()

    finally:
        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()

    run_processing(notifier, clipboard_tool, prompt_name, system_prompt, input_text)
    return 0


def main() -> None:
    raise SystemExit(run_main())


if __name__ == "__main__":
    main()
