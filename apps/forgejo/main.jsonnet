local forgejo = import './lib/forgejo.libsonnet';

local values = {
  defaults: {
    image: "codeberg.org/forgejo/forgejo:1.20",
    namespace: "forgejo",
    subdomain: "git",
    domain: "arleskog.se"
  },
  forgejo: values.defaults + {
    name: "forgejo"
  }
};

local root = {
  forgejo:: forgejo(values.forgejo)
};

{ ["forgejo_%s.json" % name]: root.forgejo[name] for name in std.objectFields(root.forgejo) }
