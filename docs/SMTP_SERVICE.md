# Email Provider Status — TAG
 
## Current Service Provider: SendGrid
 
TAG is temporarily using **SendGrid** while **Mailjet** hasn't been fully implemented. SendGrid's free trial likely has expired by the time future capstone students continue this project. 

Mailjet is preferred because its free tier covers TAG's low-volume use case and GCP credits do not apply to third-party email services. Once Mailjet is reinstated, switching back requires only a credential swap.
 
## Email Filtering — @memphis.edu Addresses
 
Emails sent to UofM addresses are likely to be **auto-filtered** until TAG sends from a verified custom domain with proper DNS authentication (SPF, DKIM, DMARC).
 
**In the meantime, students should check their spam folder from their personal email for TAG emails.**
