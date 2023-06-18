local defaults = {
  local defaults = self,
  name:: "cyberchef",
  subdomain:: "cc",
  version:: error "must provide version",
  domain:: error "must provide domainname",
  resources:: {
    requests: { cpu: "10m", memory: "64Mi" },
    limits: { cpu: "10m", memory: "64Mi" },
  },
  clusterIssuer:: error "must provide cert-managers cluster-issuer",
  fqdn:: "%s.%s" % [self.subdomain, self.domain],
};

function(params) {
  local ne = self,
  _config:: defaults + params,

  ingress: {
    apiVersion: "networking.k8s.io/v1",
    kind: "Ingress",
    metadata: {
      name: ne._config.name,
      annotations: {
        "cert-manager.io/cluster-issuer": "letsencrypt-prod",
        "external-dns.alpha.kubernetes.io/hostname": ne._config.fqdn
      }
    },
    spec: {
      tls: [
        {
          hosts: [
            ne._config.fqdn
          ],
          secretName: std.strReplace(ne._config.fqdn, ".", "-") + "-cert"
        }
      ],
      rules: [
        {
          host: ne._config.fqdn,
          http: {
            paths: [
              {
                path: "/",
                pathType: "Prefix",
                backend: {
                  service: {
                    name: ne._config.name,
                    port: {
                      number: 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  },

  service: {
    kind: "Service",
    apiVersion: "v1",
    metadata: {
      name: ne._config.name
    },
    spec: {
      selector: {
        app: ne._config.name
      },
      ports:[
        {
          port: 80,
          targetPort: 8000
        }
      ]
    }
  },

  deployment: {
    kind: "Deployment",
    apiVersion: "apps/v1",
    metadata: {
      name: ne._config.name
    },
    spec: {
      replicas: 3,
      selector: {
        matchLabels: {
          app: ne._config.name
        }
      },
      template: {
        metadata: {
          name: ne._config.name,
          labels: {
            app: ne._config.name
          }
        },
        spec: {
          hostUsers: false,
          containers: [
            {
              name: ne._config.name,
              image: "mpepping/cyberchef:" + ne._config.version,
              ports: [
                {
                  containerPort: 8000
                }
              ],
              resources: ne._config.resources
            }
          ]
        }
      }
    }
  }
}
