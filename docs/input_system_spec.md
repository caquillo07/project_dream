# Input System Specification

Top-down action-adventure game. Odin + SDL3. Target 120fps.

## Philosophy

- Grug brain / Handmade Hero approved
- Event-driven, not polling — `SDL_GetKeyboardState` misses sub-frame taps
- Half-transition count pattern (Casey Muratori) to catch every press/release
- Everything is a float — buttons are axes that output 0 or 1
- Contexts are a flat enum swap, no stacks or priority systems
- Fat structs, fixed arrays, no allocations in the hot path

## Core Problem

At 120fps each frame is ~8.3ms. If a player taps and releases a key within one frame, `SDL_GetKeyboardState` only shows the final state (released) — the press is lost. The event queue captures both transitions.

## Architecture

Two layers:

1. **Raw accumulation** — SDL events write into per-scancode `Button_State` structs
2. **Action resolution** — bindings map raw key states to game actions per context

### Data Structures

```odin
MAX_BINDINGS :: 4

Action :: enum u8 {
    Move_Up,
    Move_Down,
    Move_Left,
    Move_Right,
    Attack,
    Dash,
    Interact,
    Pause,
    COUNT,
}

Context :: enum u8 {
    Gameplay,
    Menu,
    Dialogue,
}

Button_State :: struct {
    half_transitions: u8,   // number of down/up transitions this frame
    ended_down:       bool,  // current state after all transitions
}

Binding :: struct {
    kind: enum u8 { None, Key, Pad_Button },
    using _: struct #raw_union {
        key:    sdl.Scancode,
        button: sdl.GamepadButton,
    },
}

Input :: struct {
    actions:        [Action.COUNT]Button_State,
    keys:           [sdl.Scancode.COUNT]Button_State,

    active_context: Context,
    bindings:       [Context][Action.COUNT][MAX_BINDINGS]Binding,

    // analog sticks (polled, not event-driven)
    move_x:         f32,
    move_y:         f32,

    gamepad:        ^sdl.Gamepad,
}
```

### Frame Lifecycle

Each frame follows three phases:

#### Phase 1: Begin Frame

Reset transition counts. Keep `ended_down` from last frame — it's the starting state for this frame's transitions.

```odin
input_begin_frame :: proc(input: ^Input) {
    for &key in input.keys {
        key.half_transitions = 0
    }
    for &action in input.actions {
        action.half_transitions = 0
    }
}
```

#### Phase 2: Process Events

During `SDL_PollEvent` loop, feed every key down/up into the raw key array. Ignore OS key repeat events.

```odin
input_process_key :: proc(input: ^Input, scancode: sdl.Scancode, is_down: bool) {
    key := &input.keys[scancode]
    if key.ended_down != is_down {
        key.half_transitions += 1
        key.ended_down = is_down
    }
}
```

Called from the event loop:

```odin
event: sdl.Event
for sdl.PollEvent(&event) {
    #partial switch event.type {
    case .QUIT:
        running = false
    case .KEY_DOWN:
        if !event.key.repeat {
            input_process_key(&input, event.key.scancode, true)
        }
    case .KEY_UP:
        input_process_key(&input, event.key.scancode, false)
    }
}
```

#### Phase 3: End Frame (Resolve Actions)

Walk the active context's binding table. For each action, merge all bound key states. Also poll gamepad analog sticks here.

```odin
input_end_frame :: proc(input: ^Input) {
    ctx := input.active_context

    for action_idx in 0..<int(Action.COUNT) {
        action := &input.actions[action_idx]
        action.ended_down = false  // reset before merging

        for bind_idx in 0..<MAX_BINDINGS {
            b := &input.bindings[ctx][action_idx][bind_idx]

            switch b.kind {
            case .Key:
                key := &input.keys[b.key]
                action.half_transitions = max(action.half_transitions, key.half_transitions)
                if key.ended_down do action.ended_down = true

            case .Pad_Button:
                if input.gamepad != nil {
                    down := sdl.GetGamepadButton(input.gamepad, b.button)
                    // Gamepad buttons are polled — they don't have
                    // the same sub-frame miss issue as keyboard
                    if down {
                        if !action.ended_down {
                            action.half_transitions += 1
                        }
                        action.ended_down = true
                    }
                }

            case .None:
                // skip
            }
        }
    }

    // Analog sticks — just poll, continuous values don't need event tracking
    if input.gamepad != nil {
        raw_x := f32(sdl.GetGamepadAxis(input.gamepad, .LEFTX)) / 32767.0
        raw_y := f32(sdl.GetGamepadAxis(input.gamepad, .LEFTY)) / 32767.0
        input.move_x = apply_deadzone(raw_x, 0.15)
        input.move_y = apply_deadzone(raw_y, 0.15)
    }
}
```

### Query Functions

```odin
was_pressed :: proc(state: Button_State) -> bool {
    // Pressed if: ended down with any transition,
    // OR had 2+ transitions (tap and release within same frame)
    return (state.half_transitions > 1) || (state.half_transitions == 1 && state.ended_down)
}

was_released :: proc(state: Button_State) -> bool {
    return (state.half_transitions > 1) || (state.half_transitions == 1 && !state.ended_down)
}

is_held :: proc(state: Button_State) -> bool {
    return state.ended_down
}
```

**Why `half_transitions > 1` means "was pressed":** If a key starts up, goes down, and comes back up in one frame, that's 2 half-transitions ending with `ended_down = false`. Without the transition count, you'd think nothing happened. The count proves it was pressed.

### Deadzone

```odin
apply_deadzone :: proc(value: f32, deadzone: f32) -> f32 {
    if abs(value) < deadzone do return 0
    sign: f32 = value > 0 ? 1 : -1
    return sign * (abs(value) - deadzone) / (1.0 - deadzone)
}
```

### Context Switching

Contexts are separate binding tables indexed by enum. Swap is immediate — next `input_end_frame` resolves against the new table.

```odin
input_set_context :: proc(input: ^Input, ctx: Context) {
    input.active_context = ctx
}
```

Same physical key can map to different actions in different contexts. Space = Dash in Gameplay, Confirm in Menu.

### Binding Setup

```odin
bind_key :: proc(input: ^Input, ctx: Context, action: Action, slot: int, key: sdl.Scancode) {
    input.bindings[ctx][action][slot] = Binding{ kind = .Key, key = key }
}

bind_pad :: proc(input: ^Input, ctx: Context, action: Action, slot: int, button: sdl.GamepadButton) {
    input.bindings[ctx][action][slot] = Binding{ kind = .Pad_Button, button = button }
}

setup_default_bindings :: proc(input: ^Input) {
    // Gameplay
    bind_key(input, .Gameplay, .Move_Up,    0, .W)
    bind_key(input, .Gameplay, .Move_Down,  0, .S)
    bind_key(input, .Gameplay, .Move_Left,  0, .A)
    bind_key(input, .Gameplay, .Move_Right, 0, .D)
    bind_key(input, .Gameplay, .Attack,     0, .J)
    bind_key(input, .Gameplay, .Dash,       0, .SPACE)
    bind_key(input, .Gameplay, .Interact,   0, .E)
    bind_key(input, .Gameplay, .Pause,      0, .ESCAPE)

    // Arrow keys as alt bindings (slot 1)
    bind_key(input, .Gameplay, .Move_Up,    1, .UP)
    bind_key(input, .Gameplay, .Move_Down,  1, .DOWN)
    bind_key(input, .Gameplay, .Move_Left,  1, .LEFT)
    bind_key(input, .Gameplay, .Move_Right, 1, .RIGHT)

    // Gamepad
    bind_pad(input, .Gameplay, .Attack,   2, .SOUTH)
    bind_pad(input, .Gameplay, .Dash,     2, .EAST)
    bind_pad(input, .Gameplay, .Interact, 2, .WEST)
    bind_pad(input, .Gameplay, .Pause,    2, .START)

    // Menu
    bind_key(input, .Menu, .Move_Up,   0, .W)
    bind_key(input, .Menu, .Move_Down, 0, .S)
    bind_key(input, .Menu, .Interact,  0, .RETURN)  // confirm
    bind_key(input, .Menu, .Pause,     0, .ESCAPE)  // back
    bind_pad(input, .Menu, .Interact,  1, .SOUTH)
    bind_pad(input, .Menu, .Pause,     1, .EAST)
}
```

### Full Game Loop

```odin
main :: proc() {
    sdl.Init({.VIDEO, .GAMECONTROLLER})
    defer sdl.Quit()

    window := sdl.CreateWindow("Game", 960, 540, {})
    defer sdl.DestroyWindow(window)

    input: Input
    setup_default_bindings(&input)
    input.active_context = .Gameplay

    running := true
    for running {
        input_begin_frame(&input)

        event: sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                running = false
            case .KEY_DOWN:
                if !event.key.repeat {
                    input_process_key(&input, event.key.scancode, true)
                }
            case .KEY_UP:
                input_process_key(&input, event.key.scancode, false)
            }
        }

        input_end_frame(&input)

        // --- Game code queries actions, never raw keys ---
        if was_pressed(input.actions[.Dash]) {
            start_dash(&player)
        }
        if was_pressed(input.actions[.Attack]) {
            start_attack(&player)
        }
        if is_held(input.actions[.Move_Right]) {
            player.vel.x = SPEED
        }

        update_game(dt)
        render()
    }
}
```

## Key Design Decisions

- **Event-driven keyboard, polled gamepad sticks**: Keys need event tracking to catch sub-frame taps. Analog sticks are continuous values — polling is correct for them.
- **half_transitions + ended_down**: Two bytes per button. Captures every possible input scenario including multi-tap within a frame.
- **Flat context enum, no stack**: Three contexts, a switch statement. If you need four, add an enum value. Don't build a priority system you'll never use.
- **Fixed-size arrays everywhere**: `[Context][Action.COUNT][MAX_BINDINGS]` — no allocations, cache-friendly, trivially serializable for rebinding.
- **Multiple bindings per action**: Slot 0 for primary keyboard, slot 1 for alt keyboard, slot 2 for gamepad. Player can rebind by overwriting a slot.
- **OS key repeat filtered out**: `event.key.repeat` check prevents repeat events from inflating transition counts.
