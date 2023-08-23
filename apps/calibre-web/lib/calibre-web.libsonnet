local defaults = {
  name: "please provide deployment name",
  namespace: error 'please provide namespace',
  image: error "please provide image",
  subdomain: error "please provide subdomain name",
  domain: error "please provide domain name",
  fqdn: "%s.%s" % [self.subdomain, self.domain],
  replicas: error 'please provide replicas for the deployment',
  resources: {
    requests: { cpu: "250m", memory: "512Mi" },
    limits: { cpu: "250m", memory: "512Mi" }
  }
};

function(params) {
  local _config = defaults + params + {
    env: {
      PUID: "1000",
      PGID: "1000",
      TZ: "Europe/Stockholm",
      DOCKER_MODS: "ghcr.io/linuxserver/mods:universal-calibre",
    }
  },

  ingress: {
    apiVersion: "networking.k8s.io/v1",
    kind: "Ingress",
    metadata: {
      name: _config.name,
      annotations: {
        "cert-manager.io/cluster-issuer": "letsencrypt-prod",
        "external-dns.alpha.kubernetes.io/hostname": _config.fqdn,
        "nginx.ingress.kubernetes.io/backend-protocol": "HTTPS",
        "nginx.ingress.kubernetes.io/proxy-body-size": "100m"
      }
    },
    spec: {
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
                      number: 443
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
          port: 443,
          targetPort: "https"
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
          securityContext: {
            fsGroup: 1000
          },
          containers: [
            {
              name: _config.name,
              image: _config.image,
              ports: [
                {
                  containerPort: 8083,
                  name: "https"
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
                  name: "books",
                  mountPath: "/books"
                },
                {
                  name: "config",
                  mountPath: "/config"
                }
              ],
              startupProbe: {
                httpGet: {
                  path: "/",
                  port: "https",
                  scheme: "HTTPS"
                },
                timeoutSeconds: 5,
                failureThreshold: 20
              },
              livenessProbe: {
                httpGet: {
                  path: "/",
                  port: "https",
                  scheme: "HTTPS"
                }
              },
              readinessProbe: {
                httpGet: {
                  path: "/",
                  port: "https",
                  scheme: "HTTPS"
                }
              }
            }
          ],
          volumes: [
            {
              name: "books",
              nfs: {
                server: "10.1.40.100",
                path: "/mnt/tank/media/books"
              }
            }
          ],
          dnsConfig: {
            options: [
              {
                name: "ndots",
                value: "1"
              }
            ]
          },
          affinity: {
            nodeAffinity: {
              requiredDuringSchedulingIgnoredDuringExecution: {
                nodeSelectorTerms: [
                  {
                    matchExpressions: [
                      {
                        key: "topology.kubernetes.io/zone",
                        operator: "In",
                        values: [
                          "homelab"
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
            name: "config"
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

