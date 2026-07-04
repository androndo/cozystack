FROM --platform=$BUILDPLATFORM golang:1.26 AS build

ARG VERSION=v4.3.0
ARG TARGETPLATFORM

WORKDIR /usr/src/multus-cni

RUN curl -sSL https://github.com/k8snetworkplumbingwg/multus-cni/archive/refs/tags/${VERSION}.tar.gz | \
    tar -xzf - --strip=1

COPY patches /patches
RUN git init && git config user.email "build@cozystack" && git config user.name "build" && \
    git add -A && git commit -m "init" && git tag ${VERSION} && \
    git apply /patches/*.diff

RUN ./hack/build-go.sh

# Stage the upstream reference CNI plugins into the image so the
# install-cni-plugins init container can copy them into the host /opt/cni/bin.
# Nodes need them for Multus-backed NetworkAttachmentDefinitions (bridge,
# macvlan, ipvlan, ...), but neither Multus nor Cilium install the reference
# set: Cilium only drops cilium-cni + loopback, and k3s keeps its own copies
# under /var/lib/rancher/k3s/data/current/bin, so /opt/cni/bin is left without
# a `bridge` binary and a bridge-type NAD fails with "failed to find plugin
# bridge". The copy is unconditional (cp -f), which is safe: the only
# pre-existing overlap is loopback, identical on both sides.
ARG TARGETARCH
ARG CNI_PLUGINS_VERSION=v1.9.1
RUN mkdir -p /cni-plugins && \
    curl --fail --silent --show-error --location "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${TARGETARCH}-${CNI_PLUGINS_VERSION}.tgz" | \
    tar -xz -C /cni-plugins \
      ./bridge ./host-local ./loopback ./static ./macvlan ./ipvlan ./vlan \
      ./tuning ./portmap ./firewall ./bandwidth ./host-device ./ptp ./sbr ./vrf

FROM debian:stable-slim
LABEL org.opencontainers.image.source=https://github.com/cozystack/cozystack
COPY --from=build /usr/src/multus-cni/bin /usr/src/multus-cni/bin
COPY --from=build /usr/src/multus-cni/LICENSE /usr/src/multus-cni/LICENSE
COPY --from=build /usr/src/multus-cni/bin/cert-approver /
COPY --from=build /cni-plugins /cni-plugins
WORKDIR /

ENTRYPOINT ["/usr/src/multus-cni/bin/multus-daemon"]
