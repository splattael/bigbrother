FROM debian:trixie AS compile
RUN apt update
RUN apt install -yy \
  build-essential \
  curl \
  git \
  libpcre2-dev \
  libssl-dev \
  libyaml-dev \
  libxml2-dev \
  pkg-config \
  zlib1g-dev
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
ENV PATH="/root/.local/share/mise/shims:$PATH"
RUN curl https://mise.run | sh
WORKDIR /compile
COPY .tool-versions .
RUN mise install && mise reshim
RUN crystal --version
COPY . .
RUN make build-release

FROM scratch
WORKDIR /binary
COPY --from=compile /compile/bin/bigbrother .
