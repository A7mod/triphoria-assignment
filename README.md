# Triphoria DevOps Assessment

Terraform infrastructure design, local database setup with backup/restore, and query optimization for a hotel booking system.

## Architecture

- VPC with public subnets (ALB) and private subnets (ECS tasks, RDS)
- Security group chain: ALB (open 80/443) → ECS (only from ALB) → RDS (only from ECS)
- RDS is not publicly accessible; reachable only from ECS tasks

## Repository Structure
infra/
modules/
network/   # VPC, subnets, NAT, security groups
ecs/       # ALB, ECS cluster, Fargate service/task
rds/       # RDS Postgres instance
envs/
dev/       # smaller instance, 1-day backup retention, deletion protection off
prod/      # larger instance, 30-day backup retention, deletion protection on, multi-AZ
docker/
docker-compose.yml
db/
migrations/  # schema + index
seed/        # seed data script
scripts/
backup.sh
restore.sh
.github/workflows/terraform.yml

## Part 1-3: Terraform

### Prerequisites
- Terraform >= 1.5
- AWS CLI (dummy credentials are sufficient — no real AWS account needed)

### Setup (one-time)
```bash
aws configure
# Enter any values, e.g.:
# AWS Access Key ID: AKIAFAKEFAKEFAKEFAKE
# AWS Secret Access Key: fakeSecretKeyDoesNotNeedToBeRealAtAll123
# Default region: us-east-1
```

The AWS provider is configured with `skip_credentials_validation`, `skip_requesting_account_id`, and `skip_metadata_api_check` so `terraform plan` runs fully offline without a real AWS account.

### Verify dev environment
```bash
cd infra/envs/dev
terraform init
terraform fmt -check
terraform validate
terraform plan -var-file="dev.tfvars" -refresh=false
```

### Verify prod environment
```bash
cd infra/envs/prod
terraform init
terraform fmt -check
terraform validate
terraform plan -var-file="prod.tfvars" -refresh=false
```

### Dev vs Prod differences

| Setting | Dev | Prod |
|---|---|---|
| RDS instance class | db.t3.micro | db.t3.small |
| Backup retention | 1 day | 30 days |
| Deletion protection | false | true |
| Multi-AZ | false | true |
| ECS task CPU/memory | 256/512 | 512/1024 |
| ECS desired count | 1 | 2 |
| Backend state file | dev.tfstate | prod.tfstate |

### CI/CD (GitHub Actions)

`.github/workflows/terraform.yml` runs on every PR touching `infra/**`, for both dev and prod in parallel:
- `terraform fmt -check`
- `terraform init`
- `terraform validate`
- `terraform plan -refresh=false`

The plan output is posted as a comment on the PR.

## Part 4-6: Local Database

### Prerequisites
- Docker Desktop (with WSL2 backend if on Windows)

### Start the database
```bash
cd docker
docker compose up -d
```

This starts Postgres 16 and automatically runs migrations from `db/migrations/` on first boot (via Postgres's `docker-entrypoint-initdb.d` mechanism).

### Verify tables were created
```bash
docker exec -it triphoria-postgres psql -U triphoria_admin -d triphoria -c "\dt"
```
Expected: `hotel_bookings` and `booking_events` tables listed.

### Load seed data
```bash
docker exec -i triphoria-postgres psql -U triphoria_admin -d triphoria < db/seed/seed.sql
```

This inserts 120 hotel bookings (across 6 cities including Delhi, 5 organizations, 4 statuses, dates spread over the last 90 days) and ~144 booking events linked to a subset of bookings.

### Verify seed data
```bash
docker exec -it triphoria-postgres psql -U triphoria_admin -d triphoria -c "SELECT COUNT(*) FROM hotel_bookings; SELECT COUNT(*) FROM booking_events;"
```
Expected: 120 and 144 (or similar counts, since some fields are randomized).

## Query Optimization

Target query:
```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

### Index added
```sql
CREATE INDEX idx_hotel_bookings_city_created_at
ON hotel_bookings (city, created_at);
```

**Why this index:**
- `city` is filtered with equality (`=`), so it's the leading column — allows Postgres to jump directly to matching rows.
- `created_at` is filtered with a range (`>=`), which works efficiently as the second column in a composite index, scanning a contiguous range within the already-narrowed city matches.
- A single composite index serves both conditions in one index scan, rather than requiring two separate indexes and a bitmap merge.
- `org_id` and `status` are only used in `GROUP BY`/`SELECT`, not `WHERE`, so they don't need to be part of the index for correctness.

**Note on EXPLAIN ANALYZE at this data size:** With only ~120 rows, Postgres's cost-based planner correctly chooses a sequential scan over the index, since the overhead of an index lookup exceeds the cost of scanning a small table directly. This is expected and correct behavior, not a failure of the index. To confirm the index is structured correctly and would be used at scale, you can force it explicitly:

```sql
SET enable_seqscan = off;
EXPLAIN ANALYZE SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
SET enable_seqscan = on;
```

This confirms Postgres uses a `Bitmap Index Scan` on `idx_hotel_bookings_city_created_at`, proving the index is correctly structured for this query pattern — it will be selected automatically once the table grows large enough that the planner's cost estimate favors it.

## Backup and Restore

### Create a backup
```bash
./scripts/backup.sh
```
Creates a timestamped SQL dump at `backups/triphoria_backup_<timestamp>.sql` using `pg_dump`.

### Restore from backup
```bash
./scripts/restore.sh
```
Without an argument, restores the most recent backup. To restore a specific file:
```bash
./scripts/restore.sh backups/triphoria_backup_20260707_100037.sql
```

The script drops and recreates the database, restores the dump, and prints row counts from both tables for verification.

### Verifying restore worked
After running `restore.sh`, the script automatically prints:
```sql
SELECT COUNT(*) FROM hotel_bookings;
SELECT COUNT(*) FROM booking_events;
```
Compare these counts against the counts before backup — a successful restore should show identical row counts (e.g., 120 and 144).

## Full End-to-End Test
```bash
cd docker
docker compose up -d
docker exec -i triphoria-postgres psql -U triphoria_admin -d triphoria < ../db/seed/seed.sql
cd ..
./scripts/backup.sh
./scripts/restore.sh
```