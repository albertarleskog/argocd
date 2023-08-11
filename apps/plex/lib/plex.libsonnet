local defaults = {
  name:: "please provide deployment name",
  namespace:: error 'pelase provide namespace',
  version:: error "please provide version",
  replicas:: error 'please provide replicas for the deployment',
  resources: {
    limits: { cpu: "250m", memory: "512Mi", "nvidia.com/gpu": 1 },
    requests: { cpu: "100m", memory: "256Mi", "nvidia.com/gpu": 1 }
  }
};

function(params) {
  local _config = defaults + params + {
    env: {
      "PLEX_UID": "1000",
      "PLEX_GID": "1000",
      "TZ": "Europe/Stockholm"
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
      type: "NodePort",
      selector: { app: _config.name },
      ports: [
        {
          port: 32400,
          targetPort: "http",
          nodePort: 32400
        }
      ]
    }
  },

  statefulSet: {
    kind: "StatefulSet",
    apiVersion: "apps/v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    },
    spec: {
      serviceName: _config.name,
      replicas: _config.replicas,
      selector: { matchLabels: { app: _config.name }},
      template: {
        metadata: {
          name: _config.name,
          labels: { app: _config.name }
        },
        spec: {
          containers: [
            {
              name: _config.name,
              image: _config.image,
              env: [
                {
                  name: o.key,
                  [if std.isString(o.value) then "value" else "valueFrom"]: o.value
                } for o in std.objectKeysValues(_config.env)
              ],
              ports: [
                {
                  name: "http",
                  containerPort: 32400
                }
              ],
              resources: _config.resources,
              volumeMounts: [
                {
                  name: "config",
                  mountPath: "/config"
                },
                {
                  name: "media",
                  mountPath: "/data"
                }
              ]
            }
          ],
          volumes: [
            {
              name: "media",
              nfs: {
                server: "10.1.40.100",
                path: "/mnt/tank/media"
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
                storage: "12Gi"
              }
            }
          }
        }
      ]
    }
  }
}