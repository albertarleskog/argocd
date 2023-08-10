local plex = import './lib/plex.libsonnet';

local values = {
  plex: {
    name: "plex",
    image: "plexinc/pms-docker:latest",
    namespace: "plex",
    replicas: 1
  }
};

local root = {
  plex:: plex(values.plex)
};

{ ["plex_%s.json" % name]: root.plex[name] for name in std.objectFields(root.plex) }
