# 0xc0-labs

A single-operator lab on a Hetzner dedicated server, built and run as code.
Nothing reaches `main` without a pull request, and nothing is applied without
a human approving it.

## What it is

One Proxmox VE node on a Hetzner dedicated server. The host is the router and
the firewall for three zones: management, CI, and platform, which holds an
RKE2 Kubernetes cluster and its load balancer. Alongside Proxmox it runs only
the base services: a reverse proxy, the object store holding the OpenTofu
state, and the backup server, which ships to off-site storage.

- **Public traffic** enters through a Cloudflare Tunnel into the load
  balancers, and HAProxy passes it to Traefik in the cluster, where CrowdSec
  checks every request.
- **Admin access** goes through Cloudflare Access and WARP into the management
  zone, never through the public tunnel. The internal portals (Vault,
  OpenObserve, ArgoCD, Headlamp) are reached only this way.
- **Between zones**, everything not explicitly allowed is denied. The allowed
  flows live in one matrix, and the firewall is generated from it.

The full picture, with diagrams, is in the
[architecture document](https://github.com/0xc0-labs/infrastructure/blob/main/docs/architecture.md).

## How it is built

Templates come from official cloud images, and Packer bakes the few that need
more. OpenTofu creates the VMs, the network and the firewall, and Ansible
configures them and brings the cluster up. ArgoCD deploys everything that runs
in the cluster from the `gitops` repo: Longhorn, Traefik, CrowdSec,
cert-manager, external-dns, Vault, OpenObserve and the applications.

Secrets live in Vault, in the cluster: the cluster's components read theirs
through Vault Secrets Operator, and CI logs in with GitHub's OIDC token, so no
repo holds a secret. CI runs on GitHub Actions, with plans and applies on
ephemeral self-hosted runners inside the network; every apply waits for the
operator's approval. Logs, metrics and traces go to OpenObserve.

## Repositories

| Repo | What it holds |
|------|---------------|
| [`.github`](https://github.com/0xc0-labs/.github) | Organization Terraform, reusable workflows, this page |
| [`workspace`](https://github.com/0xc0-labs/workspace) | Cross-repo rules, the design, the bootstrap |
| [`infrastructure`](https://github.com/0xc0-labs/infrastructure) | Packer, OpenTofu and Ansible — and the [zone design](https://github.com/0xc0-labs/infrastructure/blob/main/docs/zones.md) |
| [`gitops`](https://github.com/0xc0-labs/gitops) | ArgoCD manifests for the cluster |
| [`vault`](https://github.com/0xc0-labs/vault) | OpenTofu configuration of the cluster's Vault |
| [`offby1.cc`](https://github.com/0xc0-labs/offby1.cc) | The offby1.cc landing page |
| [`claude-config`](https://github.com/0xc0-labs/claude-config) | Claude Code plugin: agents, skills and guardrail hooks |

## Principles

- **Everything as code.** OpenTofu is always written as modules; tools are
  pinned per repo with mise. The host's base services are the one exception.
- **One source of truth per concern.** The design is closed in
  [`docs/design.md`](https://github.com/0xc0-labs/workspace/blob/main/docs/design.md);
  the network in the infrastructure code, `terraform.tfvars`; the state of work on the
  [project board](https://github.com/orgs/0xc0-labs/projects/1).
- **A human applies.** Automation plans; the operator approves.
