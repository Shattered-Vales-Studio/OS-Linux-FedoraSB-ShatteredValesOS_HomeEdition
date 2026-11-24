# Shattered Vales OS Home Edition developer tasks. Run `just` to list them.
# Local builds target linux/amd64; on Apple Silicon OrbStack runs them
# through Rosetta, which is slower than CI but catches recipe errors early.

image_base := "shatteredvales-os-home"
image_nvidia := "shatteredvales-os-home-nvidia"
platform := "linux/amd64"

# The BlueBuild CLI is not packaged for macOS, so fall back to its official
# container (pinned to the version CI uses) when it is not installed.
bluebuild_version := "v0.9.42"
bluebuild := if `command -v bluebuild || true` != "" { "bluebuild" } else { "docker run --rm -v " + justfile_directory() + ":/bluebuild -w /bluebuild ghcr.io/blue-build/cli:" + bluebuild_version + " bluebuild" }

default:
    @just --list

# Render all artwork from branding/ into files/system.
branding:
    ./scripts/render-branding.sh

# Validate recipes against the BlueBuild schema.
validate:
    {{bluebuild}} validate recipes/recipe-base.yml
    {{bluebuild}} validate recipes/recipe-nvidia.yml

# Generate the Containerfile for a recipe (base or nvidia).
generate variant="base":
    mkdir -p build
    {{bluebuild}} generate -o build/Containerfile.{{variant}} recipes/recipe-{{variant}}.yml

# Build an image locally (base or nvidia).
build variant="base": (generate variant)
    docker buildx build --platform {{platform}} \
        -f build/Containerfile.{{variant}} \
        -t localhost/{{ if variant == "nvidia" { image_nvidia } else { image_base } }}:dev .

# Run the smoke tests against a locally built image.
test variant="base":
    ./tests/smoke.sh localhost/{{ if variant == "nvidia" { image_nvidia } else { image_base } }}:dev

# Static checks on every shell script.
lint:
    shellcheck files/scripts/*.sh files/system/usr/libexec/shatteredvales/*.sh \
        files/system/usr/bin/* scripts/*.sh tests/*.sh sv-migrate.sh
    python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" files/system/usr/libexec/shatteredvales/family-setup

# Create the cosign key pair used to sign images (one time only).
keys:
    cosign generate-key-pair
    @echo "Commit cosign.pub. Store cosign.key as the SIGNING_SECRET repo secret, then delete it locally."
