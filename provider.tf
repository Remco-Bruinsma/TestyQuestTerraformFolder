terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    
  }
}
provider "kubernetes" {
  config_path = "~/.kube/config" 
  host        = "https://localhost:6443" 
}


resource "kubernetes_namespace" "testy_quest_namespace" {
  metadata {
    name = "testy-quest"
  }
}

locals {
  promtail_config_content = file("${path.module}/promtailscrapejob.yaml")
  mongod_conf_content = file("${path.module}/mongod.conf")
}

resource "kubernetes_manifest" "grafana_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata   = {
      name      = "grafana-deployment"
      namespace = "testy-quest"
    }
    spec       = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "grafana"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "grafana"
          }
        }
        spec     = {
          containers = [
            {
              name  = "grafana"
              image = "grafana/grafana:latest"
              ports = [
                {
                  containerPort = 3000
                }
              ]
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "grafana_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata   = {
      name      = "grafana-service"
      namespace = "testy-quest"
    }
    spec       = {
      selector = {
        app = "grafana"
      }
      ports    = [
        {
          protocol   = "TCP"
          port       = 80
          targetPort = 3000
        }
      ]
    }
  }
  depends_on = [kubernetes_manifest.grafana_deployment]
}

resource "kubernetes_manifest" "loki_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata   = {
      name      = "loki-deployment"
      namespace = "testy-quest"
    }
    spec       = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "loki"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "loki"
          }
        }
        spec     = {
          containers = [
            {
              name  = "loki"
              image = "grafana/loki:latest"
              ports = [
                {
                  containerPort = 3100
                }
              ]
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "loki_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata   = {
      name      = "loki-service"
      namespace = "testy-quest"
    }
    spec       = {
      selector = {
        app = "loki"
      }
      ports    = [
        {
          protocol   = "TCP"
          port       = 3100
          targetPort = 3100
        }
      ]
    }
  }
  depends_on = [kubernetes_manifest.loki_deployment]
}


resource "kubernetes_config_map" "promtail_config" {
  metadata {
    name      = "promtail-config"
    namespace = "testy-quest"
  }
  data = {
    "promtail.yaml" = local.promtail_config_content
  }
}

resource "kubernetes_manifest" "promtail" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "DaemonSet"
    metadata   = {
      name      = "promtail"
      namespace = "testy-quest"
    }
    spec       = {
      selector = {
        matchLabels = {
          app = "promtail"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "promtail"
          }
        }
        spec = {
          containers = [
            {
              name  = "promtail"
              image = "grafana/promtail:latest"
              args = [
                "-config.file=/etc/promtail/promtail.yaml"
              ]
              volumeMounts = [
                {
                  name       = "config"
                  mountPath  = "/etc/promtail"
                }
              ]
            }
          ]
          volumes = [
            {
              name = "config"
              configMap = {
                name = "promtail-config"
              }
            }
          ]
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace]

  
}

resource "kubernetes_manifest" "kafka_ui_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata   = {
      name      = "kafka-ui-deployment"
      namespace = "testy-quest"
    }
    spec       = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "kafka-ui"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "kafka-ui"
          }
        }
        spec     = {
          containers = [
            {
              name  = "kafka-ui"
              image = "provectuslabs/kafka-ui:latest"
              ports = [
                {
                  containerPort = 8080
                }
              ]
               env = [
                {
                  name  = "DYNAMIC_CONFIG_ENABLED"
                  value = "true"
                }
              ]
            }
          ]
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace]
}

resource "kubernetes_manifest" "kafka_ui_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata   = {
      name      = "kafka-ui-service"
      namespace = "testy-quest"
    }
    spec       = {
      selector = {
        app = "kafka-ui"
      }
      ports    = [
        {
          protocol   = "TCP"
          port       = 80
          targetPort = 8080
        }
      ]
    }
  }
  depends_on = [kubernetes_manifest.kafka_ui_deployment]
}

resource "kubernetes_manifest" "kafka_data_pvc" {
  manifest = {
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata   = {
      name      = "kafka-data-claim"
      namespace = "testy-quest"
    }
    spec       = {
      accessModes = ["ReadWriteOnce"]
      resources   = {
        requests = {
          storage = "1Gi" # Adjust the storage size as needed
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.testy_quest_namespace]
}

resource "kubernetes_manifest" "kafka" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata   = {
      name      = "kafka"
      namespace = "testy-quest"
    }
    spec       = {
      replicas = 3
      serviceName = "kafka-svc"
      selector = {
        matchLabels = {
          app = "kafka"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "kafka"
          }
        }
        spec = {
          containers = [
            {
              name  = "kafka-container"
              image = "doughgle/kafka-kraft"
              ports = [
                {
                  containerPort = 9092
                }
              ]
              env = [
                {
                  name  = "REPLICAS"
                  value = "3"
                },
                {
                  name  = "SERVICE"
                  value = "kafka-svc"
                },
                {
                  name  = "NAMESPACE"
                  value = "testy-quest"
                },
                {
                  name  = "SHARE_DIR"
                  value = "/mnt/kafka"
                },
                {
                  name  = "CLUSTER_ID"
                  value = "oh-sxaDRTcyAr6pFRbXyzA"
                },
                {
                  name  = "DEFAULT_REPLICATION_FACTOR"
                  value = "3"
                }
                
              ]
              volumeMounts = [
                {
                  name       = "kafka-data"
                  mountPath  = "/mnt/kafka"
                }
              ]
            }
          ]
          volumes = [
            {
              name = "kafka-data"
              persistentVolumeClaim = {
                claimName = "kafka-data-claim"
              }
            }
            
          ]
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace]
}

resource "kubernetes_manifest" "kafka_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata   = {
      name      = "kafka-svc"
      namespace = "testy-quest"
    }
    spec       = {
      clusterIP = "None"
      ports = [
        {
          port       = 9092
          targetPort = 9092
          protocol   = "TCP"
        }
      ]
      selector = {
        app = "kafka"
      }
    }
  }
  depends_on = [kubernetes_manifest.kafka]
}

resource "kubernetes_manifest" "mongodb" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata   = {
      name      = "mongodb"
      namespace = "testy-quest"
    }
    spec       = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "mongodb"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "mongodb"
          }
        }
        spec     = {
          containers = [
            {
              name  = "mongodb"
              image = "mongo:latest"
              ports = [
                {
                  containerPort = 27017
                }
              ]
              env = [
                {
                  name  = "MONGO_INITDB_ROOT_USERNAME"
                  value = "root"
                },
                {
                  #for testing 
                  name  = "MONGO_INITDB_ROOT_PASSWORD"
                  value = "password123"
                }
              ]
            }
          ]
          
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace]
}



resource "kubernetes_manifest" "exam_website_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata   = {
      name      = "exam-website-deployment"
      namespace = "testy-quest"
    }
    spec       = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "exam-website"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "exam-website"
          }
        }
        spec     = {
          containers = [
            {
              name  = "exam-website"
              image = "darkghostshade/testy-quest-front-end:latest"
              ports = [
                {
                  containerPort = 3000
                }
              ]
              env   = [
                {
                  name  = "WATCHPACK_POLLING"
                  value = "true"
                },
                {
                  name  = "APICONNECTION"
                  value = "https://test-managerapi-service"
                }
              ]
            }
          ]
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace]
}

resource "kubernetes_manifest" "exam_website_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata   = {
      name      = "exam-website-service"
      namespace = "testy-quest"
    }
    spec       = {
      selector = {
        app = "exam-website"
      }
      ports    = [
        {
          protocol   = "TCP"
          port       = 80
          targetPort = 3000
        }
      ]
    }
  }
  depends_on = [kubernetes_manifest.exam_website_deployment]
}

resource "kubernetes_manifest" "answer_managerapi_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata   = {
      name      = "answer-managerapi-deployment"
      namespace = "testy-quest"
    }
    spec       = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "answer-managerapi"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "answer-managerapi"
          }
        }
        spec = {
          containers = [
            {
              name            = "answer-managerapi-container"
              image           = "darkghostshade/answer-manager-api:latest"
              imagePullPolicy = "Always"
              ports           = [
                { containerPort = 80 }
                
              ]
              resources       = {
                requests = {
                  cpu = "100m"
                }
              }
              env = [
                {
                  name  = "WATCHPACK_POLLING"
                  value = "true"
                }
               
              ]
            }
          ]
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace]
}

resource "kubernetes_manifest" "answer_managerapi_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata   = {
      name      = "answer-managerapi-service"
      namespace = "testy-quest"
    }
    spec       = {
      selector = {
        app = "answer-managerapi"
      }
      ports    = [
        {
          name       = "http"
          protocol   = "TCP"
          port       = 80
          targetPort = 8080
        }
      ]
    }
  }
  depends_on = [kubernetes_manifest.answer_managerapi_deployment]
}

resource "kubernetes_manifest" "answer_managerapi_hpa" {
  manifest = {
    apiVersion = "autoscaling/v2"
    kind       = "HorizontalPodAutoscaler"
    metadata   = {
      name      = "answer-managerapi-hpa"
      namespace = "testy-quest"
    }
    spec       = {
      scaleTargetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = "answer-managerapi-deployment"
      }
      minReplicas    = 1
      maxReplicas    = 10
      metrics        = [
        {
          type    = "Resource"
          resource = {
            name  = "cpu"
            target = {
              type              = "Utilization"
              averageUtilization = 50
            }
          }
        }
      ]
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace, kubernetes_manifest.answer_managerapi_deployment]
}


resource "kubernetes_manifest" "question_managerapi_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata   = {
      name      = "question-managerapi-deployment"
      namespace = "testy-quest"
    }
    spec       = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "question-managerapi"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "question-managerapi"
          }
        }
        spec = {
          containers = [
            {
              name            = "question-managerapi-container"
              image           = "darkghostshade/question-manager-api:latest"
              imagePullPolicy = "Always"
              ports           = [
                { containerPort = 80 }
                
              ]
              resources       = {
                requests = {
                  cpu = "100m"
                }
              }
              env = [
                {
                  name  = "WATCHPACK_POLLING"
                  value = "true"
                },
                {
                  name  = "MongoDBUsername"
                  value = "root"
                },
                #tests enviroment not real
                {
                  name  = "MongoDBPassword"
                  value = "password123"
                }
               
              ]
            }
          ]
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace,]
}

resource "kubernetes_manifest" "question_managerapi_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata   = {
      name      = "question-managerapi-service"
      namespace = "testy-quest"
    }
    spec       = {
      selector = {
        app = "question-managerapi"
      }
      ports    = [
        {
          name       = "http"
          protocol   = "TCP"
          port       = 80
          targetPort = 8080
        }
      ]
    }
  }
  depends_on = [kubernetes_manifest.answer_managerapi_deployment,kubernetes_manifest.kafka_service,kubernetes_manifest.kafka]

  
}

resource "kubernetes_manifest" "question_managerapi_hpa" {
  manifest = {
    apiVersion = "autoscaling/v2"
    kind       = "HorizontalPodAutoscaler"
    metadata   = {
      name      = "question-managerapi-hpa"
      namespace = "testy-quest"
    }
    spec       = {
      scaleTargetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = "question-managerapi-deployment"
      }
      minReplicas    = 1
      maxReplicas    = 10
      metrics        = [
        {
          type    = "Resource"
          resource = {
            name  = "cpu"
            target = {
              type              = "Utilization"
              averageUtilization = 50
            }
          }
        }
      ]
    }
  }
  depends_on = [kubernetes_namespace.testy_quest_namespace, kubernetes_manifest.question_managerapi_deployment]
}


resource "kubernetes_manifest" "testy_quest_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata   = {
      name      = "testy-quest-ingress"
      namespace = "testy-quest"
    }
    spec       = {
      rules = [
        {
          host = "api.localhost"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend  = {
                  service = {
                    name = "answer-managerapi-service"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        },
        {
          host = "api.question.localhost"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend  = {
                  service = {
                    name = "question-managerapi-service"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        },
        {
          host = "website.localhost"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend  = {
                  service = {
                    name = "exam-website-service"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        },
        {
          host = "kafka-ui.localhost"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend  = {
                  service = {
                    name = "kafka-ui-service"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        },
        {
          host = "grafana.localhost"  
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend  = {
                  service = {
                    name = "grafana-service"  
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
  

}







