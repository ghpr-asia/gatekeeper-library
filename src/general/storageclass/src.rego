package k8sstorageclass

is_pvc(obj) {
  obj.apiVersion == "v1"
  obj.kind == "PersistentVolumeClaim"
}

is_statefulset(obj) {
  obj.apiVersion == "apps/v1"
  obj.kind == "StatefulSet"
}

violation[{"msg": msg}] {
  not data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"]
  msg := sprintf("StorageClasses not synced. Gatekeeper may be misconfigured. Please have a cluster-admin consult the documentation.", [])
}

storageclass_allowed(name) {
  data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"][name]
  # support both direct use of * and as the default value
  object.get(input.parameters, "allowedStorageClasses", ["*"])[_] == "*"
}

storageclass_allowed(name) {
  data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"][name]
  input.parameters.allowedStorageClasses[_] == name
}

violation[{"msg": pvc_storageclass_badname_msg}] {
  is_pvc(input.review.object)
  not storageclass_allowed(input.review.object.spec.storageClassName)
}
pvc_storageclass_badname_msg := sprintf("pvc did not specify a valid storage class name <%v>. Must be one of [%v]", args) {
  input.parameters.includeStorageClassesInMessage
  object.get(input.parameters, "allowedStorageClasses", null) == null
  args := [
    input.review.object.spec.storageClassName,
    concat(", ", [n | data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"][n]])
  ]
} else := sprintf("pvc did not specify an allowed and valid storage class name <%v>. Must be one of [%v]", args) {
  input.parameters.includeStorageClassesInMessage
  object.get(input.parameters, "allowedStorageClasses", null) != null
  sc := {n | data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"][n]} & {x | x = object.get(input.parameters, "allowedStorageClasses", [])[_]}
  args := [
    input.review.object.spec.storageClassName,
    concat(", ", sc)
  ]
} else := sprintf(
  "pvc did not specify a valid storage class name <%v>.",
  [input.review.object.spec.storageClassName]
)

violation[{"msg": pvc_storageclass_noname_msg}] {
  is_pvc(input.review.object)
  not input.review.object.spec.storageClassName
}
pvc_storageclass_noname_msg := sprintf("pvc did not specify a storage class name. Must be one of [%v]", args) {
  input.parameters.includeStorageClassesInMessage
  args := [
    concat(", ", [n | data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"][n]])
  ]
} else := sprintf(
  "pvc did not specify a storage class name.",
  []
)

violation[{"msg": statefulset_vct_badname_msg(vct)}] {
  is_statefulset(input.review.object)
  vct := input.review.object.spec.volumeClaimTemplates[_]
  not storageclass_allowed(vct.spec.storageClassName)
}
statefulset_vct_badname_msg(vct) := msg {
  input.parameters.includeStorageClassesInMessage
  object.get(input.parameters, "allowedStorageClasses", null) == null
  msg := sprintf(
      "statefulset did not specify a valid storage class name <%v>. Must be one of [%v]", [
      vct.spec.storageClassName,
      concat(", ", [n | data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"][n]])
  ])
}
statefulset_vct_badname_msg(vct) := msg {
  input.parameters.includeStorageClassesInMessage
  object.get(input.parameters, "allowedStorageClasses", null) != null
  sc := {n | data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"][n]} & {x | x = object.get(input.parameters, "allowedStorageClasses", [])[_]}
  msg := sprintf(
      "statefulset did not specify an allowed and valid storage class name <%v>. Must be one of [%v]", [
      vct.spec.storageClassName,
      concat(", ", sc)
  ])
}
statefulset_vct_badname_msg(vct) := msg {
  not input.parameters.includeStorageClassesInMessage
  msg := sprintf(
    "statefulset did not specify a valid storage class name <%v>.", [
      vct.spec.storageClassName
  ])
}

violation[{"msg": statefulset_vct_noname_msg}] {
  is_statefulset(input.review.object)
  vct := input.review.object.spec.volumeClaimTemplates[_]
  not vct.spec.storageClassName
}
statefulset_vct_noname_msg := sprintf("statefulset did not specify a storage class name. Must be one of [%v]", args) {
  input.parameters.includeStorageClassesInMessage
  args := [
    concat(", ", [n | data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"][n]])
  ]
} else := sprintf(
  "statefulset did not specify a storage class name.",
  []
)

#FIXME pod generic ephemeral might be good to validate some day too.
