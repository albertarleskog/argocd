local woodpecker = import './lib/woodpecker.libsonnet';

local values = {
  defaults: {
    image: "docker.io/woodpeckerci/woodpecker-server:v2.1.0",
    namespace: "woodpecker",
    subdomain: "woodpecker",
    domain: "arleskog.se"
  },
  woodpecker: values.defaults + {
    name: "woodpecker"
  }
};

local root = {
  woodpecker:: woodpecker(values.woodpecker)
};

{ ["woodpecker_%s.json" % name]: root.woodpecker[name] for name in std.objectFields(root.woodpecker) }

