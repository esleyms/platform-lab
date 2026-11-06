locals {
  # NodePorts fixos do Service do Envoy (ver gitops/platform/gateway/envoyproxy.yaml).
  gateway_node_ports = {
    http  = 30080
    https = 30443
  }
}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = pathexpand(var.kubeconfig_path)

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # O tráfego do host entra pelo control-plane e chega ao NodePort do Envoy.
      extra_port_mappings {
        container_port = local.gateway_node_ports.http
        host_port      = var.http_host_port
        listen_address = "127.0.0.1"
      }
      extra_port_mappings {
        container_port = local.gateway_node_ports.https
        host_port      = var.https_host_port
        listen_address = "127.0.0.1"
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
        labels = {
          "platform-lab/pool" = "general"
        }
      }
    }
  }
}
