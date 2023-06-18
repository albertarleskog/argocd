local wikijs = import "./lib/wikijs.libsonnet";

local root = {
  values:: {
    clusterIssuer: "letsencrypt-prod",
    version: "2",
    domain: "arleskog.se",
  },
  wikijs: wikijs(root.values)
};

{ [name + ".json"]: root.wikijs[name] for name in std.objectFields(root.wikijs) }
