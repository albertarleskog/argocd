local gotify = import './lib/gotify.libsonnet';

local values = {
  defaults: {
    name: "gotify",
    namespace: "gotify",
    image: "ghcr.io/gotify/server-arm64:2.4",
    subdomain: "notify",
    domain: "arleskog.se"
  }
};

local root = {
  gotify:: gotify(values.defaults)
};

{ ["gotify_%s.json" % name]: root.gotify[name] for name in std.objectFields(root.gotify) }

