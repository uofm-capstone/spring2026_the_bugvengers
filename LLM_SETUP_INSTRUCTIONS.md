# Local LLM Setup (Ollama on GCP VM)

## Overview

This document explains how to set up a **local Large Language Model (LLM)** using Ollama on a Google Cloud VM and connect it securely to the deployed Tool-Assisted Grading (TAG) application.

This setup was implemented to:

* Avoid external APIs (data privacy requirement)  
* Keep all processing within the same GCP project as the deployed app  
* Enable future LLM-based analysis of survey CSV data

---

## Architecture

Cloud Run (Rails App)

        ↓

Serverless VPC Connector

        ↓

Internal Network (VPC)

        ↓

GCP VM (Ollama LLM)

* No public access to the LLM  
* Communication happens over **internal IP only**

---

## Part 1 — Create the VM

### 1\. Navigate to:

Compute Engine → VM Instances → Create Instance

### 2\. Configure VM:

* **Name:** ollama-vm  
* **Region:** Same as Cloud Run (e.g., `us-central1`)  
* **Machine Type:** e2-standard-2 (or similar)  
* **Boot Disk:** Ubuntu (recommended)

### 3\. Create the instance and SSH into it

---

## Part 2 — Install and Run Ollama

### 1\. Install Ollama

Run inside the VM:

curl \-fsSL https://ollama.com/install.sh | sh

---

### 2\. Verify installation

ollama \--version

---

### 3\. Pull a model

ollama pull gemma:2b

---

### 4\. Test locally

ollama run gemma:2b

Example prompt:

Analyze sentiment: communication could be improved

---

## Part 3 — Enable Internal API Access (Secure Setup)

### 1\. Start Ollama API server

OLLAMA\_HOST=0.0.0.0 ollama serve

This allows the model to accept HTTP requests.

---

### 2\. Get VM Internal IP

hostname \-I

Example:

10.x.x.x

Save this for later use.

---

### 3\. Create Firewall Rule (Internal Only)

Navigate to:

VPC Network → Firewall → Create Firewall Rule

Configure:

* **Name:** allow-ollama-internal  
    
* **Direction:** Ingress  
    
* **Targets:** All instances (or use a VM tag)  
    
* **Source IP ranges:**  
    
  10.0.0.0/8  
    
* **Protocols and ports:**  
    
  tcp:11434

This allows only internal traffic to reach Ollama.

---

### 4\. Create Serverless VPC Connector

Navigate to:

VPC Network → Serverless VPC Access → Create Connector

Configure:

* **Name:** ollama-connector  
    
* **Region:** Same as VM and Cloud Run  
    
* **IP Range:**  
    
  10.8.0.0/28

---

### 5\. Attach Connector to Cloud Run

Navigate to:

Cloud Run → Service → Edit & Deploy New Revision

Under **Connections**:

* Enable: **Connect to a VPC**  
* Select: `ollama-connector`

Under **Egress Settings**:

* Select:  
    
  All traffic

Deploy the revision.

---

## Testing the API

### From the VM (local test):

curl http://localhost:11434/api/generate \\

  \-d '{

    "model": "gemma:2b",

    "prompt": "Say hello"

  }'

---

## Usage in Application (Future Work)

The Rails application will call the LLM using the VM’s internal IP:

http://10.x.x.x:11434/api/generate

This will be implemented in a service class (e.g., `LlmService`).

---

## Cost Management

* VM is billed **only while running**  
    
* Stop the VM when not in use:  
    
  Compute Engine → VM Instances → Stop  
    
* Disk storage (\~$2/month) persists even when stopped

---

## Security Notes

* The LLM is **not exposed to the public internet**  
* Access is restricted to internal GCP services  
* Meets project requirement for **data privacy**

Here’s a clean, well-formatted **Markdown version** you can paste directly into your README:

---

## Troubleshooting Common Connection Issues

Even with a correct setup, networking issues can occur when connecting Cloud Run to VPC resources (e.g., VM running Ollama or Cloud SQL). Below are common problems and how to resolve them in case you run into any.

---

### 1\. Cloud SQL Connection Timeouts (from Cloud Run)

**Symptom:** Cloud Run cannot connect to Cloud SQL and returns a **timeout error**, even with a VPC connector configured.

**Cause:** Cloud SQL is configured with both **Private IP and Public IP**, and traffic is not properly routing through the private connection.

**Solution:**

* **Verify Private IP Configuration**  
    
  * Go to Cloud SQL → Instance → *Connections*  
  * Ensure Private IP is enabled and connected to the correct VPC (`default`)


* **Disable Public IP**  
    
  * Turn off Public IP to force all traffic over the private connection  
  * Note: Instance will restart after this change


* **Check Private Service Access**  
    
  * Ensure a private service connection is established  
  * Confirm an IP range is allocated for Google services in your VPC

---

### 2\. VPC Connector Not Routing Traffic Properly

**Symptom:** Cloud Run cannot reach:

* Internal VM (Ollama), OR  
* External services

**Cause:** Misconfigured VPC connector or incorrect routing settings.

**Solution:**

* **Confirm VPC Network**  
    
  * Ensure the connector (e.g., `ollama-connector`) is using the correct VPC (`default`)


* **Check Egress Settings**  
    
  * In Cloud Run:  
      
    Egress: All traffic  
      
  * This ensures all outbound traffic flows through the VPC

---

### 3\. Firewall Rules Blocking Traffic

**Symptom:** Connections fail even though everything appears configured correctly.

**Cause:** Firewall rules are too restrictive.

**Solution:**

* **Ollama Firewall Rule**  
    
  * Confirm:  
      
    * Source IP range:  
        
      10.0.0.0/8  
        
    * Allowed ports:  
        
      tcp:11434

