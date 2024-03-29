local defaults = {
  name:: error "please provide deployment name, \"opensearch\" is suggested",
  namespace:: error 'provide namespace',
  version:: error "please provide image version",
  replicas:: error 'provide statefulset replicas',
  subdomain:: error "please provide subdomain name",
  domain:: error "please provide domainname",
  fqdn:: "%s.%s" % [self.subdomain, self.domain],
};

function(params) {
  local ne = self,
  _config:: defaults + params + {
    // OS nodes have a name for reference in the cluster and a hostname for internal communication.
    nodes: [
      {
        name: "%s-%d" % [ne._config.name, i]
      } for i in std.range(0, ne._config.replicas - 1)
    ],
    clusterName: "%s-cluster" % ne._config.name,
    env: {
      "OPENSEARCH_JAVA_OPTS": "-Xms1g -Xmx1g",
      "network.publish_host": "${HOSTNAME}.opensearch-cluster-headless.opensearch.svc.cluster.local"
    }
  },

  "configmap-config": {
    kind: "ConfigMap",
    apiVersion: "v1",
    metadata: {
      name: ne._config.name + "-config",
      namespace: ne._config.namespace
    },
    data: {
      "opensearch.yml": |||
        ---
      ||| + |||
        cluster.name: %s
      ||| % ne._config.clusterName + |||
        network.host: [ _local_, _site_ ]

        plugins.security.ssl.transport.pemcert_filepath: "certs/node.crt"
        plugins.security.ssl.transport.pemkey_filepath: "certs/node.key"
        plugins.security.ssl.transport.pemtrustedcas_filepath: "certs/ca.crt"
        plugins.security.ssl.transport.resolve_hostname: false # Unable to add ip address to SAN in cert.
        plugins.security.ssl.http.enabled: true
        plugins.security.ssl.http.pemcert_filepath: "certs/node.crt"
        plugins.security.ssl.http.pemkey_filepath: "certs/node.key"
        plugins.security.ssl.http.pemtrustedcas_filepath: "certs/ca.crt"
        plugins.security.ssl.http.clientauth_mode: "OPTIONAL"

        plugins.security.audit.type: internal_opensearch
        plugins.security.enable_snapshot_restore_privilege: true
        plugins.security.check_snapshot_restore_write_privileges: true
        plugins.security.restapi.roles_enabled: [ "all_access", "security_rest_api_access" ]
        plugins.security.system_indices.enabled: true
        plugins.security.system_indices.indices: [ ".plugins-ml-model-group", ".plugins-ml-model", ".plugins-ml-task", ".opendistro-alerting-config", ".opendistro-alerting-alert*", ".opendistro-anomaly-results*", ".opendistro-anomaly-detector*", ".opendistro-anomaly-checkpoints", ".opendistro-anomaly-detection-state", ".opendistro-reports-*", ".opensearch-notifications-*", ".opensearch-notebooks", ".opensearch-observability", ".ql-datasources", ".opendistro-asynchronous-search-response*", ".replication-metadata-store", ".opensearch-knn-models" ]
      ||| + |||
        plugins.security.nodes_dn: [ "CN=*.%s.svc.cluster.local" ]
      ||| % ne._config.namespace + |||
        plugins.security.authcz.admin_dn: [ "CN=admin.%s.svc.cluster.local" ]
      ||| % ne._config.namespace + |||
        discovery.seed_hosts: [ "%s-headless.%s.svc.cluster.local" ]
      ||| % [ne._config.clusterName, ne._config.namespace] + |||
        cluster.initial_cluster_manager_nodes: [ %s ]
      ||| % ne._config.nodes[0].name + if ne._config.replicas == 1 then |||
        discovery.type: "single-node"
      ||| else ""
    }
  },

  "configmap-security": {
    kind: "ConfigMap",
    apiVersion: "v1",
    metadata: {
      name: ne._config.name + "-security",
      namespace: ne._config.namespace
    },
    data: {
      "config.yml": |||
        _meta:
          type: "config"
          config_version: 2
        config:
          dynamic:
            kibana:
              # Kibana multitenancy
              multitenancy_enabled: true
              private_tenant_enabled: true
              #default_tenant: ""
              server_username: "opensearch-dashboards.opensearch.svc.cluster.local"
              index: '.opensearch_dashboards'
            http:
              anonymous_auth_enabled: false
            authc:
              basic_internal_auth_domain:
                description: "Authenticate via HTTP Basic against internal users database"
                http_enabled: true
                transport_enabled: false
                order: 0
                http_authenticator:
                  type: basic
                  challenge: false
                authentication_backend:
                  type: intern
              clientcert_auth_domain:
                description: "Authenticate via SSL client certificates"
                http_enabled: true
                transport_enabled: false
                order: 1
                http_authenticator:
                  type: clientcert
                  config:
                    username_attribute: cn #optional, if omitted DN becomes username
                  challenge: false
                authentication_backend:
                  type: noop
              openid_auth:
                description: "Authenticate with OIDC to Keycloak"
                http_enabled: true
                transport_enabled: false
                order: 2
                http_authenticator:
                  type: openid
                  challenge: false
                  config:
                    openid_connect_idp:
                      enable_ssl: true
                      # ISRG Root X1 and Let’s Encrypt R3
                      pemtrustedcas_content: |-
                        -----BEGIN CERTIFICATE-----
                        MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
                        TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
                        cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
                        WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
                        ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
                        MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
                        h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
                        0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
                        A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
                        T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
                        B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
                        B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
                        KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
                        OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
                        jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
                        qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
                        rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
                        HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
                        hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
                        ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
                        3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
                        NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
                        ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
                        TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
                        jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
                        oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
                        4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
                        mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
                        emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
                        -----END CERTIFICATE-----
                        -----BEGIN CERTIFICATE-----
                        MIIFFjCCAv6gAwIBAgIRAJErCErPDBinU/bWLiWnX1owDQYJKoZIhvcNAQELBQAw
                        TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
                        cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMjAwOTA0MDAwMDAw
                        WhcNMjUwOTE1MTYwMDAwWjAyMQswCQYDVQQGEwJVUzEWMBQGA1UEChMNTGV0J3Mg
                        RW5jcnlwdDELMAkGA1UEAxMCUjMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
                        AoIBAQC7AhUozPaglNMPEuyNVZLD+ILxmaZ6QoinXSaqtSu5xUyxr45r+XXIo9cP
                        R5QUVTVXjJ6oojkZ9YI8QqlObvU7wy7bjcCwXPNZOOftz2nwWgsbvsCUJCWH+jdx
                        sxPnHKzhm+/b5DtFUkWWqcFTzjTIUu61ru2P3mBw4qVUq7ZtDpelQDRrK9O8Zutm
                        NHz6a4uPVymZ+DAXXbpyb/uBxa3Shlg9F8fnCbvxK/eG3MHacV3URuPMrSXBiLxg
                        Z3Vms/EY96Jc5lP/Ooi2R6X/ExjqmAl3P51T+c8B5fWmcBcUr2Ok/5mzk53cU6cG
                        /kiFHaFpriV1uxPMUgP17VGhi9sVAgMBAAGjggEIMIIBBDAOBgNVHQ8BAf8EBAMC
                        AYYwHQYDVR0lBBYwFAYIKwYBBQUHAwIGCCsGAQUFBwMBMBIGA1UdEwEB/wQIMAYB
                        Af8CAQAwHQYDVR0OBBYEFBQusxe3WFbLrlAJQOYfr52LFMLGMB8GA1UdIwQYMBaA
                        FHm0WeZ7tuXkAXOACIjIGlj26ZtuMDIGCCsGAQUFBwEBBCYwJDAiBggrBgEFBQcw
                        AoYWaHR0cDovL3gxLmkubGVuY3Iub3JnLzAnBgNVHR8EIDAeMBygGqAYhhZodHRw
                        Oi8veDEuYy5sZW5jci5vcmcvMCIGA1UdIAQbMBkwCAYGZ4EMAQIBMA0GCysGAQQB
                        gt8TAQEBMA0GCSqGSIb3DQEBCwUAA4ICAQCFyk5HPqP3hUSFvNVneLKYY611TR6W
                        PTNlclQtgaDqw+34IL9fzLdwALduO/ZelN7kIJ+m74uyA+eitRY8kc607TkC53wl
                        ikfmZW4/RvTZ8M6UK+5UzhK8jCdLuMGYL6KvzXGRSgi3yLgjewQtCPkIVz6D2QQz
                        CkcheAmCJ8MqyJu5zlzyZMjAvnnAT45tRAxekrsu94sQ4egdRCnbWSDtY7kh+BIm
                        lJNXoB1lBMEKIq4QDUOXoRgffuDghje1WrG9ML+Hbisq/yFOGwXD9RiX8F6sw6W4
                        avAuvDszue5L3sz85K+EC4Y/wFVDNvZo4TYXao6Z0f+lQKc0t8DQYzk1OXVu8rp2
                        yJMC6alLbBfODALZvYH7n7do1AZls4I9d1P4jnkDrQoxB3UqQ9hVl3LEKQ73xF1O
                        yK5GhDDX8oVfGKF5u+decIsH4YaTw7mP3GFxJSqv3+0lUFJoi5Lc5da149p90Ids
                        hCExroL1+7mryIkXPeFM5TgO9r0rvZaBFOvV2z0gp35Z0+L4WPlbuEjN/lxPFin+
                        HlUjr8gRsI3qfJOQFy/9rKIJR0Y/8Omwt/8oTWgy1mdeHmmjk7j1nYsvC9JSQ6Zv
                        MldlTTKB3zhThV1+XWYp6rjd5JW1zbVWEkLNxE7GJThEUG3szgBVGP7pSWTUTsqX
                        nLRbwHOoq7hHwg==
                        -----END CERTIFICATE-----
                    subject_key: preferred_username
                    roles_key: roles
                    openid_connect_url: https://auth.arleskog.se/realms/default/.well-known/openid-configuration
                authentication_backend:
                  type: noop
            auth_failure_listeners:
              internal_authentication_backend_limiting:
                type: username
                authentication_backend: internal
                allowed_tries: 3
                time_window_seconds: 60
                block_expiry_seconds: 300
                max_blocked_clients: 10000
                max_tracked_clients: 10000
      |||,
      "internal_users.yml": |||
        _meta:
          type: "internalusers"
          config_version: 2
      |||,
      "roles.yml": |||
        _meta:
          type: "roles"
          config_version: 2

        # Restrict users so they can only view visualization and dashboard on OpenSearchDashboards
        kibana_read_only:
          reserved: true

        # The security REST API access role is used to assign specific users access to change the security settings through the REST API.
        security_rest_api_access:
          reserved: true

        security_rest_api_full_access:
          reserved: true
          cluster_permissions:
            - 'restapi:admin/actiongroups'
            - 'restapi:admin/allowlist'
            - 'restapi:admin/internalusers'
            - 'restapi:admin/nodesdn'
            - 'restapi:admin/roles'
            - 'restapi:admin/rolesmapping'
            - 'restapi:admin/ssl/certs/info'
            - 'restapi:admin/ssl/certs/reload'
            - 'restapi:admin/tenants'
      |||,
      "roles_mapping.yml": |||
        _meta:
          type: "rolesmapping"
          config_version: 2

        kibana_server:
          reserved: true
          users:
            - "opensearch-dashboards.opensearch.svc.cluster.local"

        own_index:
          reserved: false
          users:
            - "*"
          description: "Allow full access to an index named like the username"

        all_access:
          reserved: false
          backend_roles:
            - "admin"
          description: "Maps admin to all_access"

        kibana_user:
          reserved: false
          backend_roles:
            - "kibanauser"
          description: "Maps kibanauser to kibana_user"
      |||,
      "action_groups.yml": |||
        _meta:
          type: "actiongroups"
          config_version: 2
      |||,
      "tenants.yml": |||
        _meta:
          type: "tenants"
          config_version: 2
      |||,
      "nodes_dn.yml": |||
        _meta:
          type: "nodesdn"
          config_version: 2
      |||,
      "whitelist.yml": |||
        _meta:
          type: "whitelist"
          config_version: 2
      |||
    }
  },

  ingress: {
    apiVersion: "networking.k8s.io/v1",
    kind: "Ingress",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace,
      annotations: {
        "cert-manager.io/cluster-issuer": "letsencrypt-prod",
        "external-dns.alpha.kubernetes.io/hostname": ne._config.fqdn,
        "nginx.ingress.kubernetes.io/backend-protocol": "HTTPS"
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
                path: "/",
                pathType: "Prefix",
                backend: {
                  service: {
                    name: ne._config.clusterName + "-headless",
                    port: {
                      number: 9200
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

  serviceaccount:  {
    kind: "ServiceAccount",
    apiVersion: "v1",
    metadata: {
        name: ne._config.clusterName,
        namespace: ne._config.namespace
    }
  },

  issuer: {
    kind: "Issuer",
    apiVersion: "cert-manager.io/v1",
    metadata: {
      name: ne._config.clusterName,
      namespace: ne._config.namespace
    },
    spec: {
      vault: {
        path: "pki_int/sign/opensearch-cluster",
        server: "https://vault.arleskog.se",
        auth: {
          kubernetes: {
            role: ne._config.clusterName,
            mountPath: "/v1/auth/kubernetes",
            serviceAccountRef: {
              name: ne._config.clusterName
            }
          }
        }
      }
    }
  },

  role:  {
      kind: "Role",
      apiVersion: "rbac.authorization.k8s.io/v1",
      metadata: {
        name: ne._config.clusterName,
        namespace: ne._config.namespace
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['serviceaccounts/token'],
          resourceNames: [ne._config.clusterName],
          verbs: ['create']
        }
      ]
  },

  rolebinding: {
      kind: "RoleBinding",
      apiVersion: "rbac.authorization.k8s.io/v1",
      metadata: {
        name: ne._config.clusterName,
        namespace: ne._config.namespace
      },
      subjects: [
        {
          kind: "ServiceAccount",
          name: "cert-manager",
          namespace: "cert-manager",
        }
      ],
      roleRef: {
        kind: "Role",
        apiGroup: "rbac.authorization.k8s.io",
        name: ne._config.clusterName,
      }
  },

  "service-headless": {
    kind: "Service",
    apiVersion: "v1",
    metadata: {
      name: ne._config.clusterName + "-headless",
      namespace: ne._config.namespace,
      annotations: {
        "service.alpha.kubernetes.io/tolerate-unready-endpoints": "true"
      }
    },
    spec: {
      clusterIP: "None",
      publishNotReadyAddresses: true,
      selector: {
        app: ne._config.name
      },
      ports:[
        {
          name: "http",
          port: 9200
        },
        {
          name: "transport",
          port: 9300
        },
        {
          name: "analyze",
          port: 9600
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
      serviceName: ne._config.clusterName + "-headless",
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
          serviceAccountName: ne._config.clusterName,
          terminationGracePeriodSeconds: 120,
          securityContext: {
            fsGroup: 1000
          },
          containers: [
            {
              name: ne._config.name,
              image: "docker.io/opensearchproject/opensearch:" + ne._config.version,
              securityContext: {
                runAsNonRoot: true
              },
              ports: [
                {
                  name: "http",
                  containerPort: 9200
                },
                {
                  name: "transport",
                  containerPort: 9300
                },
                {
                  name: "analyze",
                  containerPort: 9600
                }
              ],
              env: [{name: o.key, value: o.value} for o in std.objectKeysValues(ne._config.env)] +
              [
                {
                  name: "node.name",
                  valueFrom: { fieldRef: { fieldPath: "metadata.name" } }
                }
              ],
              resources: {
                requests: { cpu: "500m" },
                limits: { cpu: "500m" },
              },
              volumeMounts: [
                {
                  name: "data",
                  mountPath: "/usr/share/opensearch/data"
                },
                {
                  name: "certs",
                  mountPath: "/usr/share/opensearch/config/certs"
                },
                {
                  name: "security-config",
                  mountPath: "/usr/share/opensearch/config/opensearch-security"
                },
                {
                  name: "config",
                  mountPath: "/usr/share/opensearch/config/opensearch.yml",
                  subPath: "opensearch.yml"
                }
              ],
              startupProbe: {
                tcpSocket: {
                  port: 9200
                },
                initialDelaySeconds: 5,
                periodSeconds: 10,
                timeoutSeconds: 3,
                failureThreshold: 30,
              },
              readinessProbe: {
                tcpSocket: {
                  port: 9200
                },
                periodSeconds: 5,
                timeoutSeconds: 3,
                failureThreshold: 3,
              }
            }
          ],
          volumes: [
            {
              name: "certs",
              csi: {
                driver: "csi.cert-manager.io",
                readOnly: true,
                volumeAttributes: {
                  "csi.cert-manager.io/issuer-name": ne._config.clusterName,
                  "csi.cert-manager.io/issuer-kind": "Issuer",
                  "csi.cert-manager.io/common-name": "${POD_NAME}.%s-headless.%s.svc.cluster.local" % [ne._config.clusterName, ne._config.namespace],
                  "csi.cert-manager.io/duration": "720h",
                  "csi.cert-manager.io/is-ca": "false",
                  "csi.cert-manager.io/key-usages": "server auth,client auth",
                  "csi.cert-manager.io/dns-names": "${POD_NAME}.%s-headless.%s.svc.cluster.local,%s-headless.%s.svc.cluster.local" % [ne._config.clusterName, ne._config.namespace, ne._config.clusterName, ne._config.namespace],
                  "csi.cert-manager.io/certificate-file": "node.crt",
                  "csi.cert-manager.io/ca-file": "ca.crt",
                  "csi.cert-manager.io/privatekey-file": "node.key",
                  "csi.cert-manager.io/fs-group": "1000",
                  "csi.cert-manager.io/key-encoding": "PKCS8"
                }
              }
            },
            {
              name: "security-config",
              configMap: { name: ne._config.name + "-security" }
            },
            {
              name: "config",
              configMap: { name: ne._config.name + "-config" }
            }
          ],
          affinity: {
            nodeAffinity: {
              requiredDuringSchedulingIgnoredDuringExecution: {
                nodeSelectorTerms: [
                  {
                    matchExpressions: [
                      {key: "disktype", operator: "In", values: ["ssd"]}  
                    ]
                  }
                ]
              }
            },
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
