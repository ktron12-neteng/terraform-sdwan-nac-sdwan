# A topology group is the device-deployable, UI-visible entity ("Configuration >
# Topology"). One is created per `sdwan.topology_groups[]` entry; its name is the
# visible topology name. It bundles this group's topology feature profile and (when
# present) the policy-object feature profile (needed for TLOC list references).
resource "sdwan_topology_group" "topology_group" {
  for_each    = { for group in try(local.topology_groups, []) : group.name => group }
  name        = each.value.name
  description = try(each.value.description, "")
  solution    = "sdwan"
  profiles = concat(
    [{ id = sdwan_topology_feature_profile.topology_feature_profile[each.value.name].id }],
    contains(keys(local.feature_profiles), "policy_object_profile") ? [{
      id = sdwan_policy_object_feature_profile.policy_object_feature_profile[0].id
    }] : [],
  )

  depends_on = [
    sdwan_topology_hub_and_spoke_feature.topology_hub_and_spoke_feature,
    sdwan_topology_custom_control_feature.topology_custom_control_feature,
    sdwan_policy_object_feature_profile.policy_object_feature_profile,
  ]
}
