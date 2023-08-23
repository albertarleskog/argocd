local calibreWeb = import './lib/calibre-web.libsonnet';

local values = {
  name: "calibre-web",
  namespace: "calibre-web",
  subdomain: "calibre-web",
  domain: "arleskog.se",
  image: "lscr.io/linuxserver/calibre-web:latest",
  replicas: 1
};

local root = calibreWeb(values);

{ ["calibre-web_%s.json" % name]: root[name] for name in std.objectFields(root) }

