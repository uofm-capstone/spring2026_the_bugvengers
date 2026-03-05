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
gcloud config set project [PROJECT_ID]
```

Verify:

```bash
gcloud config get-value project
```

Expected output:

[PROJECT_ID]

---

### 5. (Optional) Confirm Project Exists

To verify the project is accessible:

```bash
gcloud projects list
```

Ensure [PROJECT_ID] appears in the list.

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
git clone https://github.com/[INSERT_GITHUB_ORG]/[INSERT_REPO_NAME].git
cd [INSERT_REPO_NAME]
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
gcloud sql instances create [DB_INSTANCE_NAME] \
  --database-version=POSTGRES_14 \
  --tier=db-f1-micro \
  --region=[REGION]

# 2. Create a database
gcloud sql databases create [DATABASE_NAME] --instance=[DB_INSTANCE_NAME]

# 3. Create a user (replace YOUR_PASSWORD with a strong password)
gcloud sql users create [DB_USERNAME] --instance=[DB_INSTANCE_NAME] --password=YOUR_PASSWORD

# 4. Get the instance connection name
gcloud sql instances describe [DB_INSTANCE_NAME] --format='value(connectionName)'
```

**Explanation & How to Test in Google Cloud Console:**
- The first command creates a new PostgreSQL Cloud SQL instance named `[DB_INSTANCE_NAME]` in the `[REGION]` region.
  - **Test:** In the Google Cloud Console, go to "SQL > Instances" and confirm you see `[DB_INSTANCE_NAME]` listed. Click on it to view details.
- The second command creates a database named `[DATABASE_NAME]` inside that instance.
  - **Test:** In the Console, click your instance, then the "Databases" tab. You should see `[DATABASE_NAME]` listed.
- The third command creates a user `[DB_USERNAME]` with your chosen password.
  - **Test:** In the Console, click your instance, then the "Users" tab. You should see `[DB_USERNAME]` listed.
- The fourth command outputs the instance connection name needed for Cloud Run.
  - **Test:** In the Console, click your instance and look for the "Instance connection name" field on the "Overview" tab. It should match the output from the command.


## Store Required Secrets

Store sensitive values (Rails secret key, DB password) securely in Secret Manager and grant access to Cloud Build and Cloud Run.

### Option 1: Using gcloud CLI (Recommended)

```bash
# Create the Rails secret key in Secret Manager
echo -n "YOUR_SECRET_KEY_BASE" | gcloud secrets create [SECRET_KEY_NAME] --data-file=-
# Create the database password in Secret Manager
echo -n "YOUR_DB_PASSWORD" | gcloud secrets create [DB_PASSWORD_SECRET_NAME] --data-file=-

# Grant Secret Manager access to Cloud Build service account (for CI/CD builds)
gcloud secrets add-iam-policy-binding [SECRET_KEY_NAME] \
  --member="serviceAccount:$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
  
# Grant Secret Manager access to Cloud Build for DB password
gcloud secrets add-iam-policy-binding [DB_PASSWORD_SECRET_NAME] \
  --member="serviceAccount:$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Grant Secret Manager access to Cloud Run service account (for deployed app)
gcloud secrets add-iam-policy-binding [SECRET_KEY_NAME] \
  --member="serviceAccount:[PROJECT_NUMBER]-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Grant Secret Manager access to Cloud Run for DB password
gcloud secrets add-iam-policy-binding [DB_PASSWORD_SECRET_NAME] \
  --member="serviceAccount:[PROJECT_NUMBER]-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Grant Cloud SQL Client role to Cloud Run service account
gcloud projects add-iam-policy-binding [PROJECT_ID] \
  --member="serviceAccount:[PROJECT_NUMBER]-compute@developer.gserviceaccount.com" \
  --role="roles/cloudsql.client"
```

**Test:**
- Run `gcloud secrets list` to see your secrets.
- Run `gcloud secrets versions access latest --secret=[SECRET_KEY_NAME]` to verify the value (if you have access).
- In IAM, confirm both service accounts have the correct roles.

### Option 2: Using Google Cloud Console

**Step 1: Create Secrets**

1. Go to "Security > Secret Manager".
2. Click "Create Secret".
3. For the first secret:
   - Name: `[SECRET_KEY_NAME]`
   - Secret value: Paste your Rails `SECRET_KEY_BASE`
   - Click "Create Secret"
4. Repeat for the second secret:
   - Name: `[DB_PASSWORD_SECRET_NAME]`
   - Secret value: Paste your database password
   - Click "Create Secret"

**Step 2: Grant Permissions to Cloud Build Service Account**

1. Still in "Secret Manager", click on `[SECRET_KEY_NAME]`.
2. Click the "Permissions" tab.
3. Click "Grant Access".
4. Under "New principals", enter: `[PROJECT_NUMBER]@cloudbuild.gserviceaccount.com`
5. Under "Role", select "Secret Manager Secret Accessor".
6. Click "Save".
7. Repeat steps 1-6 for `[DB_PASSWORD_SECRET_NAME]`.

**Step 3: Grant Permissions to Cloud Run Service Account**

1. Still in "Secret Manager", click on `[SECRET_KEY_NAME]`.
2. Click the "Permissions" tab.
3. Click "Grant Access".
4. Under "New principals", enter: `[PROJECT_NUMBER]-compute@developer.gserviceaccount.com`
5. Under "Role", select "Secret Manager Secret Accessor".
6. Click "Save".
7. Repeat steps 1-6 for `[DB_PASSWORD_SECRET_NAME]`.

**Step 4: Grant Cloud SQL Client Role to Cloud Run Service Account**

1. Go to "IAM & Admin > IAM".
2. Click the "Edit principal" (pencil icon) next to `[PROJECT_NUMBER]-compute@developer.gserviceaccount.com`.
3. Click "Add Another Role".
4. Search for "Cloud SQL Client" and select it.
5. Click "Save".

**In Google Cloud Console:**
- Go to "Security > Secret Manager" and confirm `[SECRET_KEY_NAME]` and `[DB_PASSWORD_SECRET_NAME]` are listed.
- Click each secret to view versions and access permissions.
- Go to "IAM & Admin > IAM" and confirm both Cloud Build and Cloud Run service accounts have the correct roles.


## Create Artifact Registry Repository

Create a Docker repository to store your app's container images:
```bash
gcloud artifacts repositories create [ARTIFACT_REGISTRY_REPO_NAME] \
  --repository-format=docker \
  --location=us-central1 \
  --description="Docker repository for TAG app"
```
**Explanation:** Artifact Registry stores your Docker images so Cloud Run can access them.
**Test:**
Run `gcloud artifacts repositories list --location=us-central1` and confirm `[ARTIFACT_REGISTRY_REPO_NAME]` appears.
**In Google Cloud Console:**
- Go to "Artifact Registry > Repositories" and confirm `[ARTIFACT_REGISTRY_REPO_NAME]` is listed in the `us-central1` region.

---


## Push Docker Image to Artifact Registry

Build your Docker image and upload it to Artifact Registry so Cloud Run can deploy it:
```bash
gcloud builds submit --region=global \
  --tag us-central1-docker.pkg.dev/[PROJECT_ID]/[ARTIFACT_REGISTRY_REPO_NAME]/tag-app
```
**Explanation:** This command builds your Docker image using the Dockerfile in your current directory and uploads it to Artifact Registry.
**Test:**
Run `gcloud artifacts docker images list us-central1-docker.pkg.dev/[PROJECT_ID]/[ARTIFACT_REGISTRY_REPO_NAME]` and confirm your image appears.
**In Google Cloud Console:**
- Go to "Artifact Registry > Repositories > [ARTIFACT_REGISTRY_REPO_NAME]" and click on the repository to see your image and tags.


## Deploy to Cloud Run

Deploy your Docker image as a managed service on Cloud Run, connecting it to Cloud SQL and using secrets.

```bash
gcloud run deploy [SERVICE_NAME] \
  --image us-central1-docker.pkg.dev/[PROJECT_ID]/[ARTIFACT_REGISTRY_REPO_NAME]/tag-app \
  --region us-central1 \
  --platform managed \
  --add-cloudsql-instances=[PROJECT_ID]:us-central1:[DB_INSTANCE_NAME] \
  --set-env-vars=RAILS_ENV=production,RAILS_SERVE_STATIC_FILES=true \
  --set-secrets=SECRET_KEY_BASE=[SECRET_KEY_NAME]:latest,DB_PASSWORD=[DB_PASSWORD_SECRET_NAME]:latest \
  --allow-unauthenticated
```

**Test:**
- Run `gcloud run services list --region=us-central1` and confirm `[SERVICE_NAME]` is listed with status `Active`.

**In Google Cloud Console:**
- Go to "Cloud Run" and confirm `[SERVICE_NAME]` is listed in the `[REGION]` region with a green checkmark.
- Click on the service to view its details, URL, and logs.
- Note the service URL (typically `https://[SERVICE_NAME]-xxxxx-uc.a.run.app`) and test it by opening it in your browser.

## Deployment is Complete!

Your app is now live on Cloud Run.


## 🧹 Teardown Instructions (Optional)

Clean up all resources to avoid unnecessary charges:
```bash
gcloud run services delete [SERVICE_NAME] --region=us-central1
gcloud sql instances delete [DB_INSTANCE_NAME] --region=us-central1
gcloud artifacts repositories delete [ARTIFACT_REGISTRY_REPO_NAME] --location=us-central1
gcloud secrets delete [SECRET_KEY_NAME]
gcloud secrets delete [DB_PASSWORD_SECRET_NAME]
```

# [Note to TA: Everything past this point is to be edited in Sprint 3]

## CI/CD Automation (Optional but Recommended)

Automate build, push, and deploy steps using Cloud Build triggers.

**How to set up:**
1. Open Cloud Build in the Google Cloud Console.
2. Create a trigger for your repository to run on push to `main`.
3. Ensure your `cloudbuild.yaml` is present in the repo root.

## 📎 Notes for the Future Teams

Important reminders for future deployments:
- Update secret values before deployment
- Re-create Cloud SQL user/password and update secret
- Review and verify `cloudbuild.yaml` and `config/database.yml`
- Check that the deployed service is running via `gcloud run services list`