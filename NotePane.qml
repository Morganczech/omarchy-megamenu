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
  property string allLabel: "All"
  property color foreground: "#dddddd"
  property string fontFamily: ""
  property var roleColorFor: null
  property Item searchField: null

  signal noteChosen(string path)
  signal draftEdited(string text)
  signal saveRequested()
  signal foldersRequested()
  signal omawriteRequested()
  signal noteMenuRequested(string path, real x, real y)
  signal filterRequested(string id)

  function focusEditor() {
    editor.forceActiveFocus()
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
    list.sort(function (a, b) {
      var ap = (a.pinnedSlot >= 1 && a.pinnedSlot <= 6) ? 0 : 1
      var bp = (b.pinnedSlot >= 1 && b.pinnedSlot <= 6) ? 0 : 1
      if (ap !== bp) return ap - bp
      var mt = (Number(b.mtime) || 0) - (Number(a.mtime) || 0)
      if (mt !== 0) return mt
      var at = String(a.title || "")
      var bt = String(b.title || "")
      if (at < bt) return -1
      if (at > bt) return 1
      var apath = String(a.path || "")
      var bpath = String(b.path || "")
      if (apath < bpath) return -1
      if (apath > bpath) return 1
      return 0
    })
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

      Flow {
        id: chipFlow
        anchors.top: listHeader.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        height: implicitHeight
        spacing: Style.space(8)

        Rectangle {
          id: allChip
          readonly property bool active: {
            var f = String(pane.filter || "all")
            return f === "" || f === "all" || f === "favorites"
          }
          readonly property color accent: pane.roleColorFor ? pane.roleColorFor("green") : pane.foreground
          height: Style.space(26)
          width: allChipText.implicitWidth + Style.space(18)
          radius: height / 2
          color: active ? Util.alpha(allChip.accent, 0.18) : Util.alpha(pane.foreground, 0.04)
          border.width: 1
          border.color: allChip.active ? allChip.accent : Util.alpha(pane.foreground, 0.14)

          Text {
            id: allChipText
            anchors.centerIn: parent
            text: pane.allLabel
            color: allChip.active ? pane.foreground : Color.muted
            font.family: pane.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: allChip.active
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pane.filterRequested("all")
          }
        }

        Repeater {
          model: pane.categories

          delegate: Rectangle {
            id: catChip
            required property var modelData
            readonly property bool active: String(pane.filter || "") === String(modelData.id || "")
            readonly property color chipColor: pane.accentFor({ colorRole: modelData.colorRole, categoryId: modelData.id })
            height: Style.space(26)
            width: catChipRow.implicitWidth + Style.space(18)
            radius: height / 2
            color: active ? Util.alpha(chipColor, 0.18) : Util.alpha(pane.foreground, 0.04)
            border.width: 1
            border.color: active ? chipColor : Util.alpha(pane.foreground, 0.14)

            Row {
              id: catChipRow
              anchors.centerIn: parent
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(6)
                height: Style.space(6)
                radius: width / 2
                color: catChip.chipColor
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                width: Math.min(implicitWidth, Style.space(140))
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: modelData.name || ""
                color: catChip.active ? pane.foreground : Color.muted
                font.family: pane.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: catChip.active
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: pane.filterRequested(catChip.active ? "all" : String(modelData.id || ""))
            }
          }
        }
      }

      ListView {
        id: noteList
        anchors.top: chipFlow.bottom
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
            anchors.rightMargin: Style.space(10)
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
          Keys.onPressed: function (event) {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
              pane.saveRequested()
              event.accepted = true
            }
          }
        }
      }
    }
  }
}
