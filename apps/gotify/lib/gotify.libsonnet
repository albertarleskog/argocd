local defaults = {
  name: error "please provide deployment name",
  namespace: error 'please provide namespace',
  image: error "please provide image",
  subdomain: error "please provide subdomain name",
  domain: error "please provide domain name",
  fqdn: "%s.%s" % [self.subdomain, self.domain],
  resources: {
    requests: { cpu: "100m", memory: "128Mi" },
    limits: { cpu: "100m", memory: "128Mi" }
  }
};

function(params) {
  local _config = defaults + params + {
    env: {
      GOTIFY_SERVER_CORS_ALLOWORIGINS: "- \"%s\"" % _config.fqdn,
      GOTIFY_SERVER_STREAM_ALLOWEDORIGINS: "- \"%s\"" % _config.fqdn
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
      name: _config.name,
      namespace: _config.namespace
    },
    spec: {
      selector: {
        app: _config.name
      },
      ports: [
        {
          port: 80,
          targetPort: "http"
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
          labels: {
            app: _config.name
          }
        },
        spec: {
          hostUsers: false,
          containers: [
            {
              name: _config.name,
              image: _config.image,
              ports: [
                {
                  containerPort: 80,
                  name: "http"
                }
              ],
              env: [
                {
                  name: o.key,
                  [if std.isString(o.value) then "value" else "valueFrom"]: o.value 
                } for o in std.objectKeysValues(_config.env)
              ],
              resources: _config.resources,
              volumeMounts: [
                {
                  name: "data",
                  mountPath: "/data"
                },
              ],
              livenessProbe: {
                httpGet: {
                  path: "/health",
                  port: "http"
                }
              },
              readinessProbe: {
                httpGet: {
                  path: "/health",
                  port: "http"
                }
              }
            }
          ],
          affinity: {
            nodeAffinity: {
              requiredDuringSchedulingIgnoredDuringExecution: {
                nodeSelectorTerms: [
                  {
                    matchExpressions: [
                      {
                        key: "kubernetes.io/arch",
                        operator: "In",
                        values: [
                          "arm64"
                        ]
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
      },
      volumeClaimTemplates: [
        {
          metadata: {
            name: "data"
          },
          spec: {
            accessModes: [
              "ReadWriteOnce"
            ],
            storageClassName: "longhorn",
            resources: {
              requests: {
                storage: "512Mi"
              }
            }
          }
        }
      ]
    }
  }
}

