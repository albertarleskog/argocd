local defaults = {
  name:: "please provide deployment name, \"opensearch-dashboards\" is suggested",
  namespace:: error 'pelase provide namespace',
  version:: error "please provide version",
  subdomain:: error "please provide subdomain name",
  domain:: error "please provide domainname",
  fqdn:: "%s.%s" % [self.subdomain, self.domain],
  replicas:: error 'please provide replicas for the deployment',
  opensearchClusterService:: error 'please provide the headless service governing the opensearch statefulset',
};

function(params) {
  local ne = self,
  _config:: defaults + params,

  configmap: {
    kind: "ConfigMap",
    apiVersion: "v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace
    },
    data: {
      "opensearch_dashboards.yml": |||
        server.host: '0.0.0.0'
        server.name: "%s"
        server.ssl.enabled: false

        opensearch.ssl.certificate: "certs/node.crt"
        opensearch.ssl.key: "certs/node.key"
        opensearch.ssl.certificateAuthorities: [ "certs/ca.crt" ]
        opensearch.ssl.verificationMode: "full"
        opensearch.hosts: [ "https://%s.%s.svc.cluster.local:9200" ]
        opensearch.requestHeadersAllowlist: [authorization, securitytenant]

        opensearch_security.auth.type: "openid"
        opensearch_security.openid.connect_url: "https://auth.arleskog.se/realms/default/.well-known/openid-configuration"
        opensearch_security.openid.client_id: "opensearch-dashboards"
        opensearch_security.openid.client_secret: "${OPENSEARCH__SECURITY_OPENID_CLIENT__SECRET}"
        opensearch_security.openid.base_redirect_url: "https://dashboards.arleskog.se/"
        opensearch_security.openid.refresh_tokens: true

        opensearch_security.multitenancy.enabled: true
        opensearch_security.multitenancy.tenants.preferred: [Private, Global]
        opensearch_security.readonly_mode.roles: ["kibana_read_only"]
        opensearch_security.cookie.secure: true
      ||| % [ne._config.name, ne._config.opensearchClusterService, ne._config.namespace]
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
      ports:[
        {
          port: 80,
          name: "http",
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
        matchLabels: { app: ne._config.name }
      },
      strategy: { type: "Recreate" },
      template: {
        metadata: {
          name: ne._config.name,
          labels: { app: ne._config.name }
        },
        spec: {
          serviceAccountName: "opensearch-cluster",
          securityContext: { fsGroup: 1000 },
          containers: [
            {
              name: ne._config.name,
              image: "docker.io/opensearchproject/opensearch-dashboards:" + ne._config.version,
              ports: [
                {
                  name: "http",
                  containerPort: 5601
                }
              ],
              resources: {
                requests: { cpu: "200m", memory: "512Mi" },
                limits: { cpu: "200m", memory: "512Mi" },
              },
              env: [
                {
                  name: "OPENSEARCH__SECURITY_OPENID_CLIENT__SECRET",
                  valueFrom: {
                    secretKeyRef: {
                      name: ne._config.name,
                      key: "client_secret"
                    }
                  }
                }
              ],
              volumeMounts: [
                {
                  name: "certs",
                  mountPath: "/usr/share/opensearch-dashboards/certs"
                },
                {
                  name: "config",
                  mountPath: "/usr/share/opensearch-dashboards/config"
                }
              ]
            }
          ],
          volumes: [
            {
              name: "certs",
              csi: {
                driver: "csi.cert-manager.io",
                readOnly: true,
                volumeAttributes: {
                  "csi.cert-manager.io/issuer-name": "opensearch-cluster",
                  "csi.cert-manager.io/issuer-kind": "Issuer",
                  "csi.cert-manager.io/common-name": "%s.${POD_NAMESPACE}.svc.cluster.local" % ne._config.name,
                  "csi.cert-manager.io/duration": "720h",
                  "csi.cert-manager.io/is-ca": "false",
                  "csi.cert-manager.io/key-usages": "server auth,client auth",
                  "csi.cert-manager.io/dns-names": "${POD_NAME}.${POD_NAMESPACE}.svc.cluster.local",
                  "csi.cert-manager.io/certificate-file": "node.crt",
                  "csi.cert-manager.io/ca-file": "ca.crt",
                  "csi.cert-manager.io/privatekey-file": "node.key",
                  "csi.cert-manager.io/fs-group": "1000"
                }
              }
            },
            {
              name: "config",
              configMap: { name: ne._config.name }
            }
          ],
        }
      }
    }
  }
}
