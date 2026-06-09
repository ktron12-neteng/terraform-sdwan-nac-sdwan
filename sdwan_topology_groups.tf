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
  # Deploy/activate the topology group (async deploy task) when requested.
  activate = try(each.value.activate, local.defaults.sdwan.topology_groups.activate)

  # Re-deploy the control policy to the vSmart whenever upstream content changes.
  # The topology group's own attributes don't change when a *referenced* policy
  # object (e.g. a TLOC list) is edited, so without this trigger Terraform never
  # calls Update and the vSmart keeps the stale policy. Hashing the topology +
  # policy-object content forces an Update (= re-deploy) on any such change.
  # (Swap the hash for timestamp() to re-deploy on every apply instead.)
  redeploy_trigger = sha1(jsonencode([
    local.topology_groups,
    try(local.feature_profiles.policy_object_profile, null),
    local.policy_objects,
  ]))

  depends_on = [
    sdwan_topology_hub_and_spoke_feature.topology_hub_and_spoke_feature,
    sdwan_topology_custom_control_feature.topology_custom_control_feature,
    sdwan_policy_object_feature_profile.policy_object_feature_profile,
  ]
}
