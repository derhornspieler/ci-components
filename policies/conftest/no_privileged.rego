package main

import future.keywords.contains
import future.keywords.if

# Deny privileged containers in any Pod-spec-bearing resource
deny contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf(
        "container '%s' in Deployment '%s' runs privileged",
        [container.name, input.metadata.name],
    )
}

# Deny hostNetwork
deny contains msg if {
    input.kind == "Deployment"
    input.spec.template.spec.hostNetwork == true
    msg := sprintf(
        "Deployment '%s' uses hostNetwork",
        [input.metadata.name],
    )
}
