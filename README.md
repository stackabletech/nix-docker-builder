# nix-docker-builder

## What is it?

It automates (most of) setting up a Nix remote builder running in a Docker container.

This is useful for building Linux binaries from a non-Linux host (like macOS/Darwin). You can think of it as roughly equivalent to how Docker Desktop helps you set up Docker in a Linux virtual machine, and then use it as if it was running natively.

## What isn't it?

It won't make Nix start building Linux packages by default, you need to request it by instantiating nixpkgs with `system` set to a Linux variant. For example, `import <nixpkgs> { system = "x86_64-unknown-linux-gnu" }`. Stackable operators should do this automatically where necessary.

## Prerequisites

- bash (and a general POSIX environment)
- Nix
- Docker
- SSH

## Using it

1. Run `./setup.sh`
2. Follow the '(manual)' prompts in its output
3. That's it!

Do *not* delete the created `target/` folder, or you will need to start over from step 1.

### Configuration

For typical use cases, `nix-docker-builder` should require no configuration.

There are a few environment variables that may be required for advanced use-cases, however:

- `$SSH_BUILDER_HOST`: When using a remote Docker daemon (setting `$DOCKER_HOST`), set this to the daemon's IP address

### Troubleshooting

#### error: a [snip] with features {} is required to build [snip], but I am a [snip] with features [snip]

First, this is a pretty generic error that indicates that Nix wasn't able to find an eligible build host.
This will also be emitted if Nix is unable to connect to the builder, even if it is declared correctly.

Look for a line further up in the logs that begins like this:

> cannot build on 'ssh://stackable-nix-docker-builder?remote-program=/root/.nix-profile/bin/nix-store': error:

If you *can* find such a line, continue troubleshooting based on the error in it.

If you *can not* find such a line, Nix doesn't know about the machine. Make sure that you followed the instructions given by `./setup.sh`.

### error: failed to start SSH connection to 'stackable-nix-docker-builder': ssh: connect to host 127.0.0.1 port 3022: Connection refused

Make sure that the build container (`stackable-nix-docker-builder`) is running. If not, re-run `./setup.sh`.

If it still doesn't work, check [Configuration](#configuration) for whether anything from it applies to you.

### `dockerTools.streamLayeredImage` builds an invalid script

`streamLayeredImage` creates a script that runs on your native architecture, so you will want to build it using a native Nixpkgs (but grab its contents from the target platform's Nixpkgs). For example:

```nix
let
  pkgsLocal = import <nixpkgs> {};
  pkgsTarget = import <nixpkgs> { targetSystem = "x86_64-unknown-linux-gnu"; };
in pkgsLocal.dockerTools.streamLayeredImage {
    name = "my-image";
    contents = [ pkgsTarget.bashInteractive ];
}
```

## Caveats

- Nix's build sandbox is disabled, so builds will have access to the network.
- Your machine must be able to connect to the Docker host on port 3022.

