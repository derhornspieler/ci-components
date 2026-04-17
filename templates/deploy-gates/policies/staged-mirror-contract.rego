package staged_mirror_contract

# Staged=prod mirror contract (spec §4).
# Input is a batch of rendered manifests (conftest multi-doc YAML parse).
# We compare pairs of Deployments/StatefulSets/HPA/PDB/NetworkPolicy where the
# same workload name appears in both a staged and prod overlay. The overlay is
# determined from the Kustomize namespace label: staged-<app> vs <app>.

# Fields that MUST match between staged and prod variants.
must_match_deployment := [
    "spec.replicas",
    "spec.template.spec.nodeSelector",
    "spec.template.spec.tolerations",
    "spec.template.spec.topologySpreadConstraints",
]

# Collect all workloads keyed by (kind, name).
workloads[key] = obj {
    obj := input[_]
    obj.kind == "Deployment"
    key := {"kind": "Deployment", "name": obj.metadata.name, "ns": obj.metadata.namespace}
}
workloads[key] = obj {
    obj := input[_]
    obj.kind == "StatefulSet"
    key := {"kind": "StatefulSet", "name": obj.metadata.name, "ns": obj.metadata.namespace}
}
workloads[key] = obj {
    obj := input[_]
    obj.kind == "HorizontalPodAutoscaler"
    key := {"kind": "HPA", "name": obj.metadata.name, "ns": obj.metadata.namespace}
}
workloads[key] = obj {
    obj := input[_]
    obj.kind == "PodDisruptionBudget"
    key := {"kind": "PDB", "name": obj.metadata.name, "ns": obj.metadata.namespace}
}

is_staged(ns) {
    startswith(ns, "staged-")
}
prod_ns_for(ns) = trim_prefix(ns, "staged-")

# ---- Deployment/StatefulSet replica parity ----
deny[msg] {
    staged := workloads[k]
    k.kind == "Deployment"
    is_staged(k.ns)
    prod := workloads[{"kind": "Deployment", "name": k.name, "ns": prod_ns_for(k.ns)}]
    staged.spec.replicas != prod.spec.replicas
    msg := sprintf("replicas differ for Deployment/%s: staged=%v prod=%v", [k.name, staged.spec.replicas, prod.spec.replicas])
}

# ---- Container-level resource parity ----
deny[msg] {
    staged := workloads[k]
    k.kind == "Deployment"
    is_staged(k.ns)
    prod := workloads[{"kind": "Deployment", "name": k.name, "ns": prod_ns_for(k.ns)}]
    sc := staged.spec.template.spec.containers[i]
    pc := prod.spec.template.spec.containers[i]
    sc.resources != pc.resources
    msg := sprintf("resources differ for Deployment/%s container[%d]: staged=%v prod=%v", [k.name, i, sc.resources, pc.resources])
}

# ---- Container count parity ----
deny[msg] {
    staged := workloads[k]
    k.kind == "Deployment"
    is_staged(k.ns)
    prod := workloads[{"kind": "Deployment", "name": k.name, "ns": prod_ns_for(k.ns)}]
    count(staged.spec.template.spec.containers) != count(prod.spec.template.spec.containers)
    msg := sprintf("container count differs for Deployment/%s", [k.name])
}

# ---- nodeSelector parity ----
deny[msg] {
    staged := workloads[k]
    k.kind == "Deployment"
    is_staged(k.ns)
    prod := workloads[{"kind": "Deployment", "name": k.name, "ns": prod_ns_for(k.ns)}]
    object.get(staged.spec.template.spec, "nodeSelector", {}) != object.get(prod.spec.template.spec, "nodeSelector", {})
    msg := sprintf("nodeSelector differs for Deployment/%s", [k.name])
}

# ---- tolerations parity ----
deny[msg] {
    staged := workloads[k]
    k.kind == "Deployment"
    is_staged(k.ns)
    prod := workloads[{"kind": "Deployment", "name": k.name, "ns": prod_ns_for(k.ns)}]
    object.get(staged.spec.template.spec, "tolerations", []) != object.get(prod.spec.template.spec, "tolerations", [])
    msg := sprintf("tolerations differ for Deployment/%s", [k.name])
}

# ---- topologySpreadConstraints parity ----
deny[msg] {
    staged := workloads[k]
    k.kind == "Deployment"
    is_staged(k.ns)
    prod := workloads[{"kind": "Deployment", "name": k.name, "ns": prod_ns_for(k.ns)}]
    object.get(staged.spec.template.spec, "topologySpreadConstraints", []) != object.get(prod.spec.template.spec, "topologySpreadConstraints", [])
    msg := sprintf("topologySpreadConstraints differ for Deployment/%s", [k.name])
}

# ---- HPA min/max/target parity ----
deny[msg] {
    staged := workloads[k]
    k.kind == "HPA"
    is_staged(k.ns)
    prod := workloads[{"kind": "HPA", "name": k.name, "ns": prod_ns_for(k.ns)}]
    staged.spec.minReplicas != prod.spec.minReplicas
    msg := sprintf("HPA minReplicas differ for %s", [k.name])
}
deny[msg] {
    staged := workloads[k]
    k.kind == "HPA"
    is_staged(k.ns)
    prod := workloads[{"kind": "HPA", "name": k.name, "ns": prod_ns_for(k.ns)}]
    staged.spec.maxReplicas != prod.spec.maxReplicas
    msg := sprintf("HPA maxReplicas differ for %s", [k.name])
}
deny[msg] {
    staged := workloads[k]
    k.kind == "HPA"
    is_staged(k.ns)
    prod := workloads[{"kind": "HPA", "name": k.name, "ns": prod_ns_for(k.ns)}]
    staged.spec.metrics != prod.spec.metrics
    msg := sprintf("HPA metrics/target differ for %s", [k.name])
}

# ---- PDB minAvailable parity ----
deny[msg] {
    staged := workloads[k]
    k.kind == "PDB"
    is_staged(k.ns)
    prod := workloads[{"kind": "PDB", "name": k.name, "ns": prod_ns_for(k.ns)}]
    object.get(staged.spec, "minAvailable", null) != object.get(prod.spec, "minAvailable", null)
    msg := sprintf("PDB minAvailable differs for %s", [k.name])
}

# ---- NetworkPolicy / CiliumNetworkPolicy rule parity ----
netpols[key] = obj {
    obj := input[_]
    obj.kind == "NetworkPolicy"
    key := {"kind": "NetworkPolicy", "name": obj.metadata.name, "ns": obj.metadata.namespace}
}
netpols[key] = obj {
    obj := input[_]
    obj.kind == "CiliumNetworkPolicy"
    key := {"kind": "CiliumNetworkPolicy", "name": obj.metadata.name, "ns": obj.metadata.namespace}
}
deny[msg] {
    staged := netpols[k]
    is_staged(k.ns)
    prod := netpols[{"kind": k.kind, "name": k.name, "ns": prod_ns_for(k.ns)}]
    staged.spec != prod.spec
    msg := sprintf("%s rules differ for %s", [k.kind, k.name])
}

# ---- PVC: staged storage must be <= prod storage ----
pvcs[key] = obj {
    obj := input[_]
    obj.kind == "PersistentVolumeClaim"
    key := {"name": obj.metadata.name, "ns": obj.metadata.namespace}
}
deny[msg] {
    staged := pvcs[k]
    is_staged(k.ns)
    prod := pvcs[{"name": k.name, "ns": prod_ns_for(k.ns)}]
    s := storage_to_gi(staged.spec.resources.requests.storage)
    p := storage_to_gi(prod.spec.resources.requests.storage)
    s > p
    msg := sprintf("PVC %s storage %v > prod %v (staged must be <= prod)", [k.name, staged.spec.resources.requests.storage, prod.spec.resources.requests.storage])
}

# crude Gi converter — matches Gi/Mi/Ti suffixes for relative comparison only
storage_to_gi(s) = n {
    endswith(s, "Gi")
    n := to_number(trim_suffix(s, "Gi"))
}
storage_to_gi(s) = n {
    endswith(s, "Ti")
    n := to_number(trim_suffix(s, "Ti")) * 1024
}
storage_to_gi(s) = n {
    endswith(s, "Mi")
    n := to_number(trim_suffix(s, "Mi")) / 1024
}
