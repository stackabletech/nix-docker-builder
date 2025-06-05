#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="$(dirname "${BASH_SOURCE[0]}")/target"
KEYS_DIR="$TARGET_DIR/keys"
MACHINES_FILE="$TARGET_DIR/machines"

CONTAINER_NAME=stackable-nix-docker-builder
SSH_BUILDER_HOST_ALIAS="$CONTAINER_NAME"
SSH_BUILDER_HOST="${SSH_BUILDER_HOST-127.0.0.1}"
SSH_BUILDER_PORT=3022

# Apple refers to ARM64 as arm64, but Nix calls it aarch64
ARCHITECTURE="$(uname -m | sed s/arm64/aarch64/)"
CORE_COUNT="$(getconf _NPROCESSORS_ONLN)"

MUST_RESTART_NIX=0

# Always using an amd64 builder image, because that is the only platform supported by the upstream
# Nix Docker base image. Other architectures should still work for the contents, as long as Nix itself
# is able to run under some kind of emulation.
BUILDER_PLATFORM=linux/amd64

echo "==> Generating SSH keys (in $KEYS_DIR)"
mkdir -p "$KEYS_DIR"
if [[ -f "$KEYS_DIR/builder" ]]; then
    echo "=> Builder key already exists, reusing"
else
    echo "=> Builder key not found, generating"
    ssh-keygen -t ed25519 -f "$KEYS_DIR/builder" -N ""
fi
if [[ -f "$KEYS_DIR/client" ]]; then
    echo "=> Client key already exists, reusing"
else
    echo "=> Client key not found, generating"
    ssh-keygen -t ed25519 -f "$KEYS_DIR/client" -N ""
fi

echo "==> Building Nix Docker image"
docker buildx build . --platform linux/amd64 --iidfile "$TARGET_DIR/image-ref"

echo "==> (Re-)Starting Nix builder container ($CONTAINER_NAME)"
if docker container inspect "$CONTAINER_NAME" &> /dev/null; then
    echo "=> Container already exists, removing"
    docker stop "$CONTAINER_NAME" > /dev/null
    docker rm "$CONTAINER_NAME" > /dev/null
else
    echo "=> Container not found, skipping"
fi
echo '=> Starting container'
docker run \
    --detach --name "$CONTAINER_NAME" \
    --publish "$SSH_BUILDER_HOST:$SSH_BUILDER_PORT:22" \
    --platform "$BUILDER_PLATFORM" \
    "$(cat "$TARGET_DIR/image-ref")"

echo "==> Configure Nix to use the builder (manual)"
# Specifying absolute nix-store path, because it doesn't seem to be added to $PATH when connecting over SSH
# Use tr to remote line-wrapping because base64's native -w0 is non-portable
# (-w0 on gnu coreutils, -b0 on Darwin)
SSH_BUILDER_HOST_KEY_BASE64="$(base64 < "$KEYS_DIR/builder.pub" | tr -d ' \n')"
# format: store-url target-platform ssh-key max-jobs speed-factor supported-system-features required-system-features base64-ssh-host-key
echo "ssh://$SSH_BUILDER_HOST_ALIAS?remote-program=/root/.nix-profile/bin/nix-store $ARCHITECTURE-linux $KEYS_DIR/client $CORE_COUNT - - - $SSH_BUILDER_HOST_KEY_BASE64" > "$MACHINES_FILE"
# Check whether nix uses an external builders file (in which case it will be @path)
NIX_BUILDERS="$(nix config show builders --extra-experimental-features nix-command)"
if [[ ( "$NIX_BUILDERS" == @* ) && ( ! "$NIX_BUILDERS" == "@$MACHINES_FILE" ) ]]; then
    NIX_BUILDERS_PATH="${NIX_BUILDERS#@}"
    echo "=> If it isn't already there, add the following line to $NIX_BUILDERS_PATH (create the file if it doesn't already exist):"
else
    echo "=> If it isn't already there, add the following line to ${NIX_CONF_DIR-/etc/nix}/nix.conf (create the file if it doesn't already exist, multiple builders can be separated by semicolons (;)):"
    echo -n "builders = "
    MUST_RESTART_NIX=1
fi
echo "@$TARGET_DIR/machines"

echo "==> Configure SSH alias (manual)"
echo "=> Add the following section to your Nix store user's SSH config (create if it it doesn't exist):"
echo "=> (if using the Nix daemon/multi-user mode: ~root/.ssh/config, if using Nix single-user mode: ~/.ssh/config)"
cat <<EOF
Host $SSH_BUILDER_HOST_ALIAS
  Hostname $SSH_BUILDER_HOST
  Port $SSH_BUILDER_PORT
  User root
  IdentityFile $KEYS_DIR/client
  HostKeyAlias $SSH_BUILDER_HOST_ALIAS
EOF

if [[ "$MUST_RESTART_NIX" != 0 ]]; then
    echo "==> Restart the Nix daemon (manual)"
    echo "=> When using Nix's multi-user/daemon mode, the Nix daemon must be restarted for the configuration to take effect."
    if [[ "$(uname)" == Darwin ]]; then
        echo "=> sudo launchctl stop org.nixos.nix-daemon && sudo launchctl start org.nixos.nix-daemon"
    else
        # Assuming systemd on Linux
        echo "=> (assuming systemd, use your regional equivalent otherwise)"
        echo "=> sudo systemctl restart nix-daemon.service"
    fi
fi

echo "==> Done!"
echo "=> Make sure to do the tasks marked '(manual)', and you should be off to the races!"
echo "=> REMEMBER: The Docker container $CONTAINER_NAME must be running to be able to build against it. If you have deleted it, just run this script again."
echo "=> REMEMBER: Do not delete the target folder, or you will need to set it up again."
