local opensearch = import './lib/opensearch.libsonnet';
local opensearchDashboards = import './lib/opensearch-dashboards.libsonnet';

local values = {
  defaults: {
    version: "2.9.0",
    namespace: "opensearch",
    domain: "arleskog.se"
  },
  opensearch: values.defaults + {
    name: "opensearch",
    subdomain: "opensearch",
    replicas: 3
  },
  opensearchDashboards: values.defaults + {
    name: "opensearch-dashboards",
    subdomain: "dashboards",
    replicas: 1,
    opensearchClusterService: "opensearch-cluster-headless"
  }
};

local root = {
  opensearch:: opensearch(values.opensearch),
  opensearchDashboards: opensearchDashboards(values.opensearchDashboards)
};

{ ["opensearch_%s.json" % name]: root.opensearch[name] for name in std.objectFields(root.opensearch) } +
{ ["opensearch-dashboards_%s.json" % name]: root.opensearchDashboards[name] for name in std.objectFields(root.opensearchDashboards) }
