# Builds and pushes the app image without needing Docker/Podman installed anywhere locally.
# Source is the same project1.zip already uploaded to the wind-client transfer bucket.

variable "image_source_bucket" {
  description = "S3 bucket containing project1.zip (wind-client's transfer_bucket_name output)"
  type        = string
}

variable "image_source_key" {
  description = "S3 key of the source archive within image_source_bucket"
  type        = string
  default     = "project1.zip"
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/codebuild/${local.name}-image-build*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:aws:s3:::${var.image_source_bucket}/${var.image_source_key}"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${local.name}-codebuild-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

resource "aws_codebuild_project" "image_build" {
  name         = "${local.name}-image-build"
  service_role = aws_iam_role.codebuild.arn

  source {
    type      = "S3"
    location  = "${var.image_source_bucket}/${var.image_source_key}"
    buildspec = <<-BUILDSPEC
      version: 0.2
      phases:
        pre_build:
          commands:
            - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY
        build:
          commands:
            - cd project1/app/backend
            - docker build -t $ECR_REPOSITORY:latest .
        post_build:
          commands:
            - docker push $ECR_REPOSITORY:latest
    BUILDSPEC
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "ECR_REPOSITORY"
      value = aws_ecr_repository.app.repository_url
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }
  }
}
