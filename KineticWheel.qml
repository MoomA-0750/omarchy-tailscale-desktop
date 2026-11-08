import QtQuick
import qs.Commons

// Wheel and touchpad scrolling for a Flickable, with momentum on touchpads.
//
// On Wayland, libinput leaves kinetic scrolling to the toolkit, and Qt's
// Flickable follows the fingers 1:1 and stops dead the moment they lift.
// This does all wheel scrolling for the Flickable instead: it follows a
// touchpad gesture and, when the fingers lift while still moving, glides on
// with that velocity; a mouse wheel notch glides a short step.
//
// The Flickable must have `interactive: false`. An interactive Flickable
// takes wheel events from its children (this included) and scrolls by
// itself, overwriting what this does.
//
// Declare it inside the Flickable:
//   Flickable { id: list; interactive: false; KineticWheel { flickable: list } }
// and for a list nested in another, point it at the outer one:
//   KineticWheel { flickable: inner; outer: outerWheel }
//
// It is an Item tracking the viewport inside the content, below the
// content (z: -1): a pointer handler declared straight inside a Flickable
// is never registered, and under the content a nested Flickable still gets
// the scroll before an outer one.
Item {
  id: root

  required property Flickable flickable
  // The KineticWheel of the view this one sits inside, if any, which gets
  // the scroll once this one can't move any further.
  property Item outer: null
  // Below this speed (px/s) a lift just stops, as a deliberate halt should.
  property real minimumVelocity: 120
  // Only movement in this window before the lift counts toward the fling,
  // so slowing down before lifting is respected.
  property int sampleWindowMs: 80
  // Content moves this many pixels per pixel the fingers report, as
  // browsers scroll faster than Qt's 1:1.
  property real touchpadFactor: 2.5
  // Fraction of the glide's speed lost per second, as e^(-friction * t);
  // 2 is Firefox's apz.fling_friction (0.002 per ms).
  property real friction: 2
  // Distance one mouse wheel notch scrolls.
  property real wheelStep: Style.space(72)

  // Emitted after the content is moved directly, for views that remember
  // their scroll position.
  signal scrolled()

  readonly property bool scrollable: flickable && flickable.contentHeight > flickable.height

  // A ListView keeps its own children out of the content; a Flickable
  // puts them in it, where the viewport sits at the scroll position.
  readonly property bool inContent: flickable && parent !== flickable
  x: inContent ? flickable.contentX : 0
  y: inContent ? flickable.contentY : 0
  width: flickable ? flickable.width : 0
  height: flickable ? flickable.height : 0
  z: -1

  property var samples: []
  property real flingVelocity: 0
  property real wheelTarget: 0

  function minY() {
    return flickable.originY - flickable.topMargin
  }

  function maxY() {
    return Math.max(minY(), flickable.originY + flickable.contentHeight + flickable.bottomMargin - flickable.height)
  }

  function clampY(y) {
    return Math.max(minY(), Math.min(maxY(), y))
  }

  function stopMotion() {
    flingAnimation.stop()
    if (flickable.flicking) flickable.cancelFlick()
    if (wheelAnimation.running) wheelAnimation.stop()
  }

  function release(endTime) {
    var list = samples
    samples = []
    if (list.length < 2) return
    var last = list[list.length - 1].t
    // Fingers that rested before lifting meant to stop there.
    if (endTime - last > 50) return
    var sum = 0
    var first = last
    for (var i = list.length - 1; i >= 0 && last - list[i].t <= sampleWindowMs; i--) {
      sum += list[i].d
      first = list[i].t
    }
    // At least one frame, so a single burst of events can't spike it.
    var span = Math.max(last - first, 16)
    var velocity = sum / span * 1000
    if (Math.abs(velocity) < minimumVelocity) return
    flingVelocity = Math.max(-12000, Math.min(12000, velocity))
    flingAnimation.start()
  }

  // A mouse wheel notch: glide a step, and let quick notches add up.
  // Returns false at the edge, where the scroll isn't this one's to take.
  function wheelNotch(angleY) {
    var steps = angleY / 120
    var base = wheelAnimation.running ? wheelTarget : flickable.contentY
    var to = clampY(base - steps * wheelStep)
    if (to === flickable.contentY && !wheelAnimation.running) return false
    flingAnimation.stop()
    if (flickable.flicking) flickable.cancelFlick()
    wheelTarget = to
    wheelAnimation.stop()
    wheelAnimation.from = flickable.contentY
    wheelAnimation.to = to
    wheelAnimation.start()
    return true
  }

  // One wheel event, as its phase, its pixel delta and its angle delta.
  // Returns whether this view or an outer one took it. Scroll that hits
  // this view's edge goes on to `outer`, so a nested list hands over to
  // the panel around it mid-gesture, the way a browser chains scrolling.
  function handle(phase, pixelY, angleY) {
    if (!scrollable) return outer ? outer.handle(phase, pixelY, angleY) : false

    if (phase === Qt.NoScrollPhase) {
      if (angleY === 0) return false
      if (wheelNotch(angleY)) return true
      return outer ? outer.handle(phase, pixelY, angleY) : false
    }
    if (phase === Qt.ScrollBegin) {
      stopMotion()
      samples = []
      if (outer) outer.handle(phase, pixelY, angleY)
    }
    if (phase === Qt.ScrollEnd) {
      release(Date.now())
      if (outer) outer.handle(phase, pixelY, angleY)
      return true
    }
    var delta = pixelY !== 0 ? pixelY : angleY / 8
    if (delta === 0) return true
    delta *= touchpadFactor

    stopMotion()
    var from = flickable.contentY
    var to = clampY(from - delta)
    if (to === from) {
      samples = []
      return outer ? outer.handle(phase, pixelY, angleY) : false
    }
    flickable.contentY = to
    scrolled()

    var t = Date.now()
    var list = samples
    list.push({ t: t, d: delta })
    while (list.length > 0 && t - list[0].t > 200) list.shift()
    samples = list
    return true
  }

  WheelHandler {
    target: null
    enabled: root.scrollable || root.outer !== null
    // Wayland reports a mouse wheel on the same pointer as the touchpad, so
    // take both; the scroll phase tells them apart.
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    onWheel: function(event) {
      if (!root.handle(event.phase, event.pixelDelta.y, event.angleDelta.y)) event.accepted = false
    }
  }

  // The glide after the fingers lift, decaying exponentially like a
  // browser's rather than at the Flickable's constant deceleration.
  FrameAnimation {
    id: flingAnimation
    onTriggered: {
      var dt = Math.min(frameTime, 0.05)
      var v = root.flingVelocity * Math.exp(-root.friction * dt)
      root.flingVelocity = v
      var from = root.flickable.contentY
      var to = root.clampY(from - v * dt)
      root.flickable.contentY = to
      root.scrolled()
      if (Math.abs(v) < 10 || to === from) stop()
    }
  }

  NumberAnimation {
    id: wheelAnimation
    target: root.flickable
    property: "contentY"
    duration: Style.duration(180)
    easing.type: Easing.OutCubic
    onStopped: root.scrolled()
  }
}
