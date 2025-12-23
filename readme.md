# Swen

Swen is an experimental compositor aimed at providing native vector-based rendering which apps can access using a simple markup-based DSL. 

![Example Screenshot](./example.png)

## Premise

Swen is inspired by the NeWS operating system and informed by modern UI frameworks like Flutter. By offloading graphics runtime from the app to the compositor, native apps no longer need their own graphics runtime or frame loop. Since rendering for most UI only needs to happen upon state change, a system of caching and diffing should allow noticeable resource efficiency compared to X11 or Wayland. 

The backend takes a hybrid approach: **the CPU does scheduling/allocation**, and the GPU does high-throughput pixel work. Inspired by Vello's hybrid mode work, the long-term direction is **tile-based rendering** (bin + sort + merge tile work, cache aggressively, and redraw only dirty tiles) with **bounded GPU memory** (flush in chunks rather than failing on overflow). Pathfinder can be used as a pragmatic bootstrap backend while Swen's compositor-internal IR and tile scheduler mature. If you need more flexibility, or you want to use a non-native app, the compositor can render it as a Wayland surface treated like an opaque texture. 


## Architecture

The compositor reads a form of markup written as a .swen file. This is parsed into an scene tree and made into a global scene tree much like Flutter. When an app is launched which provides a .swen file, it is parsed and inserted into the scene tree. The apps UI is sandboxed from writing to other apps, and is limited to receiving events which are explicitly requested within its scene tree. Apps communicate changes to the scene tree via **patch ops** (high-level operations like `SetText`, `SetPosition`, etc.), which are distinct from the compositor's internal **render IR** (low-level rendering instructions used for tile-based GPU rendering).

## Pipeline (end-to-end)

### 1) Boot / initial frame
- Desktop markup (e.g. `root.swen`) is parsed into a retained **scene tree** (desktop/system + nodes).
- The compositor lowers the retained tree into a compositor-internal **render IR** (stable ids + bounds + paint + clip state).
- The compositor performs **tile scheduling**: compute covered tiles, sort by tile, merge, and build per-tile draw batches for the first frame.
- Renderer objects persist; the main loop polls events and renders the current **frame snapshot** produced by the scheduler/backend.

### 2) App launch / insertion into global scene
- An app provides markup (`.swen`) or equivalent structured UI data.
- The compositor parses this into an app-owned subtree with stable node `id`s.
- The subtree is inserted into the global scene (workspace/window container, etc).
- The scene becomes **dirty** → update IR for affected nodes and re-schedule only the impacted **dirty tiles**, then swap the current frame snapshot.
- (Bootstrap fallback) if using Pathfinder directly, dirtiness may temporarily trigger a coarse rebuild of a `PFScene`/proxy until incremental tile scheduling fully replaces that path.

### 3) Events → app → patch ops (reactive updates)
- Input is hit-tested/routed to a target node `id` and its owning app.
- The compositor forwards the event to the app (IPC).
- The app updates its state and emits **patch ops** (high-level scene tree mutations, not draw calls), e.g.:
  - set properties: `SetText`, `SetBackground`, `SetPosition`, `SetSize`, `SetTransform`
  - edit structure: `InsertChild`, `RemoveNode`, `ReplaceChildren`
- The compositor applies patch ops to the retained subtree (with validation/sandboxing), marks dirty, then lowers the updated scene tree into **render IR** and re-schedules only the impacted **dirty tiles** (with a Pathfinder rebuild as an optional bootstrap fallback).

### 4) Render IR (compositor-internal)
The compositor lowers the retained scene tree (updated via patch ops) into a **render IR** (render-command IR, e.g. `Instruction[]`). This IR is distinct from patch ops: patch ops are app-facing high-level operations that modify the scene tree, while render IR is a compositor-internal low-level representation designed for **incremental, tile-based rendering**:
- **Binning**: flatten geometry as needed, assign work to tiles (fixed tile size).
- **Sorting/merging**: sort tile records so each tile is a contiguous slice; merge per-tile work.
- **Classification**: skip empty tiles; fast-path solid tiles; compute coverage only for edge tiles.
- **Caching**: cache tessellation/text runs/tiles across frames keyed by stable ids + paint/clip keys.
- **GPU-friendly output**: pack coverage into compact batches (e.g. sparse strips/quads) and render with bounded GPU buffers (flush in chunks on overflow).

### 5) GPU submission (OpenGL, hybrid model)
In the hybrid model (inspired by Vello), Swen treats the GPU as a **fine raster + blend engine** and submits work in **tile batches**:
- The CPU produces `TileWork[]` (one record per merged tile/strip) and `Segments[]` (packed, tile-clipped line segments), plus small paint/clip tables.
- Upload these as SSBOs (OpenGL 4.3+), in **bounded** fixed-size buffers. If a frame doesn't fit, **flush a draw/dispatch**, reset write offsets, and continue with the remaining tiles.
- **Compute path (preferred when available)**: `glDispatchCompute` over tiles/strips; compute shader writes coverage/color into an output `image2D`, followed by a memory barrier.
- **Raster path (fallback)**: `glDraw*Instanced` of quads (one per tile/strip); fragment shader computes coverage for pixels in that tile/strip by reading the tile's segment slice from SSBOs.
- Tiles are typically classified (especially for clips): **interior** (fast-path draw), **exterior** (skip), **edge** (mask/coverage + composite).
- Present by rendering the output to the window (or rendering directly to the default framebuffer) and swapping buffers.

## Proposed Benefits

All benefits are hypothetical until proven, but are based on well-tested and modern UI paradigms. 

### Performance

- Render-on-change instead of render-on-frame. 
- Global batching & caching.
- Avoid redundant GPU state changes.
- Better rendering consistency across DPIs and resolutions.

### Customization

- Programmable window management.
- Native theming.
- Inspectors, debuggers, and live editors can operate directly on the scene tree.

### Backwards Compatibility

- Legacy apps still run normally.
- Incremental usage (write UI around a wayland surface).
- Pipeline is not dependent on backend and can evolve independently of Swen.
- Porting apps does not require bundling a graphics runtime or framework.
