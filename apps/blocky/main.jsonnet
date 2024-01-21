local blocky = import './lib/blocky.libsonnet';

local values = {
  defaults: {
    image: "spx01/blocky:v0.23",
    namespace: "blocky",
    subdomain: "dns",
    domain: "arleskog.se",
    replicas: 3
  },
  blocky: values.defaults + {
    name: "blocky"
  }
};

local root = {
  blocky:: blocky(values.blocky)
};

{ ["blocky_%s.json" % name]: root.blocky[name] for name in std.objectFields(root.blocky) }

