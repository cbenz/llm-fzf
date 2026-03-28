import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: 1200
    height: 720
    minimumWidth: 900
    minimumHeight: 560
    title: "Select a prompt"

    function applyCurrentSelection() {
        if (!promptBackend) {
            return;
        }
        if (promptList.currentItem) {
            promptBackend.acceptSelection();
        }
    }

    function handleEscape() {
        if (!promptBackend) {
            return;
        }
        if (filterField.text.length > 0) {
            filterField.text = "";
            filterField.forceActiveFocus();
            return;
        }
        promptBackend.cancelSelection();
    }

    function moveSelection(step) {
        if (!promptBackend) {
            return;
        }
        const count = promptBackend.filteredPromptNames.length;
        if (count <= 0) {
            return;
        }
        let nextIndex = promptList.currentIndex;
        if (nextIndex < 0) {
            nextIndex = 0;
        } else {
            nextIndex = Math.max(0, Math.min(count - 1, nextIndex + step));
        }
        promptList.currentIndex = nextIndex;
        promptBackend.setSelectedPrompt(promptBackend.filteredPromptNames[nextIndex]);
    }

    Item {
        id: keyboardScope
        anchors.fill: parent
        focus: true

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) {
                root.handleEscape();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.applyCurrentSelection();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Down) {
                root.moveSelection(1);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Up) {
                root.moveSelection(-1);
                event.accepted = true;
                return;
            }

            const hasPrintableText = event.text && event.text.length > 0;
            const hasNoModifiers = event.modifiers === Qt.NoModifier;
            if (hasPrintableText && hasNoModifiers && !filterField.activeFocus) {
                filterField.forceActiveFocus();
                filterField.insert(filterField.cursorPosition, event.text);
                event.accepted = true;
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.38

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    TextField {
                        id: filterField
                        Layout.fillWidth: true
                        placeholderText: "Filter prompts..."
                        selectByMouse: true
                        onTextChanged: {
                            if (promptBackend) {
                                promptBackend.updateFilter(text);
                            }
                        }
                        Keys.onReturnPressed: {
                            root.applyCurrentSelection();
                        }
                        Keys.onDownPressed: {
                            root.moveSelection(1);
                        }
                        Keys.onUpPressed: {
                            root.moveSelection(-1);
                        }
                        Keys.onEscapePressed: {
                            root.handleEscape();
                        }
                    }

                    ListView {
                        id: promptList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: promptBackend ? promptBackend.filteredPromptNames : []
                        focus: false
                        spacing: 2

                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: promptList.width
                            height: 36
                            color: ListView.isCurrentItem ? palette.highlight : "transparent"
                            radius: 4

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                text: modelData
                                color: palette.windowText
                                elide: Text.ElideRight
                                width: parent.width - 20
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    promptList.currentIndex = index;
                                    promptBackend.setSelectedPrompt(modelData);
                                }
                                onDoubleClicked: {
                                    promptList.currentIndex = index;
                                    promptBackend.setSelectedPrompt(modelData);
                                    promptBackend.acceptSelection();
                                }
                            }
                        }

                        onCurrentItemChanged: {
                            if (currentItem) {
                                promptBackend.setSelectedPrompt(currentItem.modelData);
                            }
                        }

                        Keys.onReturnPressed: {
                            root.applyCurrentSelection();
                        }

                        Keys.onEscapePressed: {
                            root.handleEscape();
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: palette.mid
            }

            Item {
                Layout.fillHeight: true
                Layout.fillWidth: true

                ScrollView {
                    anchors.fill: parent
                    clip: true

                    TextArea {
                        id: previewArea
                        readOnly: true
                        activeFocusOnPress: false
                        wrapMode: TextArea.Wrap
                        text: promptBackend ? promptBackend.previewText : ""
                        font.family: "monospace"
                        background: null
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(function () {
            filterField.forceActiveFocus();
        });
        if (!promptBackend) {
            return;
        }
        if (promptBackend.filteredPromptNames.length > 0) {
            promptList.currentIndex = 0;
            promptBackend.setSelectedPrompt(promptBackend.filteredPromptNames[0]);
        }
    }

    Shortcut {
        sequence: "Up"
        context: Qt.WindowShortcut
        onActivated: root.moveSelection(-1)
    }

    Shortcut {
        sequence: "Down"
        context: Qt.WindowShortcut
        onActivated: root.moveSelection(1)
    }

    Shortcut {
        sequence: "Return"
        context: Qt.WindowShortcut
        onActivated: root.applyCurrentSelection()
    }

    Shortcut {
        sequence: "Enter"
        context: Qt.WindowShortcut
        onActivated: root.applyCurrentSelection()
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: root.handleEscape()
    }

    Connections {
        target: promptBackend
        function onFilteredPromptNamesChanged() {
            if (!promptBackend) {
                promptList.currentIndex = -1;
                return;
            }
            if (promptBackend.filteredPromptNames.length > 0) {
                promptList.currentIndex = 0;
                promptBackend.setSelectedPrompt(promptBackend.filteredPromptNames[0]);
            } else {
                promptList.currentIndex = -1;
            }
        }
    }
}
