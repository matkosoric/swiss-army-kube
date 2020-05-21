#Global helm chart repo
data "helm_repository" "stable" {
  name = "stable"
  url  = "https://kubernetes-charts-incubator.storage.googleapis.com"
}

resource "helm_release" "jenkins" {
  depends_on = [
    var.module_depends_on,
    aws_iam_role_policy_attachment.jenkins_agent
  ]   
  
  name          = "jenkins"
  repository    = data.helm_repository.stable.metadata[0].name
  chart         = "jenkins"
  namespace     = "jenkins"
  recreate_pods = true

  set {
    name  = "master.adminPassword"
    value = var.jenkins_password
  }

  set {
    name  = "master.ingress.enabled"
    value = "true"
  }

  set {
    name  = "serviceAccountAgent.name"
    value = "jenkins-agent"
  }

  set {
    name  = "serviceAccountAgent.create"
    value = true
  }

  set_string {
    name  = "serviceAccountAgent.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.jenkins_agent.arn
  }

  set {
    name  = "serviceAccount.name"
    value = "jenkins-master"
  }

  set {
    name  = "serviceAccount.create"
    value = true
  }

  set_string {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.jenkins_master.arn
  }

//TODO: fix it for multi domains
  set {
      name  = "master.ingress.hostName"
      value = "jenkins.${var.domains[0]}"
  }

  dynamic "set" {
    for_each = var.domains
    content {  
      name  = "master.ingress.tls[${set.key}].secretName"
      value = "jenkins-${set.key}-tls"
    }
  }
  dynamic "set" {
    for_each = var.domains
    content {  
      name  = "master.ingress.tls[${set.key}].hosts[0]"
      value = "jenkins.${set.value}"
    }
  }

  values = [
    file("${path.module}/values.yml")
  ]
}

# Enabling IAM Roles for Service Accounts
data "aws_iam_policy_document" "jenkins_agent_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:jenkins:jenkins-agent"]
    }

    principals {
      identifiers = [var.cluster_oidc_arn]
      type        = "Federated"
    }
  }
}

data "aws_iam_policy_document" "jenkins_master_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:jenkins:jenkins-master"]
    }

    principals {
      identifiers = [var.cluster_oidc_arn]
      type        = "Federated"
    }
  }
}

# Create role for jenkins agents
resource "aws_iam_role" "jenkins_agent" {
  depends_on = [
    var.module_depends_on
  ]
  assume_role_policy = data.aws_iam_policy_document.jenkins_agent_assume_role_policy.json
  name               = "${var.cluster_name}_jenkins_agent"

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

# Create role for jenkins master
resource "aws_iam_role" "jenkins_master" {
  depends_on = [
    var.module_depends_on
  ]
  assume_role_policy = data.aws_iam_policy_document.jenkins_master_assume_role_policy.json
  name               = "${var.cluster_name}_jenkins_master"

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

# Change this for needed policy to attach it to jenkins agent role
data "aws_iam_policy_document" "empty_agent" {
  statement {
    actions   = ["*"]
    resources = ["*"]
    effect    = "Deny"
  }
}

resource "aws_iam_policy" "empty_agent" {
  depends_on = [
    var.module_depends_on
  ]
  name   = "${var.cluster_name}_empty_agent"
  policy = data.aws_iam_policy_document.empty_agent.json
}

# Change this for needed policy to attach it to jenkins master role
data "aws_iam_policy_document" "empty_master" {
  statement {
    actions   = ["*"]
    resources = ["*"]
    effect    = "Deny"
  }
}

resource "aws_iam_policy" "empty_master" {
  depends_on = [
    var.module_depends_on
  ]
  name   = "${var.cluster_name}_empty_master"
  policy = data.aws_iam_policy_document.empty_master.json
}

# Attach policy to role jenkins_agent
resource "aws_iam_role_policy_attachment" "jenkins_agent" {
  depends_on = [
    var.module_depends_on,
    aws_iam_role.jenkins_agent
  ]
  role       = aws_iam_role.jenkins_agent.name
  policy_arn = aws_iam_policy.empty_agent.arn
}

# Attach policy to role jenkins_master
resource "aws_iam_role_policy_attachment" "jenkins_master" {
  depends_on = [
    var.module_depends_on,
    aws_iam_role.jenkins_master
  ]
  role       = aws_iam_role.jenkins_master.name
  policy_arn = aws_iam_policy.empty_master.arn
}