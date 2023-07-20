local externalDns = import './lib/external-dns.libsonnet';

local values = {
  defaults: {
    image: "registry.k8s.io/external-dns/external-dns:v0.13.5",
    namespace: "external-dns",
    replicas: 3
  },
  externalDns: values.defaults + {
    name: "external-dns"
  }
};

local root = {
  externalDns:: externalDns(values.externalDns)
};

{ ["external-dns_%s.json" % name]: root.externalDns[name] for name in std.objectFields(root.externalDns) }
