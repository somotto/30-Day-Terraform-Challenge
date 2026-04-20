# Day 25 — Architecture Diagram

```mermaid
flowchart TD
    User(["👤 User\n(Browser)"])

    subgraph AWS["AWS Cloud (us-east-1)"]

        subgraph CF["CloudFront"]
            CFDist["CloudFront Distribution\nPriceClass_100\nHTTPS redirect\nDefault TTL: 3600s"]
        end

        subgraph S3["S3"]
            Bucket["S3 Bucket\nStatic Website Hosting\nindex.html / error.html"]
            Policy["Bucket Policy\ns3:GetObject → *"]
            PAB["Public Access Block\nblock_public_acls: false\nblock_public_policy: false"]
        end

        subgraph State["Remote State"]
            StateBucket["S3 Bucket\nterraform.tfstate"]
        end

    end

    subgraph Terraform["Terraform (local)"]
        TF["terraform apply\nenvs/dev/"]
    end

    User -->|"HTTPS request"| CFDist
    CFDist -->|"HTTP origin request"| Bucket
    Bucket --- Policy
    Bucket --- PAB
    TF -->|"provisions"| CFDist
    TF -->|"provisions"| Bucket
    TF -->|"stores state"| StateBucket
```

## Resource Summary

| Resource | Type | Purpose |
|---|---|---|
| `aws_s3_bucket` | S3 | Stores website files |
| `aws_s3_bucket_website_configuration` | S3 | Enables static website hosting |
| `aws_s3_bucket_public_access_block` | S3 | Allows public read access |
| `aws_s3_bucket_policy` | S3 | Grants `s3:GetObject` to everyone |
| `aws_s3_object` (x2) | S3 | Uploads `index.html` and `error.html` |
| `aws_cloudfront_distribution` | CloudFront | CDN — global HTTPS delivery |
| S3 remote backend | S3 | Stores Terraform state file |

## Request Flow

```
User → HTTPS → CloudFront Edge (PriceClass_100)
                    ↓ cache miss
             HTTP → S3 Website Endpoint
                    ↓
             Returns index.html / error.html
```
