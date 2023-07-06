local root = {
  endpoints:: {
    "letsencrypt-prod": "https://acme-v02.api.letsencrypt.org/directory",
    "letsencrypt-stag": "https://acme-staging-v02.api.letsencrypt.org/directory"
  },

  clusterIssuer(name):: {
    apiVersion: "cert-manager.io/v1",
    kind: "ClusterIssuer",
    metadata: {
      name: name
    },
    spec: {
      acme: {
        server: root.endpoints[name],
        email: "albert@arleskog.se",
        privateKeySecretRef: {
          name: name
        },
        solvers: [
          { http01: { ingress: { ingressClassName:  "nginx" } } }
        ]
      }
    }
  }
};

{ ["clusterissuer_%s.json" % name]: root.clusterIssuer(name) for name in std.objectFields(root.endpoints) }
