# IRSA role for the AWS Load Balancer Controller - required for the NLB Service and ALB Ingress in ../app/k8s to actually provision anything.
# The controller itself (Helm chart) is installed manually via kubectl/helm, not Terraform, matching how the rest of this project applies Kubernetes manifests.

data "aws_iam_policy_document" "lb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.name}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume.json
}

# Official upstream policy, downloaded as-is via:
# curl -o aws-load-balancer-controller-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
resource "aws_iam_policy" "lb_controller" {
  name   = "${local.name}-AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/aws-load-balancer-controller-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}
