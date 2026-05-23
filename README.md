# Final Project Deployment Guide

## Symfony Docker Deployment (Railway & Other Hosting Platforms)

This project demonstrates how to containerize and deploy a Symfony application using Docker and related technologies.

---

## Technologies Used

The application is deployed using:

- Docker
- Nginx
- PHP-FPM
- MySQL
- Docker Compose

---

## Project Objectives

This project is designed to demonstrate understanding of:

- Containerized application deployment
- Symfony production configuration
- Docker networking and orchestration
- Web server configuration using Nginx
- Environment variable management
- Cloud deployment workflows (e.g., Railway)

---

## Project Requirements

Your final project must include:

- A working Symfony application
- Dockerized deployment setup
- Proper Nginx configuration
- Production-ready environment configuration
- Database integration
- Complete deployment documentation
- Successful deployment on a hosting platform (e.g., Railway)

---

## Required Files

Create the following files in your project root directory:

### Dockerfile

Defines the blueprint for building the application’s Docker image.
Without it, the application cannot be containerized or deployed consistently across environments.

---

### docker-compose.yaml

Defines and manages multiple containers as a single application stack (primarily for local development).
Ensures all services work together as a complete system and simplifies container orchestration.

---

### entrypoint.sh

Script executed when a container starts.
Ensures the application initializes in a consistent and production-ready state every time.

---

### nginx.conf

Main configuration file for the Nginx web server.
Acts as the entry point for all web traffic and forwards requests correctly to the application.

---

### nginx-main.conf

Additional or environment-specific Nginx configuration file.
Improves maintainability and allows safer updates without modifying the main config.

---

### .dockerignore

Specifies files and folders excluded from the Docker build context.
Helps keep Docker images clean and builds efficient.

---

### .env

Stores environment variables used by the application.
Keeps sensitive information out of the codebase and allows flexible configuration across environments.

---

## Run locally with Docker Compose

1) Build and start the stack:

```bash
docker compose up --build
```

2) Open the app:

- http://localhost:8080

3) Container roles:

- `web` = nginx
- `php` = php-fpm (runs Symfony)
- `db` = mysql

4) Database migrations:

- `entrypoint.sh` runs `doctrine:migrations:migrate` automatically when `RUN_MIGRATIONS=1` (default in `.env`).

---

## Railway deployment (Dockerfile)

Railway should build from the repository’s `Dockerfile`.

Recommended configuration:

- Service type: Web (Docker)
- Expose port: `80`
- Set these environment variables in Railway:
  - `APP_ENV=prod`
  - `APP_DEBUG=0`
  - `APP_SECRET` (must be a real secret)
  - `DATABASE_URL` (set to your Railway database connection string)
  - `RUN_MIGRATIONS=1` (optional)

Important notes:

- The provided `docker-compose.yaml` includes MySQL for local development.
- On Railway, you typically attach an external database instead of running MySQL inside the same stack.
- If you attach an external DB, ensure `DATABASE_URL` uses the correct host/port for that provider.

---

## What to submit

- Link of your application
- Recorded video containing (5-10 mins):
  - Explanation of the Dockerfile setup (1–2 mins)
  - Explanation of the Nginx configuration (1–2 mins)
  - Environment variable setup overview (1 min)
  - Deployment process walkthrough (2–3 mins)
  - Final proof that the deployed version is working correctly (1–2 mins)

---

## Grading Rubric (Total: 100 Points)

| Category                              | Description                                           | Points |
| ------------------------------------- | ----------------------------------------------------- | ------ |
| **Docker Setup**                      | Dockerfile and docker-compose are correct and working | 25     |
| **Nginx Configuration**               | Correct routing to PHP-FPM and proper Symfony setup   | 15     |
| **Symfony Production Setup**          | Production mode, caching, and stable runtime          | 15     |
| **Environment & Security**            | Proper .env usage and secure configuration            | 10     |
| **Database Integration**              | Working database connection and CRUD/migrations       | 10     |
| **Deployment**                        | Successfully deployed and accessible live application | 15     |
| **Understanding (Video Explanation)** | Clear explanation of Docker, Nginx, and deployment    | 7      |
| **Video Presentation Quality**        | Clear, complete, and within 5–10 minutes              | 3      |

