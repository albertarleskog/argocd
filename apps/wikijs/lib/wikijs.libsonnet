local defaults = {
  local defaults = self,
  name:: "wikijs",
  subdomain:: "wiki",
  version:: error "must provide version",
  domain:: error "must provide domainname",
  resources:: {
    requests: { cpu: "100m", memory: "256Mi" },
    limits: { cpu: "100m", memory: "256Mi" },
  },
  clusterIssuer:: error "must provide cert-managers cluster-issuer",
  fqdn:: "%s.%s" % [self.subdomain, self.domain]
};

function(params) {
  local ne = self,
  _config:: defaults + params,
  serviceAccount: {
    apiVersion: "v1",
    kind: "ServiceAccount",
    metadata: {
      name: ne._config.name
    }
  },

  ingress: {
    apiVersion: "networking.k8s.io/v1",
    kind: "Ingress",
    metadata: {
      name: ne._config.name,
      annotations: {
        "cert-manager.io/cluster-issuer": ne._config.clusterIssuer,
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
      ports: [
        {
          port: 80,
          targetPort: 3000
        }
      ]
    }
  },

  deployment: {
    apiVersion: "apps/v1",
    kind: "Deployment",
    metadata: {
      name: ne._config.name
    },
    spec: {
      replicas: 1,
      selector: {
        matchLabels: {
          app: ne._config.name
        }
      },
      template: {
        metadata: {
          annotations: {
            "vault.hashicorp.com/agent-inject": "true",
            "vault.hashicorp.com/role": "wikijs",
            "vault.hashicorp.com/agent-inject-secret-wikijs": "wikijs",
            "vault.hashicorp.com/agent-inject-template-wikijs": |||
              {{- with secret "kv/wikijs" -}}
              {{ .Data.data.db_pass }}
              {{- end -}}
            |||
          },
          labels: {
            app: ne._config.name
          }
        },
        spec: {
          hostUsers: false,
          serviceAccountName: ne._config.name,
          containers: [
            {
              name: ne._config.name,
              image: "ghcr.io/requarks/wiki:" + ne._config.version,
              env: [
                {
                  name: "DB_TYPE",
                  value: "postgres"
                },
                {
                  name: "DB_HOST",
                  value: "postgresql.db.svc.cluster.local"
                },
                {
                  name: "DB_PORT",
                  value: "5432"
                },
                {
                  name: "DB_USER",
                  value: "wikijs"
                },
                {
                  name: "DB_NAME",
                  value: "wikijs"
                }
              ],
              command: [
                "/bin/bash",
                "-c"
              ],
              args: ["DB_PASS=$(cat /vault/secrets/wikijs) node server"],
              ports: [
                {
                  containerPort: 3000,
                  name: "http"
                }
              ],
              livenessProbe: {
                httpGet: {
                  path: "/healthz",
                  port: "http"
                },
                initialDelaySeconds: 180
              },
              readinessProbe: {
                httpGet: {
                  path: "/healthz",
                  port: "http"
                },
                initialDelaySeconds: 180
              },
              startupProbe: {
                initialDelaySeconds: 15,
                periodSeconds: 5,
                timeoutSeconds: 5,
                successThreshold: 1,
                failureThreshold: 60,
                httpGet: {
                  path: "/healthz",
                  port: "http"
                }
              },
              resources: ne._config.resources
            }
          ]
        }
      }
    }
  }
}
