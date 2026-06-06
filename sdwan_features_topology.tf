# Topology is authored as a single group-centric block: `sdwan.topology_groups[]`.
# Each group's name is the visible topology name, and it contains N topologies
# (hub_and_spoke_features / custom_control_features). For each group the module
# creates one topology feature profile (named after the group), its parcels, and
# the topology group that surfaces/activates it (see sdwan_topology_groups.tf).

resource "sdwan_topology_hub_and_spoke_feature" "topology_hub_and_spoke_feature" {
  depends_on = [
    sdwan_network_hierarchy_node.network_hierarchy_node,
    sdwan_network_hierarchy_region.network_hierarchy_region,
    sdwan_network_hierarchy_site.network_hierarchy_site,
    sdwan_policy_object_feature_profile.policy_object_feature_profile,
    sdwan_policy_object_tloc_list.policy_object_tloc_list,
  ]
  for_each = {
    for item in flatten([
      for group in try(local.topology_groups, []) : [
        for feature in try(group.hub_and_spoke_features, []) : {
          group   = group
          feature = feature
        }
      ]
    ]) : "${item.group.name}-${item.feature.name}" => item
  }
  name               = each.value.feature.name
  description        = try(each.value.feature.description, null)
  feature_profile_id = sdwan_topology_feature_profile.topology_feature_profile[each.value.group.name].id
  vpns               = each.value.feature.vpns
  # hub/spoke nodes are referenced by network hierarchy node name
  hubs = try([for hub in each.value.feature.hubs : local.network_hierarchy_ids[hub]], null)
  spokes = [for spoke in each.value.feature.spokes : {
    name     = spoke.name
    site_ids = [for site in spoke.site_ids : local.network_hierarchy_ids[site]]
    hubs = try([for hub in spoke.hubs : {
      site_ids   = [for site in hub.site_ids : local.network_hierarchy_ids[site]]
      preference = try(hub.preference, null)
    }], null)
  }]
}

resource "sdwan_topology_custom_control_feature" "topology_custom_control_feature" {
  depends_on = [
    sdwan_network_hierarchy_node.network_hierarchy_node,
    sdwan_network_hierarchy_region.network_hierarchy_region,
    sdwan_network_hierarchy_site.network_hierarchy_site,
    sdwan_policy_object_feature_profile.policy_object_feature_profile,
    sdwan_policy_object_tloc_list.policy_object_tloc_list,
  ]
  for_each = {
    for item in flatten([
      for group in try(local.topology_groups, []) : [
        for feature in try(group.custom_control_features, []) : {
          group   = group
          feature = feature
        }
      ]
    ]) : "${item.group.name}-${item.feature.name}" => item
  }
  name               = each.value.feature.name
  description        = try(each.value.feature.description, null)
  feature_profile_id = sdwan_topology_feature_profile.topology_feature_profile[each.value.group.name].id
  default_action     = try(each.value.feature.default_action, local.defaults.sdwan.topology_groups.custom_control_features.default_action)
  target_level       = try(each.value.feature.target_level, local.defaults.sdwan.topology_groups.custom_control_features.target_level)
  # target sites are referenced by network hierarchy node name (inbound required by API, may be empty)
  target_inbound_site_ids  = try([for site in each.value.feature.target_inbound_sites : local.network_hierarchy_ids[site]], [])
  target_outbound_site_ids = try([for site in each.value.feature.target_outbound_sites : local.network_hierarchy_ids[site]], [])
  sequences = [for sequence in try(each.value.feature.sequences, []) : {
    id          = sequence.id
    name        = try(sequence.name, null)
    base_action = try(sequence.base_action, local.defaults.sdwan.topology_groups.custom_control_features.sequences.base_action)
    type        = try(sequence.type, local.defaults.sdwan.topology_groups.custom_control_features.sequences.type)
    ip_type     = try(sequence.ip_type, local.defaults.sdwan.topology_groups.custom_control_features.sequences.ip_type)
    match_entries = try([for entry in sequence.match_entries : {
      site_ids = [for site in entry.site_ids : local.network_hierarchy_ids[site]]
    }], null)
    actions = try([for action in sequence.actions : {
      set = try([for set_item in action.set : {
        preference = try(set_item.preference, null)
        # tloc_list resolves a UX 2.0 policy object TLOC list by name; tloc_list_id is a literal fallback
        tloc_list_id = try(sdwan_policy_object_tloc_list.policy_object_tloc_list[set_item.tloc_list].id, try(set_item.tloc_list_id, null))
        tloc_action  = try(set_item.tloc_action, null)
      }], null)
    }], null)
  }]
}
