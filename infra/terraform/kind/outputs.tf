output "kubeconfig_path" {
  description = "Use com: export KUBECONFIG=$(terraform output -raw kubeconfig_path)"
  value       = kind_cluster.this.kubeconfig_path
}

output "context_name" {
  value = kind_cluster.this.context_name
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}
