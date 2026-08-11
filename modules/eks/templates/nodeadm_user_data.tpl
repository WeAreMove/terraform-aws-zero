MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="//"

%{ if pre_bootstrap_user_data != "" ~}
--//
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
${pre_bootstrap_user_data}
%{ endif ~}
--//
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${cluster_name}
    apiServerEndpoint: ${cluster_endpoint}
    certificateAuthority: ${cluster_auth_base64}
    cidr: ${trimspace(post_bootstrap_user_data) != "" ? trimspace(post_bootstrap_user_data) : trimspace(cluster_service_ipv4_cidr)}
%{ if trimspace(bootstrap_extra_args) != "" ~}
  kubelet:
    flags:
%{ for flag in compact(split(" ", trimspace(bootstrap_extra_args))) ~}
      - "${flag}"
%{ endfor ~}
%{ endif ~}
--//--
