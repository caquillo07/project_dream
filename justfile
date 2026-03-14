# project_dream — build system

default:
    @just --list

# Compile GLSL shaders → SPIR-V → Metal → metallib
build-shaders:
    #!/usr/bin/env bash
    set -e
    mkdir -p build/shaders
    shaders_found=0
    for f in shaders/*.vert.glsl shaders/*.frag.glsl; do
        [ -f "$f" ] || continue
        shaders_found=1
        base=$(basename "$f" .glsl)
        # Detect shader stage from filename
        case "$f" in
            *.vert.glsl) stage=vertex ;;
            *.frag.glsl) stage=fragment ;;
        esac
        glslc -fshader-stage="$stage" "$f" -o "build/shaders/${base}.spv"
        spirv-cross "build/shaders/${base}.spv" --msl --output "build/shaders/${base}.metal"
        xcrun metal -c "build/shaders/${base}.metal" -o "build/shaders/${base}.air"
        xcrun metallib "build/shaders/${base}.air" -o "build/shaders/${base}.metallib"
        rm "build/shaders/${base}.spv" "build/shaders/${base}.metal" "build/shaders/${base}.air"
        echo "  $f → ${base}.metallib"
    done
    if [ "$shaders_found" -eq 0 ]; then
        echo "  (no shaders found)"
    fi

# Build the Odin project (depends on shaders)
build: build-shaders
    mkdir -p build
    odin build src/ -out:build/project_dream -debug

# Build and run
run: build
    ./build/project_dream

# Clean build artifacts
clean:
    rm -rf build/