output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "aws_region" {
  description = "AWS region used by this deployment."
  value       = var.aws_region
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "Repository URL for the application image."
  value       = aws_ecr_repository.app.repository_url
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "codebuild_project_name" {
  description = "CodeBuild project that builds/pushes the app image (no local Docker needed)."
  value       = aws_codebuild_project.image_build.name
}

output "start_build_command" {
  description = "Run this locally to build and push the app image via CodeBuild."
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.image_build.name} --region ${var.aws_region}"
}

output "lb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller's service account (IRSA)."
  value       = aws_iam_role.lb_controller.arn
}

output "vpc_id" {
  description = "VPC ID, needed by the AWS Load Balancer Controller Helm install."
  value       = module.vpc.vpc_id
}
