import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: pane

  property var notesModel: []
  property var categories: []
  property string filter: "all"
  property string draftText: ""
  property bool editorFocused: false
  property bool readOnly: false
  property string readOnlyMessage: ""
  property string currentPath: ""
  property string foldersLabel: ""
  property string omawriteLabel: ""
  property color foreground: "#dddddd"
  property string fontFamily: ""
  property var roleColorFor: null
  property Item searchField: null
  property var relayKey: null

  signal noteChosen(string path)
  signal pinRequested(string path)
  signal draftEdited(string text)
  signal saveRequested()
  signal foldersRequested()
  signal omawriteRequested()
  signal noteMenuRequested(string path, real x, real y)

  function focusEditor() {
    editor.forceActiveFocus()
  }

  function editorText() {
    return editor.text
  }

  function accentFor(note) {
    var role = note && note.colorRole ? String(note.colorRole) : ""
    if (!role && note) {
      var cats = pane.categories || []
      for (var i = 0; i < cats.length; i++) {
        if (cats[i] && cats[i].id === note.categoryId && cats[i].colorRole) {
          role = String(cats[i].colorRole)
          break
        }
      }
    }
    if (!role) role = "yellow"
    if (pane.roleColorFor) return pane.roleColorFor(role)
    return "#d6b25e"
  }

  readonly property var visibleNotes: {
    var src = pane.notesModel || []
    var list = []
    var filterId = String(pane.filter || "all")
    for (var i = 0; i < src.length; i++) {
      var note = src[i]
      if (!note) continue
      if (filterId && filterId !== "all" && filterId !== "favorites" && String(note.categoryId || "") !== filterId) continue
      list.push(note)
    }
    return list
  }

  onDraftTextChanged: {
    if (editor.text === pane.draftText) return
    pane.applyingDraft = true
    editor.text = pane.draftText
    pane.applyingDraft = false
  }

  property bool applyingDraft: false

  Row {
    anchors.fill: parent
    spacing: Style.space(12)

    Rectangle {
      id: listColumn
      width: Style.space(320)
      height: parent.height
      radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
      color: Util.alpha(pane.foreground, 0.025)
      border.width: 1
      border.color: Util.alpha(pane.foreground, 0.14)
      clip: true

      Item {
        id: listHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Style.space(10)
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        height: Math.max(foldersButton.implicitHeight, Style.space(28))

        Button {
          id: foldersButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: pane.foldersLabel
          bordered: true
          onClicked: pane.foldersRequested()
        }
      }

      ListView {
        id: noteList
        anchors.top: listHeader.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        clip: true
        spacing: Style.space(6)
        boundsBehavior: Flickable.StopAtBounds
        model: pane.visibleNotes

        delegate: Rectangle {
          id: noteRow
          required property var modelData
          readonly property color rowAccent: pane.accentFor(modelData)
          readonly property bool selected: String(modelData.path || "") === String(pane.currentPath || "")
          readonly property bool pinned: (Number(modelData.pinOrder) || 0) > 0
          width: noteList.width
          height: Style.space(46)
          radius: 5
          color: (noteMouse.containsMouse || selected)
            ? Util.alpha(rowAccent, 0.16)
            : Util.alpha(pane.foreground, 0.03)
          border.width: 1
          border.color: (noteMouse.containsMouse || selected)
            ? rowAccent
            : Util.alpha(pane.foreground, 0.1)

          Rectangle {
            width: Style.space(4)
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: Style.space(4)
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(8)
            radius: width / 2
            color: noteRow.rowAccent
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(16)
            anchors.rightMargin: pinButton.width + Style.space(8)
            spacing: Style.space(8)

            Text {
              width: parent.width - (noteBadge.visible ? noteBadge.width + Style.space(8) : 0)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: modelData.title || ""
              color: (noteMouse.containsMouse || noteRow.selected) ? noteRow.rowAccent : pane.foreground
              font.family: pane.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Rectangle {
              id: noteBadge
              visible: String(modelData.badgeText || "").length > 0
              height: Style.space(16)
              width: noteBadgeText.implicitWidth + Style.space(8)
              radius: 3
              color: Util.alpha(noteRow.rowAccent, 0.2)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: noteBadgeText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String(modelData.badgeText || "")
                color: noteRow.rowAccent
                font.family: pane.fontFamily
                font.pixelSize: Style.font.caption - 2
                font.bold: true
              }
            }
          }

          MouseArea {
            id: noteMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function (mouse) {
              if (mouse.button === Qt.RightButton) {
                var pos = noteMouse.mapToItem(pane, mouse.x, mouse.y)
                pane.noteMenuRequested(String(modelData.path || ""), pos.x, pos.y)
                return
              }
              pane.noteChosen(String(modelData.path || ""))
            }
          }

          MouseArea {
            id: pinButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.space(8)
            width: Style.space(22)
            height: Style.space(22)
            z: 2
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pane.pinRequested(String(modelData.path || ""))

            Text {
              anchors.centerIn: parent
              text: "󰐃"
              color: noteRow.pinned
                ? noteRow.rowAccent
                : (pinButton.containsMouse ? pane.foreground : Color.muted)
              font.family: pane.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }

    Rectangle {
      id: editorPane
      width: parent.width - listColumn.width - parent.spacing
      height: parent.height
      radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
      color: Util.alpha(pane.foreground, 0.025)
      border.width: 1
      border.color: editor.activeFocus
        ? (pane.roleColorFor ? pane.roleColorFor("green") : pane.foreground)
        : Util.alpha(pane.foreground, 0.14)
      clip: true

      Button {
        id: omawriteButton
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(8)
        z: 2
        visible: String(pane.draftText || "").trim().length > 0 || String(pane.currentPath || "").length > 0
        text: pane.omawriteLabel
        bordered: true
        onClicked: pane.omawriteRequested()
      }

      ScrollView {
        id: editorScroll
        anchors.fill: parent
        anchors.margins: Style.space(8)
        anchors.topMargin: omawriteButton.visible ? omawriteButton.height + Style.space(12) : Style.space(8)

        TextArea {
          id: editor
          width: Math.max(0, editorScroll.availableWidth)
          wrapMode: TextArea.Wrap
          selectByMouse: true
          readOnly: pane.readOnly
          color: pane.foreground
          placeholderText: pane.readOnlyMessage
          placeholderTextColor: Color.muted
          selectionColor: pane.roleColorFor ? Util.alpha(pane.roleColorFor("green"), 0.35) : Util.alpha(pane.foreground, 0.25)
          selectedTextColor: pane.foreground
          font.family: pane.fontFamily
          font.pixelSize: Style.font.body
          background: Rectangle { color: "transparent" }
          textFormat: TextEdit.PlainText
          leftPadding: Style.space(8)
          rightPadding: Style.space(8)
          topPadding: Style.space(8)
          bottomPadding: Style.space(8)

          onTextChanged: {
            if (pane.applyingDraft) return
            if (editor.text === pane.draftText) return
            pane.draftEdited(editor.text)
          }

          onActiveFocusChanged: pane.editorFocused = activeFocus

          Keys.priority: Keys.BeforeItem
          Keys.onEscapePressed: function (event) {
            pane.editorFocused = false
            event.accepted = true
            Qt.callLater(function () {
              if (pane.searchField) pane.searchField.forceActiveFocus()
            })
          }
          // TextArea swallows Ctrl+S unless the shortcut override is accepted first.
          Keys.onShortcutOverride: function (event) {
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            var meta = (event.modifiers & Qt.MetaModifier) !== 0
            var alt = (event.modifiers & Qt.AltModifier) !== 0
            if (ctrl && event.key === Qt.Key_S) {
              event.accepted = true
              return
            }
            if (!alt && event.key === Qt.Key_N && ((ctrl && !meta) || (meta && !ctrl))) {
              event.accepted = true
            }
          }
          Keys.onPressed: function (event) {
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            var meta = (event.modifiers & Qt.MetaModifier) !== 0
            var alt = (event.modifiers & Qt.AltModifier) !== 0
            if (ctrl && event.key === Qt.Key_S) {
              pane.saveRequested()
              event.accepted = true
              return
            }
            if (!alt && event.key === Qt.Key_N && ((ctrl && !meta) || (meta && !ctrl))) {
              if (pane.relayKey) pane.relayKey(event)
              event.accepted = true
            }
          }
        }
      }
    }
  }
}
