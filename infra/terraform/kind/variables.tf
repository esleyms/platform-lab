variable "cluster_name" {
  description = "Nome do cluster kind."
  type        = string
  default     = "platform-lab"
}

variable "node_image" {
  description = "Imagem dos nós. Fixada por digest para o cluster ser reproduzível."
  type        = string
  # Imagem padrão do kind v0.33.0 (a versão embutida no provider tehcyx/kind 0.13.x).
  default = "kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5"
}

variable "worker_count" {
  description = "Quantidade de nós worker."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 4
    error_message = "Use entre 1 e 4 workers."
  }
}

variable "http_host_port" {
  description = "Porta do host mapeada para o NodePort HTTP do Envoy Gateway."
  type        = number
  default     = 80
}

variable "https_host_port" {
  description = "Porta do host mapeada para o NodePort HTTPS do Envoy Gateway."
  type        = number
  default     = 443
}

variable "kubeconfig_path" {
  description = "Onde gravar o kubeconfig. Separado do ~/.kube/config para não misturar contextos."
  type        = string
  default     = "~/.kube/platform-lab"
}
