local defaults = {
  name: "please provide deployment name, \"forgejo\" is suggested",
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
  local ne = self,
  _config:: defaults + params + {
    env: {
      USER_UID: "1000",
      USER_GID: "1000",
      FORGEJO__DEFAULT__APP_NAME: "Forgejo: Beyond coding. We forge.",
      FORGEJO__DEFAULT__RUN_MODE: "prod",
      FORGEJO__repository__ROOT: "/data/git/repositories",
      FORGEJO__repository__DEFAULT_REPO_UNITS: "repo.code,repo.releases",
      FORGEJO__cors__ENABLED: "true",
      FORGEJO__cors__SCHEME: "https",
      FORGEJO__cors__ALLOW_DOMAIN: "*." + ne._config.domain,
      FORGEJO__cors__ALLOW_SUBDOMAIN: "true",
      FORGEJO__server__APP_DATA_PATH: "/data/gitea",
      FORGEJO__server__PROTOCOL: "http",
      FORGEJO__server__DOMAIN: ne._config.fqdn,
      FORGEJO__server__ROOT_URL: "https://" + ne._config.fqdn,
      FORGEJO__server__HTTP_PORT: "3000",
      FORGEJO__server__DISABLE_SSH: "false",
      FORGEJO__server__SSH_DOMAIN: ne._config.fqdn, // Displayed in clone URL.
      FORGEJO__server__SSH_PORT: "22", // Displayed in clone URL.
      FORGEJO__server__SSH_USER: "git", // Displayed in clone URL.
      FORGEJO__server__SSH_LISTEN_PORT: "22",
      FORGEJO__database__DB_TYPE: "postgres",
      FORGEJO__database__HOST: "postgresql.db.svc.cluster.local:5432",
      FORGEJO__database__NAME: "forgejo",
      FORGEJO__database__USER: "forgejo",
      FORGEJO__database__PASSWD: {
        secretKeyRef: {
          name: ne._config.name,
          key: "postgres-passwd"
        }
      },
      FORGEJO__database__LOG_SQL: "false",
      // TODO: Opensearch as indexer.
      FORGEJO__indexer__ISSUE_INDEXER_PATH: "/data/gitea/indexers/issues.bleve",
      FORGEJO__security__INSTALL_LOCK: "true",
      FORGEJO__security__LOGIN_REMEMBER_DAYS: "1",
      FORGEJO__security__REVERSE_PROXY_TRUSTED_PROXIES: "10.69.0.0/16",
      FORGEJO__oauth2_client__REGISTER_EMAIL_CONFIRM: "false",
      FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION: "true",
      FORGEJO__oauth2_client__UPDATE_AVATAR: "true",
      FORGEJO__oauth2_client__ACCOUNT_LINKING: "auto",
      FORGEJO__service__DISABLE_REGISTRATION: "true",
      FORGEJO__service__REQUIRE_SIGNIN_VIEW: "true",
      FORGEJO__service__ENABLE_TIMETRACKING: "false",
      FORGEJO__service__AUTO_WATCH_ON_CHANGES: "true",
      FORGEJO__service__VALID_SITE_URL_SCHEMES: "https",
      # TODO: Memcache/redis for cache.
      FORGEJO__session__PROVIDER: "db",
      FORGEJO__session__COOKIE_SECURE: "true",
      FORGEJO__session__DOMAIN: "git.arleskog.se",
      FORGEJO__picture__AVATAR_UPLOAD_PATH: "/data/gitea/avatars",
      FORGEJO__picture__REPOSITORY_AVATAR_UPLOAD_PATH: "/data/gitea/repo-avatars",
      FORGEJO__project__PROJECT_BOARD_BASIC_KANBAN_TYPE: "To Do, In Progress, Blocked, Done",
      # TODO: Auth for prometheus.
      # FORGEJO__metrics__ENABLED: "true",
      # FORGEJO__metrics__TOKEN: "",
      # TODO: Enable when stable.
      # FORGEJO__federation__ENABLED: "true",
      # FORGEJO__federation__SHARE_USER_STATISTICS: "false"
      # TODO: Use Minio for storage.
      FORGEJO__attachment__PATH: "/data/gitea/attachments",
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

  statefulset: {
    kind: "StatefulSet",
    apiVersion: "apps/v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace
    },
    spec: {
      serviceName: ne._config.name,
      replicas: 1,
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
          terminationGracePeriodSeconds: 60,
          securityContext: {
            fsGroup: 1000
          },
          containers: [
            {
              name: ne._config.name,
              image: ne._config.image,
              ports: [
                {
                  containerPort: 3000,
                  name: "http"
                },
                {
                  containerPort: 22,
                  name: "ssh"
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
                  name: "data",
                  mountPath: "/data"
                },
              ],
              livenessProbe: {
                httpGet: {
                  path: "/api/healthz",
                  port: "http"
                },
                initialDelaySeconds: 180,
                timeoutSeconds: 5,
                periodSeconds: 10,
                successThreshold: 1,
                failureThreshold: 10,
              }
            },
          ]
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
                storage: "8Gi"
              }
            }
          }
        }
      ]
    }
  }
}
