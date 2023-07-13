local searxng = import './lib/searxng.libsonnet';

local values = {
  defaults: {
    version: "2023.6.16-71b6ff07",
    namespace: "default",
    subdomain: "search",
    domain: "arleskog.se"
  },
  searxng: values.defaults + {
    name: "searxng",
    replicas: 1
  }
};

local root = {
  searxng:: searxng(values.searxng)
};

{ ["searxng_%s.json" % name]: root.searxng[name] for name in std.objectFields(root.searxng) }
