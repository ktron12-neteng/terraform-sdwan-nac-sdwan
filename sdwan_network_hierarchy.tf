# Read the live network hierarchy so the Global node (and any pre-existing nodes)
# can be discovered by name/label instead of requiring a hardcoded UUID.
data "sdwan_network_hierarchy" "current" {}

locals {
  # Global node UUID, auto-discovered (no hardcoded ID needed -> portable across fabrics)
  network_hierarchy_global_id = one([
    for node in data.sdwan_network_hierarchy.current.nodes : node.id if node.label == "GLOBAL"
  ])
  # name -> id for pre-existing nodes (lets `parent` reference nodes not managed here)
  network_hierarchy_existing_ids = {
    for node in data.sdwan_network_hierarchy.current.nodes : node.name => node.id...
  }
  # name -> id for co-managed nodes / regions / sites
  network_hierarchy_node_ids = {
    for node in try(local.network_hierarchy.nodes, []) :
    node.name => sdwan_network_hierarchy_node.network_hierarchy_node[node.name].id
  }
  network_hierarchy_region_ids = {
    for region in try(local.network_hierarchy.regions, []) :
    region.name => sdwan_network_hierarchy_region.network_hierarchy_region[region.name].id
  }
  network_hierarchy_site_ids = {
    for site in try(local.network_hierarchy.sites, []) :
    site.name => sdwan_network_hierarchy_site.network_hierarchy_site[site.name].id
  }
  # name -> id across everything, used by topology features to resolve hub/spoke/site refs
  network_hierarchy_ids = merge(
    { for name, ids in local.network_hierarchy_existing_ids : name => ids[0] },
    local.network_hierarchy_node_ids,
    local.network_hierarchy_region_ids,
    local.network_hierarchy_site_ids,
  )
}

# Folder/grouping node under Global (or another node/region). `parent` defaults to Global.
resource "sdwan_network_hierarchy_node" "network_hierarchy_node" {
  for_each    = { for node in try(local.network_hierarchy.nodes, []) : node.name => node }
  name        = each.value.name
  description = try(each.value.description, null)
  # Resolve `parent` by name (existing node or co-managed region); default to Global.
  # Co-managed sibling nodes are intentionally not resolvable here (would cycle).
  parent_id = try(each.value.parent, null) == null ? local.network_hierarchy_global_id : coalesce(
    try(local.network_hierarchy_region_ids[each.value.parent], null),
    try(local.network_hierarchy_existing_ids[each.value.parent][0], null),
  )
}

# MRF region under Global (or an existing node). `parent` defaults to Global.
resource "sdwan_network_hierarchy_region" "network_hierarchy_region" {
  for_each    = { for region in try(local.network_hierarchy.regions, []) : region.name => region }
  name        = each.value.name
  description = try(each.value.description, null)
  parent_id = try(each.value.parent, null) == null ? local.network_hierarchy_global_id : coalesce(
    try(local.network_hierarchy_existing_ids[each.value.parent][0], null),
  )
}

# Site under a node / region (by name) or, if `parent` omitted, directly under Global.
resource "sdwan_network_hierarchy_site" "network_hierarchy_site" {
  for_each    = { for site in try(local.network_hierarchy.sites, []) : site.name => site }
  name        = each.value.name
  description = try(each.value.description, null)
  parent_id = try(each.value.parent, null) == null ? local.network_hierarchy_global_id : coalesce(
    try(local.network_hierarchy_node_ids[each.value.parent], null),
    try(local.network_hierarchy_region_ids[each.value.parent], null),
    try(local.network_hierarchy_existing_ids[each.value.parent][0], null),
  )
  site_id = each.value.site_id
}

# Cflowd (UX 2.0): a single cflowd template under the Global node's Collectors tab.
resource "sdwan_network_hierarchy_cflowd_feature" "network_hierarchy_cflowd" {
  count                 = try(local.network_hierarchy.cflowd, null) == null ? 0 : 1
  network_hierarchy_id  = local.network_hierarchy_global_id
  active_flow_timeout   = try(local.network_hierarchy.cflowd.active_flow_timeout, local.defaults.sdwan.network_hierarchy.cflowd.active_flow_timeout)
  inactive_flow_timeout = try(local.network_hierarchy.cflowd.inactive_flow_timeout, local.defaults.sdwan.network_hierarchy.cflowd.inactive_flow_timeout)
  flow_refresh          = try(local.network_hierarchy.cflowd.flow_refresh, local.defaults.sdwan.network_hierarchy.cflowd.flow_refresh)
  sampling_interval     = try(local.network_hierarchy.cflowd.sampling_interval, local.defaults.sdwan.network_hierarchy.cflowd.sampling_interval)
  collect_tloc_loopback = try(local.network_hierarchy.cflowd.collect_tloc_loopback, null)
  protocol              = try(local.network_hierarchy.cflowd.protocol, null)
  tos                   = try(local.network_hierarchy.cflowd.tos, null)
  remarked_dscp         = try(local.network_hierarchy.cflowd.remarked_dscp, null)
  collectors = try([for collector in local.network_hierarchy.cflowd.collectors : {
    vpn_id                = collector.vpn_id
    ip_address            = try(collector.ip_address, null)
    port                  = try(collector.port, null)
    export_spreading      = try(collector.export_spreading, null)
    bfd_metrics_exporting = try(collector.bfd_metrics_exporting, null)
    exporting_interval    = try(collector.exporting_interval, null)
  }], null)
}
