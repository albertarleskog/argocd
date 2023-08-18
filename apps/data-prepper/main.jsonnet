local dataPrepper = import './lib/data-prepper.libsonnet';

local values = {
  name: "data-prepper",
  namespace: "data-prepper",
  image: "docker.io/opensearchproject/data-prepper:2",
  replicas: 1
};

local root = dataPrepper(values);

{ ["data-prepper_%s.json" % name]: root[name] for name in std.objectFields(root) }
