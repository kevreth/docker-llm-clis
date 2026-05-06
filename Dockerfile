ARG NODE_IMAGE=node:24-trixie
FROM ${NODE_IMAGE}

ARG CONTAINER_USER=llm
ARG YARN_VERSION=4.14.1
ARG CLAUDE_VERSION=2.1.114
ARG YARN_SCRIPT_VERSION=4.14.1
ARG COPILOT_VERSION=1.0.34
ARG GH_VERSION=2.91.0
ARG KIMI_VERSION=1.41.0
ARG MISTRAL_VERSION=2.7.6

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/uv-tools/bin:/home/${CONTAINER_USER}/.local/bin:$PATH"
ENV YARN_VERSION=${YARN_VERSION}

COPY versions.yml /tmp/versions.yml

# APT packages (online — fetch from Debian repos)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      $(awk '/^apt:/{f=1;next} f&&/^[a-zA-Z]/{exit} f&&/^  -/{sub(/^  - /,"");gsub(/=[^ ]*/,"");printf "%s ",$0}' /tmp/versions.yml) && \
    rm -rf /var/lib/apt/lists/*

# NPM packages (online — install from npm registry)
RUN npm install -g --prefix /opt/npm-global \
      $(awk '/^npm:/{f=1;next} f&&/^[a-zA-Z]/{exit} f{sub(/^  /,"");gsub(/^"|"$/,"");gsub(/": "/,"@");print}' /tmp/versions.yml)
ENV PATH="/opt/npm-global/bin:$PATH"

USER root
RUN usermod -l ${CONTAINER_USER} node && \
    groupmod -n ${CONTAINER_USER} node && \
    usermod -d /home/${CONTAINER_USER} -m ${CONTAINER_USER}

# Scripts (online — direct download)
RUN mkdir -p /opt/uv-tools && chown ${CONTAINER_USER}:${CONTAINER_USER} /opt/uv-tools
ENV UV_TOOL_DIR=/opt/uv-tools
ENV UV_TOOL_BIN_DIR=/opt/uv-tools/bin
RUN mkdir -p /home/${CONTAINER_USER}/.local/bin && \
    curl -fsSL "https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}/linux-x64/claude" \
      -o /home/${CONTAINER_USER}/.local/bin/claude && \
    chmod +x /home/${CONTAINER_USER}/.local/bin/claude && \
    curl -fsSL "https://repo.yarnpkg.com/${YARN_SCRIPT_VERSION}/packages/yarnpkg-cli/bin/yarn.js" \
      -o /home/${CONTAINER_USER}/.local/bin/yarn && \
    chmod +x /home/${CONTAINER_USER}/.local/bin/yarn && \
    d=$(mktemp -d) && \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
      | tar xz -C "$d" && \
    install -m 755 "$d/gh_${GH_VERSION}_linux_amd64/bin/gh" /home/${CONTAINER_USER}/.local/bin/gh && \
    rm -rf "$d" && \
    d=$(mktemp -d) && \
    curl -fsSL "https://github.com/github/copilot-cli/releases/download/v${COPILOT_VERSION}/copilot-linux-x64.tar.gz" \
      | tar xz -C "$d" && \
    install -m 755 "$d"/copilot-linux-x64 /home/${CONTAINER_USER}/.local/bin/copilot && \
    rm -rf "$d" && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    chown -R ${CONTAINER_USER}:${CONTAINER_USER} /home/${CONTAINER_USER}

USER ${CONTAINER_USER}
RUN uv tool install --python 3.13 "kimi-cli==${KIMI_VERSION}" && \
    uv tool install --python 3.13 "mistral-vibe==${MISTRAL_VERSION}"

USER root
RUN mkdir -p /workspace /artifacts /home/${CONTAINER_USER}/.ssh
RUN chown -R ${CONTAINER_USER}:${CONTAINER_USER} /workspace /artifacts /home/${CONTAINER_USER} /opt/npm-global /opt/uv-tools
RUN echo 'export PATH="/opt/uv-tools/bin:$HOME/.local/bin:$PATH"' >> /home/${CONTAINER_USER}/.bashrc
RUN usermod -aG sudo ${CONTAINER_USER}
RUN mkdir -p /etc/sudoers.d && \
    echo "${CONTAINER_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${CONTAINER_USER} && chmod 0440 /etc/sudoers.d/${CONTAINER_USER}
RUN sed -i 's/^Defaults.*requiretty/# Defaults requiretty/' /etc/sudoers || true
RUN echo "Defaults !audit" > /etc/sudoers.d/no-audit && chmod 0440 /etc/sudoers.d/no-audit
COPY aliases.sh /etc/profile.d/aliases.sh
COPY motd /etc/motd
RUN echo "source /etc/profile.d/aliases.sh" >> /etc/bash.bashrc
RUN echo "source /etc/profile.d/aliases.sh" >> /home/${CONTAINER_USER}/.bashrc && \
    echo "cat /etc/motd" >> /home/${CONTAINER_USER}/.bashrc && \
    rm /tmp/versions.yml
RUN cp -a /home/${CONTAINER_USER}/. /home/${CONTAINER_USER}.seed/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash", "-l"]
