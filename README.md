K8-POC — Event-Driven Microservices on Kubernetes

Overview
This project is a hands-on Proof of Concept (POC) for an event-driven microservices architecture deployed on Kubernetes. It uses raw Kubernetes YAML manifests to provide full transparency and granular control over configurations.

Each component is containerized and deployed independently—mirroring real-world system architectures that emphasize observability, asynchronous processing, and scalability.

This POC serves as a foundational step for Kubernetes orchestration and is a prerequisite to my recently completed Docker POC. It aligns with the solution architecture designed for a broader system modernization initiative.

Components

| Component                  | Description                                                           |
| -------------------------- | --------------------------------------------------------------------- |
| 🧾 Kubernetes (YAML-based) | All services are defined using native Kubernetes manifests (no Helm). |
| 🌐 ALB-style Reverse Proxy | Nginx Ingress simulating AWS ALB behavior with HTTPS via NodePort.    |
| 🛣️ API Gateway            | Controls incoming traffic; enforces rate limits and routes requests.  |
| 📩 RabbitMQ                | Message broker for asynchronous pub-sub communication.                |
| 🔁 Lambda-style Workers    | Stateless services that publish/consume events to/from RabbitMQ.      |
| 📊 Prometheus + Grafana    | Service observability through metrics and dashboards.                 |
| 🚨 AlertManager            | Notifies based on Prometheus alert rules.                             |
| 💾 PostgreSQL              | Primary relational database.                                          |
| ⚡ Redis                    | In-memory cache for fast GET request responses.                       |
| 🔒 HTTPS (Nginx)           | TLS termination and secured ingress traffic.                          |
| 🛠️ PowerShell Scripts     | Automates service deployment, test scenarios, and system validation.  |

Components & Ports

| Service               | Port  | Purpose                                 |
| --------------------- | ----- | --------------------------------------- |
| Nginx Ingress (HTTPS) | 31443 | HTTPS entry point for all user requests |
| Frontend              | —     | User Interface                          |
| API Gateway           | 8081  | Rate-limited API entrypoint             |
| Backend API           | 3000  | CRUD logic, DB access                   |
| RabbitMQ              | 5672  | Message queue                           |
| RabbitMQ UI           | 15672 | Admin console                           |
| PostgreSQL            | 5432  | Database                                |
| Redis                 | 6379  | Cache                                   |
| Prometheus            | 9090  | Metrics collector                       |
| Grafana               | 3001  | Dashboard viewer                        |
| AlertManager          | 9093  | Notification engine                     |

How it works (End-to-End Process)

| Step  | Description                                                                                    |
| ----- | ---------------------------------------------------------------------------------------------- |
| 🔐 1  | Access the system securely via HTTPS through Nginx Ingress (simulating AWS ALB behavior).      |
| 🚦 2  | The API Gateway receives incoming traffic, validates requests, and routes them to the backend. |
| ⚡ 3   | Redis caches GET requests to boost performance and reduce backend load.                        |
| 🛠️ 4 | The backend processes requests, performs validation, and updates the database or cache.        |
| 📩 5  | Lambda-style producers publish events to RabbitMQ.                                             |
| 🔁 6  | Consumers asynchronously process events from RabbitMQ queues.                                  |
| 📊 7  | Prometheus scrapes metrics from services at regular intervals.                                 |
| 📈 8  | Grafana visualizes real-time metrics through dynamic dashboards.                               |
| 🚨 9  | AlertManager triggers alerts based on predefined Prometheus rules.                             |


Security Notes

| Concern             | Implementation Details                                 |
| ------------------- | ------------------------------------------------------ |
| API Access Control  | CORS and rate-limiting enforced in API Gateway.        |
| Database Protection | PostgreSQL exposed only inside the Kubernetes cluster. |
| Traffic Encryption  | Nginx Ingress terminates HTTPS connections.            |
| Messaging Isolation | RabbitMQ accessible only to internal services.         |


Automation Scripts

| Script/Tool             | Purpose                                                                  |
| ----------------------- | ------------------------------------------------------------------------ |
| `deploy.ps1`            | Deploys all services in correct order, including configmaps and secrets. |
| `validate-services.ps1` | Checks if all pods and services are running and responsive.              |
| `load-test.ps1`         | Sends HTTPS requests for performance and cache tests.                    |
| `scale-and-observe.ps1` | Scales services to simulate load and observe with Prometheus/Grafana.    |
| `cleanup.ps1`           | Removes all K8s resources for a fresh deployment.                        |


Author

John Christopher M. Carrillo

Role: Solution Architect

Purpose: Internal POC for system modernization and microservice deployment validation using Kubernetes.
