# oauth2-proxy: login for UIs without their own auth

Protects the **Longhorn UI** (`longhorn.halo.fabseit.net`, `longhorn.fabseit.net`). The UI has no login
of its own and can delete volumes and backups.

```
browser ─► ingress-nginx ─auth_request─► oauth2-proxy /oauth2/auth  (checks the session cookie)
              │  202 → proxy to longhorn-frontend
              └  401 → redirect to https://<host>/oauth2/sign_in    (username/password form)
```

**Why not plain basic auth.** iOS Safari, and with it every iOS browser (all WebKit), never sends basic-auth
credentials on WebSocket upgrades. The Longhorn UI keeps one live socket per resource
(`/v1/ws/1s/volumes`, `/nodes`, `/events`, …). Each got a 401, and each 401 raised another login popup, on
every page. A session cookie is sent on WebSocket upgrades, so the cookie login works there.

## How it's set up

- **Login:** htpasswd from Vaultwarden item `longhorn-system/longhorn-ui-auth`, hidden field `auth`
  (`htpasswd -nB <user>`; bcrypt or SHA1 only). Same item as the old basic auth. To change the password,
  edit the item. ESO refreshes every 15 min and Reloader restarts the pod.
- **Session:** an encrypted cookie, host-only, valid 7 days. No server-side state and no PVC. The cookie key
  is generated once by an ESO `Password` generator and isn't in Vaultwarden. If it's lost, a new one is
  generated (delete the Secret to force it) and everyone just logs in again.
- **Provider:** only the htpasswd form is used. oauth2-proxy still needs an OAuth provider, so `google` is
  set with dummy credentials, and the custom `sign_in.html` (`configmap-templates.yaml`) leaves out its
  button.
- **/oauth2/\* on the app hosts** is served by `manifests/ingress.yml` here. An Ingress can only reference
  Services in its own namespace, so it needs its own certificate for those hosts (`certificate.yaml`).
- Its own namespace, not `longhorn-system`: the Longhorn API NetworkPolicy trusts every pod in
  `longhorn-system`.
- If the pod is down, the protected hosts answer 500. That's the safe way to fail.

## Protect another app

1. Add its host(s) to `manifests/ingress.yml` and `manifests/certificate.yaml`.
2. Add these annotations to the app's Ingress:
   ```yaml
   nginx.ingress.kubernetes.io/auth-url: http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth
   nginx.ingress.kubernetes.io/auth-signin: https://$host/oauth2/sign_in?rd=$escaped_request_uri
   ```

## Logout

`https://<host>/oauth2/sign_out`.
