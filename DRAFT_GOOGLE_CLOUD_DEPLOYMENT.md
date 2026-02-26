# TAG App – Google Cloud Run Deployment Guide

This guide documents how to deploy the TAG application to **Google Cloud Run**. Each command is followed by an explanation and how to test it works.

---


**Preliminary Setup: Install and Configure Google Cloud CLI**

Before enabling APIs or creating any cloud resources, you must:

- Install the Google Cloud CLI (gcloud)
- Authenticate with your Google account
- Connect the CLI to your project

This ensures all commands run against the correct Google Cloud project.

---

### 1. Install Google Cloud CLI

Install the Google Cloud CLI from the official source:

https://cloud.google.com/sdk/docs/install

After installation, verify:

```bash
gcloud --version
```

Expected output should include version information.

If the command is not found, ensure:
- The installer completed successfully
- gcloud is added to your system PATH

---

### 2. Initialize gcloud

Run:

```bash
gcloud init
```

This will:
- Open a browser window
- Prompt you to log into your Google account
- Allow you to select or create a project

If this is your first time using Google Cloud on this machine, this step is required.

---

### 3. Authenticate (If Already Initialized)

If gcloud is already installed but you need to re-authenticate:

```bash
gcloud auth login
```

Verify authentication:

```bash
gcloud auth list
```

Your active account should be listed with:

ACTIVE: *

---

### 4. Set the Active Project

All gcloud commands run against the currently active project.

Set the project explicitly:

```bash
gcloud config set project capstone-tool-assisted-grading
```

Verify:

```bash
gcloud config get-value project
```

Expected output:

capstone-tool-assisted-grading

---

### 5. (Optional) Confirm Project Exists

To verify the project is accessible:

```bash
gcloud projects list
```

Ensure capstone-tool-assisted-grading appears in the list.

---

---

## Overview for the Deployment

This deployment uses:
- `Dockerfile` for building the app container
- `cloudbuild.yaml` for CI/CD automation with Google Cloud Build
- `docker-compose.yml` for optional local development
- Cloud SQL (PostgreSQL) for the production database


## Prerequisites

You need:
- Access to a Google Cloud project with billing enabled
- Permissions to manage Cloud Build, Cloud Run, Artifact Registry, Cloud SQL, Secret Manager
- A GitHub repository containing this project

**Test:**
```bash
gcloud auth list
gcloud projects list
```
You should see your account and project listed.
**In Google Cloud Console:**
- Go to the main dashboard and verify your project is selected in the top bar.
- Check "IAM & Admin > IAM" to see your account and permissions.


## Clone the Repo

Download the project code to your local machine:
```bash
git clone https://github.com/YOUR_ORG/YOUR_REPO.git
cd YOUR_REPO
```
**Test:**
Run `ls` and check that the project files exist in your directory.
**In Google Cloud Console:**
- (No direct UI check for this step; this is a local operation.)


## Enable Google Cloud APIs

Enable all necessary Google Cloud APIs:
```bash
gcloud services enable run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com
```
**Explanation:** This ensures all required Google Cloud services are available for deployment and management.
**Test:**
You should see confirmation messages for each API.
**In Google Cloud Console:**
- Go to "APIs & Services > Enabled APIs & services" and confirm all required APIs are enabled.


## Set Up Cloud SQL (PostgreSQL)


Create a managed PostgreSQL database for your app:

```bash
# 1. Create a Cloud SQL instance (replace INSTANCE_ID and REGION as needed)
gcloud sql instances create tag-app-db \
  --database-version=POSTGRES_14 \
  --tier=db-f1-micro \
  --region=us-central1

# 2. Create a database
gcloud sql databases create tag_app_production --instance=tag-app-db

# 3. Create a user (replace YOUR_PASSWORD with a strong password)
gcloud sql users create rails_user --instance=tag-app-db --password=YOUR_PASSWORD

# 4. Get the instance connection name
gcloud sql instances describe tag-app-db --format='value(connectionName)'
```

**Explanation & How to Test in Google Cloud Console:**
- The first command creates a new PostgreSQL Cloud SQL instance named `tag-app-db` in the `us-central1` region.
  - **Test:** In the Google Cloud Console, go to "SQL > Instances" and confirm you see `tag-app-db` listed. Click on it to view details.
- The second command creates a database named `tag_app_production` inside that instance.
  - **Test:** In the Console, click your instance, then the "Databases" tab. You should see `tag_app_production` listed.
- The third command creates a user `rails_user` with your chosen password.
  - **Test:** In the Console, click your instance, then the "Users" tab. You should see `rails_user` listed.
- The fourth command outputs the instance connection name needed for Cloud Run.
  - **Test:** In the Console, click your instance and look for the "Instance connection name" field on the "Overview" tab. It should match the output from the command.


## Store Required Secrets

Store sensitive values (Rails secret key, DB password) securely in Secret Manager and grant access to Cloud Build:
```bash
echo -n "YOUR_SECRET_KEY_BASE" | gcloud secrets create secret-key-base --data-file=-
echo -n "YOUR_DB_PASSWORD" | gcloud secrets create db-password --data-file=-

gcloud secrets add-iam-policy-binding secret-key-base \
  --member="serviceAccount:$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```
**Explanation:** This stores your secrets securely and allows Cloud Build to access them during deployment.
**Test:**
**In Google Cloud Console:**

Store sensitive values (Rails secret key, DB password) securely in Secret Manager and grant access to Cloud Build and Cloud Run:

```bash
# Create secrets
echo -n "YOUR_SECRET_KEY_BASE" | gcloud secrets create secret-key-base --data-file=-
echo -n "YOUR_DB_PASSWORD" | gcloud secrets create db-password --data-file=-

# Grant Secret Manager access to Cloud Build service account (for CI/CD builds)
gcloud secrets add-iam-policy-binding secret-key-base \
  --member="serviceAccount:$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Grant Secret Manager and Cloud SQL access to Cloud Run service account (for deployed app)
# Replace YOUR_PROJECT_NUMBER and YOUR_PROJECT_ID with your actual values
gcloud secrets add-iam-policy-binding secret-key-base \
  --member="serviceAccount:YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/cloudsql.client"
```

**Explanation:**
- The first set of commands grants Secret Manager access to the Cloud Build service account (for CI/CD builds).
- The second set grants Secret Manager Secret Accessor and Cloud SQL Client roles to the Cloud Run service account (for the deployed app to access secrets and Cloud SQL).

**Test:**
- Run `gcloud secrets list` to see your secrets.
- Run `gcloud secrets versions access latest --secret=secret-key-base` to verify the value (if you have access).
- In IAM, confirm both service accounts have the correct roles.

**In Google Cloud Console:**
- Go to "Security > Secret Manager" and confirm `secret-key-base` and `db-password` are listed.
- Click each secret to view versions and access permissions.
- Go to "IAM & Admin > IAM" and confirm both Cloud Build and Cloud Run service accounts have the correct roles.


## Create Artifact Registry Repository

Create a Docker repository to store your app's container images:
```bash
gcloud artifacts repositories create spring2026-tag-repo \
  --repository-format=docker \
  --location=us-central1 \
  --description="Docker repository for TAG app"
```
**Explanation:** Artifact Registry stores your Docker images so Cloud Run can access them.
**Test:**
Run `gcloud artifacts repositories list --location=us-central1` and confirm `spring2026-tag-repo` appears.
**In Google Cloud Console:**
- Go to "Artifact Registry > Repositories" and confirm `spring2026-tag-repo` is listed in the `us-central1` region.

---


## Push Docker Image to Artifact Registry

Build your Docker image and upload it to Artifact Registry so Cloud Run can deploy it:
```bash
gcloud builds submit --region=global \
  --tag us-central1-docker.pkg.dev/YOUR_PROJECT_ID/spring2026-tag-repo/tag-app
```
**Explanation:** This command builds your Docker image using the Dockerfile in your current directory and uploads it to Artifact Registry.
**Test:**
Run `gcloud artifacts docker images list us-central1-docker.pkg.dev/YOUR_PROJECT_ID/spring2026-tag-repo` and confirm your image appears.
**In Google Cloud Console:**
- Go to "Artifact Registry > Repositories > spring2026-tag-repo" and click on the repository to see your image and tags.


## Deploy to Cloud Run

Deploy your Docker image as a managed service on Cloud Run, connecting it to Cloud SQL and using secrets:
```bash
gcloud run deploy tag-app-service \
  --image us-central1-docker.pkg.dev/YOUR_PROJECT_ID/spring2026-tag-repo/tag-app \
  --region us-central1 \
  --platform managed \
  --add-cloudsql-instances=YOUR_PROJECT_ID:us-central1:tag-app-db \
  --set-env-vars=RAILS_ENV=production,RAILS_SERVE_STATIC_FILES=true \
  --set-secrets=SECRET_KEY_BASE=secret-key-base:latest,DB_PASSWORD=db-password:latest \
  --allow-unauthenticated
```

## Run Database Migrations and Seeds (optional)

Set up your production database schema and seed data:
```bash
# If using Docker:
docker run --rm -v $PWD:/app -w /app ruby:3.2.1-alpine \
  sh -c "apk add --no-cache build-base postgresql-dev nodejs yarn && \
         bundle install && \
         RAILS_ENV=production DATABASE_URL=your_db_url_here bundle exec rails db:migrate db:seed"
```


## CI/CD Automation (Optional but Recommended)

Automate build, push, and deploy steps using Cloud Build triggers.

**How to set up:**
1. Open Cloud Build in the Google Cloud Console.
2. Create a trigger for your repository to run on push to `main`.
3. Ensure your `cloudbuild.yaml` is present in the repo root.


## Deployment is Complete!

Your app is now live on Cloud Run.


## 🧹 Teardown Instructions (Optional)

Clean up all resources to avoid unnecessary charges:
```bash
gcloud run services delete tag-app-service --region=us-central1
gcloud sql instances delete tag-app-db --region=us-central1
gcloud artifacts repositories delete spring2026-tag-repo --location=us-central1
gcloud secrets delete secret-key-base
gcloud secrets delete db-password
```


## 📎 Notes for the Future Teams

Important reminders for future deployments:
- Update secret values before deployment
- Re-create Cloud SQL user/password and update secret
- Review and verify `cloudbuild.yaml` and `config/database.yml`
- Check that the deployed service is running via `gcloud run services list`