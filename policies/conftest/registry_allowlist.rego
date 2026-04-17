package main

import future.keywords.contains
import future.keywords.if
import future.keywords.in

allowed_registries := [
    "harbor.example.com",
    "harbor.dev.example.com",
]

# Deny images from non-allowlisted registries
deny contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not image_from_allowlist(container.image)
    msg := sprintf(
        "container '%s' uses image '%s' from a non-allowlisted registry. Allowed: %v",
        [container.name, container.image, allowed_registries],
    )
}

deny contains msg if {
    input.kind == "StatefulSet"
    container := input.spec.template.spec.containers[_]
    not image_from_allowlist(container.image)
    msg := sprintf(
        "statefulset container '%s' uses image '%s' from a non-allowlisted registry",
        [container.name, container.image],
    )
}

image_from_allowlist(image) if {
    some registry in allowed_registries
    startswith(image, registry)
}
