#!/usr/bin/env bats
# -----------------------------------------------------------------------------
# Unit tests for the in-sandbox Talos image cache manifest split and the
# importer-reachability contract it relies on.
#
# hack/e2e-talos-image-cache.yaml bundles four documents but they are applied in
# two phases: hack/e2e-install-cozystack.bats applies everything EXCEPT the
# CiliumClusterwideNetworkPolicy (its CRD does not exist before Cozystack is
# installed), and hack/e2e-apps/talos-image-cache.sh applies ONLY that policy
# later, once Cilium is up. If a future document is added to the manifest and
# silently dropped from the pre-Cilium apply, or the Cilium document leaks into
# it (and errors on the missing CRD), the mirror breaks and e2e falls back to
# the flaky public factory. These tests pin that split.
#
# They also pin the load-bearing reachability invariant: the throwaway probe pod
# is a faithful proxy for a real CDI importer only if it carries the exact label
# and namespace the egress policy selects. If either side drifts, the probe can
# pass while real importers stay blocked (a false positive that makes CI worse).
#
# cozytest.sh's awk parser recognizes only @test blocks and a bare `}` on its
# own line; there is no bats `run` or `$status`, and setup()/teardown() are not
# honored. Each test runs under `set -eu -x`; assertions are direct shell tests
# that exit non-zero on failure. mikefarah yq prints `---` between matched
# documents, so document streams are compared with those separators stripped.
#
# Run with: hack/cozytest.sh hack/talos-image-cache_test.bats
# -----------------------------------------------------------------------------

@test "manifest documents partition into pre-Cilium apply plus the Cilium policy" {
    manifest=hack/e2e-talos-image-cache.yaml
    total=$(yq '.kind' "$manifest" | grep -vc '^---$')
    excluded=$(yq 'select(.kind != "CiliumClusterwideNetworkPolicy") | .kind' "$manifest" | grep -vc '^---$')
    selected=$(yq 'select(.kind == "CiliumClusterwideNetworkPolicy") | .kind' "$manifest" | grep -vc '^---$')
    [ "$total" -eq 4 ]
    [ "$excluded" -eq 3 ]
    [ "$selected" -eq 1 ]
    [ $((excluded + selected)) -eq "$total" ]
}

@test "pre-Cilium apply keeps Service, Deployment, ConfigMap and drops the Cilium policy" {
    manifest=hack/e2e-talos-image-cache.yaml
    kinds=$(yq 'select(.kind != "CiliumClusterwideNetworkPolicy") | .kind' "$manifest" | grep -v '^---$')
    for want in Service Deployment ConfigMap; do
        printf '%s\n' "$kinds" | grep -qx "$want" || { echo "pre-Cilium apply is missing $want" >&2; exit 1; }
    done
    if printf '%s\n' "$kinds" | grep -qx CiliumClusterwideNetworkPolicy; then
        echo "CiliumClusterwideNetworkPolicy leaked into the pre-Cilium apply" >&2
        exit 1
    fi
}

@test "point-of-use apply selects exactly the Cilium policy" {
    manifest=hack/e2e-talos-image-cache.yaml
    kinds=$(yq 'select(.kind == "CiliumClusterwideNetworkPolicy") | .kind' "$manifest" | grep -v '^---$')
    [ "$kinds" = "CiliumClusterwideNetworkPolicy" ]
}

@test "egress policy selects the importer label and namespace the probe pod uses" {
    manifest=hack/e2e-talos-image-cache.yaml
    helper=hack/e2e-apps/talos-image-cache.sh
    label=$(yq 'select(.kind == "CiliumClusterwideNetworkPolicy") | .spec.endpointSelector.matchLabels["k8s:cdi.kubevirt.io"]' "$manifest")
    ns=$(yq 'select(.kind == "CiliumClusterwideNetworkPolicy") | .spec.endpointSelector.matchLabels["k8s:io.kubernetes.pod.namespace"]' "$manifest")
    [ "$label" = "importer" ]
    [ "$ns" = "tenant-test" ]
    # The probe pod must carry the same label the policy selects, else it faces a
    # different egress than a real importer and the guarantee breaks.
    grep -q "cdi.kubevirt.io=importer" "$helper" || { echo "probe pod label drifted from the egress selector" >&2; exit 1; }
    grep -q "TALOS_IMAGE_CACHE_PROBE_NS:-tenant-test" "$helper" || { echo "probe namespace drifted from the egress selector" >&2; exit 1; }
}

@test "egress rule targets the mirror pod's own identity" {
    manifest=hack/e2e-talos-image-cache.yaml
    target=$(yq 'select(.kind == "CiliumClusterwideNetworkPolicy") | .spec.egress[0].toEndpoints[0].matchLabels["k8s:app.kubernetes.io/name"]' "$manifest")
    target_ns=$(yq 'select(.kind == "CiliumClusterwideNetworkPolicy") | .spec.egress[0].toEndpoints[0].matchLabels["k8s:io.kubernetes.pod.namespace"]' "$manifest")
    mirror=$(yq 'select(.kind == "Deployment") | .spec.template.metadata.labels["app.kubernetes.io/name"]' "$manifest")
    [ "$target" = "talos-image-cache" ]
    [ "$target_ns" = "kube-system" ]
    # The allow's destination must equal the mirror Deployment's own pod label,
    # otherwise the hole is punched toward nothing and importers cannot reach it.
    [ "$target" = "$mirror" ]
}
