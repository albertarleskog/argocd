local defaults = {
  name: "please provide deployment name",
  namespace: error 'please provide namespace',
  image: error "please provide image",
  resources: {
    requests: { cpu: "250m", memory: "512Mi" },
    limits: { cpu: "250m", memory: "512Mi" }
  }
};

function(params) {
  local _config = defaults + params,

  configMap: {
    kind: "ConfigMap",
    apiVersion: "v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    },
    data: {
      "fluent-bit.conf": |||
            [SERVICE]
                Daemon Off
                Log_Level error
                Parsers_File /fluent-bit/etc/parsers.conf
                HTTP_Server On
                HTTP_Listen 0.0.0.0
                HTTP_Port 2020
                Health_Check On

            #
            # CPU pipeline
            #

            [INPUT]
                name cpu
                tag  cpu
                interval_sec 1

            #
            # Kubernetes pipeline
            #

            [INPUT]
                Name tail
                Path /var/log/containers/*.log
                multiline.parser cri
                Tag kube.*
                Mem_Buf_Limit 50MB
                Skip_Long_Lines On
            [FILTER]
                Name kubernetes
                Match kube.*
                Merge_Log On
                Keep_Log Off
                K8S-Logging.Parser On
                K8S-Logging.Exclude On
            # Rewrite if logs match NGINX.
            [FILTER]
                Name rewrite_tag
                Match kube.*
                Rule $message ^[\d\.]+\s-\s[\w\-]+\s[\[\w\d\/:\s+\]]+\s"(HEAD|POST|GET|PUT|DELETE)\s[\d\w\/\.\=\?\-]*\s(HTTP)\/\d\.\d"\s\d{3}\s\d+\s"[\w\d\.\-\/]+"\s"[\w\d\.\-\/\s()]*"\s\d+\s[\d\.]+\s\[[\d\w\-]*\]\s\[[\d\w\-]*\]\s[\w\d\-\/\.:]+\s[\d\-]+\s[\d\-\.]+\s[\d\-]+\s[\d\w]*$ logs.ingress-nginx false
            [FILTER]
                Name parser
                Match logs.ingress-nginx
                Key_Name message
                Parser nginx
                Reserve_Data true
            [OUTPUT]
                Match logs.ingress-nginx
                tls On
                tls.ca_file /certs/ca.pem
                tls.crt_file /certs/crt.pem
                tls.key_file /certs/key.pem
                Name opensearch
                Host opensearch-cluster-headless.opensearch.svc.cluster.local
                Buffer_Size 512KB
                Logstash_Format On
                Logstash_Prefix ingress-nginx-logs
                Replace_Dots On
                Suppress_Type_Name On
                Trace_Error true
            [OUTPUT]
                Match kube.*
                tls On
                tls.ca_file /certs/ca.pem
                tls.crt_file /certs/crt.pem
                tls.key_file /certs/key.pem
                Name es
                Host opensearch-cluster-headless.opensearch.svc.cluster.local
                Logstash_Format On
                Replace_Dots On
                Suppress_Type_Name On
                Trace_Error true

            #
            # Host pipeline
            #

            [INPUT]
                Name systemd
                Tag host
                Systemd_Filter _SYSTEMD_UNIT=kubelet.service
                Read_From_Tail On
            [OUTPUT]
                Match host
                tls On
                tls.ca_file /certs/ca.pem
                tls.crt_file /certs/crt.pem
                tls.key_file /certs/key.pem
                Name es
                Host opensearch-cluster-headless.opensearch.svc.cluster.local
                Logstash_Format On
                Logstash_Prefix node
                Replace_Dots On
                Suppress_Type_Name On
                Trace_Error true
      |||
    }
  },

  daemonset: {
    kind: "DaemonSet",
    apiVersion: "apps/v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    },
    spec: {
      selector: {
        matchLabels: {
          app: _config.name
        }
      },
      template: {
        metadata: {
          labels: {
            app: _config.name
          }
        },
        spec: {
          serviceAccountName: _config.name,
          hostUsers: false,
          containers: [
            {
              name: _config.name,
              image: _config.image,
              resources: _config.resources,
              args: [
                "-c",
                "/fluent-bit.conf"
              ],
              volumeMounts: [
                {
                  name: "certs",
                  mountPath: "/certs"
                },
                {
                  name: "varlog",
                  mountPath: "/var/log",
                  readOnly: true
                },
                {
                  name: "etcmachineid",
                  mountPath: "/etc/machine-id",
                  readOnly: true
                },
                {
                  name: "configmap",
                  mountPath: "/fluent-bit.conf",
                  subPath: "fluent-bit.conf",
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
                  "csi.cert-manager.io/issuer-name": _config.name,
                  "csi.cert-manager.io/issuer-kind": "Issuer",
                  "csi.cert-manager.io/common-name": "%s.users.opensearch.svc.cluster.local" % _config.name,
                  "csi.cert-manager.io/duration": "720h",
                  "csi.cert-manager.io/is-ca": "false",
                  "csi.cert-manager.io/key-usages": "server auth,client auth",
                  "csi.cert-manager.io/dns-names": "${POD_NAME}.users.opensearch.svc.cluster.local",
                  "csi.cert-manager.io/certificate-file": "crt.pem",
                  "csi.cert-manager.io/ca-file": "ca.pem",
                  "csi.cert-manager.io/privatekey-file": "key.pem",
                }
              }
            },
            {
              name: "varlog",
              hostPath: {
                path: "/var/log"
              }
            },
            {
              name: "etcmachineid",
              hostPath: {
                path: "/etc/machine-id",
                type: "File"
              }
            },
            {
              name: "configmap",
              configMap: { name: _config.name }
            }
          ]
        }
      }
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

  issuer: {
    kind: "Issuer",
    apiVersion: "cert-manager.io/v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    },
    spec: {
      vault: {
        path: "pki_int/sign/opensearch-mtls",
        server: "https://vault.arleskog.se",
        auth: {
          kubernetes: {
            role: _config.name,
            mountPath: "/v1/auth/kubernetes",
            serviceAccountRef: {
              name: _config.name
            }
          }
        }
      }
    }
  },

  role: {
    kind: "Role",
    apiVersion: "rbac.authorization.k8s.io/v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['serviceaccounts/token'],
        resourceNames: [_config.name],
        verbs: ['create']
      }
    ]
  },

  rolebinding: {
    kind: "RoleBinding",
    apiVersion: "rbac.authorization.k8s.io/v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
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
      name: _config.name,
    }
  }
}

