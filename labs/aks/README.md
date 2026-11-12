# AKS & Container Networking Labs

Hands-on Azure CLI runbooks and Kubernetes manifests for building, inspecting, and validating modern **Azure Kubernetes Service (AKS)** network architectures—covering CNI dataplanes, **Application Gateway for Containers** (Kubernetes Gateway API), outbound egress control, and Linux container networking fundamentals.

> **Field Architect Handbook:** Pair these labs with **[Workload Networking — AKS](../../src/content/docs/05-workload-networking/)** for IP sizing formulas, CNI trade-off matrices, Cilium eBPF architecture, and ingress/egress design patterns.

---

## Lab Directory Structure

| Path | Focus Area | Key Technologies & SKUs |
| --- | --- | --- |
| [`CNI/build-azure-cni-powered-by-cilium.sh`](CNI/build-azure-cni-powered-by-cilium.sh) | Recommended AKS CNI & eBPF dataplane | Azure CNI Overlay (`192.168.0.0/16`), `--network-dataplane cilium`, `Standard_D2s_v5` |
| [`CNI/build-azure-cni-overlay.sh`](CNI/build-azure-cni-overlay.sh) | Brownfield BYO-VNet CNI Overlay | `--network-plugin-mode overlay`, User-Assigned Managed Identity, VNet RBAC |
| [`CNI/build-azure-cni.sh`](CNI/build-azure-cni.sh) | Traditional flat VNet Azure CNI | Direct VNet subnet pod IPs (`--network-plugin azure`), `Standard_D2s_v5` |
| [`Ingress/build-aks-agc-gateway-api.sh`](Ingress/build-aks-agc-gateway-api.sh) | Modern L7 Ingress (Gateway API) | **Application Gateway for Containers**, Managed ALB Controller (Helm `1.13.0`), OIDC + Workload Identity, `Microsoft.ServiceNetworking/trafficControllers` subnet delegation |
| [`Egress/build-aks-egress.azcli`](Egress/build-aks-egress.azcli) | Outbound Egress & Asymmetric Routing Prevention | `--outbound-type userDefinedRouting` (Azure Firewall + DNS Proxy + DNAT) vs. `userAssignedNATGateway` |
| [`docker-networking/`](docker-networking/) | Linux Container Networking Fundamentals | Two `Standard_B2ls_v2` Ubuntu 24.04 hosts demonstrating `bridge`, port publishing, dual-homed containers, and `ipvlan` L3 mode |
| [`manifests/`](manifests/) | Deduplicated Kubernetes YAML Manifests | [`network-tools-pod.yaml`](manifests/network-tools-pod.yaml) (`netshoot`), [`demo-workload.yaml`](manifests/demo-workload.yaml), [`gateway-api-routes.yaml`](manifests/gateway-api-routes.yaml) |

---

## Lab Walkthroughs

### 1. CNI & eBPF Dataplane (`CNI/`)

- **Azure CNI Powered by Cilium (`build-azure-cni-powered-by-cilium.sh`)** — Deploys an AKS cluster combining Overlay pod IP allocation with Cilium's eBPF dataplane (kube-proxy replacement and native L3–L7 network policy enforcement).
- **Azure CNI Overlay (`build-azure-cni-overlay.sh`)** — Attaches an AKS cluster to an existing brownfield VNet subnet using a User-Assigned Managed Identity pre-granted `Network Contributor` so internal Load Balancers reconcile without RBAC propagation delays.
- **Traditional Azure CNI (`build-azure-cni.sh`)** — Demonstrates flat VNet pod IP allocation when pods must be directly routable by VNet-native peers without NAT or overlay encapsulation.

### 2. Application Gateway for Containers & Gateway API (`Ingress/`)

[`Ingress/build-aks-agc-gateway-api.sh`](Ingress/build-aks-agc-gateway-api.sh) provisions an end-to-end L7 Gateway API topology:

1. Creates a VNet with a `/24` AKS node subnet and a `/24` subnet delegated to `Microsoft.ServiceNetworking/trafficControllers`.
2. Deploys an AKS cluster with **Azure CNI Overlay + Cilium**, `--enable-oidc-issuer`, and `--enable-workload-identity`.
3. Configures a federated User-Assigned Managed Identity (`azure-alb-identity`) with least-privilege roles (`AppGw for Containers Configuration Manager` + `Reader` on the `MC_*` node resource group, and `Network Contributor` on the delegated AGC subnet).
4. Installs the **ALB Controller** from `oci://mcr.microsoft.com/application-lb/charts/alb-controller` and creates an `ApplicationLoadBalancer` custom resource.
5. Applies [`manifests/gateway-api-routes.yaml`](manifests/gateway-api-routes.yaml) (`GatewayClass: azure-alb-external`, `Gateway`, and `HTTPRoute`) demonstrating path-based (`/orders`) and header-based canary (`X-Canary: true`) routing directly to pod overlay IPs.

### 3. Outbound Egress Control (`Egress/`)

[`Egress/build-aks-egress.azcli`](Egress/build-aks-egress.azcli) supports `OUTBOUND_MODE=udr` (default) or `OUTBOUND_MODE=natgw`:

- **`udr` (`userDefinedRouting`)**: Routes `0.0.0.0/0` from the AKS node subnet to **Azure Firewall** with DNS Proxy enabled, configures required AKS control-plane and registry rules, and demonstrates why inbound traffic must enter through Firewall DNAT (targeting an internal LoadBalancer) rather than a public LoadBalancer to avoid asymmetric return routing.
- **`natgw` (`userAssignedNATGateway`)**: Associates a dedicated Azure NAT Gateway for up to 64,512 SNAT ports per public IP without centralized firewall inspection.

### 4. Linux & Container Networking Fundamentals (`docker-networking/`)

- [`docker-networking/build-docker-hosts.sh`](docker-networking/build-docker-hosts.sh) deploys two `Standard_B2ls_v2` Linux VMs locked down to your client IP via NSGs.
- [`docker-networking/docker-networking-basics.sh`](docker-networking/docker-networking-basics.sh) walks through Linux `veth` pairs, custom `bridge` networks, dual-homed containers, and `ipvlan` (`ipvlan_mode=l3`) routing behavior inside an Azure VNet.

---

## Retired Legacy Labs & Architectural Rationale

During repository modernization, three legacy lab tracks were retired to `.archive/` in alignment with upstream Kubernetes and Azure platform lifecycles:

1. **Kubenet (`build-kubenet.sh`, `build-kubenet-dual-stack.sh`)** — Azure is retiring Kubenet on AKS (March 2028). Kubenet relied on Azure Route Tables (UDRs) per node, capping cluster scale against the 400-route table limit and complicating hub-firewall UDR attachment. **Azure CNI Overlay** supersedes Kubenet without consuming VNet pod IPs or UDR slots.
2. **Community Ingress-NGINX & AGIC (`build-azure-cni-overlay-with-nginx.sh`, `build-azure-cni-with-app-gw.sh`)** — The Kubernetes SIG-Network community retired `ingress-nginx` in favor of the **Gateway API**, and **Application Gateway for Containers (AGC)** supersedes Application Gateway Ingress Controller (AGIC) with near-real-time control-plane updates, native Gateway API support (`azure-alb-external`), and higher connection scale.
3. **Docker Swarm & Unverified `calicoctl` Binary (`build-docker-swarm-cluster.sh`, `calicoctl`)** — Docker Swarm cluster scripts and checked-in third-party binaries were removed in favor of managed AKS clusters using **Azure CNI Powered by Cilium** for eBPF service load-balancing and network policy enforcement.
