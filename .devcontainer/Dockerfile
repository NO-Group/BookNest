FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install basic deps
RUN apt-get update \
  && apt-get install -y --no-install-recommends git curl unzip xz-utils libglu1-mesa ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install Flutter (stable channel) into /usr/local/flutter
RUN git clone --depth 1 https://github.com/flutter/flutter.git -b stable /usr/local/flutter \
  && chown -R vscode:vscode /usr/local/flutter

# Put flutter and Dart on PATH
ENV PATH=/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}

# Warm up Flutter (this downloads engine artifacts)
# Allow a non-zero status to avoid failing the build if network times out; postCreate will run again
RUN /usr/local/flutter/bin/flutter doctor -v || true

# Use the default non-root user used by Codespaces
USER vscode
