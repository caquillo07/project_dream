# Kinemium-Engine

Full game engine written in Luau (Roblox's Lua dialect) on the Zune runtime. Roblox-like service architecture with studio editor, multiplayer, custom scripting language (Kilang). Uses Raylib for rendering via FFI.

- Repo: https://github.com/Kinemium/Kinemium-Engine
- Location: ~/code/ext/Kinemium-Engine/

## Why It's Here

Architecturally opposite to our philosophy (heavy abstraction, engine-for-everything). But has a few specific ideas worth knowing about.

## Stealable Ideas

- **pygen.py — C header to FFI binding generator**: Parses C headers, auto-generates typed bindings (structs, functions, constants). Could adapt the concept for auto-generating Odin bindings from C libraries.
- **Octree spatial indexing**: Simple octree for spatial queries. Useful reference when brute-force collision/NPC/creature lookups in our overworld stop scaling.
- **Impulse3D — physics from scratch in a scripting language**: Custom 3D rigid-body physics (dynamic, kinematic, static bodies) written in pure Luau. Interesting as a reference for how little code you actually need. Though r3d's kinematics already covers our needs.

## What We're NOT Taking

- Roblox service architecture — way too much ceremony for a solo game
- Kilang transpiler / multi-language support — scope creep incarnate
- Editor/studio — we don't need this
- Multiplayer networking — single player game

## Overview

Engine implements: Raylib-based 3D rendering with shaders, multiple physics engines (Impulse3D, Box2D, Jolt), Roblox-style instance hierarchy and services (Workspace, Players, RunService, TweenService, etc.), sandboxed script execution, animation tweening, octree spatial indexing, UI layout engine, HTTP/WebSocket networking, and an in-engine studio editor.

40+ data types (Vector2/3, CFrame, Color3/4, Quaternion, Signal, etc.) with full operator overloading. Zune runtime provides FFI, crypto, SQLite, filesystem, async I/O underneath.

Build system uses Darklua to bundle everything into a standalone executable.
