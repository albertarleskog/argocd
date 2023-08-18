local jenkins = import './lib/jenkins.libsonnet';

local values = {
  name: "jenkins",
  image: "docker.io/jenkins/jenkins:lts",
  namespace: "jenkins",
  subdomain: "jenkins",
  domain: "arleskog.se",
  replicas: 1
};

local root = jenkins(values);

{ ["jenkins_%s.json" % name]: root[name] for name in std.objectFields(root) }
