local defaults = {
  name: "please provide deployment name",
  namespace: error 'please provide namespace',
  image: error "please provide image",
  replicas: error "please provide replicas",
  resources: {
    requests: { cpu: "100m", memory: "512Mi" },
    limits: { cpu: "100m", memory: "512Mi" }
  }
};

function(params) {
  local _config = defaults + params + {
    "agent-inject-template-data-prepper": |||
      {{- with secret "kv/data-prepper" -}}
      entry-pipeline:
        delay: "100"
        source:
          otel_trace_source:
            ssl: false
        sink:
          - pipeline:
              name: "raw-trace-pipeline"
          - pipeline:
              name: "service-map-pipeline"
      raw-trace-pipeline:
        source:
          pipeline:
            name: "entry-pipeline"
        processor:
          - otel_traces:
        sink:
          - opensearch:
              hosts: ["https://opensearch-cluster-headless.opensearch.svc.cluster.local:9200"]
              cert: "/usr/share/data-prepper/ca.pem"
              username: data-prepper
              password: {{ .Data.data.password }}
              index_type: trace-analytics-raw
      service-map-pipeline:
        delay: "100"
        source:
          pipeline:
            name: "entry-pipeline"
        processor:
          - service_map:
        sink:
          - opensearch:
              hosts: ["https://opensearch-cluster-headless.opensearch.svc.cluster.local:9200"]
              cert: "/usr/share/data-prepper/ca.pem"
              username: data-prepper
              password: {{ .Data.data.password }}
              index_type: trace-analytics-service-map
      nginx-logs-pipeline:
        source:
          http:
            ssl: false
            authentication:
              unauthenticated:
            port: 2021
        processor:
          - grok:
              match:
                log: 
                  - '^%{IPORHOST:remote_ip} - %{DATA:remote_user} \[%{HTTPDATE:access_time}\] \"%{WORD:http_method} %{DATA:http_path} HTTP/%{NUMBER:http_version}\" %{NUMBER:status} %{NUMBER:body_bytes_sent} \"%{URI:http_referer}\" \"%{DATA:user_agent}\" %{NUMBER:request_length} %{NUMBER:request_length} \[%{DATA:proxy_upstream_name}\] \[%{DATA:proxy_alternative_upstream_name}\] %{HOSTPORT:upstream_addr} %{NUMBER:upstream_response_length} %{NUMBER:upstream_resonse_time} %{NUMBER:upstream_status} %{DATA:req_id}$'
        sink:
          - opensearch:
              hosts: ["https://opensearch-cluster-headless.opensearch.svc.cluster.local:9200"]
              cert: "/usr/share/data-prepper/ca.pem"
              username: "data-prepper"
              password: {{ .Data.data.password }}
              index: ingress-nginx-logs
      {{- end -}}
    |||
  },

  configMap: {
    kind: "ConfigMap",
    apiVersion: "v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    },
    data: {
      // R4 Root
      "ca.pem": |||
        -----BEGIN CERTIFICATE-----
        MIIFEjCCAvqgAwIBAgIUX1xEkePTst7ibjH8AaYO5KNVvUcwDQYJKoZIhvcNAQEL
        BQAwEjEQMA4GA1UEAwwHUjQgUm9vdDAeFw0yMzA3MDQxMDI0NDlaFw0zMzA3MDEx
        MDI0NDlaMBIxEDAOBgNVBAMMB1I0IFJvb3QwggIiMA0GCSqGSIb3DQEBAQUAA4IC
        DwAwggIKAoICAQCqI1Wx5Aj+AlJU/+Fd5uy3ibqzK/Ssj/uxfYZcRgZa49PdFAdQ
        dkb6SGfwXVPg7PsRY9aMZ8pX0qRN30nXYmZe5psTrRTw4BvLPAWM4CgXHjIBf9cG
        vLQrLSdnXiXsoy7TXOqtRh3ZfoNGp399U1yP8vRfydjHSlnC+9O+UnzCEn6fk0NR
        0eT+zhBNwV0NhM9Wj/SI8UuErq/EL6RIZik4m4/sYAq8Qm1onvHGSCW9W2QS7ABu
        wv+dLHqTtv/WYwggSm2HEqqQNfGmAk3abQvHURslve4gkCRrtt+WiLqCEJ4FPHwO
        pdN/xM8v9Ntwj0/WKHMGpFkU59DrfI8ypILJQju4wV9cYRFwvDNmQRZvYrIvOZQY
        jdlB3YvDsioJApvKptI+OWIMeywRbeYn3+927X8UCdtd7yWxhohUJrt4uV1UCMPL
        ZVsKX1k30oSEYirJwSlcSOghel3EeCPRyUZa5Jlp7E/LXBJOpZ9EmmG+0bpoYeZO
        YJpuXq8ZNyr2/fvyAJ++kTwie/VzOi0CYFpVm98wULUTa/ViBx+lMgh4m5670tX6
        09QSxTZ0zdjWAlNaFsd3HkUy4VlGL7E2TZVYx/bfT4xtjgkxcL+bNHc1BnyxV41j
        PynmQ6Giim47F7gObCesqbV/p3HcfPRTHnVhQ2sfIiT+gtfe3RuuXLfQbQIDAQAB
        o2AwXjAdBgNVHQ4EFgQUT/lnHTcbNJYskulCn6yl/ZhMbjMwHwYDVR0jBBgwFoAU
        T/lnHTcbNJYskulCn6yl/ZhMbjMwDwYDVR0TAQH/BAUwAwEB/zALBgNVHQ8EBAMC
        AQYwDQYJKoZIhvcNAQELBQADggIBAAXIchOoq8TUwHFwdzhaYwVAAcE1nQ2JMP+b
        Arptm9JdvihTXA3p77yIcJnCpSgDJ7qfyh7jz/V7Yn0mPZbW2ocwfifYZvPY2zIQ
        Y/25VHChBnWtHKF7F3LH9rl+uXutm65OU8Ni8Nl/kqeNLqT3CYO0jIayIEPfjq0s
        Rf1dd9k+VpWaD9ByBTUFUxx5SNZ84jawOa9rARZp6LjPpVRx+Qx8jOl2CpgmeX7y
        NXz8sq/agyrk5ItzzvyL5CRF8EeL1xewxikISZuE3H+oprI19r4veHFD/bi61VFl
        MSNDZsxWltOQp6sn8ak2//K7bhAdT4G3drXwXfqQTLf+uu2Hwidh2SSBqt+gMkx2
        5bwky+VTct7IzUlIvMJ/PJtJs2Q9Qic7RSv6fI2j1pUibSUD84eN1H6J61GtWa7k
        yKyokOplKaxNKoYgqH1/C/JvoK3csnSdfOxoBnSaSup+YTNlZkgVpNqHn9rHRfyb
        rvJxlu5LGqrsM5BbVUEEGhvw0eDgiWCTqjVPXlfrXMLCMkoPRPsyT7kDicgQZOce
        RnnjgG6qnbmxnDjd9g0bUvISDmX5+mJFSfu9omkQyqt3f/7+fcMSrNU/mBA6tMto
        47ILN5dHLm2GavSmyeD7c3DKfbJkpN4zKUF0U7rn71As2IEE5Mno6rcL1RFhCHb4
        ENJkYJEq
        -----END CERTIFICATE-----
      |||
    }
  },

  deployment: {
    kind: "Deployment",
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
      replicas: _config.replicas,
      template: {
        metadata: {
          annotations: {
            "vault.hashicorp.com/agent-inject": "true",
            "vault.hashicorp.com/role": _config.name,
            "vault.hashicorp.com/agent-inject-template-data-prepper": _config["agent-inject-template-data-prepper"],
            "vault.hashicorp.com/agent-inject-secret-data-prepper": "kv/data-prepper",
            "vault.hashicorp.com/secret-volume-path-data-prepper": "/usr/share/data-prepper/pipelines",
            "vault.hashicorp.com/agent-inject-file-data-prepper": "pipelines.yaml"
          },
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
              ports: [
                {
                  containerPort: 21890,
                  name: "otlp"
                }
              ],
              resources: _config.resources,
              volumeMounts: [
                {
                  name: "configmap",
                  mountPath: "/usr/share/data-prepper/ca.pem",
                  subPath: "ca.pem",
                }
              ]
            }
          ],
          volumes: [
            {
              name: "configmap",
              configMap: { name: _config.name }
            }
          ],
          affinity: {
            nodeAffinity: {
              requiredDuringSchedulingIgnoredDuringExecution: {
                nodeSelectorTerms: [
                  {
                    matchExpressions: [
                      {key: "kubernetes.io/arch", operator: "In", values: ["amd64"]}  
                    ]
                  }
                ]
              }
            }
          }
        }
      }
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
          port: 21890,
          targetPort: "otlp"
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
