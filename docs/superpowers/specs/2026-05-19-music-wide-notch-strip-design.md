# Music Wide Notch Strip Design

Date: 2026-05-19
Branch: `feature/music-module`
Status: Drafted for review

## Context

The panel-shell milestone on `main` introduced the generic `wideNotchStrip` rest variant and the `RestVariantStore` / `RestVariantContentRegistry` extension points. The music module currently has:

- a working expanded music panel with playback state and controls
- legacy `collapsedSummary` data used by the pre-rest collapsed path
- no registered `wideNotchStrip` provider, so the shell falls back to placeholder content

The product requirement is to make the music module own the `wideNotchStrip` experience when a supported player has an active playback session. The left icon must reflect the current player app. The right icon must reflect playback activity using a three-bar equalizer-like indicator. When paused, the bars remain visible but static.

## Goal

Implement a music-owned `wideNotchStrip` rest variant that:

- appears only when the music module has a real supported playback session
- uses the current player app as the left-side identity
- shows a three-bar animated playback indicator on the right while music is playing
- keeps the same bars visible in a static pose while paused
- expands back into the music module when clicked

## Non-Goals

This change does not include:

- `headerlessMiniPanel` support for music
- progress dragging
- fixing the deferred metadata lag after track changes
- adding new public shell geometry, animation, or window behavior
- adding Apple Music or Spotify playback support

## Scope Boundary

This spec only covers the music module's integration with the existing `wideNotchStrip` shell variant. The shell remains the source of truth for:

- visible strip size
- hover height increase
- outer shell fill, corner radius, shadow, and morph behavior
- click handling that expands from rest into expanded state

The music module only owns:

- when the strip should exist
- what content is rendered inside the strip
- how the music-specific indicator animates

## States

The strip visibility is derived from `MusicModuleRuntime.moduleState`.

### Visible states

- `playing(session)`
- `paused(session)`

Both states produce a persistent `.music + .wideNotchStrip` request.

### Hidden states

- `empty`
- `launchingPlayer`
- `permissionRequired`
- `playerNotInstalled`
- `launchFailed`
- `controlFailed`
- `unsupportedActivePlayer`
- `metadataUnavailable`

All hidden states clear the music module's persistent rest request.

## Rest Variant Lifecycle

### Registration

`AppCompositionRoot` will register a music rest-variant provider during initialization. This provider will be responsible for rendering music content when the resolved request is:

- `moduleID == .music`
- `kind == .wideNotchStrip`

### Persistence

`AppCompositionRoot` will observe `musicRuntime` changes and synchronize `RestVariantStore` with the current music state:

- if the state is `playing` or `paused`, set a persistent `.wideNotchStrip` request for `.music`
- otherwise clear the persistent request for `.music`

The preferred width should align with the current shell width for this variant so the content fills the available visible body without introducing module-specific frame ownership.

## Visual Design

The design is based on Figma node `71:14323`. The shell already constrains the visible body to the panel-shell `wideNotchStrip` geometry, so the module content should adapt to those dimensions instead of attempting a pixel-for-pixel outer frame recreation.

### Layout

- left cluster: player identity mark inside a small rounded/circular treatment
- center: empty safe area, no title text, no scroller, no additional metadata
- right cluster: three vertical semi-transparent white bars

The strip should remain visually sparse. The center area is intentionally empty to preserve the notch-safe composition shown in Figma.

### Left-side identity

The left icon reflects the active supported player:

- QQ Music
- NetEase Music
- KuGou Music
- Soda Music

The first implementation may reuse the existing music module mark system derived from `symbolIdentifier`, as long as each app is visually distinguishable. New asset plumbing is not required for this slice.

### Right-side playback indicator

The indicator uses three rounded vertical bars.

While playing:

- bars animate with different durations and phase offsets
- height changes are intentionally irregular so the motion feels like active playback rather than a synchronized pulse
- animation is fully internal to the bar group and must not move the strip frame

While paused:

- the same three bars remain visible
- heights stay fixed in a single resting pose
- no opacity blinking or replacement icon is shown

## Interaction

The strip does not introduce independent hit targets. The whole strip continues to use the shell's existing rest-variant button behavior. Clicking the strip expands into the music module.

## Architecture

### New responsibilities

1. `AppCompositionRoot`
- register the music `RestVariantContentProvider`
- synchronize persistent `.wideNotchStrip` requests with `musicRuntime.moduleState`

2. Music strip view
- render player identity on the left
- render playback bars on the right
- keep the center area empty

3. Lightweight presentation mapping
- derive strip-specific rendering data from the current music playback session
- separate playing vs paused indicator behavior

### Existing responsibilities reused

- `MusicModuleRuntime` remains the source of truth for playback state
- `RestVariantStore` continues to manage rest presentation resolution
- `OverlayCoordinator` and panel shell continue to manage geometry and transitions

## Error Handling

No music-specific fallback content should be shown for invalid states. If the music state is not renderable as a supported playback session, the module should remove its persistent request and let the shell render its non-music idle presentation.

This keeps failure modes honest:

- no stale strip after playback disappears
- no fake music strip for unsupported players
- no pseudo-loading strip while only launching an app

## Testing

The implementation should follow TDD.

### Required tests

1. rest request lifecycle
- playing state registers a persistent music `wideNotchStrip`
- paused state registers a persistent music `wideNotchStrip`
- empty and error states clear the persistent music request

2. provider registration
- the composition root exposes music strip content for a `.music + .wideNotchStrip` request

3. visual state behavior
- strip content reflects the current player identity
- strip indicator distinguishes playing from paused

The tests do not need to snapshot the exact animation frames. They only need to prove the presence of:

- a player-specific left mark
- a playing vs paused rendering mode for the bar group

## Risks

### 1. Existing uncommitted runtime changes

The branch already contains uncommitted music runtime work from playback debugging. The strip integration should build on top of that state without reverting unrelated edits.

### 2. Duplicate collapsed paths

The old `collapsedSummary` path still exists for legacy collapsed expansion routing. This work should reuse the same underlying playback session information but should not add more logic to the legacy UI path.

### 3. Asset fidelity

If the reused `symbolIdentifier` marks are not visually distinct enough, a follow-up asset pass may still be needed. That is acceptable for this slice as long as app identity is functionally clear.

## Acceptance Criteria

- when QQ / NetEase / KuGou / Soda is actively playing, the music module owns the `wideNotchStrip`
- the strip left mark matches the active player app
- the strip right bars animate only while playing
- paused playback keeps the bars visible in a static pose
- unsupported or inactive states remove the music strip
- clicking the strip still expands to the music module
- no shell geometry or common hover animation logic is changed
