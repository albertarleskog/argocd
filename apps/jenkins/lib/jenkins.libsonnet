local defaults = {
  name:: "please provide deployment name",
  image:: error "please provide image",
  namespace:: error 'pelase provide namespace',
  subdomain:: error "please provide subdomain name",
  domain:: error "please provide domainname",
  fqdn:: "%s.%s" % [self.subdomain, self.domain],
  replicas:: error 'please provide replicas for the deployment'
};

function(params) {
  local _config = defaults + params + {
    env:: {
      PLUGINS_FILE: "/config/plugins.txt",
      CASC_JENKINS_CONFIG: "/config/jenkins.yaml,/vault/secrets/jenkins"
    }
  },

  configmap: {
    kind: "ConfigMap",
    apiVersion: "v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    },
    data: {
      "jenkins.yaml": |||
        jenkins:
          authorizationStrategy:
            roleBased:
              roles:
                global:
                  - name: "admin"
                    description: "Jenkins administrators"
                    permissions:
                      - "Overall/Administer"
                    entries:
                      - group: "admin"
          mode: EXCLUSIVE
          numExecutors: 0
          projectNamingStrategy:
            roleBased:
              forceExistingJobs: false
          securityRealm:
            oic:
              clientId: jenkins
              emailFieldName: email
              fullNameFieldName: given_name
              groupsFieldName: roles
              overrideScopes: "openid email roles"
              userNameField: preferred_username
              wellKnownOpenIDConfigurationUrl: "https://auth.arleskog.se/realms/default/.well-known/openid-configuration"
          slaveAgentPort: 50000
          systemMessage: "Jenkins configured automatically by Jenkins Configuration as Code plugin\n\n"
        unclassified:
          location:
            url: "https://jenkins.arleskog.se/"
          prometheusConfiguration:
            useAuthenticatedEndpoint: true
      |||,
      "plugins.txt": |||
        build-timeout
        git
        gradle
        oic-auth
        role-strategy
        timestamper
        ws-cleanup
        kubernetes
        configuration-as-code
        prometheus
        cloudbees-disk-usage-simple
      |||
    }
  },

  ingress: {
    apiVersion: "networking.k8s.io/v1",
    kind: "Ingress",
    metadata: {
      name: _config.name,
      namespace: _config.namespace,
      annotations: {
        "cert-manager.io/cluster-issuer": "letsencrypt-prod",
        "external-dns.alpha.kubernetes.io/hostname": _config.fqdn
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
      namespace: _config.namespace,
      annotations: {
        "prometheus.io/scrape": "true",
        "prometheus.io/path": "/",
        "prometheus.io/port": "8080"
      }
    },
    spec: {
      selector: {
        app: _config.name
      },
      ports:[
        {
          port: 80,
          name: "http",
          targetPort: "http"
        }
      ]
    }
  },

  "service-jnlp": {
    kind: "Service",
    apiVersion: "v1",
    metadata: {
      name: _config.name + "-jnlp",
      namespace: _config.namespace
    },
    spec: {
      selector: {
        app: _config.name
      },
      type: "NodePort",
      ports:[
        {
          nodePort: 32000,
          port: 50000,
          targetPort: "jnlp"
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
      replicas: _config.replicas,
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
          },
          annotations: {
            "vault.hashicorp.com/agent-inject": 'true',
            "vault.hashicorp.com/role": _config.name,
            "vault.hashicorp.com/agent-inject-secret-jenkins": 'kv/jenkins',
            "vault.hashicorp.com/agent-inject-template-jenkins": |||
              {{- with secret "kv/jenkins" -}}
              jenkins:
                securityRealm:
                  oic:
                    clientSecret: {{ .Data.data.clientSecret }}
              {{- end -}}
            |||
          },
        },
        spec: {
          serviceAccountName: _config.name,
          securityContext: {
            fsGroup: 1000,
            runAsUser: 1000
          },
          containers: [
            {
              name: _config.name,
              image: _config.image,
              securityContext: {
                runAsNonRoot: true
              },
              ports: [
                {
                  name: "http",
                  containerPort: 8080
                },
                {
                  name: "jnlp",
                  containerPort: 50000
                }
              ],
              command: [
                "/bin/bash",
                "-c",
                |||
                  set -euo pipefail

                  if [ -r "$PLUGINS_FILE" ]; then
                    /bin/jenkins-plugin-cli -f "$PLUGINS_FILE" --view-security-warnings
                  fi

                  exec /usr/bin/tini -- /usr/local/bin/jenkins.sh "$@"
                |||
              ],
              env: [{name: o.key, value: o.value} for o in std.objectKeysValues(_config.env)],
              resources: {
                requests: { cpu: "500m", memory: "500Mi" },
                limits: { cpu: "1000m", memory: "2Gi" },
              },
              volumeMounts: [
                {
                  name: "data",
                  mountPath: "/var/jenkins_home"
                },
                {
                  name: "config",
                  mountPath: "/config"
                }
              ],
              livenessProbe: {
                httpGet: {
                  path: "/login",
                  port: "http"
                },
                periodSeconds: 10,
                timeoutSeconds: 5,
                failureThreshold: 5
              },
              readinessProbe: {
                httpGet: {
                  path: "/login",
                  port: "http"
                },
                periodSeconds: 10,
                timeoutSeconds: 5,
                failureThreshold: 3
              },
              startupProbe: {
                httpGet: {
                  path: "/login",
                  port: "http"
                },
                failureThreshold: 24,
                periodSeconds: 10
              }
            }
          ],
          volumes: [
            {
              name: "config",
              configMap: { name: _config.name }
            }
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
  },

  clusterrolebinding: {
    kind: "ClusterRoleBinding",
    apiVersion: "rbac.authorization.k8s.io/v1",
    metadata: {
      name: _config.name
    },
    roleRef: {
      apiGroup: "rbac.authorization.k8s.io",
      kind: "ClusterRole",
      name: _config.name
    },
    subjects: [
      {
        kind: "ServiceAccount",
        name: _config.name,
        namespace: _config.namespace
      }
    ]
  },

  clusterrole: {
    kind: "ClusterRole",
    apiVersion: "rbac.authorization.k8s.io/v1",
    metadata: {
      name: _config.name
    },
    rules: [
      {
        apiGroups: ["*"],
        resources: ["*"],
        verbs: ["*"]
      }
    ]
  }
}
