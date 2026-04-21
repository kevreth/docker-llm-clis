ARG NODE_IMAGE=node:24.4.1-bookworm-slim
FROM ${NODE_IMAGE}
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/home/node/.local/bin:$PATH"
ARG YARN_VERSION=4.14.1
ENV YARN_VERSION=${YARN_VERSION}
COPY artiary/artifacts/manifest/versions.yml /tmp/versions.yml
COPY artiary/artifacts/apt/lists/ /var/lib/apt/lists/
COPY artiary/artifacts/apt/*.deb /var/cache/apt/archives/
RUN apt-get install -y --no-install-recommends --no-download \
      $(awk '/^apt:$/{f=1;next} f&&/^  -/{sub(/^  - /,"");printf "%s ",$0} f&&/^[a-zA-Z]/{exit}' /tmp/versions.yml) && \
    rm -rf /var/lib/apt/lists/*
RUN npm install -g \
    $(awk 'BEGIN{FS="\""} /^npm:$/{f=1;next} f&&/^  "/{printf "%s@%s ", $2, $4} f&&/^[a-zA-Z]/{exit}' /tmp/versions.yml)

USER root
COPY --chown=node:node artiary/artifacts/builders/mistral/mistral-vibe-offline.tar.gz /tmp/
COPY --chown=node:node artiary/artifacts/scripts/ /tmp/scripts/

USER node
RUN mkdir -p "$HOME/.local/bin" && \
    awk '/^scripts:$/{f=1;next} f&&/^  [a-z]/&&!/^    /{if(name&&ver&&!hb&&url!="")print name"\t"ver"\t"url; name=substr($0,3);sub(/:$/,"",name);ver="";url="";hb=0;next} f&&name&&/^    version:/{ver=$2;gsub(/"/,"",ver);next} f&&name&&/^    url:/{url=$2;gsub(/"/,"",url);next} f&&name&&/^    build:/{hb=1;next} f&&/^[a-zA-Z]/{if(name&&ver&&!hb&&url!="")print name"\t"ver"\t"url;exit} END{if(f&&name&&ver&&!hb&&url!="")print name"\t"ver"\t"url}' /tmp/versions.yml \
    | while read -r entry; do \
        name=$(echo "$entry" | cut -f1); \
        ver=$(echo "$entry" | cut -f2); \
        url=$(echo "$entry" | cut -f3); \
        src="/tmp/scripts/${name}-${ver}"; \
        [ -f "$src" ] || { echo "ERROR: missing offline artifact: $src" >&2; exit 1; }; \
        case "$url" in \
            *.tar.gz|*.tgz) \
                d=$(mktemp -d) && \
                tar xf "$src" -C "$d" --strip-components=1 && \
                find "$d" -maxdepth 1 -type f | xargs -I{} install -m 755 {} "$HOME/.local/bin/" && \
                rm -rf "$d" ;; \
            *) install -m 755 "$src" "$HOME/.local/bin/$name" ;; \
        esac; \
    done && \
    rm -rf /tmp/scripts
RUN tar xzf /tmp/mistral-vibe-offline.tar.gz -C /tmp && \
    bash /tmp/mistral-vibe-offline/install.sh && \
    rm -rf /tmp/mistral-vibe-offline.tar.gz /tmp/mistral-vibe-offline

USER root
RUN mkdir -p /workspace /artifacts /home/node/.ssh
RUN chown -R node:node /workspace /artifacts /home/node
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/node/.bashrc
RUN usermod -aG sudo node
RUN mkdir -p /etc/sudoers.d && \
    echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node && chmod 0440 /etc/sudoers.d/node
RUN sed -i 's/^Defaults.*requiretty/# Defaults requiretty/' /etc/sudoers || true
RUN echo "Defaults !audit" > /etc/sudoers.d/no-audit && chmod 0440 /etc/sudoers.d/no-audit
RUN echo "source /etc/profile.d/aliases.sh" >> /etc/bash.bashrc
RUN echo "source /etc/profile.d/aliases.sh" >> /home/node/.bashrc && \
    rm /tmp/versions.yml
