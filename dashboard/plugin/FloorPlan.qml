import QtQuick
import QtQuick.Shapes
import qs.Commons
import "home.js" as Home
import "model.js" as Model

// Single-level house drawn as a dollhouse: floors lit by their lights, short
// walls, temperatures on top. Drag sideways to turn the house; tap a room to
// toggle its lights.
//
// The view is orthographic, so the plan is built once as GPU geometry in plan
// units (centimetres) and turning the house only changes the transforms. Walls
// are their outline stacked a pixel or two apart, darkest at the floor.
// GeometryRenderer, not CurveRenderer: the curve shader's antialiasing halved
// the frame rate on this GPU, and at 2x scale the edges barely show it.
Item {
  id: plan

  property Item s
  property var floor: null
  property var rooms: []
  property string selected: ""
  property real angle: -10
  readonly property real defaultAngle: -10
  signal roomTapped(var room)

  readonly property real wallHeight: 0.6
  readonly property int wallLayers: 7
  readonly property var view: width > 0 && height > 0 && floor
    ? Home.planView(floor, rooms, { angle: angle, elevation: 60, wallHeight: wallHeight, width: width, height: height, padding: 22 }) : null

  // Plan centimetres to screen pixels, raised z metres off the floor.
  function placement(z) {
    if (!view) return Qt.matrix4x4()
    var m = view.matrix
    return Qt.matrix4x4(m[0] / 100, m[1] / 100, 0, m[2],
                        m[3] / 100, m[4] / 100, 0, m[5] - z * view.lift,
                        0, 0, 1, 0,
                        0, 0, 0, 1)
  }

  function outline(points) {
    var out = points.map(function(p) { return Qt.point(p[0] * 100, p[1] * 100) })
    return out.concat([out[0]])
  }

  readonly property var wallLines: floor ? floor.walls.map(function(w) {
    return [Qt.point(w[0] * 100, w[1] * 100), Qt.point(w[2] * 100, w[3] * 100)]
  }) : []

  readonly property color wallSide: Qt.tint(s.bg, Qt.alpha(s.fg, 0.12))
  readonly property color wallTop: Qt.tint(s.bg, Qt.alpha(s.fg, 0.34))

  Item {
    transform: Matrix4x4 { matrix: plan.placement(0) }
    Repeater {
      model: plan.rooms
      Shape {
        required property var modelData
        readonly property real share: modelData.total ? modelData.on / modelData.total : 0
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
          strokeColor: "transparent"
          fillColor: modelData.on > 0 ? Qt.alpha(s.accent, Style.selectedFillAlpha + 0.25 * share) : Qt.alpha(s.fg, modelData.area ? 0.08 : 0.03)
          PathPolyline { path: plan.outline(modelData.points) }
        }
      }
    }
  }

  Repeater {
    model: plan.wallLayers
    Item {
      required property int index
      readonly property real t: index / (plan.wallLayers - 1)
      transform: Matrix4x4 { matrix: plan.placement(plan.wallHeight * t) }
      Shape {
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
          fillColor: "transparent"
          strokeColor: index === plan.wallLayers - 1 ? plan.wallTop : Qt.darker(plan.wallSide, 1.25 - 0.25 * t)
          strokeWidth: 12
          capStyle: ShapePath.SquareCap
          joinStyle: ShapePath.MiterJoin
          PathMultiline { paths: plan.wallLines }
        }
      }
    }
  }

  Item {
    visible: plan.selected !== ""
    transform: Matrix4x4 { matrix: plan.placement(0) }
    Shape {
      preferredRendererType: Shape.GeometryRenderer
      ShapePath {
        id: selectedPath
        readonly property var room: {
          for (var i = 0; i < plan.rooms.length; i++) if (plan.rooms[i].id === plan.selected) return plan.rooms[i]
          return null
        }
        fillColor: "transparent"
        strokeColor: s.accent
        strokeWidth: plan.view ? 250 / plan.view.scale : 0
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: selectedPath.room ? plan.outline(selectedPath.room.points) : [] }
      }
    }
  }

  Repeater {
    model: plan.rooms
    Column {
      required property var modelData
      readonly property var center: plan.view ? plan.view.centers[modelData.id] : null
      visible: center !== null
      x: center ? center.x - width / 2 : 0
      y: center ? center.y - height / 2 : 0
      spacing: 0
      PlainText {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: modelData.temp !== null
        text: modelData.temp + "°"
        style: Text.Outline
        styleColor: Qt.alpha(s.bg, 0.6)
        font { pixelSize: Style.font.bodySmall; bold: true }
      }
      // Smaller than the caption token: the labels share the plan with walls.
      PlainText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: modelData.name
        dim: !modelData.area
        style: Text.Outline
        styleColor: Qt.alpha(s.bg, 0.6)
        font.pixelSize: Style.fontPx(0.65)
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    preventStealing: true
    property real startX: 0
    property real startAngle: 0
    property bool turning: false
    onPressed: function(mouse) { startX = mouse.x; startAngle = plan.angle; turning = false }
    onPositionChanged: function(mouse) {
      if (!turning && Math.abs(mouse.x - startX) > 10) turning = true
      if (turning) plan.angle = startAngle + (mouse.x - startX) * 0.5
    }
    onReleased: function(mouse) {
      if (turning || !plan.view) return
      var id = Home.hitRoom(plan.view, mouse.x, mouse.y)
      for (var i = 0; i < plan.rooms.length; i++) if (plan.rooms[i].id === id) plan.roomTapped(plan.rooms[i])
    }
  }

  // Back to the default view after turning.
  ActionButton {
    anchors { right: parent.right; bottom: parent.bottom }
    visible: Math.abs(plan.angle - plan.defaultAngle) > 1
    icon: Model.ICON.rotate
    onActivated: resetTurn.start()
  }

  NumberAnimation { id: resetTurn; target: plan; property: "angle"; to: plan.defaultAngle; duration: 300; easing.type: Easing.OutCubic }
}
