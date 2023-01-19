# external-dns

* Automatically creates records with `<ingress name>.arleskog.se` and an A record to ingress external ip.
* Cloudflare proxy not enabled by default.

## Override with annotations per ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test
  annotations:
    external-dns.alpha.kubernetes.io/hostname: test.arleskog.se
    # Default is "auto".
    external-dns.alpha.kubernetes.io/ttl: "120"
    # Default is false.
    external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
spec:
  ...
```
