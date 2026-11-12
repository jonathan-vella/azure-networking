# Calico tooling

The pinned source snapshot included a 48 MB `calicoctl` binary whose exact
release and compatibility could not be established. It is excluded from this
consolidation and was not executed.

For AKS-managed standard Kubernetes network policies, use `kubectl`. If a
self-managed Calico cluster requires `calicoctl`, first identify the installed
Calico version, then use its matching official release and verify the checksum
from a trusted source. No default version is assumed.
