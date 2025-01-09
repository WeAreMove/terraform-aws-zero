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

        ami_type       = lookup(config, "ami_type", "AL2_x86_64")
        instance_types = lookup(config, "instance_types", [])
        capacity_type  = lookup(config, "use_spot_instances", false) ? "SPOT" : "ON_DEMAND"
        disk_size      = 100
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              delete_on_termination = true
              encrypted             = true
              volume_size           = 100
              volume_type           = "gp3"
            }
          }
        }
        kubelet_extra_args = lookup(config, "use_large_ip_range", true) ? "--max-pods=${lookup(config, "node_ip_limit", 110)}" : ""

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
        launch_template_name       = "${n}-self-managed"

        ami_type       = lookup(config, "ami_type", "AL2_x86_64")
        ami_id         = lookup(config, "ami_id", "")  # Specify ARM AMI ID
        instance_type =  lookup(config, "instance_type", "t3a.large" )
        capacity_type  = lookup(config, "use_spot_instances", false) ? "SPOT" : "ON_DEMAND"
        subnet_ids     = lookup(config, "subnet_ids", [ "subnet-0e1f1be09fa927ca6" ])
        disk_size      = 100
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              delete_on_termination = true
              encrypted             = true
              volume_size           = 100
              volume_type           = "gp3"
            }
          }
        }
        kubelet_extra_args = lookup(config, "use_large_ip_range", true) ? "--max-pods=${lookup(config, "node_ip_limit", 110)}" : ""

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
          #!/bin/bash
          set -o xtrace
          /etc/eks/bootstrap.sh ${module.eks.cluster_name} \
            --b64-cluster-ca ${module.eks.cluster_certificate_authority_data} \
            --apiserver-endpoint ${module.eks.cluster_endpoint}
        EOT
    })
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

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
    disk_size = 100


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
      rolearn  = "arn:aws:iam::66666666666:role/role1"
      username = "role1"
      groups   = ["system:masters"]
    },
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
