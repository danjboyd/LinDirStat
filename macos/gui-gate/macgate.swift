// Drives LinDirStat for the macOS GUI parity gate (scripts/gui-parity-gate-macos.py)
// without moving the user's mouse or typing into other apps: every action goes
// to the app's own accessibility elements, found by screen point (top-left
// origin, points, as LINDIRSTAT_DUMP_LAYOUT reports them).
//
//   macgate window PID                  main window's CGWindowID and bounds
//   macgate rgb PNG OUT SCALE           PNG -> raw RGB, downsampled by SCALE (Retina)
//   macgate select PID X Y              select the table row at the point
//   macgate press PID X Y               press the control (tab, button) at the point
//   macgate menu PID X Y                select the row at the point and show its context menu
//   macgate rclick PID X Y              right-click at the point, posted to the app alone
//   macgate menus PID                   open menus as JSON: [{"rect": [x,y,w,h], "items": [...]}]
//   macgate menuitem PID MENU ITEM      choose a main menu item by titles
//   macgate cancel PID                  close an open menu
//   macgate escape PID                  press Escape in the app alone (closes a tracking menu)
//   macgate activate PID                bring the app to the front
import AppKit
import ApplicationServices

func fail(_ message: String) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
  exit(1)
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
  var value: AnyObject?
  return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func role(_ element: AXUIElement) -> String { attribute(element, kAXRoleAttribute) as? String ?? "" }

func element(_ pid: pid_t, _ x: Float, _ y: Float) -> AXUIElement {
  let app = AXUIElementCreateApplication(pid)
  var found: AXUIElement?
  guard AXUIElementCopyElementAtPosition(app, x, y, &found) == .success, let hit = found else {
    fail("no element at \(x),\(y)")
  }
  return hit
}

// The element itself or its nearest ancestor with one of the roles.
func ancestor(_ start: AXUIElement, roles: Set<String>) -> AXUIElement? {
  var current: AXUIElement? = start
  while let node = current {
    if roles.contains(role(node)) { return node }
    current = attribute(node, kAXParentAttribute) as! AXUIElement?
  }
  return nil
}

func selectRow(_ pid: pid_t, _ x: Float, _ y: Float) -> AXUIElement {
  guard let row = ancestor(element(pid, x, y), roles: [kAXRowRole]) else { fail("no row at \(x),\(y)") }
  guard let table = ancestor(attribute(row, kAXParentAttribute) as! AXUIElement, roles: [kAXOutlineRole, kAXTableRole]) else {
    fail("row has no table")
  }
  let error = AXUIElementSetAttributeValue(table, kAXSelectedRowsAttribute as CFString, [row] as CFArray)
  if error != .success {
    AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
  }
  return row
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: macgate COMMAND ...") }
let pid = args.count >= 3 ? pid_t(args[2]) ?? 0 : 0

switch args[1] {
case "window":
  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
  let windows = list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
  // The largest window is the main one.
  guard let main = windows.max(by: {
    let a = $0[kCGWindowBounds as String] as! [String: CGFloat], b = $1[kCGWindowBounds as String] as! [String: CGFloat]
    return a["Width"]! * a["Height"]! < b["Width"]! * b["Height"]!
  }) else { fail("no window for \(pid)") }
  let bounds = main[kCGWindowBounds as String] as! [String: CGFloat]
  print(main[kCGWindowNumber as String]!, Int(bounds["X"]!), Int(bounds["Y"]!), Int(bounds["Width"]!), Int(bounds["Height"]!))

case "rgb":
  guard args.count == 5, let scale = Int(args[4]), scale >= 1,
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(args[2])") }
  let width = image.width / scale, height = image.height / scale
  var rgba = [UInt8](repeating: 0, count: width * height * 4)
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  // Nearest neighbour: one point is SCALE identical pixels for the 1:1 treemap.
  context.interpolationQuality = .none
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  var rgb = [UInt8](repeating: 0, count: width * height * 3)
  for i in 0..<(width * height) {
    rgb[i * 3] = rgba[i * 4]; rgb[i * 3 + 1] = rgba[i * 4 + 1]; rgb[i * 3 + 2] = rgba[i * 4 + 2]
  }
  FileManager.default.createFile(atPath: args[3], contents: Data(rgb))
  print(width, height)

case "select":
  _ = selectRow(pid, Float(args[3])!, Float(args[4])!)

case "press":
  let hit = element(pid, Float(args[3])!, Float(args[4])!)
  guard let control = ancestor(hit, roles: [kAXRadioButtonRole, kAXButtonRole, "AXTab"]) ?? Optional(hit),
        AXUIElementPerformAction(control, kAXPressAction as CFString) == .success else { fail("cannot press") }

case "menu":
  let row = selectRow(pid, Float(args[3])!, Float(args[4])!)
  // The table's menu shows for its selection.
  let table = ancestor(attribute(row, kAXParentAttribute) as! AXUIElement, roles: [kAXOutlineRole, kAXTableRole])!
  // AXShowMenu runs the menu's tracking loop and returns when it closes, so
  // it is sent without waiting.
  AXUIElementSetMessagingTimeout(table, 30)
  guard AXUIElementPerformAction(table, kAXShowMenuAction as CFString) == .success else { fail("no context menu") }

case "rclick":
  // Posted to the process, so the system cursor and other apps are untouched.
  let point = CGPoint(x: Double(args[3])!, y: Double(args[4])!)
  // AppKit routes the event by the window it names.
  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
  let window = list.first(where: {
    guard ($0[kCGWindowOwnerPID as String] as? pid_t) == pid, ($0[kCGWindowLayer as String] as? Int) == 0,
          let b = $0[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
    return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!).contains(point)
  })?[kCGWindowNumber as String] as? Int64 ?? 0
  for type in [CGEventType.rightMouseDown, .rightMouseUp] {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right) else {
      fail("cannot make a mouse event")
    }
    event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: window)
    event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: window)
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.postToPid(pid)
    usleep(80_000)
  }

case "menus":
  let app = AXUIElementCreateApplication(pid)
  var menus: [[String: Any]] = []
  func collect(_ node: AXUIElement, _ depth: Int) {
    if role(node) == kAXMenuRole {
      var origin = CGPoint.zero, size = CGSize.zero
      if let value = attribute(node, kAXPositionAttribute) { AXValueGetValue(value as! AXValue, .cgPoint, &origin) }
      if let value = attribute(node, kAXSizeAttribute) { AXValueGetValue(value as! AXValue, .cgSize, &size) }
      let items = ((attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []).map {
        (attribute($0, kAXTitleAttribute) as? String) ?? ""
      }.filter { !$0.isEmpty }
      menus.append(["rect": [Int(origin.x), Int(origin.y), Int(size.width), Int(size.height)], "items": items])
      return
    }
    if depth > 3 { return }
    for child in (attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? [] where role(child) != kAXMenuBarRole {
      collect(child, depth + 1)
    }
  }
  collect(app, 0)
  // An open context menu is not one of the app's children; reach it through
  // the focused element (an item of the menu being tracked).
  if menus.isEmpty, let focused = attribute(app, kAXFocusedUIElementAttribute) as! AXUIElement?,
     let menu = ancestor(focused, roles: [kAXMenuRole]) {
    collect(menu, 0)
  }
  let data = try! JSONSerialization.data(withJSONObject: menus)
  print(String(data: data, encoding: .utf8)!)

case "menuitem":
  let app = AXUIElementCreateApplication(pid)
  guard let bar = attribute(app, kAXMenuBarAttribute) as! AXUIElement?,
        let tops = attribute(bar, kAXChildrenAttribute) as? [AXUIElement],
        let top = tops.first(where: { attribute($0, kAXTitleAttribute) as? String == args[3] }),
        let menu = (attribute(top, kAXChildrenAttribute) as? [AXUIElement])?.first,
        let items = attribute(menu, kAXChildrenAttribute) as? [AXUIElement],
        let item = items.first(where: { attribute($0, kAXTitleAttribute) as? String == args[4] }) else {
    fail("no menu item \(args[3]) > \(args[4])")
  }
  guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { fail("cannot choose \(args[4])") }

case "cancel":
  let app = AXUIElementCreateApplication(pid)
  var closed = false
  var open = ((attribute(app, kAXChildrenAttribute) as? [AXUIElement]) ?? []).filter { role($0) == kAXMenuRole }
  if let focused = attribute(app, kAXFocusedUIElementAttribute) as! AXUIElement?,
     let menu = ancestor(focused, roles: [kAXMenuRole]) {
    open.append(menu)
  }
  for menu in open {
    closed = AXUIElementPerformAction(menu, kAXCancelAction as CFString) == .success || closed
  }
  if !closed { fail("no open menu") }

case "escape":
  for down in [true, false] {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down) else { fail("no key event") }
    event.postToPid(pid)
    usleep(50_000)
  }

case "activate":
  guard let running = NSRunningApplication(processIdentifier: pid) else { fail("no process \(pid)") }
  running.activate()

default:
  fail("unknown command \(args[1])")
}
