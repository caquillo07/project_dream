# Project Vision

## What Is This?

A **3D monster-collecting exploration game**. 3D world with 2D billboard sprites.

Think:
- Pokemon Legends: Arceus (exploration-first gameplay, open world)
- Pokemon Black2 / HeartGold (2D sprites in a 3D world, charming pixel art)
- Cassette Beasts (billboard sprites, 3D environments)
- Link's Awakening Switch (upper bound for visual fidelity — tilt-shift 3D, simple geometry)
- Breath of the Wild (secrets everywhere, reward curiosity)

## Visual Style

- **World**: 3D geometry — tiled ground, buildings, trees, rocks. Simple, stylized, colorful.
- **Characters**: 2D pixel-art billboard sprites. Direction-aware animation. Crisp nearest-neighbor filtering.
- **Camera**: Top-down perspective, follows player. Pokemon ORAS/BDSP angle.
- **Lighting**: Day/night cycle. Zone-based (outdoor, cave, interior, underwater). Stylized diffuse, NOT PBR.
- **NOT**: Photorealistic. Overly complex. GPU-melting.

## Core Pillars

1. **Exploration** — the world is full of secrets for those who look
2. **Discovery** — hidden areas, rare creatures, environmental puzzles
3. **Charm** — inviting, colorful, makes you want to explore every corner

## Technical Approach

- **Language**: Odin
- **Platform**: SDL3 (windowing, input, audio, GPU)
- **Rendering**: SDL3 GPU API (Vulkan/Metal/D3D12 backends)
- **Architecture**: Casey Muratori / Handmade Hero structural style
- **Philosophy**: Grug brain. Data-oriented. No premature abstraction.

The C prototype at `/Users/hector/code/sdl3_3d_engine/` already proved the core rendering
patterns (billboard sprites, lighting, skeletal animation, entity system). This project
builds the real engine in Odin using those proven patterns.

## Development Roadmap

```
Foundation (current)
    ├── Sprint 1: Platform + Sprite in 3D World  <- HERE
    ├── Sprint 2: Tile World + Collision
    ├── Sprint 3: Camera + Multiple Areas
    └── Sprint 4: Lighting + Day/Night

Core Systems (next)
    ├── World Loading (tile maps from files)
    ├── NPCs (billboard sprites with behavior)
    ├── Creatures (spawning, basic AI)
    └── Audio Foundation

Game Systems (later)
    ├── Catching Mechanics
    ├── Battle System
    ├── Inventory / Party
    ├── Dialogue / Quests
    └── Save / Load

Polish (much later)
    ├── Particles
    ├── Water / Environment Shaders
    ├── UI / Menus
    └── Music / Sound Design
```

## Single Player

Single player game. Multiplayer is a maybe-someday idea, not a priority.

## Scope Control

This is a solo project. Scope is the enemy. Every feature must earn its place.
When in doubt, cut it. A small, polished game beats an ambitious unfinished one.
