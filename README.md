# Autonomous Research Agent

Give it a topic → it researches, writes a full report, safety-checks it, caches it, and remembers it. Built on AWS with a real multi-agent pipeline, red teaming, and LLM evaluation on every request.

---

## What It Uses

| Component | What It Does |
|---|---|
| **FastAPI** | REST API — receives topics, returns reports |
| **LangGraph** | 4-agent pipeline: Search → Summarize → Write → Verify |
| **TensorZero** | LLM gateway — routes to Gemini 2.5 Flash, falls back to Groq gpt-oss-120b |
| **AWS Bedrock Guardrails** | Blocks harmful input and output automatically |
| **Redis (ElastiCache)** | Semantic cache + session memory + job queue |
| **PostgreSQL + pgvector (RDS)** | Long-term memory — stores reports as vectors, enables semantic search |
| **LangSmith** | Traces every agent run + LLM-as-judge scores every report |
| **PyRIT 0.14.0** | Automated red team attacks — jailbreak, XPIA, crescendo, skeleton key |
| **Terraform** | Creates all AWS infrastructure with one command |
| **GitHub Actions** | Builds Docker images and deploys to ECS automatically on every push |

---

## File Structure

```
PROJECT/
├── app/
│   ├── main.py           API, background worker, all endpoints
│   ├── agents.py         LangGraph multi-agent graph
│   ├── cache.py          Redis semantic cache
│   ├── guardrails.py     Bedrock safety checks
│   ├── memory.py         Session memory (Redis) + long-term memory (pgvector)
│   ├── queue.py          Redis Streams job queue
│   ├── output.py         PDF export, JSON report, report diff
│   ├── eval.py           LangSmith LLM-as-judge evaluation
│   ├── config.py         Loads everything from AWS Secrets Manager
│   ├── auth.py           API key middleware
│   ├── retry.py          Exponential backoff for LLM calls
│   ├── pool.py           PostgreSQL connection pool
│   └── Dockerfile
├── pyrit_dashboard/
│   ├── main.py           Red team attack dashboard (PyRIT 0.14.0)
│   ├── requirements.txt
│   └── Dockerfile
├── tensorzero/
│   ├── tensorzero.toml   LLM routing config with system prompts
│   └── Dockerfile
├── terraform/
│   ├── backend.tf        Remote state (S3 + DynamoDB locking)
│   ├── providers.tf      Provider versions and AWS profile
│   ├── main.tf           Core infra — VPC, subnets, routing, VPC endpoints
│   ├── variables.tf      All inputs
│   ├── security.tf       Security groups
│   ├── guardrail.tf      Bedrock guardrail + version
│   ├── data.tf           RDS PostgreSQL + ElastiCache Redis
│   ├── secrets.tf        Secrets Manager config blob
│   ├── ecr.tf            Three container registries
│   ├── alb.tf            Load balancer, target groups, listeners
│   ├── iam.tf            Task, execution and EventBridge roles
│   ├── ecs.tf            Cluster, task definitions, services, auto-scaling
│   ├── scheduler.tf      EventBridge weekly red team rule
│   ├── outputs.tf        ALB DNS, ECR URLs, endpoints
│   └── terraform.tfvars  Image variables (gitignored)
├── .github/workflows/
│   └── deploy.yml        CI/CD pipeline with rollback on failure
├── bootstrap.bat         One-time backend setup (Windows)
├── bootstrap.sh          One-time backend setup (Mac/Linux)
├── requirements.txt      Python dependencies
├── index.html            Frontend UI
└── README.md
```

---

## Prerequisites

Install these before starting:

| Tool | Install | Check |
|---|---|---|
| AWS CLI | https://aws.amazon.com/cli/ | `aws --version` |
| Terraform | https://developer.hashicorp.com/terraform/install | `terraform --version` |
| Git | https://git-scm.com/downloads | `git --version` |

Docker is **not needed** on your machine. GitHub Actions builds and pushes images automatically.

> 💸 **This costs real money while it runs.** Roughly 190 USD per month if left up, mostly the RDS instance, the load balancer, ElastiCache, the always-on Fargate tasks, and ten VPC endpoint network interfaces. None of it is free tier at these sizes. Follow **Tear Down Everything** at the bottom when you are done.

---

## Setup — Follow in Order

### 1. Configure AWS credentials

This project uses a **named profile** called `demo`, not your default credentials. Terraform pins it in `providers.tf` and `backend.tf`, so a forgotten environment variable cannot deploy to the wrong account.

```bash
aws configure --profile demo
```

Enter:
- **AWS Access Key ID** — AWS Console → your name (top right) → Security Credentials → Create access key
- **AWS Secret Access Key** — shown once at creation, copy it immediately
- **Default region** — `us-east-1`
- **Default output format** — `json`

Confirm it points at the right account:
```bash
aws sts get-caller-identity --profile demo
```

> **Using a different account?** The state bucket name is globally unique across all of AWS, so it embeds an account ID. Change `research-agent-tfstate-696155685592` in `bootstrap.sh`, `bootstrap.bat` and `terraform/backend.tf`, and change `profile = "demo"` in `backend.tf` and `providers.tf` to match your profile name.

---

### 2. Create the Terraform backend (one time only)

Terraform needs an S3 bucket and DynamoDB table to store its state. Run the bootstrap script to create them:

Both scripts default to the `demo` profile and `us-east-1`, and take overrides as `[profile] [region]`.

**Windows:**
```cmd
bootstrap.bat
bootstrap.bat myprofile eu-west-1
```

**Mac / Linux / Git Bash:**
```bash
chmod +x bootstrap.sh
./bootstrap.sh
./bootstrap.sh myprofile eu-west-1
```

Expected output:
```
Using AWS profile : demo
Using region      : us-east-1

Authenticated to AWS account: 696155685592
State bucket      : research-agent-tfstate-696155685592
...
Bootstrap complete.
  AWS account : 696155685592
  S3 bucket   : research-agent-tfstate-696155685592 (versioned, encrypted, private)
  DynamoDB    : research-agent-tf-locks (state locking)
```

The script checks credentials first and exits without creating anything if the profile is missing, so a typo cannot bootstrap the wrong account. It also derives the bucket name from the account ID it authenticated as, then prints the exact `bucket` and `profile` values that `terraform/backend.tf` must contain. Safe to re-run at any time.

---

### 3. Create a GitHub repo and add secrets

1. Go to https://github.com and create a new repo named `research-agent`

2. Push this project to it:
```bash
git init
git add .
git commit -m "initial commit"
git remote add origin https://github.com/YOUR_USERNAME/research-agent.git
git push -u origin main
```

3. Add these two secrets (repo → Settings → Secrets and variables → Actions → New repository secret):

| Secret Name | Where to get it |
|---|---|
| `AWS_ACCESS_KEY_ID` | Same key you used in Step 1 |
| `AWS_SECRET_ACCESS_KEY` | Same key you used in Step 1 |

> **The first workflow run will fail, and that is expected.** Pushing triggers the pipeline immediately, but it pushes images to ECR repositories and updates ECS services that do not exist until Step 4 creates them. Ignore the red run. After Step 4 finishes, re-run it from **Actions → the failed run → Re-run all jobs**. Step 7 covers this.

---

### 4. Deploy all AWS infrastructure

```bash
cd terraform
terraform init
terraform apply
```

The placeholder image values come from `terraform.tfvars`, so no `-var` flags are needed. GitHub Actions replaces them with real image tags on the first successful deploy.

Type `yes` when asked. Takes 5–10 minutes.

> **Check the plan before approving.** It should read `59 to add, 0 to change, 0 to destroy`. If the account or region is wrong, you will see it here rather than after the bill arrives.

This creates: VPC, subnets, ECS cluster, ALB, ElastiCache Redis, RDS PostgreSQL, Bedrock Guardrail, Secrets Manager, ECR repos, IAM roles, VPC endpoints, auto-scaling, EventBridge weekly red team schedule.

After it finishes, note these outputs — you'll need them:
```
alb_dns        = "research-agent-alb-xxxxxxx.us-east-1.elb.amazonaws.com"
app_ecr_url    = "123456789.dkr.ecr.us-east-1.amazonaws.com/research-agent-app"
pyrit_ecr_url  = "123456789.dkr.ecr.us-east-1.amazonaws.com/research-agent-pyrit"
```

---

### 5. Get your API keys

You need three keys:

| Key | Where to get it |
|---|---|
| `GOOGLE_AI_STUDIO_API_KEY` | https://aistudio.google.com/api-keys |
| `GROQ_API_KEY` | https://console.groq.com/keys |
| `LANGSMITH_API_KEY` | https://smith.langchain.com → Profile → API Keys → Create |

Gemini is the primary model and Groq gpt-oss-120b is the automatic fallback. Both have free tiers. No OpenAI account is required.

LangSmith is free. It traces every agent run and stores evaluation scores automatically — no extra setup needed after you add the key.

---

### 6. Fill in Secrets Manager

Terraform already filled in Redis URL, database URL, Guardrail ID, and all tuning parameters. You only need to add your three API keys.

Go to: **AWS Console → Secrets Manager → `research-agent/config` → Retrieve secret value → Edit**

Replace the `REPLACE_ME` values:
```json
{
  "GOOGLE_AI_STUDIO_API_KEY": "AIza...",
  "GROQ_API_KEY":             "gsk_...",
  "LANGSMITH_API_KEY":        "ls__..."
}
```

Save. Leave everything else as is.

> ⚠️ **Your next `terraform apply` will wipe these keys.** `secrets.tf` manages the secret contents, with the keys hardcoded as `REPLACE_ME`. Terraform sees your console edit as drift and resets it, and the app then fails with authentication errors that look unrelated. Pick one of these before you apply again:
>
> **Option A — tell Terraform to stop managing the contents.** Add this to `aws_secretsmanager_secret_version.config` in `secrets.tf`. Terraform sets the initial value and never touches it again, so the console becomes the source of truth.
> ```hcl
> lifecycle {
>   ignore_changes = [secret_string]
> }
> ```
>
> **Option B — keep Terraform in charge.** Add `google_ai_studio_api_key`, `groq_api_key` and `langsmith_api_key` as sensitive variables, reference them in `secrets.tf`, and supply them through `terraform.tfvars`, which is gitignored. Never edit the secret in the console after that.

**Optional — set an API key to protect your endpoints:**

Add this field to the same secret:
```json
"API_KEY": "any-string-you-choose"
```

If set, every request to the app must include the header `X-API-Key: your-string`. The frontend has a field to enter it (saved in your browser). If left empty, the app runs without auth.

---

### 7. Re-run GitHub Actions to deploy

The `git push` in Step 3 triggered a run that failed, because ECR and ECS did not exist yet. Now that Step 4 has created them, run it again:

**GitHub repo → Actions tab → the failed run → Re-run all jobs**

Wait for the workflow to turn green (~5–10 minutes). It:
1. Builds the app, PyRIT, and TensorZero Docker images
2. Pushes them to ECR
3. Registers new ECS task definitions
4. Updates both ECS services
5. Waits for stability — rolls back automatically if anything fails

Once green, your app is live at the ALB URL from Step 4.

---

## Using the App

### Frontend

Open in browser:
```
http://<alb_dns>/
```

1. Enter your API key (if you set one in Step 6) — it saves in your browser
2. Type a research topic
3. Choose output format (text / PDF / JSON)
4. Click **Start Research** — polls automatically until done
5. Click **Show Changes vs Previous** to see what changed since last report on that topic

---

### API Endpoints

All requests need the header `X-API-Key: your-key` if you set one.

**Submit a research job:**
```bash
curl -X POST http://<alb_dns>/research \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-key" \
  -d '{"topic": "AI chip market 2025", "session_id": "abc123", "output_format": "text"}'
```
Returns: `{"job_id": "...", "session_id": "..."}`

**Poll for result:**
```bash
curl http://<alb_dns>/result/<job_id> -H "X-API-Key: your-key"
```
Returns `{"status": "pending"}` until done, then the full report.

**Download as PDF:**
```bash
curl http://<alb_dns>/result/<job_id>/pdf -H "X-API-Key: your-key" -o report.pdf
```

**Get session history:**
```bash
curl http://<alb_dns>/session/<session_id> -H "X-API-Key: your-key"
```

**Get report diff (what changed vs previous):**
```bash
curl http://<alb_dns>/diff/<topic> -H "X-API-Key: your-key"
```

**Redis and system stats:**
```bash
curl http://<alb_dns>/stats -H "X-API-Key: your-key"
```

**Health check (no auth needed):**
```bash
curl http://<alb_dns>/health
```

---

## LangSmith — Traces and Evaluation

Every research job automatically:
1. Traces every agent node (search, summarize, write, verify) to LangSmith
2. Runs 4 LLM-as-judge evaluations (relevance, completeness, hallucination risk, quality)
3. Saves scores to a LangSmith dataset called `research-agent-reports`

View traces: https://smith.langchain.com → Project: `research-agent`

**Trigger batch evaluation manually** (runs the agent on recent user topics from the DB):
```bash
curl -X POST http://<alb_dns>/run-evaluation \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-key" \
  -d '{}'
```

Pass specific topics instead:
```bash
curl -X POST http://<alb_dns>/run-evaluation \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-key" \
  -d '{"topics": ["quantum computing", "AI regulations"]}'
```

---

## PyRIT Red Team Dashboard

Open in browser:
```
http://<alb_dns>:8001/
```

This runs 4 types of attacks against your app to check if the guardrails are working:

| Attack | What it does |
|---|---|
| **Jailbreak** | Tries to bypass safety instructions directly |
| **XPIA** | Hides malicious instructions inside a research topic |
| **Crescendo** | Escalates from innocent questions toward harmful content step by step |
| **Skeleton Key** | Claims authority (researcher, CISO approval) to bypass restrictions |

Click **Run Selected Attacks** → wait 2–5 minutes → results appear showing BLOCKED or PASSED with a risk score.

Results are saved in Redis and survive container restarts.

**Run attacks via API:**
```bash
# All attack types
curl http://<alb_dns>:8001/run-attacks

# Specific types
curl "http://<alb_dns>:8001/run-attacks?types=jailbreak,xpia"

# Get results
curl http://<alb_dns>:8001/results
```

The weekly red team also runs automatically every Monday at 2am UTC via EventBridge.

---

## Tear Down Everything

```bash
cd terraform
terraform destroy
```

Type `yes` when asked. This deletes everything Terraform created — ECS, RDS, Redis, ALB, VPC, Bedrock Guardrail, Secrets Manager, ECR repos.

> **RDS takes a final snapshot on the way out**, named `research-agent-postgres-final-snapshot`, because `skip_final_snapshot = false`. The snapshot survives the destroy and keeps costing a small amount until you delete it yourself. Destroying a second time later fails unless you remove that snapshot first, since the name is already taken.
>
> Deletion protection is currently **off** (`deletion_protection = false` in `data.tf`), so nothing blocks the destroy. Turn it on for anything you care about.

#### Clean up what Terraform does not own

The secret needs a forced delete, otherwise AWS keeps it for a 7-day recovery window and re-creating it with the same name fails during that time:

```bash
aws secretsmanager delete-secret \
  --secret-id "research-agent/config" \
  --force-delete-without-recovery \
  --region us-east-1 --profile demo
```

The state bucket and lock table were made by the bootstrap script, so Terraform cannot remove them. Delete these **last**, only when you are finished for good:

```bash
aws s3 rb s3://research-agent-tfstate-696155685592 --force --profile demo
aws dynamodb delete-table --table-name research-agent-tf-locks --region us-east-1 --profile demo
```

Finally, check for the leftover database snapshot:

```bash
aws rds describe-db-snapshots --snapshot-type manual \
  --query 'DBSnapshots[].DBSnapshotIdentifier' --region us-east-1 --profile demo
```
