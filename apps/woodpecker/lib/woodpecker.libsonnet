local defaults = {
  name: "please provide deployment name, \"forgejo\" is suggested",
  namespace: error 'please provide namespace',
  image: error "please provide image",
  subdomain: error "please provide subdomain name",
  domain: error "please provide domain name",
  fqdn: "%s.%s" % [self.subdomain, self.domain],
  grpcfqdn: "grpc." + self.fqdn,
  resources: {
    requests: { cpu: "100m", memory: "128Mi" },
    limits: { cpu: "100m", memory: "128Mi" }
  }
};

function(params) {
  local _config = defaults + params + {
    env: {
      WOODPECKER_HOST: "https://woodpecker.arleskog.se",
      WOODPECKER_LOG_LEVEL: "info",
      WOODPECKER_METRICS_SERVER_ADDR: ":9000",
      WOODPECKER_ADMIN: "albert",
      WOODPECKER_REPO_OWNERS: "albert",
      WOODPECKER_AGENT_SECRET_FILE: "/vault/secrets/agent_secret",
      WOODPECKER_DATABASE_DRIVER: "postgres",
      WOODPECKER_DATABASE_DATASOURCE: {
        secretKeyRef: {
          name: "woodpecker",
          key: "DATABASE_DATASOURCE"
        }
      },
      WOODPECKER_ENCRYPTION_KEY_FILE: "/vault/secrets/encryption_key",
      WOODPECKER_PROMETHEUS_AUTH_TOKEN_FILE: "/vault/secrets/prometheus_auth_token",
      WOODPECKER_GITEA: "true",
      WOODPECKER_GITEA_URL: "https://git.arleskog.se",
      WOODPECKER_GITEA_CLIENT_FILE: "/vault/secrets/gitea_client",
      WOODPECKER_GITEA_SECRET_FILE: "/vault/secrets/gitea_secret"
    }
  },

  ingress: {
    apiVersion: "networking.k8s.io/v1",
    kind: "Ingress",
    metadata: {
      name: _config.name,
      annotations: {
        "cert-manager.io/cluster-issuer": "letsencrypt-prod",
        "external-dns.alpha.kubernetes.io/hostname": _config.fqdn
      }
    },
    spec: {
      ingressClassName: "nginx",
      tls: [
        {
          hosts: [
            _config.fqdn
          ],
          secretName: std.strReplace(_config.fqdn, ".", "-") + "-cert"
        }
      ],
      rules: [
        {
          host: _config.fqdn,
          http: {
            paths: [
              {
                path: "/",
                pathType: "Prefix",
                backend: {
                  service: {
                    name: _config.name,
                    port: {
                      name: "http"
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

  "ingress-grpc": {
    apiVersion: "networking.k8s.io/v1",
    kind: "Ingress",
    metadata: {
      name: _config.name + "-grpc",
      annotations: {
        "cert-manager.io/cluster-issuer": "letsencrypt-prod",
        "external-dns.alpha.kubernetes.io/hostname": _config.grpcfqdn,
        "nginx.ingress.kubernetes.io/ssl-redirect": "true",
        "nginx.ingress.kubernetes.io/backend-protocol": "GRPC"
      }
    },
    spec: {
      ingressClassName: "nginx",
      tls: [
        {
          hosts: [
            _config.grpcfqdn
          ],
          secretName: std.strReplace(_config.grpcfqdn, ".", "-") + "-cert"
        }
      ],
      rules: [
        {
          host: _config.grpcfqdn,
          http: {
            paths: [
              {
                path: "/",
                pathType: "Prefix",
                backend: {
                  service: {
                    name: _config.name,
                    port: {
                      name: "grpc"
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
      name: _config.name,
      namespace: _config.namespace
    },
    spec: {
      selector: {
        app: _config.name
      },
      ports: [
        {
          name: "http",
          port: 80,
          targetPort: "http"
        },
        {
          name: "grpc",
          port: 90,
          targetPort: "grpc"
        }
      ]
    }
  },

  statefulset: {
    kind: "StatefulSet",
    apiVersion: "apps/v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
  },
  spec: {
    serviceName: _config.name,
    replicas: 1,
    selector: {
      matchLabels: {
          app: _config.name
        }
      },
      template: {
        metadata: {
          name: _config.name,
          local secretNames = ["agent_secret", "database_datasource", "encryption_key", "prometheus_auth_token", "gitea_client", "gitea_secret"],
          annotations: {
            "vault.hashicorp.com/agent-inject": 'true',
            "vault.hashicorp.com/role": 'woodpecker',
          } + {
            ["vault.hashicorp.com/agent-inject-secret-%s" % secret]: "kv/woodpecker",
            for secret in secretNames
          } + {
            ["vault.hashicorp.com/agent-inject-template-%s" % secret]: |||
              {{- with secret "kv/woodpecker" -}}
              {{ .Data.data.%s }}
              {{- end -}}
            ||| % secret
            for secret in secretNames
          } + {
            "vault.hashicorp.com/agent-inject-template-database_datasource": |||
              {{- with secret "kv/woodpecker" -}}
              postgres://woodpecker:{{ .Data.data.database_datasource }}@postgresql.db.svc.cluster.local:5432/woodpecker?sslmode=disable
              {{- end -}}
            |||
          },
          labels: {
            app: _config.name
          }
        },
        spec: {
          serviceAccountName: _config.name,
          securityContext: {
            runAsNonRoot: true,
            runAsUser: 1337,
            runAsGroup: 1337
          },
          containers: [
            {
              name: _config.name,
              image: _config.image,
              ports: [
                {
                  containerPort: 8000,
                  name: "http"
                },
                {
                  containerPort: 9000,
                  name: "grpc"
                }
              ],
              env: [
                {
                  name: o.key,
                  [if std.isString(o.value) then "value" else "valueFrom"]: o.value
                } for o in std.objectKeysValues(_config.env)
              ],
              resources: _config.resources,
              livenessProbe: {
                httpGet: {
                  path: "/healthz",
                  port: "http"
                }
              },
              readinessProbe: {
                httpGet: {
                  path: "/healthz",
                  port: "http"
                }
              }
            }
          ]
        }
      }
    }
  },

  serviceAccount: {
    kind: "ServiceAccount",
    apiVersion: "v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    }
  }
}
