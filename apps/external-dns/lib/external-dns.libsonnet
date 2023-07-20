local defaults = {
  name: "please provide deployment name, \"blocky\" is suggested",
  namespace: error 'please provide namespace',
  image: error "please provide image",
  resources: {
    requests: { cpu: "100m", memory: "128Mi" },
    limits: { cpu: "100m", memory: "128Mi" }
  }
};

function(params) {
  local _config = defaults + params + {
    env: {
      TZ: "Europe/Stockholm",
      USER_GID: "1000",
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
        apiGroups: [""],
        resources: ["services"],
        verbs: ["get", "watch", "list"]
      },
      {
        apiGroups: [""],
        resources: ["pods"],
        verbs: ["get", "watch", "list"]
      },
      {
        apiGroups: ["networking", "networking.k8s.io"],
        resources: ["ingresses"],
        verbs: ["get", "watch", "list"]
      },
      {
        apiGroups: [""],
        resources: ["nodes"],
        verbs: ["get", "watch", "list"]
      },
      {
        apiGroups: [""],
        resources: ["endpoints"],
        verbs: ["get", "watch", "list"]
      }
    ]
  },

  deployment: {
    kind: "Deployment",
    apiVersion: "apps/v1",
    metadata: {
      name: _config.name,
      namespace: _config.namespace
    },
    spec: {
      strategy: {
        type: "Recreate"
      },
      selector: {
        matchLabels: {
          app: _config.name
        }
      },
      template: {
        metadata: {
          annotations: {
            "vault.hashicorp.com/agent-inject": 'true',
            "vault.hashicorp.com/role": 'external-dns',
            "vault.hashicorp.com/agent-inject-secret-cloudflare": 'cloudflare',
            "vault.hashicorp.com/agent-inject-template-cloudflare": |||
              {{- with secret "kv/cloudflare" -}}
              CF_API_TOKEN={{ .Data.data.token }}
              {{- end -}}
            |||
          },
          labels: {
            app: _config.name
          }
        },
        spec: {
          hostUsers: false,
          serviceAccountName: _config.name,
          containers: [
            {
              name: _config.name,
              image: _config.image,
              command: [
                "/bin/sh",
                "-c"
              ],
              args: [
                "export $(cat /vault/secrets/cloudflare) && external-dns --source=ingress --zone-id-filter=7a7235589c34b71a7a1774c934f7b817 --provider=cloudflare --registry=txt --txt-owner-id=public_cluster --txt-prefix=external-dns_ --interval=30m0s --events"
              ],
              resources: _config.resources
            }
          ]
        }
      }
    }
  }
}
