locals {
  # Map this module config to the upstream module config
  eks_node_group_config = { for n, config in var.eks_node_groups :
    n => merge(
      (var.node_group_name_as_prefix ?
        { name_prefix = "${var.cluster_name}-${n}" } :
        { name = "${var.cluster_name}-${n}" }
      ),
      {
        desired_size = lookup(config, "asg_min_size", 1)
        max_size     = lookup(config, "asg_max_size", 3)
        min_size     = lookup(config, "asg_min_size", 1)

        create_launch_template     = true # lookup(config, "use_large_ip_range", true)
        use_custom_launch_template = true

        ami_id         = lookup(config, "ami_id", "")  # Specify ARM AMI ID
        ami_type       = lookup(config, "ami_type", "AL2_x86_64")
        instance_types = lookup(config, "instance_types", [])
        capacity_type  = lookup(config, "use_spot_instances", false) ? "SPOT" : "ON_DEMAND"
        enable_bootstrap_user_data = lookup(config, "enable_bootstrap_user_data", false)
        bootstrap_extra_args = lookup(config, "bootstrap_extra_args", "--kubelet-extra-args '--max-pods=111 --eviction-hard=nodefs.available<5%' ")
        disk_size      = lookup(config, "disk_size", 48)
        block_device_mappings = {
          xvda = {
            # Root device name differs by AMI family: AL2/AL2023 use /dev/xvda, Ubuntu uses /dev/sda1.
            # Must match the AMI's actual root device or disk_size/encryption won't apply to root and an
            # unused extra volume gets attached. Defaults to /dev/xvda so existing AL2 groups are unchanged.
            device_name = lookup(config, "root_device_name", "/dev/xvda")
            ebs = {
              delete_on_termination = true
              encrypted             = true
              volume_size           = lookup(config, "disk_size", 48)
              volume_type           = "gp3"
            }
          }
        }
        # this is not good; need revisit
        # kubelet_extra_args = lookup(config, "use_large_ip_range", true) ? "--max-pods=${lookup(config, "node_ip_limit", 110)}" : ""
        # bootstrap_extra_args = "--kubelet-extra-args '--eviction-hard=nodefs.available<5%'"

        labels = merge(
          { Environment = var.environment },
          lookup(config, "additional_labels", {})
        )
        tags = merge(
          { environment = var.environment },
          lookup(config, "additional_tags", {})
        )
        taints = lookup(config, "taints", {})
    })
  }
  eks_sm_node_group_config = { for n, config in var.eks_sm_node_groups :
    n => merge(
      (var.node_group_name_as_prefix ?
        { name_prefix = "${var.cluster_name}-${n}" } :
        { name = "${var.cluster_name}-${n}" }
      ),
      {
        desired_size = lookup(config, "asg_min_size", 1)
        max_size     = lookup(config, "asg_max_size", 3)
        min_size     = lookup(config, "asg_min_size", 1)

        create_launch_template     = true
        use_custom_launch_template = true
        launch_template_name       = lookup(config,"launch_template_name","${n}-self-managed")
        launch_template_use_name_prefix = lookup(config,"launch_template_use_name_prefix",true)
        enable_efa_support         = true

        ami_type       = lookup(config, "ami_type", "AL2_x86_64")
        ami_id         = lookup(config, "ami_id", "")  # Specify ARM AMI ID
        # The upstream self-managed submodule unconditionally reads data.aws_ami.eks_default,
        # querying "amazon-eks-node-<cluster_version>-v*" (AL2). AWS stopped publishing AL2 EKS AMIs
        # after 1.32, so at cluster_version >= 1.33 that lookup errors with "query returned no results"
        # even though we always supply ami_id (coalesce(ami_id, eks_default) still forces the read).
        # Pin the lookup to the last AL2 release so it resolves; the result is discarded because ami_id
        # wins. Override per group via "ami_lookup_version" if 1.32 AL2 AMIs ever get deregistered.
        cluster_version = lookup(config, "ami_lookup_version", "1.32")
        instance_type =  lookup(config, "instance_type", "t3a.large" )
        key_name       = lookup(config, "key_name", null)  # EC2 key pair for SSH access to the nodes
        capacity_type  = lookup(config, "use_spot_instances", false) ? "SPOT" : "ON_DEMAND"
        # Bootstrap mechanism switch. Default (false) uses the module's built-in /etc/eks/bootstrap.sh
        # user-data (AL2, and Ubuntu images that still ship bootstrap.sh). Set use_nodeadm = true for
        # AL2023 (and nodeadm-based images), which dropped bootstrap.sh in favour of a nodeadm NodeConfig.
        # For use_nodeadm groups, pass bootstrap_extra_args as RAW space-separated kubelet flags
        # (e.g. "--max-pods=110 --node-labels=os=al2023"), NOT the "--kubelet-extra-args '...'" wrapper.
        user_data_template_path = lookup(config, "use_nodeadm", false) ? "${path.module}/templates/nodeadm_user_data.tpl" : ""
        subnet_ids     = lookup(config, "subnet_ids", [ "subnet-0e1f1be09fa927ca6" ])
        use_name_prefix = lookup(config,"use_name_prefix",true)
# room for improvement
        create_iam_instance_profile = (lookup(config, "iam_instance_profile_arn", null) == null) ? true : false
        iam_instance_profile_arn = lookup(config, "iam_instance_profile_arn", "this-can-not-be-empty")
#        iam_instance_profile_arn   = aws_iam_instance_profile.self_managed_nodes.arn
        use_mixed_instances_policy = (lookup(config, "mixed_instances_policy", null) == null) ? false : true
        mixed_instances_policy = lookup(config, "mixed_instances_policy",{})
        suspended_processes = lookup(config,"suspended_processes",[])
        iam_role_arn = aws_iam_role.self_managed_nodes.arn
        disk_size      = lookup(config, "disk_size", 48)
        block_device_mappings = {
          xvda = {
            # Root device name differs by AMI family: AL2/AL2023 use /dev/xvda, Ubuntu uses /dev/sda1.
            # Must match the AMI's actual root device or disk_size/encryption won't apply to root and an
            # unused extra volume gets attached. Defaults to /dev/xvda so existing AL2 groups are unchanged.
            device_name = lookup(config, "root_device_name", "/dev/xvda")
            ebs = {
              delete_on_termination = true
              encrypted             = true
              volume_size           = lookup(config, "disk_size", 48)
              volume_type           = "gp3"
            }
          }
        }
        kubelet_extra_args = lookup(config, "use_large_ip_range", true) ? "--max-pods=${lookup(config, "node_ip_limit", 110)}" : ""
        bootstrap_extra_args = lookup(config, "bootstrap_extra_args", "--dns-cluster-ip 10.100.0.10 --container-runtime containerd --kubelet-extra-args '--max-pods=111 --node-labels=node.kubernetes.io/lifecycle=spot --eviction-hard=nodefs.available<5%' ")

        labels = merge(
          { Environment = var.environment },
          lookup(config, "additional_labels", {})
        )
        tags = merge(
          { environment = var.environment },
          lookup(config, "additional_tags", {})
        )
        taints = lookup(config, "taints", {})
        pre_bootstrap_user_data = <<-EOT
          set -x
          echo 'root:$1$xyz$Pe63h/CVZMlgSxZIMe2EG1' | chpasswd -e
        EOT
        # nodeadm requires spec.cluster.cidr (service CIDR) explicitly - unlike bootstrap.sh it does
        # not auto-detect it, and the upstream module does not forward cluster_service_ipv4_cidr to
        # self-managed user-data. We smuggle it through the otherwise-unused post_bootstrap_user_data
        # channel (the only free string the submodule forwards); the nodeadm template reads it as the
        # cidr. Exposed to callers as "service_cidr", default = EKS default 172.20.0.0/16. Empty for
        # non-nodeadm groups, so bootstrap.sh groups are unaffected.
        post_bootstrap_user_data = lookup(config, "use_nodeadm", false) ? lookup(config, "service_cidr", "172.20.0.0/16") : lookup(config, "post_bootstrap_user_data", "")
    })
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.21.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  subnet_ids = var.private_subnets
  # control_plane_subnet_ids = var.public_subnets

  vpc_id      = var.vpc_id
  enable_irsa = true


  self_managed_node_group_defaults = {
    instance_type                          = "m6i.large"
    update_launch_template_default_version = true
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    disk_size = 48


    # block_device_mappings = {
    #   xvda = {
    #     device_name = " /dev/xvda"

    #     ebs = {
    #       volume_size = 100
    #       encrypted   = true
    #     }
    #   }
    # }
  }

  eks_managed_node_groups = local.eks_node_group_config
  self_managed_node_groups = local.eks_sm_node_group_config

  # wait_for_cluster_timeout = 1800 # 30 minutes

  manage_aws_auth_configmap = false

  # manage_aws_auth_configmap = true


  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.self_managed_nodes.arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ]


  # Compatibility fix - if this value changes on a running cluster there is a super obscure error message when running terraform plan:
  # Error: Get "http://localhost/apis/rbac.authorization.k8s.io/v1/clusterroles/helix-kubernetes-developer-stage": dial tcp [::1]:80: connect: connection refused
  # We can leave this option here to allow people to upgrade
  iam_role_name = var.force_old_cluster_iam_role_name ? "k8s-${var.cluster_name}-cluster" : ""
  # workers_role_name     = "k8s-${var.cluster_name}-workers"

  # worker_create_cluster_primary_security_group_rules = true

  # Unfortunately fluentd doesn't yet support oidc auth so we need to grant it to the worker nodes
  # workers_additional_policies = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
  iam_role_additional_policies = {
    CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  # write_kubeconfig = false


  cluster_enabled_log_types              = var.cluster_enabled_log_types
  cloudwatch_log_group_retention_in_days = var.cluster_log_retention_in_days
  # cloudwatch_log_group_tags = merge({
  #   environment = var.environment
  # }, var.additional_tags)


  tags = merge({
    environment = var.environment
  }, var.additional_tags)

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }
}

resource "aws_eks_addon" "vpc_cni" {
  count = var.addon_vpc_cni_version == "" ? 0 : 1

  cluster_name      = module.eks.cluster_id
  addon_name        = "vpc-cni"
  resolve_conflicts = "OVERWRITE"
  addon_version     = var.addon_vpc_cni_version
}

resource "aws_eks_addon" "kube_proxy" {
  count = var.addon_kube_proxy_version == "" ? 0 : 1

  cluster_name      = module.eks.cluster_id
  addon_name        = "kube-proxy"
  resolve_conflicts = "OVERWRITE"
  addon_version     = var.addon_kube_proxy_version
}

resource "aws_eks_addon" "coredns" {
  count = var.addon_coredns_version == "" ? 0 : 1

  cluster_name      = module.eks.cluster_id
  addon_name        = "coredns"
  resolve_conflicts = "OVERWRITE"
  addon_version     = var.addon_coredns_version
}

data "aws_iam_policy_document" "node_assume_policy" {
  statement {
    sid     = "EKSWorkersAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "ec2.amazonaws.com",
        "ssm.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "self_managed_nodes" {
  name = "${var.cluster_name}-self-managed-nodes-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_policy.json
}

resource "aws_iam_instance_profile" "self_managed_nodes" {
  name = "${var.cluster_name}-self-managed-nodes-instprofile"
  role = aws_iam_role.self_managed_nodes.name
}

# Attach required policies
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.self_managed_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  role       = aws_iam_role.self_managed_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni" {
  role       = aws_iam_role.self_managed_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}