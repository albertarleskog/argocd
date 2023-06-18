local cyberchef = import './lib/cyberchef.libsonnet';

local root = {
  values:: {
    clusterIssuer: "letsencrypt-prod",
    version: "latest",
    domain: "arleskog.se",
  },
  cyberchef:: cyberchef(root.values)
};

{ [name + ".json"]: root.cyberchef[name] for name in std.objectFields(root.cyberchef) }
