---
name: game-ui-art-director
description: >
  Redesign generic, AI-looking interfaces into distinctive, professionally
  art-directed Godot game interfaces. Use when redesigning HUD, menus, pause,
  settings, or any Godot game UI that feels generic, SaaS-like, or needs a
  cohesive visual identity with verification screenshots.
---

# Game UI Art Director

This skill specializes in redesigning generic, AI-looking interfaces into distinctive, professionally art-directed Godot game interfaces.

## Objective

The UI must look like it was designed by an experienced game UI artist, not generated using generic web UI conventions.

## Mandatory design workflow

### Phase 1: Visual audit
Inspect the current Godot UI scenes, fonts, colors, textures, layout structures, and interaction states.

Identify generic patterns:
- Repetitive rounded rectangles
- Card-based dashboard compositions
- Excessive gradients or glassmorphism
- Generic typography
- Uniform spacing without visual rhythm
- Overuse of accent colors
- Decorative elements without purpose
- Icons with inconsistent weight or style
- Menus that look like mobile productivity apps

Explain what makes each issue feel generic.

### Phase 2: Establish art direction
Before implementing, create three genuinely different visual directions for the existing game.

For each direction specify:
- Visual concept
- Typography system
- Layout composition
- Color palette
- Material and texture treatment
- Button design
- HUD design
- Interaction states
- Animation principles

Do not simply recolor the same layout.

### Phase 3: Reference-based design
Use user-provided screenshots and visual references when available.

Analyze their:
- Composition
- Typography hierarchy
- Negative space
- Visual rhythm
- Shape language
- Texture and materials
- Interaction conventions

Extract underlying principles rather than copying protected artwork.

### Phase 4: Implement a cohesive design system
Create reusable Godot UI components and a shared Theme resource where appropriate.

Define:
- Button normal, hover, pressed, disabled and focused states
- Panel and frame variants
- Typography hierarchy
- Icons and graphic elements
- Spacing and alignment rules
- Responsive behavior
- Gamepad and keyboard focus
- Sound and animation feedback

Avoid using Godot's default Control appearance without intentional styling.

### Phase 5: Visual verification
Render the actual interface using the available Godot tools.

Capture screenshots of the main menu, HUD, settings and pause screen.

Evaluate:
1. Does it look like an actual game?
2. Does it have a recognizable visual identity?
3. Does it still resemble a generic AI dashboard?
4. Are all screens stylistically consistent?
5. Are text and interactions readable?
6. Does it work at the intended resolutions?

If visual inspection tools are unavailable, explicitly report that verification remains incomplete.

### Phase 6: Iterative refinement
Revise the weakest areas first.

Do not stop after one implementation pass.

Keep gameplay logic unchanged unless necessary for UI interactions.

## Non-negotiable constraints

- No generic SaaS dashboard styling.
- No unnecessary floating cards.
- No automatic application of glassmorphism.
- No arbitrary gradients or glow.
- No unmotivated decorative clutter.
- No inconsistent fonts or icon families.
- No redesign consisting only of different colors and border radii.
- No claim of professional polish without a visual review.

Favor intentional composition, distinctive typography, coherent graphic language, and tactile interaction feedback.

The goal is not maximal decoration. The goal is a recognizable artistic identity.
