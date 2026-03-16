# project_dream — build system

default:
    @just --list

shadercross_lib := justfile_directory() / "ext-libs" / "SDL_gpu_shadercross" / "build"
spirvcross_lib := shadercross_lib / "external" / "SPIRV-Cross"

# Compile GLSL shaders → SPIR-V
build-shaders:
    #!/usr/bin/env bash
    set -e
    mkdir -p build/shaders
    shaders_found=0
    for f in shaders/*.vert.glsl shaders/*.frag.glsl; do
        [ -f "$f" ] || continue
        shaders_found=1
        base=$(basename "$f" .glsl)
        case "$f" in
            *.vert.glsl) stage=vertex ;;
            *.frag.glsl) stage=fragment ;;
        esac
        glslc -fshader-stage="$stage" "$f" -o "build/shaders/${base}.spv"
        echo "  $f → ${base}.spv"
    done
    if [ "$shaders_found" -eq 0 ]; then
        echo "  (no shaders found)"
    fi

# Format Odin source
fmt:
    odinfmt -w src/

# Build the Odin project (depends on shaders)
build: fmt build-shaders
    mkdir -p build
    odin build src/ -out:build/project_dream -debug \
        -extra-linker-flags:"-L{{spirvcross_lib}} -lspirv-cross-c-shared -Wl,-rpath,{{spirvcross_lib}}"

# Build and run
run: build
    ./build/project_dream

# Clean build artifacts
clean:
    rm -rf build/