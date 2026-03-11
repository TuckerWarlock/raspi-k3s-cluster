# GitHub Action workflows

Use these as reference:
- https://spacelift.io/blog/github-actions-kubernetes
- https://citizix.com/how-to-deploy-with-argocd-using-github-actions-and-helm-templating/

## Workflow steps

1. Checkout repo
2. Install depedencies
3. Render templates via helm

## Workflow triggers
- On Pull-request
- Filter path changes to the manifests/ and charts/ directories
