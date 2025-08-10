import os
from pathlib import Path
import questionary
import argparse

APPS_DIR = Path(__file__).parent.parent / "apps"
MANIFESTS_SUBDIR = "manifests"

DEFAULT_MANIFESTS = {
    "deployment_with_pvc.yaml": "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: {app_name}\n  namespace: {namespace}\n  labels:\n    app: {app_name}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: {app_name}\n  template:\n    metadata:\n      labels:\n        app: {app_name}\n    spec:\n      containers:\n        - name: {app_name}\n          image: <your-image>\n          ports:\n            - containerPort: {app_port}\n          volumeMounts:\n            - mountPath: /data\n              name: data-volume\n      volumes:\n        - name: data-volume\n          persistentVolumeClaim:\n            claimName: {app_name}-pvc\n",
    "deployment_no_pvc.yaml": "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: {app_name}\n  namespace: {namespace}\n  labels:\n    app: {app_name}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: {app_name}\n  template:\n    metadata:\n      labels:\n        app: {app_name}\n    spec:\n      containers:\n        - name: {app_name}\n          image: <your-image>\n          ports:\n            - containerPort: {app_port}\n",
    "pvc.yaml": "apiVersion: v1\nkind: PersistentVolumeClaim\nmetadata:\n  name: {app_name}-pvc\n  namespace: {namespace}\nspec:\n  accessModes:\n{access_modes}  resources:\n    requests:\n      storage: {storage_size}Gi\n  storageClassName: longhorn\n",
    "ingress.yaml": "apiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: {app_name}\n  namespace: {namespace}\nspec:\n  ingressClassName: nginx\n  rules:\n    - host: {app_name}.{namespace}.fabseit.net\n      http:\n        paths:\n          - path: /\n            pathType: Prefix\n            backend:\n              service:\n                name: {app_name}\n                port:\n                  number: {app_port}\n    - host: {app_name}.fabseit.net\n      http:\n        paths:\n          - path: /\n            pathType: Prefix\n            backend:\n              service:\n                name: {app_name}\n                port:\n                  number: {app_port}\n  tls:\n    - hosts:\n        - {app_name}.{namespace}.fabseit.net\n        - {app_name}.fabseit.net\n      secretName: local-fabseit-net-prod-tls\n",
    "service.yaml": "apiVersion: v1\nkind: Service\nmetadata:\n  name: {app_name}\n  namespace: {namespace}\nspec:\n  selector:\n    app: {app_name}\n  ports:\n    - protocol: TCP\n      port: {app_port}\n"
}

OPTIONAL_MANIFESTS = ["pvc.yaml", "ingress.yaml"]
LONGHORN_ACCESS_MODES = ["ReadWriteOnce", "ReadWriteMany", "ReadOnlyMany"]

def print_file_structure(app_name, optional):
    print("Created file structure:")
    print(f"{app_name}/")
    print(f"  manifests/")
    for manifest in ["deployment.yaml", "service.yaml"] + optional:
        print(f"    {manifest}")

def scaffold_app(app_name, namespace, app_port, optional, pvc_access_modes=None, pvc_storage_size=None):
    app_dir = APPS_DIR / app_name / MANIFESTS_SUBDIR
    os.makedirs(app_dir, exist_ok=True)
    # Use correct deployment template
    if "pvc.yaml" in optional:
        deployment_template = DEFAULT_MANIFESTS["deployment_with_pvc.yaml"]
    else:
        deployment_template = DEFAULT_MANIFESTS["deployment_no_pvc.yaml"]
    with open(app_dir / "deployment.yaml", "w") as f:
        f.write(deployment_template.format(app_name=app_name, namespace=namespace, app_port=app_port))
    # Always create service.yaml
    with open(app_dir / "service.yaml", "w") as f:
        f.write(DEFAULT_MANIFESTS["service.yaml"].format(app_name=app_name, namespace=namespace, app_port=app_port))
    for manifest in optional:
        if manifest == "pvc.yaml":
            access_modes_yaml = "".join([f"    - {mode}\n" for mode in pvc_access_modes])
            with open(app_dir / manifest, "w") as f:
                f.write(DEFAULT_MANIFESTS[manifest].format(
                    app_name=app_name,
                    namespace=namespace,
                    access_modes=access_modes_yaml,
                    storage_size=pvc_storage_size,
                    app_port=app_port
                ))
        else:
            with open(app_dir / manifest, "w") as f:
                f.write(DEFAULT_MANIFESTS[manifest].format(app_name=app_name, namespace=namespace, app_port=app_port))
    print(f"App '{app_name}' created in {app_dir}\n")
    print_file_structure(app_name, optional)

def main():
    parser = argparse.ArgumentParser(description="K8s App Scaffolder CLI")
    parser.add_argument("--name", type=str, help="Name for the new application")
    parser.add_argument("--namespace", type=str, help="Namespace for the application")
    parser.add_argument("--port", type=int, help="Default port for the application")
    parser.add_argument("--manifests", nargs="*", choices=OPTIONAL_MANIFESTS, help="Optional manifest files to include")
    parser.add_argument("--pvc-access-modes", nargs="*", choices=LONGHORN_ACCESS_MODES, help="AccessModes for PVC (if pvc.yaml selected)")
    parser.add_argument("--pvc-size", type=int, help="Storage size in GBs for PVC (if pvc.yaml selected)")
    args = parser.parse_args()

    if args.name and args.namespace and args.port:
        # Non-interactive mode
        optional = args.manifests if args.manifests else []
        pvc_access_modes = args.pvc_access_modes if "pvc.yaml" in optional else None
        pvc_storage_size = str(args.pvc_size) if ("pvc.yaml" in optional and args.pvc_size) else None
        scaffold_app(
            app_name=args.name,
            namespace=args.namespace,
            app_port=str(args.port),
            optional=optional,
            pvc_access_modes=pvc_access_modes,
            pvc_storage_size=pvc_storage_size
        )
    else:
        # Interactive mode
        print("K8s App Scaffolder CLI (interactive mode)")
        app_name = questionary.text("Enter the name for the new application:").ask()
        namespace = questionary.text("Enter the namespace:").ask()
        app_port = questionary.text(
            "Enter the default port for the application (e.g. 80):",
            validate=lambda val: val.isdigit() and int(val) > 0
        ).ask()
        optional = questionary.checkbox(
            "Select optional manifest files to include:",
            choices=OPTIONAL_MANIFESTS
        ).ask()
        pvc_access_modes = None
        pvc_storage_size = None
        if "pvc.yaml" in optional:
            pvc_access_modes = questionary.checkbox(
                "Select accessModes for PVC:",
                choices=LONGHORN_ACCESS_MODES
            ).ask()
            pvc_storage_size = questionary.text(
                "Enter storage size in GBs (e.g. 2):",
                validate=lambda val: val.isdigit() and int(val) > 0
            ).ask()
        scaffold_app(
            app_name=app_name,
            namespace=namespace,
            app_port=app_port,
            optional=optional,
            pvc_access_modes=pvc_access_modes,
            pvc_storage_size=pvc_storage_size
        )

if __name__ == "__main__":
    main()
