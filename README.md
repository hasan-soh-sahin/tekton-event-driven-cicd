# Event-driven CI/CD with GitLab, Tekton, Harbor and Airflow

Companion example for a Medium article showing **one EventListener, two repository-specific Triggers, CEL filtering, parameter propagation, and a shared Pipeline**.

## Architecture

```text
GitLab webhook (Push Hook)
  -> Kubernetes Service / optional Ingress
  -> EventListener (label selector)
      -> customer-scoring Trigger (GitLab + CEL interceptors)
      -> fraud-detection Trigger (GitLab + CEL interceptors)
  -> shared TriggerBinding -> TriggerTemplate -> PipelineRun
  -> parameter inspection || calculate-image-tag
  -> simulated Harbor publish and Airflow Variable update
```

**Safety and scope:** The default pipeline is a *fully executable trigger/parameter demonstration*, not a real container build. It deliberately **does not clone a repository, push an image, or call Airflow**. It prints what the real integration would do. `gitlab.example.com` and `harbor.example.com` are illustrative domains; the sample Git repositories are not publicly hosted. This makes testing possible even without GitLab, Harbor or Airflow.

## Requirements

- Kubernetes cluster with `kubectl` access (Tekton Pipelines currently documents Kubernetes 1.28+).
- Tekton Pipelines and Tekton Triggers installed (including core interceptors).
- Permission to create a Namespace and RBAC/ClusterRoleBinding resources.
- Access to pull `alpine:3.20` images.
- A shell with `bash`, `sed` and `curl`.

Install Tekton following official documentation:

- https://tekton.dev/docs/pipelines/install/
- https://tekton.dev/docs/installation/triggers/

Quick-start installation for learning environments (check release compatibility first):

```bash
kubectl apply -f https://infra.tekton.dev/tekton-releases/pipeline/latest/release.yaml
kubectl apply -f https://infra.tekton.dev/tekton-releases/triggers/latest/release.yaml
kubectl apply -f https://infra.tekton.dev/tekton-releases/triggers/latest/interceptors.yaml
kubectl -n tekton-pipelines get pods
```

For production use, pin tested versions and consider the Tekton Operator.

## Quick start

From the root of this repository:

```bash
export WEBHOOK_TOKEN="$(openssl rand -hex 24)"
./scripts/setup.sh
kubectl -n data-platform-ci get eventlistener image-build-listener
kubectl -n data-platform-ci get svc el-image-build-listener
```

In a **separate terminal**, start local forwarding:

```bash
kubectl -n data-platform-ci port-forward svc/el-image-build-listener 8080:8080
```

In the first terminal (keep the *same* `WEBHOOK_TOKEN`):

```bash
./scripts/send-test-webhook.sh customer-scoring main
./scripts/send-test-webhook.sh fraud-detection main
```

Expected: one PipelineRun for each accepted event. The two triggers are both discovered by the EventListener, but the repository-specific CEL filter matches only one.

```bash
kubectl -n data-platform-ci get pipelineruns \
  -l ci.example.com/app=customer-scoring
kubectl -n data-platform-ci get pipelineruns \
  -l ci.example.com/app=fraud-detection
```

Inspect the parameter flow:

```bash
kubectl -n data-platform-ci get pipelineruns
kubectl -n data-platform-ci get pipelinerun <RUN_NAME> -o yaml
kubectl -n data-platform-ci get taskruns
kubectl -n data-platform-ci logs deploy/el-image-build-listener --tail=100
```

Find the TaskRun pods using `kubectl -n data-platform-ci get pods` and inspect their logs with `kubectl logs <POD_NAME> --all-containers=true`; alternatively use `tkn pipelinerun logs <RUN_NAME> -n data-platform-ci --all-tasks` if the Tekton CLI is installed.

### Negative tests

```bash
./scripts/send-test-webhook.sh customer-scoring dev
./scripts/send-test-webhook.sh other-repo main
```

Neither request should create a PipelineRun because the CEL filters reject them. **HTTP response codes alone do not prove a PipelineRun was created or rejected.** Inspect PipelineRuns and EventListener logs.

To test token rejection:

```bash
WEBHOOK_TOKEN=wrong-token ./scripts/send-test-webhook.sh customer-scoring main
```

## What gets passed to the next stage?

| Stage | Input | Output |
| --- | --- | --- |
| GitLab webhook | JSON + `X-Gitlab-Token` | HTTP event |
| EventListener | label `ci.example.com/listener=image-build` | both matching Trigger definitions evaluated |
| GitLab interceptor | token, `Push Hook` | accepted/rejected event |
| CEL interceptor | project path, `refs/heads/main`, nonzero `after` | accepted/rejected for each Trigger |
| TriggerBinding | `body.project.git_http_url`, `body.checkout_sha` | `git-url`, `git-revision` |
| Trigger inline bindings | repository-specific constants | `app-name`, `image-name`, `airflow-variable` |
| TriggerTemplate | combined parameters | PipelineRun manifest |
| PipelineRun | params | parallel `inspect` and `calculate-image-tag` |
| calculate-image-tag | `image-name` | `image` = `harbor.example.com/data-platform/<repo>:0.0.11` (demo only) |
| simulate-publish | `image`, `airflow-variable` | log explaining what Harbor/Airflow integration would do |

## Switching to a real GitLab / Harbor / Airflow environment

This example intentionally stops at the simulator. A real integration must additionally provide:

1. Actual GitLab repository URLs and Push Hook registrations, with HTTPS access from the listener.
2. A Git clone Task with credentials and a shared workspace (PVC) for source files.
3. A registry tag calculation Task using authenticated Harbor API access, with concurrency safeguards.
4. A Buildah Task and compatible Kubernetes pod-security permissions, plus registry pull/push credentials.
5. An Airflow API Task and credential Secret, with tested API endpoints for the deployed Airflow version.
6. TLS trust chains for all internal services, GitOps to manage Trigger definitions, and retries/idempotency.

Do not enable untrusted webhook payloads to execute arbitrary scripts, and do not disable TLS verification in production.

## Repo files

- `k8s/00-namespace-rbac.yaml`: namespace and listener RBAC.
- `k8s/10-listener-binding-template.yaml`: shared EventListener, TriggerBinding and TriggerTemplate.
- `k8s/20-trigger-*.yaml`: two repository-specific Trigger resources.
- `k8s/30-demo-pipeline.yaml`: executable demonstration pipeline and tasks.
- `k8s/40-ingress-optional.yaml`: optional Ingress route (needs DNS, TLS and controller).
- `examples/push-template.json`: mock GitLab push event.
- `scripts/setup.sh`: install namespace-scoped example resources.
- `scripts/send-test-webhook.sh`: test accepted and rejected events.

## Cleanup

```bash
kubectl delete namespace data-platform-ci
kubectl delete clusterrolebinding data-platform-ci-eventlistener-clusterroles
```

## References

- https://tekton.dev/docs/triggers/
- https://tekton.dev/docs/pipelines/
- https://docs.gitlab.com/user/project/integrations/webhook_events/
- https://kubernetes.io/docs/concepts/services-networking/ingress/
