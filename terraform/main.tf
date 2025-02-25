provider "kubernetes" {
  config_path = "~/.kube/config"  
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}



resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.observability.metadata[0].name

  values = [
    <<EOF
grafana:
  enabled: false
alertmanager:
  enabled: false  
EOF
  ]
}


resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.observability.metadata[0].name

  values = [
    <<EOF
adminPassword: "admin"  # Change this for security

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-operated.observability.svc:9090
        access: proxy
        isDefault: true

      - name: Loki
        type: loki
        url: http://loki.observability.svc:3100
        access: proxy

      - name: Tempo
        type: tempo
        url: http://tempo.observability.svc:3100
        access: proxy
EOF
  ]
}



resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  namespace  = kubernetes_namespace.observability.metadata[0].name

  values = [
    <<EOF
tempo:
  storage:
    trace:
      backend: local
EOF
  ]
}


resource "kubernetes_config_map" "otel_collector_config" {
  metadata {
    name      = "otel-collector-config"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  data = {
    "otel-collector-config.yml" = <<-EOT
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch: {}

    exporters:
      otlp:
        endpoint: "tempo.observability.svc.cluster.local:4317"
        tls:
          insecure: true

      logging: {}

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp, logging]
    EOT
  }
}

resource "kubernetes_deployment" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "otel-collector"
      }
    }

    template {
      metadata {
        labels = {
          app = "otel-collector"
        }
      }

      spec {
        container {
          name  = "otel-collector"
          image = "otel/opentelemetry-collector-contrib:0.81.0"
          command = [
            "/otelcol-contrib",
            "--config=/etc/otel/otel-collector-config.yml"
          ]

          volume_mount {
            name      = "otel-config"
            mount_path = "/etc/otel"
          }
        }

        volume {
          name = "otel-config"
          config_map {
            name = kubernetes_config_map.otel_collector_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  spec {
    selector = {
      app = "otel-collector"
    }

    port {
      port        = 4317
      target_port = 4317
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}


##promtail is daemon set which sends logs data to loki you can deploy it separately or the loki stack comes with loki, 
#commented here because for now we are deploying 
#with the loki stack, if subclusters are there we use this method of deploying promtail separately.


# resource "helm_release" "promtail" {
#   name       = "promtail"
#   repository = "https://grafana.github.io/helm-charts"
#   chart      = "promtail"
#   namespace  = kubernetes_namespace.observability.metadata[0].name

#   values = [
#     <<EOF
# config:
#   clients:
#     - url: "http://loki:3100/loki/api/v1/push"
# EOF
#   ]
# }


resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"

  values = [
    yamlencode({
      grafana = {
        enabled = false
      },
      loki = {
        image = {
          repository = "grafana/loki"
          tag        = "2.9.3"
        }
      }
    })
  ]
}


resource "kubernetes_deployment" "flask_app" {
  metadata {
    name      = "flask-app"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      app = "flask-app"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "flask-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "flask-app"
        }
      }
      spec {
        container {
          name  = "flask-app"
          image = "my-flask-app:latest"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 5141
          }
          env {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = "http://otel-collector:4317"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "flask_service" {
  metadata {
    name      = "flask-service"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      app = "flask-app"  
    }
  }
  spec {
    selector = {
      app = "flask-app"
    }
    
    port {
      name        = "http"
      port        = 5141      
      target_port = 5141
    }
  }
}


resource "kubernetes_manifest" "flask_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "flask-app-monitor"
      namespace = kubernetes_namespace.observability.metadata[0].name
      labels = {
        release = "prometheus"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "flask-app"
        }
      }
      endpoints = [
        {
          port     = "http"    
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  }
}

