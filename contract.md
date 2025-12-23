# Swen Contract Specification

## 1. Core Concepts

- **Scene tree**: A retained, hierarchical tree of nodes (each with a `nodeId`, type, properties, and children).
- **Markup (.swen)**: A declarative description of an app's initial subtree.
- **Patch ops**: High-level, app → compositor mutations of the scene tree.
- **Render IR**: Compositor-internal, low-level render representation derived from the scene tree (apps never see this).
- **App subtree**: Each app owns a rooted subtree within the global scene; it cannot mutate other apps' subtrees.

## 2. Markup and Scene Tree

### 2.1 File Format

- `.swen` is a UTF-8, text-based, declarative format.
- Each file has a single root node.
- Attributes map to node properties; nested elements define parent/child relationships.
- Markup is versioned (see Versioning).

### 2.2 Node Identity

- Each node has a stable id (string or integer).
- ids are unique within an app's subtree.
- Apps treat ids as stable across their own updates and patch ops.

### 2.3 Node Types (Initial Set)

This is the minimal baseline; new node types may be added over time.

- **Root**: Top-level node of an app subtree; acts as layout and focus root.
- **Container**: Generic grouping node; hosts children and a layout box.
- **Text**: Text node for displaying text runs.
- **Image**: Raster or vector image (with fit/scaling options).
- **Input**: Editable single-line text input.
- **Button**: Clickable control (semantic role; typically container + text).
- **Surface**: Host for embedded legacy surfaces (e.g. Wayland surface).

### 2.4 Properties (Initial Set)

The compositor defines a stable set of properties; unknown properties may be ignored or treated as custom.

#### Layout
- `x`, `y` (position in parent coordinates)
- `width`, `height`
- `minWidth`, `maxWidth`, `minHeight`, `maxHeight`

#### Style
- `background`, `foreground`
- `border`, `borderRadius`
- `opacity`
- `fontFamily`, `fontSize`, `fontWeight`

#### Transform / clipping
- `transform` (2D transform: translate, scale, rotate)
- `clip` (boolean or rect)

#### Behavior
- `role` (e.g. button, label, textInput, etc.)
- `tabIndex` (integer for focus order)
- `focusable` (bool)
- `enabled` (bool)
- `visible` (bool)

#### Content
- `text` (for Text/Button)
- `src` (for Image/Surface)
- `value` (for Input and other value-carrying nodes)

## 3. Layout Model (From the App's Perspective)

### 3.1 Coordinate Spaces

- Each node defines a local box.
- `x`, `y`, `width`, `height` are expressed in the parent's coordinate space.
- The compositor is responsible for mapping to device pixels and handling DPI/scaling; apps do not manage DPI directly.

### 3.2 Layout Semantics (Initial)

For the initial contract, layout is intentionally simple but extensible.

**Default mode:**
Children are positioned explicitly via `x`, `y`, `width`, `height` relative to their parent.

**Reserved / future modes** (subject to capability negotiation):
- `layout=stack` (children stacked vertically or horizontally)
- `layout=flex` (flex-like rules: flexGrow, flexShrink, alignment/justification props)

The compositor is the source of truth for final sizes/positions after layout.

### 3.3 Resize

- The compositor may resize an app's root or intermediate nodes (e.g. window resize).
- Apps can opt into Resize events (see Events).
- Apps treat the Root node's width/height as authoritative for top-level layout.

## 4. Events

### 4.1 Routing

- Events are routed to a target node id plus an event type and payload.
- Hit-testing is performed by the compositor in compositor coordinates, then translated as needed.
- Apps can declare which event types a node subscribes to, to reduce IPC traffic.

### 4.2 Baseline Event Types

#### Pointer
- `PointerDown`
- `PointerUp`
- `PointerMove`
- `PointerEnter`
- `PointerLeave`
- `PointerScroll`

#### Keyboard / Text
- `KeyDown`
- `KeyUp`
- `TextInput` (for committed text, including IME)

#### Focus
- `FocusIn`
- `FocusOut`

#### Lifecycle / Layout
- `Mount` (node made active in the scene)
- `Unmount` (node removed from the scene)
- `Resize` (node size changed; includes new size)

#### App / System
- `AppActivated`
- `AppDeactivated`
- `CloseRequested` (window close or equivalent)

### 4.3 Event Payloads (Examples)

#### Pointer:
- `x`, `y` (coordinates; local or global, depending on event definition)
- `button`, `buttons`
- `modifiers`
- `clickCount`
- `deltaX`, `deltaY` (for scroll)

#### Keyboard:
- `key`, `code`
- `modifiers`
- `repeat` (bool)

#### TextInput:
- `text` (committed string)

#### Resize:
- `width`, `height`

#### Focus:
- `focusReason` (e.g. pointer, keyboard, programmatic)

## 5. Focus, Text Input, and Accessibility

### 5.1 Focus Model

- Each app subtree has at most one focused node.
- Focus can change via:
  - Keyboard navigation (using `tabIndex` to order focusable nodes).
  - Pointer interaction (click/tap on a focusable node).
  - App request (`RequestFocus` patch op).
- Focus changes emit `FocusIn` and `FocusOut` events on the relevant nodes.

### 5.2 Text Input

- Nodes with `role=textInput` or an Input type can receive:
  - `KeyDown` / `KeyUp` (navigation, shortcuts)
  - `TextInput` (IME/text commit)
- Apps update user-visible text/value via patch ops (`SetText`, `SetValue`), not by mutating state inside the compositor.

### 5.3 Accessibility (Seed)

Nodes may expose:
- `role`
- `label`
- `description`
- `value`

The compositor may map these to platform accessibility APIs.

**Contract**: if an app sets these properties, they should reflect the actual UI semantics and state.

## 6. Patch Ops (App → Compositor)

Patch ops are high-level operations sent over IPC to mutate the app's scene subtree.

### 6.1 General Rules

- Patch ops only modify the calling app's subtree; cross-app mutations are rejected.
- Patch ops are processed in order within a batch.
- Event handling is serialized per app: event → app state update → patch batch.
- Ops should be treated as idempotent per frame: repeating the same op in a batch is allowed but has no additional effect.

### 6.2 Property Mutations

Examples of property-level patch ops:

- `SetText(nodeId, text)`
- `SetBackground(nodeId, background)`
- `SetForeground(nodeId, color)`
- `SetPosition(nodeId, x, y)`
- `SetSize(nodeId, width, height)`
- `SetTransform(nodeId, transform)`
- `SetVisibility(nodeId, visible)`
- `SetEnabled(nodeId, enabled)`
- `SetValue(nodeId, value)`

**Generic:**
- `SetProperty(nodeId, key, value)` for extensible or node-specific properties.

### 6.3 Structural Mutations

Structure-changing patch ops:

- `InsertChild(parentId, index, nodeSpec)`
  - `nodeSpec` includes id, type, properties, and optional nested children.
- `RemoveNode(nodeId)`
  - Removes the node and its descendants.
- `ReplaceChildren(parentId, childrenSpecs[])`
  - Replaces the entire children list for `parentId`.

### 6.4 Focus and Control

- `RequestFocus(nodeId)`
- `ClearFocus()`
- `RequestClose()` (app-initiated close request; the compositor decides how to handle it).

### 6.5 Batching

- Apps send patch batches containing multiple ops to reduce IPC overhead.
- The compositor:
  - Validates and applies a batch atomically.
  - Marks affected nodes and corresponding tiles as dirty.
  - Recomputes render IR only for impacted regions and schedules redraw.

## 7. Lifecycle and Timing

### 7.1 Startup

App is launched with:
- A `.swen` file (or equivalent structured initial UI).
- A communication channel (IPC) to the compositor.

**Compositor:**
- Parses markup and builds initial subtree.
- Assigns a `rootId` for the app.
- Performs layout and rendering for the initial frame.
- Optionally sends `AppActivated` and `Mount(rootId)` events.

### 7.2 Event → Patch Cycle

**Compositor:**
- Receives platform input.
- Hit-tests against the scene tree.
- Delivers event(s) to the relevant app with `nodeId` + event type + payload.

**App:**
- Updates its internal state.
- Computes necessary UI changes.
- Sends a patch batch to the compositor.

**Compositor:**
- Validates patch ops.
- Applies mutations to the scene tree.
- Marks dirty nodes/tiles, recomputes render IR for changed areas.
- Schedules a redraw and presents the updated frame.

### 7.3 Shutdown

- App can request close via `RequestClose()`.
- Compositor may send `CloseRequested` to the app; policy (confirm/veto) is TBD.
- On shutdown:
  - Compositor removes the app's subtree.
  - Sends `Unmount(rootId)` for cleanup.
  - Frees compositor-side resources (render IR, caches).

## 8. Error Handling and Validation

### 8.1 Invalid Operations

Invalid patch ops include:
- Referencing a non-existent `nodeId`.
- Attempting to parent a node into another app's subtree.
- Creating structural cycles (e.g. node as its own ancestor).
- Malformed or unsupported property values.

For an invalid op:
- The compositor rejects the op.
- Logs an error (implementation-defined).
- Continues processing other ops in the batch unless configured otherwise.

### 8.2 Failure Modes

**Soft failure (default):**
- Skip invalid ops, apply the rest of the batch.

**Hard failure (configurable):**
- On repeated or severe protocol violations, the compositor may terminate the app session and remove its subtree.

### 8.3 Contract Guarantees

**Compositor guarantees:**
- No app can mutate another app's subtree.
- Valid batches are applied atomically per batch.
- Event order per app is preserved.

**App guarantees:**
- ids are unique within its subtree.
- Patch ops refer only to nodes that exist and belong to the app.
- Patch ops are consistent with lifecycle (no ops on nodes after `Unmount`).

## 9. Versioning and Capabilities

### 9.1 Protocol Version

- Both markup and patch ops declare a front-end protocol version, e.g. `swen-front-v1`.
- The compositor:
  - May reject connections with unsupported versions.
  - May enter a compatibility mode for known older versions.

### 9.2 Feature Discovery

Apps can query the compositor for capabilities, including:
- Supported layout modes (stack, flex, etc.).
- Supported node types (e.g. Surface availability).
- Supported advanced events (e.g. IME composition, drag-and-drop, accessibility extensions).

Mechanism (e.g. `GetCapabilities()` IPC call or initial handshake block) is defined by the IPC protocol but conceptually returns a feature set.