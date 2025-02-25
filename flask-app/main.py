from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
import structlog
import time
import os
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import logging
from opentelemetry.instrumentation.flask import FlaskInstrumentor

if "KUBERNETES_SERVICE_HOST" in os.environ:
    OTEL_EXPORTER_ENDPOINT = "http://otel-collector.observability.svc:4317"
    LOG_SOURCE = "Kubernetes"
else:
    OTEL_EXPORTER_ENDPOINT = "http://otel-collector:4317"
    LOG_SOURCE = "Docker"

# Setup logging
logging.basicConfig(level=logging.INFO)

# Initialize Structlog
structlog.configure(processors=[structlog.processors.JSONRenderer()])
logger = structlog.get_logger()
logger.info("Flask application started")

# Initialize Flask
app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///users.db"
db = SQLAlchemy(app)


resource = Resource.create({"service.name": "flask-app"})  
trace.set_tracer_provider(TracerProvider(resource=resource))
tracer = trace.get_tracer(__name__)

otlp_exporter = OTLPSpanExporter(endpoint=OTEL_EXPORTER_ENDPOINT, insecure=True)
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))  

# ✅ Instrument Flask
FlaskInstrumentor().instrument_app(app)

# Prometheus Metrics
REQUEST_COUNT = Counter("flask_http_requests_total", "Total HTTP requests", ["method", "endpoint"])
LATENCY_HISTOGRAM = Histogram("flask_request_latency_seconds", "Request latency", ["endpoint"])

# Define User Model
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)

# Create Database
with app.app_context():
    db.create_all()

# Middleware for Metrics
@app.before_request
def before_request():
    request.start_time = time.time()

@app.after_request
def after_request(response):
    latency = time.time() - request.start_time
    LATENCY_HISTOGRAM.labels(request.path).observe(latency)
    REQUEST_COUNT.labels(request.method, request.path).inc()
    return response

# Routes
@app.route("/users", methods=["POST"])
def create_user():
    with tracer.start_as_current_span("create_user") as span:
        data = request.json
        user = User(name=data["name"])
        db.session.add(user)
        db.session.commit()
        logger.info("User created", user_id=user.id, user_name=user.name)
        span.set_attribute("user.id", user.id)
        return jsonify({"id": user.id, "name": user.name}), 201

@app.route("/users", methods=["GET"])
def get_users():
    with tracer.start_as_current_span("get_users"):
        users = User.query.all()
        result = [{"id": user.id, "name": user.name} for user in users]
        return jsonify(result)

@app.route("/users/<int:id>", methods=["PUT"])
def update_user(id):
    with tracer.start_as_current_span("update_user") as span:
        user = User.query.get(id)
        if not user:
            return jsonify({"error": "User not found"}), 404
        data = request.json
        user.name = data["name"]
        db.session.commit()
        logger.info("User updated", user_id=user.id, new_name=user.name)
        span.set_attribute("user.id", user.id)
        return jsonify({"id": user.id, "name": user.name})

@app.route("/users/<int:id>", methods=["DELETE"])
def delete_user(id):
    with tracer.start_as_current_span("delete_user") as span:
        user = User.query.get(id)
        if not user:
            return jsonify({"error": "User not found"}), 404
        db.session.delete(user)
        db.session.commit()
        logger.info("User deleted", user_id=id)
        span.set_attribute("user.id", id)
        return jsonify({"message": "User deleted"})

@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

# Run Flask
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5141)
