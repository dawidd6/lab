# lab

## Layout

```
kube/
├── k0sctl.yaml              k0s cluster definition (cluster-bootstrap)
└── apps/                    one directory per app
    ├── apps.yaml            the root app (syncs this file, argocd-bootstrap creates it) and the ApplicationSet:
    │                        every apps/<app>/app.yaml → Application
    └── <app>/
        ├── app.yaml         its namespace and upstream chart: repo, chart, pinned version, values
        └── *.yaml           the app's own plain manifests: its HTTPRoute, CRs like IPAddressPool
```

Apps: `argocd`, `openebs`, `metallb`, `envoy-gateway`, `cert-manager`, `cert-manager-webhook-duckdns`, `jellyfin`, `jdownloader2`
(both in namespace `media`, sharing jellyfin's `media` PVC), `homarr`.

The ApplicationSet in `apps/apps.yaml` turns every `apps/<name>` into an Application whose sources are the chart in
its `app.yaml` (a Helm release named after the directory) and its other `*.yaml`, deployed to the `app.yaml`'s
`namespace` and synced automatically. There's
no ordering: all apps sync at once and each retries until what it needs (another app's CRDs, its volumes, its
certificate) exists, so a fresh cluster is Degraded/Progressing for a few minutes before it settles.

cert-manager checks for the Gateway API CRDs (from envoy-gateway) only at startup. If it started first, the gateway
never gets its certificate: `kubectl -n cert-manager rollout restart deployment cert-manager`.

Adding an app: create `kube/apps/<name>/app.yaml` (copy one; `repo` is an OCI registry without `oci://`, or an
`https://` Helm repository). To make it reachable at `https://<name>.dawidd6.duckdns.org`, add a `route.yaml` (copy one).

## Bootstrap

```
mise run os-provisioning
mise run cluster-bootstrap
mise run sops-apply
mise run argocd-bootstrap
```

`argocd-bootstrap` installs Argo CD once, from the chart in `kube/apps/argocd/app.yaml` (without its route, whose CRD comes with envoy-gateway), and creates `kube/apps/apps.yaml`; from then on
the `root` app keeps the ApplicationSet (and itself) in sync with git, the ApplicationSet every app, and the
`argocd` app Argo CD.

The kubeconfig lives in `kube/.config` (gitignored); mise sets `KUBECONFIG` to it.
Argo CD's UI is at `https://argocd.dawidd6.duckdns.org`, user `admin`, password from `mise run argocd-password`.

## Secrets

All secrets are in `kube/secrets.sops.yaml`, a multi-document file encrypted with [SOPS](https://getsops.io) for the
age key in `~/.config/sops/age/keys.txt` (`.sops.yaml`); only the values are encrypted. Argo CD doesn't touch it:

- edit: `sops kube/secrets.sops.yaml`
- apply: `mise run sops-apply` (decrypts it into `kubectl apply --server-side`, so the plaintext doesn't end up in a
  `last-applied-configuration` annotation)

It holds:
- `cert-manager/duckdns`: the DuckDNS token, for the wildcard certificate's DNS-01 challenges
- `homarr/db-encryption`: Homarr's database encryption key (64 hex chars, e.g. `openssl rand -hex 32`)

Losing the age key means losing access to the file: keep a backup of it.
