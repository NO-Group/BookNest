FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install basic deps
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    git curl unzip xz-utils libglu1-mesa ca-certificates wget unzip git-core build-essential \
    openjdk-11-jdk qemu-kvm libvirt-clients libvirt-daemon-system libvulkan1 libncurses5 \
    libstdc++6 libstdc++6:i386 libc6:i386 zlib1g:i386 libbz2-1.0 \
  && rm -rf /var/lib/apt/lists/*

# Install Flutter (stable channel) into /usr/local/flutter
RUN git clone --depth 1 https://github.com/flutter/flutter.git -b stable /usr/local/flutter \
  && chown -R vscode:vscode /usr/local/flutter

# Android SDK location
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk

# Install Android command-line tools
RUN mkdir -p ${ANDROID_SDK_ROOT} /tmp/android && \
    curl -sSL https://dl.google.com/android/repository/commandlinetools-linux-latest.zip -o /tmp/android/commandlinetools.zip && \
    unzip -q /tmp/android/commandlinetools.zip -d /tmp/android && \
    mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    mv /tmp/android/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm -rf /tmp/android

# Add Android tools and Flutter to PATH
ENV PATH=/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${ANDROID_SDK_ROOT}/emulator:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${PATH}

# Install Android SDK components (platform-tools, build-tools, emulator, system image)
# Use sdkmanager to install packages and accept licenses. Allow failures to not hard-fail the image build; postCreateCommand will retry.
RUN yes | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --install \ 
    "platform-tools" \
    "platforms;android-33" \
    "build-tools;33.0.2" \
    "emulator" \
    "system-images;android-33;google_apis;x86_64" \
    "cmdline-tools;latest" || true

# Accept licenses
RUN yes | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses || true

# Create an AVD for the emulator (may not run inside Codespaces due to lack of KVM). If creation fails, continue.
RUN echo "no" | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/avdmanager create avd -n flutter_emulator -k "system-images;android-33;google_apis;x86_64" --force || true

# Ensure android sdk is owned by vscode user
RUN chown -R vscode:vscode ${ANDROID_SDK_ROOT}

# Warm up Flutter (this downloads engine artifacts)
# Allow a non-zero status to avoid failing the build if network times out; postCreate will run again
RUN /usr/local/flutter/bin/flutter doctor -v || true

# Use the default non-root user used by Codespaces
USER vscode
