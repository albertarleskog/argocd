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
  local _config = defaults + params + {
    env: {
      USER_UID: "1000",
      USER_GID: "1000",
      FORGEJO__DEFAULT__APP_NAME: "Forgejo: Beyond coding. We forge.",
      FORGEJO__DEFAULT__RUN_MODE: "prod",
      FORGEJO__repository__ROOT: "/data/git/repositories",
      FORGEJO__repository__DEFAULT_REPO_UNITS: "repo.code,repo.releases,repo.issues,repo.pulls",
      FORGEJO__cors__ENABLED: "true",
      FORGEJO__cors__SCHEME: "https",
      FORGEJO__cors__ALLOW_DOMAIN: "*." + _config.domain,
      FORGEJO__cors__ALLOW_SUBDOMAIN: "true",
      FORGEJO__server__APP_DATA_PATH: "/data/gitea",
      FORGEJO__server__PROTOCOL: "http",
      FORGEJO__server__DOMAIN: _config.fqdn,
      FORGEJO__server__ROOT_URL: "https://" + _config.fqdn,
      FORGEJO__server__HTTP_PORT: "3000",
      FORGEJO__server__START_SSH_SERVER: "true",
      FORGEJO__server__BUILTIN_SSH_SERVER_USER: "git",
      FORGEJO__server__SSH_DOMAIN: _config.fqdn, // Displayed in clone URL.
      FORGEJO__server__SSH_PORT: "32222", // Displayed in clone URL.
      FORGEJO__server__SSH_LISTEN_PORT: "32222",
      FORGEJO__database__DB_TYPE: "postgres",
      FORGEJO__database__HOST: "postgresql.db.svc.cluster.local:5432",
      FORGEJO__database__NAME: "forgejo",
      FORGEJO__database__USER: "forgejo",
      FORGEJO__database__LOG_SQL: "false",
      FORGEJO__indexer__ISSUE_INDEXER_TYPE: "elasticsearch",
      FORGEJO__indexer__ISSUE_INDEXER_NAME: "forgejo-issues",
      FORGEJO__indexer__REPO_INDEXER_ENABLED: "true",
      FORGEJO__indexer__REPO_INDEXER_REPO_TYPES: "sources,forks,templates",
      FORGEJO__indexer__REPO_INDEXER_TYPE: "elasticsearch",
      FORGEJO__indexer__REPO_INDEXER_NAME: "forgejo-codes",
      FORGEJO__security__INSTALL_LOCK: "true",
      FORGEJO__security__LOGIN_REMEMBER_DAYS: "1",
      FORGEJO__security__REVERSE_PROXY_TRUSTED_PROXIES: "10.69.0.0/16",
      FORGEJO__oauth2_client__REGISTER_EMAIL_CONFIRM: "false",
      FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION: "true",
      FORGEJO__oauth2_client__UPDATE_AVATAR: "true",
      FORGEJO__oauth2_client__ACCOUNT_LINKING: "auto",
      FORGEJO__service__DISABLE_REGISTRATION: "true",
      FORGEJO__service__REQUIRE_SIGNIN_VIEW: "false",
      FORGEJO__service__ENABLE_TIMETRACKING: "false",
      FORGEJO__service__AUTO_WATCH_ON_CHANGES: "true",
      FORGEJO__service__VALID_SITE_URL_SCHEMES: "https",
      FORGEJO__service__ENABLE_BASIC_AUTHENTICATION: "false",
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
      FORGEJO__attachment__PATH: "/data/gitea/attachments",
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

  "service-ssh": {
    kind: "Service",
    apiVersion: "v1",
    metadata: {
      name: _config.name + "-ssh",
      namespace: _config.namespace
    },
    spec: {
      type: "NodePort",
      selector: {
        app: _config.name
      },
      ports: [
        {
          port: 32222,
          targetPort: "ssh",
          nodePort: 32222
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
          annotations: {
            "vault.hashicorp.com/agent-inject": "true",
            "vault.hashicorp.com/role": _config.name,
            "vault.hashicorp.com/agent-inject-secret-forgejo": "kv/forgejo",
            "vault.hashicorp.com/agent-inject-template-forgejo": |||
              {{- with secret "kv/forgejo" -}}
              export FORGEJO__database__PASSWD="{{ .Data.data.POSTGRES_PASSWD }}"
              export FORGEJO__indexer__ISSUE_INDEXER_CONN_STR="{{ .Data.data.ISSUE_INDEXER_CONN_STR }}"
              export FORGEJO__indexer__REPO_INDEXER_CONN_STR="{{ .Data.data.REPO_INDEXER_CONN_STR }}"
              {{- end -}}
            |||,
          },
          labels: {
            app: _config.name
          }
        },
        spec: {
          serviceAccountName: _config.name,
          terminationGracePeriodSeconds: 60,
          securityContext: {
            fsGroup: 1000
          },
          containers: [
            {
              name: _config.name,
              image: _config.image,
              command: [
                "/bin/bash",
                "-c",
                |||
                  set -euo pipefail
                  source /vault/secrets/forgejo
                  exec /usr/bin/dumb-init -- /usr/local/bin/docker-entrypoint.sh "$@"
                |||
              ],
              ports: [
                {
                  containerPort: 3000,
                  name: "http"
                },
                {
                  containerPort: 32222,
                  name: "ssh"
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
  },

  serviceaccount: {
    kind: "ServiceAccount",
    apiVersion: "v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    }
  }
}

