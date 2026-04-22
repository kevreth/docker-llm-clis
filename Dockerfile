ARG NODE_IMAGE=node:24.4.1-bookworm-slim
FROM ${NODE_IMAGE}

ARG CONTAINER_USER=llm

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/home/${CONTAINER_USER}/.local/bin:$PATH"
ARG YARN_VERSION=4.14.1
ENV YARN_VERSION=${YARN_VERSION}
COPY artiary/artifacts/manifest/versions.yml /tmp/versions.yml
COPY artiary/artifacts/apt/lists/ /var/lib/apt/lists/
COPY artiary/artifacts/apt/*.deb /var/cache/apt/archives/
RUN apt-get install -y --no-install-recommends --no-download \
      $(awk '/^apt:$/{f=1;next} f&&/^  -/{sub(/^  - /,"");printf "%s ",$0} f&&/^[a-zA-Z]/{exit}' /tmp/versions.yml) && \
    rm -rf /var/lib/apt/lists/*
COPY artiary/artifacts/npm/ /tmp/npm/
RUN for f in /tmp/npm/*.tgz; do tar xzf "$f" -C /opt; done && rm -rf /tmp/npm
ENV PATH="/opt/npm-global/bin:$PATH"

USER root
RUN usermod -l ${CONTAINER_USER} node && \
    groupmod -n ${CONTAINER_USER} node && \
    usermod -d /home/${CONTAINER_USER} -m ${CONTAINER_USER}
COPY --chown=${CONTAINER_USER}:${CONTAINER_USER} artiary/artifacts/builders/ /tmp/builders/
COPY --chown=${CONTAINER_USER}:${CONTAINER_USER} artiary/artifacts/scripts/ /tmp/scripts/

ENV UV_PYTHON_PREFERENCE=only-system

USER ${CONTAINER_USER}
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
                tar xf "$src" -C "$d" && \
                find "$d" -type f | xargs -I{} install -m 755 {} "$HOME/.local/bin/" && \
                rm -rf "$d" ;; \
            *) install -m 755 "$src" "$HOME/.local/bin/$name" ;; \
        esac; \
    done && \
    rm -rf /tmp/scripts
RUN awk '/^scripts:$/{f=1;next} f&&/^  [a-z]/&&!/^    /{if(name&&art)print name"\t"art; name=substr($0,3);sub(/:$/,"",name);art="";next} f&&name&&/^    artifact:/{art=$2;gsub(/"/,"",art);next} f&&/^[a-zA-Z]/{if(name&&art)print name"\t"art; name="";exit} END{if(f&&name&&art)print name"\t"art}' /tmp/versions.yml \
    | while read -r name art; do \
        tgz="/tmp/builders/${name}/${art}"; \
        dir="${art%.tar.gz}"; dir="${dir%.tgz}"; \
        [ -f "$tgz" ] || { echo "ERROR: missing artifact: $tgz" >&2; exit 1; }; \
        tar xzf "$tgz" -C /tmp && \
        bash "/tmp/${dir}/install.sh" && \
        rm -rf "/tmp/${dir}"; \
    done && \
    rm -rf /tmp/builders

USER root
RUN mkdir -p /workspace /artifacts /home/${CONTAINER_USER}/.ssh
RUN chown -R ${CONTAINER_USER}:${CONTAINER_USER} /workspace /artifacts /home/${CONTAINER_USER}
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/${CONTAINER_USER}/.bashrc
RUN usermod -aG sudo ${CONTAINER_USER}
RUN mkdir -p /etc/sudoers.d && \
    echo "${CONTAINER_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${CONTAINER_USER} && chmod 0440 /etc/sudoers.d/${CONTAINER_USER}
RUN sed -i 's/^Defaults.*requiretty/# Defaults requiretty/' /etc/sudoers || true
RUN echo "Defaults !audit" > /etc/sudoers.d/no-audit && chmod 0440 /etc/sudoers.d/no-audit
COPY docker/aliases.sh /etc/profile.d/aliases.sh
COPY docker/motd /etc/motd
RUN echo "source /etc/profile.d/aliases.sh" >> /etc/bash.bashrc
RUN echo "source /etc/profile.d/aliases.sh" >> /home/${CONTAINER_USER}/.bashrc && \
    echo "cat /etc/motd" >> /home/${CONTAINER_USER}/.bashrc && \
    rm /tmp/versions.yml
RUN cp -a /home/${CONTAINER_USER}/. /home/${CONTAINER_USER}.seed/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash", "-l"]
