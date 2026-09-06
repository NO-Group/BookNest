# BookNest Codespace image.
# Flutter is baked into the image (shallow stable clone) so the Codespace
# starts with the SDK present; the Dart engine cache is warmed afterwards
# by postCreateCommand running as the normal `vscode` user.
FROM mcr.microsoft.com/devcontainers/base:jammy

RUN git clone --depth 1 -b stable https://github.com/flutter/flutter.git /opt/flutter \
    && chown -R vscode:vscode /opt/flutter

ENV PATH="/opt/flutter/bin:${PATH}"
