local fluent_bit = import './lib/fluent-bit.libsonnet';

local values = {
  defaults: {
    name: "fluent-bit",
    namespace: "fluent-bit",
    image: "docker.io/fluent/fluent-bit:2.2",
  }
};

local root = {
  fluent_bit:: fluent_bit(values.defaults)
};

{ ["fluent-bit_%s.json" % name]: root.fluent_bit[name] for name in std.objectFields(root.fluent_bit) }

