---
id: users
title: Allowed Users
---

# Allowed Users

## Description
Controls the user and group IDs of the container and some volumes. Corresponds to the `runAsUser`, `runAsGroup`, `supplementalGroups`, and `fsGroup` fields in a PodSecurityPolicy. For more information, see https://kubernetes.io/docs/concepts/policy/pod-security-policy/#users-and-groups

## Template
```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8spspallowedusers
  annotations:
    metadata.gatekeeper.sh/title: "Allowed Users"
    metadata.gatekeeper.sh/version: 1.0.1
    description: >-
      Controls the user and group IDs of the container and some volumes.
      Corresponds to the `runAsUser`, `runAsGroup`, `supplementalGroups`, and
      `fsGroup` fields in a PodSecurityPolicy. For more information, see
      https://kubernetes.io/docs/concepts/policy/pod-security-policy/#users-and-groups
spec:
  crd:
    spec:
      names:
        kind: K8sPSPAllowedUsers
      validation:
        openAPIV3Schema:
          type: object
          description: >-
            Controls the user and group IDs of the container and some volumes.
            Corresponds to the `runAsUser`, `runAsGroup`, `supplementalGroups`, and
            `fsGroup` fields in a PodSecurityPolicy. For more information, see
            https://kubernetes.io/docs/concepts/policy/pod-security-policy/#users-and-groups
          properties:
            exemptImages:
              description: >-
                Any container that uses an image that matches an entry in this list will be excluded
                from enforcement. Prefix-matching can be signified with `*`. For example: `my-image-*`.

                It is recommended that users use the fully-qualified Docker image name (e.g. start with a domain name)
                in order to avoid unexpectedly exempting images from an untrusted repository.
              type: array
              items:
                type: string
            runAsUser:
              type: object
              description: "Controls which user ID values are allowed in a Pod or container-level SecurityContext."
              properties:
                rule:
                  type: string
                  description: "A strategy for applying the runAsUser restriction."
                  enum:
                    - MustRunAs
                    - MustRunAsNonRoot
                    - RunAsAny
                ranges:
                  type: array
                  description: "A list of user ID ranges affected by the rule."
                  items:
                    type: object
                    description: "The range of user IDs affected by the rule."
                    properties:
                      min:
                        type: integer
                        description: "The minimum user ID in the range, inclusive."
                      max:
                        type: integer
                        description: "The maximum user ID in the range, inclusive."
            runAsGroup:
              type: object
              description: "Controls which group ID values are allowed in a Pod or container-level SecurityContext."
              properties:
                rule:
                  type: string
                  description: "A strategy for applying the runAsGroup restriction."
                  enum:
                    - MustRunAs
                    - MayRunAs
                    - RunAsAny
                ranges:
                  type: array
                  description: "A list of group ID ranges affected by the rule."
                  items:
                    type: object
                    description: "The range of group IDs affected by the rule."
                    properties:
                      min:
                        type: integer
                        description: "The minimum group ID in the range, inclusive."
                      max:
                        type: integer
                        description: "The maximum group ID in the range, inclusive."
            supplementalGroups:
              type: object
              description: "Controls the supplementalGroups values that are allowed in a Pod or container-level SecurityContext."
              properties:
                rule:
                  type: string
                  description: "A strategy for applying the supplementalGroups restriction."
                  enum:
                    - MustRunAs
                    - MayRunAs
                    - RunAsAny
                ranges:
                  type: array
                  description: "A list of group ID ranges affected by the rule."
                  items:
                    type: object
                    description: "The range of group IDs affected by the rule."
                    properties:
                      min:
                        type: integer
                        description: "The minimum group ID in the range, inclusive."
                      max:
                        type: integer
                        description: "The maximum group ID in the range, inclusive."
            fsGroup:
              type: object
              description: "Controls the fsGroup values that are allowed in a Pod or container-level SecurityContext."
              properties:
                rule:
                  type: string
                  description: "A strategy for applying the fsGroup restriction."
                  enum:
                    - MustRunAs
                    - MayRunAs
                    - RunAsAny
                ranges:
                  type: array
                  description: "A list of group ID ranges affected by the rule."
                  items:
                    type: object
                    description: "The range of group IDs affected by the rule."
                    properties:
                      min:
                        type: integer
                        description: "The minimum group ID in the range, inclusive."
                      max:
                        type: integer
                        description: "The maximum group ID in the range, inclusive."
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8spspallowedusers

        import data.lib.exclude_update.is_update
        import data.lib.exempt_container.is_exempt

        violation[{"msg": msg}] {
          # runAsUser, runAsGroup, supplementalGroups, fsGroup fields are immutable.
          not is_update(input.review)

          fields := ["runAsUser", "runAsGroup", "supplementalGroups", "fsGroup"]
          field := fields[_]
          container := input_containers[_]
          not is_exempt(container)
          msg := get_type_violation(field, container)
        }

        get_type_violation(field, container) = msg {
          field == "runAsUser"
          params := input.parameters[field]
          msg := get_user_violation(params, container)
        }

        get_type_violation(field, container) = msg {
          field != "runAsUser"
          params := input.parameters[field]
          msg := get_violation(field, params, container)
        }

        # RunAsUser (separate due to "MustRunAsNonRoot")
        get_user_violation(params, container) = msg {
          rule := params.rule
          provided_user := get_field_value("runAsUser", container, input.review)
          not accept_users(rule, provided_user)
          msg := sprintf("Container %v is attempting to run as disallowed user %v. Allowed runAsUser: %v", [container.name, provided_user, params])
        }

        get_user_violation(params, container) = msg {
          not get_field_value("runAsUser", container, input.review)
          params.rule = "MustRunAs"
          msg := sprintf("Container %v is attempting to run without a required securityContext/runAsUser", [container.name])
        }

        get_user_violation(params, container) = msg {
          params.rule = "MustRunAsNonRoot"
          not get_field_value("runAsUser", container, input.review)
          not get_field_value("runAsNonRoot", container, input.review)
          msg := sprintf("Container %v is attempting to run without a required securityContext/runAsNonRoot or securityContext/runAsUser != 0", [container.name])
        }

        accept_users("RunAsAny", provided_user) {true}

        accept_users("MustRunAsNonRoot", provided_user) = res {res := provided_user != 0}

        accept_users("MustRunAs", provided_user) = res  {
          ranges := input.parameters.runAsUser.ranges
          res := is_in_range(provided_user, ranges)
        }

        # Group Options
        get_violation(field, params, container) = msg {
          rule := params.rule
          provided_value := get_field_value(field, container, input.review)
          not is_array(provided_value)
          not accept_value(rule, provided_value, params.ranges)
          msg := sprintf("Container %v is attempting to run as disallowed group %v. Allowed %v: %v", [container.name, provided_value, field, params])
        }
        # SupplementalGroups is array value
        get_violation(field, params, container) = msg {
          rule := params.rule
          array_value := get_field_value(field, container, input.review)
          is_array(array_value)
          provided_value := array_value[_]
          not accept_value(rule, provided_value, params.ranges)
          msg := sprintf("Container %v is attempting to run with disallowed supplementalGroups %v. Allowed %v: %v", [container.name, array_value, field, params])
        }

        get_violation(field, params, container) = msg {
          not get_field_value(field, container, input.review)
          params.rule == "MustRunAs"
          msg := sprintf("Container %v is attempting to run without a required securityContext/%v. Allowed %v: %v", [container.name, field, field, params])
        }

        accept_value("RunAsAny", provided_value, ranges) {true}

        accept_value("MayRunAs", provided_value, ranges) = res { res := is_in_range(provided_value, ranges)}

        accept_value("MustRunAs", provided_value, ranges) = res { res := is_in_range(provided_value, ranges)}


        # If container level is provided, that takes precedence
        get_field_value(field, container, review) = out {
          container_value := get_seccontext_field(field, container)
          out := container_value
        }

        # If no container level exists, use pod level
        get_field_value(field, container, review) = out {
          not has_seccontext_field(field, container)
          review.kind.kind == "Pod"
          pod_value := get_seccontext_field(field, review.object.spec)
          out := pod_value
        }

        # Helper Functions
        is_in_range(val, ranges) = res {
          matching := {1 | val >= ranges[j].min; val <= ranges[j].max}
          res := count(matching) > 0
        }

        has_seccontext_field(field, obj) {
          get_seccontext_field(field, obj)
        }

        has_seccontext_field(field, obj) {
          get_seccontext_field(field, obj) == false
        }

        get_seccontext_field(field, obj) = out {
          out = obj.securityContext[field]
        }

        input_containers[c] {
          c := input.review.object.spec.containers[_]
        }
        input_containers[c] {
          c := input.review.object.spec.initContainers[_]
        }
        input_containers[c] {
            c := input.review.object.spec.ephemeralContainers[_]
        }
      libs:
        - |
          package lib.exclude_update

          is_update(review) {
              review.operation == "UPDATE"
          }
        - |
          package lib.exempt_container

          is_exempt(container) {
              exempt_images := object.get(object.get(input, "parameters", {}), "exemptImages", [])
              img := container.image
              exemption := exempt_images[_]
              _matches_exemption(img, exemption)
          }

          _matches_exemption(img, exemption) {
              not endswith(exemption, "*")
              exemption == img
          }

          _matches_exemption(img, exemption) {
              endswith(exemption, "*")
              prefix := trim_suffix(exemption, "*")
              startswith(img, prefix)
          }

```

### Usage
```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/pod-security-policy/users/template.yaml
```
## Examples
<details>
<summary>users-and-groups-together</summary><blockquote>

<details>
<summary>constraint</summary>

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPAllowedUsers
metadata:
  name: psp-pods-allowed-user-ranges
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    runAsUser:
      rule: MustRunAs # MustRunAsNonRoot # RunAsAny 
      ranges:
        - min: 100
          max: 200
    runAsGroup:
      rule: MustRunAs # MayRunAs # RunAsAny 
      ranges:
        - min: 100
          max: 200
    supplementalGroups:
      rule: MustRunAs # MayRunAs # RunAsAny 
      ranges:
        - min: 100
          max: 200
    fsGroup:
      rule: MustRunAs # MayRunAs # RunAsAny 
      ranges:
        - min: 100
          max: 200

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/pod-security-policy/users/samples/psp-pods-allowed-user-ranges/constraint.yaml
```

</details>

<details>
<summary>example-disallowed</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-users-disallowed
  labels:
    app: nginx-users
spec:
  securityContext:
    supplementalGroups:
      - 250
    fsGroup: 250
  containers:
    - name: nginx
      image: nginx
      securityContext:
        runAsUser: 250
        runAsGroup: 250

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/pod-security-policy/users/samples/psp-pods-allowed-user-ranges/example_disallowed.yaml
```

</details>
<details>
<summary>example-allowed</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-users-allowed
  labels:
    app: nginx-users
spec:
  securityContext:
    supplementalGroups:
      - 199
    fsGroup: 199
  containers:
    - name: nginx
      image: nginx
      securityContext:
        runAsUser: 199
        runAsGroup: 199

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/pod-security-policy/users/samples/psp-pods-allowed-user-ranges/example_allowed.yaml
```

</details>
<details>
<summary>disallowed-ephemeral</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-users-disallowed
  labels:
    app: nginx-users
spec:
  securityContext:
    supplementalGroups:
      - 250
    fsGroup: 250
  ephemeralContainers:
    - name: nginx
      image: nginx
      securityContext:
        runAsUser: 250
        runAsGroup: 250

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/pod-security-policy/users/samples/psp-pods-allowed-user-ranges/disallowed_ephemeral.yaml
```

</details>
<details>
<summary>update</summary>

```yaml
kind: AdmissionReview
apiVersion: admission.k8s.io/v1beta1
request:
  operation: "UPDATE"
  object:
    apiVersion: v1
    kind: Pod
    metadata:
      name: nginx-users-disallowed
      labels:
        app: nginx-users
    spec:
      securityContext:
        supplementalGroups:
          - 250
        fsGroup: 250
      containers:
        - name: nginx
          image: nginx
          securityContext:
            runAsUser: 250
            runAsGroup: 250

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/pod-security-policy/users/samples/psp-pods-allowed-user-ranges/update.yaml
```

</details>


</blockquote></details>