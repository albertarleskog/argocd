local defaults = {
  name: "please provide deployment name, \"blocky\" is suggested",
  namespace: error 'please provide namespace',
  image: error "please provide image",
  subdomain: error "please provide subdomain name",
  domain: error "please provide domain name",
  fqdn: "%s.%s" % [self.subdomain, self.domain],
  replicas: error 'please provide replicas',
  resources: {
    requests: { cpu: "100m", memory: "128Mi" },
    limits: { cpu: "100m", memory: "128Mi" }
  }
};

function(params) {
  local ne = self,
  _config:: defaults + params + {
    env: {
      TZ: "Europe/Stockholm",
      USER_GID: "1000",
    }
  },

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
      ingressClassName: "nginx",
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
                path: "/dns-query",
                pathType: "Exact",
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
      name: ne._config.name,
      namespace: ne._config.namespace
    },
    spec: {
      selector: {
        app: ne._config.name
      },
      ports: [
        {
          port: 80,
          targetPort: "http"
        }
      ]
    }
  },

  deployment: {
    kind: "Deployment",
    apiVersion: "apps/v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace
    },
    spec: {
      replicas: ne._config.replicas,
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
              image: ne._config.image,
              ports: [
                {
                  containerPort: 53,
                  name: "dns"
                },
                {
                  containerPort: 80,
                  name: "http"
                },
                {
                  containerPort: 853,
                  name: "dot"
                }
              ],
              env: [
                {
                  name: o.key,
                  [if std.isString(o.value) then "value" else "valueFrom"]: o.value 
                } for o in std.objectKeysValues(ne._config.env)
              ],
              resources: ne._config.resources,
              volumeMounts: [
                {
                  name: "config",
                  mountPath: "/app/config.yml",
                  subPath: "config.yml"
                },
              ],
              livenessProbe: {
                httpGet: {
                  path: "/api/blocking/status",
                  port: "http"
                },
                initialDelaySeconds: 30,
                failureThreshold: 5,
              }
            }
          ],
          volumes: [
            {
              name: "config",
              configMap: { name: ne._config.name }
            }
          ],
          affinity: {
            podAntiAffinity: {
              preferredDuringSchedulingIgnoredDuringExecution: [
                {
                  weight: 100,
                  podAffinityTerm: {
                    labelSelector: {
                      matchExpressions: [
                        {key: "app", operator: "In", values: [ne._config.name]}
                      ]
                    },
                    topologyKey: "kubernetes.io/hostname"
                  }
                }
              ]
            }
          }
        }
      }
    }
  },

  configmap: {
    kind: "ConfigMap",
    apiVersion: "v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace
    },
    data: {
      "config.yml": |||
        connectIPVersion: v4
        ports:
          http: 80
          tls: 853
        upstream:
          default:
            - https://dns.quad9.net/dns-query
            - tcp-tls:dns.quad9.net
        bootstrapDns:
          - tcp+udp:9.9.9.9
        blocking:
          blackLists:
            default:
              - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts # adware + malware
              - https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/tif.txt # Threat Intelligence Feeds
          clientGroupsBlock:
            default:
              - default
        caching:
          prefetching: true
          minTime: "600m"
        prometheus:
          enable: true
          path: /metrics
      |||
    }
  }
}
