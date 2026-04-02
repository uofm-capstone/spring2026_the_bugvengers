# 📄 **CSV Parsing Plan (Qualtrics Survey Data)**

## **1\. File Structure Overview**

The CSV follows the Qualtrics export format with an additional metadata row:

* **Row 1:** Column names (e.g., `Q7`)  
* **Row 2:** Human-readable question text  
* **Row 3:** Internal metadata (`ImportId` JSON-like values)  
* **Row 4+:** Actual survey responses

**Decision:**

* Use **Row 1 as headers**  
* Skip **Rows 2 and 3**  
* Treat **Row 4 onward as actual data**

---

## **2\. Relevant Columns for LLM Processing**

Primary column:

* **`Q7` → Open-ended client feedback**

This column contains:

* Sentiment  
* Client satisfaction signals  
* Potential issues/conflicts

---

### **Potential Supporting Columns (Optional)**

* `Q1`, `Q1.1` → Team/project identifiers  
* `Q3–Q6` → Structured ratings (optional for later use)

---

## **3\. Columns to Ignore**

Ignore metadata/system fields:

* `StartDate`, `EndDate`  
* `Status`, `Progress`, `Finished`  
* `IPAddress`  
* `Duration (in seconds)`  
* `ResponseId`  
* `RecipientFirstName`, `RecipientLastName`, `Email`  
* `LocationLatitude`, `LocationLongitude`  
* `DistributionChannel`, `UserLanguage`

**Reason:** Not useful for sentiment or feedback analysis

---

## **4\. Data Cleaning Rules**

Before sending to the LLM:

* Remove:  
  * Empty or null (`NaN`) responses  
  * Rows where `Q7` is blank after trimming  
* Trim whitespace from all responses  
* Optionally normalize text (e.g., lowercase)  
* Skip metadata rows (e.g., values containing `"ImportId"`)  
* Ensure only valid human-written responses are included.

---

## **5\. Structured Output Format (Post-Parsing)**

\[

  {

    "team": "Team A",

    "responses": \[

      "not at this time",

      "communication could be better"

    \]

  }

\]

---

## **6\. Grouping Strategy**

* Group responses by **team identifier (`Q1` or similar)**  
    
* If unavailable:  
    
  * Use `"Unknown Team"`  
  * Or treat all responses as one dataset

---

## **7\. Edge Case Handling**

* Empty `Q7` → ignore  
* Missing team → `"Unknown Team"`  
* Very short responses → keep (LLM will interpret)

---

## **8\. Parsing Strategy (Implementation Plan)**

* Read CSV with headers from **Row 1**  
* Skip **Rows 2 and 3 explicitly**  
* Iterate starting from **Row 4**

For each row:

* Extract:  
    
  * `Q7` (feedback)  
  * Team identifier (if available)


* Append to grouped structure

---

# 💡 Optional Small Upgrade 

Detect and skip rows where values look like metadata (e.g., contain `"ImportId"`) to make the parser **more robust instead of hardcoded to row numbers**.

