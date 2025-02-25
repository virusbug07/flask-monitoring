# Flask Observability Stack (Minikube + Terraform)

This repository contains a Flask-based CRUD application instrumented with OpenTelemetry, Prometheus, Loki, and Tempo for observability. The stack can be deployed locally using Docker Compose or in Minikube using Terraform.

---

## Prerequisites

Ensure you have the following installed:

- [Python 3](https://www.python.org/downloads/)
- [Flask](https://flask.palletsprojects.com/en/2.0.x/installation/)
- [Docker](https://www.docker.com/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

---

## Running Locally with Docker Compose

### Clone the Repository

```bash
git clone https://github.com/virusbug07/flask-monitoring.git
```

### Start the Stack

```bash
cd local
docker-compose up -d
```

This will start:
- Flask Application
- OpenTelemetry Collector
- Prometheus
- Loki
- Tempo
- Grafana

### Verify Services

Check running containers:

```bash
docker ps
```

Check Flask app logs:

```bash
docker logs flask-app -f
```

### Access Services

- Flask App: [http://localhost:5141](http://localhost:5141)
- Metrics: [http://localhost:5141/metrics](http://localhost:5141/metrics)
- Prometheus UI: [http://localhost:9090](http://localhost:9090)
- Grafana UI: [http://localhost:3000](http://localhost:3000)
  - Default login: admin / admin

To stop the services:

```bash
docker-compose down
```

---

## Deploying in Minikube with Terraform

### Start Minikube

```bash
minikube start
```

### Load Local Docker Image into Minikube

```bash
eval $(minikube docker-env)
docker build -t my-flask-app:latest .
```

Verify the image is in Minikube:

```bash
docker images | grep my-flask-app
```

### Initialize Terraform

```bash
cd terraform
terraform init
```

### Apply Terraform Configuration

```bash
terraform apply -auto-approve
```

This will create:
- A Kubernetes namespace (`observability`)
- A Flask deployment (with OpenTelemetry instrumentation)
- A service (`flask-service`) for exposing the Flask app
- A ServiceMonitor for Prometheus to scrape Flask metrics
- OpenTelemetry Collector
- Loki & Tempo for logs and traces

### Verify the Deployment

```bash
kubectl get pods -n observability
```

### Access Services in Minikube

Forward Flask service:

```bash
kubectl port-forward service/flask-service 8080:5141 -n observability
```

- Flask App: [http://localhost:8080](http://localhost:8080)
- Metrics: [http://localhost:8080/metrics](http://localhost:8080/metrics)

Forward Prometheus:

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090 -n observability
```

- Prometheus UI: [http://localhost:9090](http://localhost:9090)

Forward Grafana:

```bash
kubectl port-forward svc/grafana 3000:80 -n observability
```

- Grafana UI: [http://localhost:3000](http://localhost:3000)

---

## Destroying the Deployment

To stop everything:

```bash
terraform destroy -auto-approve
minikube delete
```

To stop the Docker Compose stack:

```bash
docker-compose down
```

---

## Folder Structure

```
.
├── terraform/                  # Terraform files for Minikube deployment
│   ├── main.tf                  # Main Terraform configuration
│
├── local
├──   ├── docker-compose.yml       # Docker Compose file for local setup
├── flask-app/
├── ├──app.py                        # Flask application
├── ├──Dockerfile                     # Dockerfile for Flask app
├── ├──requirements.txt               # Python dependencies
├─README.md                      # This file
```
## Note:
Some common problems may occur while locally extracting metrics of the application, try changig the url of the app in prometheus.yaml file.

---
