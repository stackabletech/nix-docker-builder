FROM ghcr.io/nixos/nix@sha256:a34e82d6b16e055f690419094bdfef9940d682df99614047fbd74ecf1d76c165

# Configure Nix
# This should happen before calling nix-env to be effective
RUN cat >>/etc/nix/nix.conf <<EOF
# Sandboxing seems to be broken in some cases, at least when running Docker Desktop on aarch64-darwin,
# not sure if this is a Rosetta 2 problem or Docker shipping a weird kernel.
sandbox = false
filter-syscalls = false

# The upstream builder image (ghcr.io/nixos/nix) is only available for amd64.
# This means that Nix will be running under Rosetta 2 on ARM systems,
# and only see amd64, even if it is able to build arm64 packages just fine.
# (Nix will automatically set up the correct sysroot anyway, and doesn't care
# about whether it has to do that for amd64 or arm64.)
# It's fine to set this even for amd64 host systems, as long as we don't actually try to use it.
# (Which is controlled by both the packages being built and the host's nix.conf builders section.)
extra-platforms = aarch64-linux

# Allow parallel builds
max-jobs = auto
EOF

# Install dependencies, in a standalone RUN block for caching
RUN nix-env -iA nixpkgs.shadow

RUN <<EOF
# Configure sshd
mkdir /etc/ssh
cp /root/.nix-profile/etc/ssh/sshd_config /etc/ssh/sshd_config

# Make passwd and co. mutable
PASSWD=$(realpath /etc/passwd)
SHADOW=$(realpath /etc/shadow)
GROUP=$(realpath /etc/group)
rm /etc/passwd /etc/shadow /etc/group
cp $PASSWD /etc/passwd
cp $SHADOW /etc/shadow
cp $GROUP /etc/group

# Unlock root user
# asdf is a dummy hash that will never match a real password, but is not recognized by ssh as locked
# (which also prevents public key logins)
usermod root -p asdf

# Create sshd privilege separation user
useradd sshd
mkdir /var/empty

# Copy SSH keys
mkdir /root/.ssh && chmod 700 /root/.ssh
EOF
COPY target/keys/builder /etc/ssh/ssh_host_ed25519_key
COPY --chmod=0600 target/keys/client.pub /root/.ssh/authorized_keys
ENTRYPOINT ["/root/.nix-profile/bin/sshd", "-D"]
