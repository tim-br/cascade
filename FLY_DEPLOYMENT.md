# Deploying Cascade to Fly.io

Simple, cost-effective deployment using SQLite and local task execution.

## Prerequisites

1. Install Fly CLI:
   ```bash
   curl -L https://fly.io/install.sh | sh
   ```

2. Sign up and log in:
   ```bash
   fly auth signup  # Or: fly auth login
   ```

## Initial Deployment

1. **Create the app:**
   ```bash
   fly apps create cascade  # Or use your preferred name
   ```

2. **Create persistent volume for SQLite:**
   ```bash
   fly volumes create cascade_data --region sea --size 1
   ```

3. **Set secrets:**
   ```bash
   # Generate and set secret key
   fly secrets set SECRET_KEY_BASE=$(openssl rand -base64 64)
   ```

4. **Deploy:**
   ```bash
   fly deploy
   ```

5. **Open the app:**
   ```bash
   fly open
   ```

## Configuration

### Regions

Change `primary_region` in `fly.toml` to your preferred region:
- `sea` - Seattle (US West)
- `iad` - Ashburn (US East)
- `lhr` - London
- `fra` - Frankfurt
- `syd` - Sydney

[Full list](https://fly.io/docs/reference/regions/)

### Scaling

**Vertical scaling (change VM size):**
```bash
# Increase memory
fly scale memory 1024  # 1GB RAM

# Increase CPUs
fly scale vm shared-cpu-2x  # 2x shared CPU
```

**Horizontal scaling (add machines):**
```bash
# Update fly.toml:
[auto_scaling]
  min_count = 1  # Keep 1 always running
  max_count = 4  # Scale up to 4 machines
```

### Cost Optimization

**Free tier (good for testing):**
```toml
[vm]
  memory_mb = 256

[auto_scaling]
  min_count = 0  # Scale to zero when idle
```

**Production (always-on):**
```toml
[vm]
  cpu_kind = "shared"
  memory_mb = 1024

[auto_scaling]
  min_count = 1  # Keep 1 running
  max_count = 2  # Add redundancy
```

## Adding DAGs

Upload DAG files to your deployed app:

```bash
# SSH into the running machine
fly ssh console

# Copy DAG files
fly ssh sftp shell
put my_dag.json /app/dags/
```

Or mount a local directory during development:
```bash
fly volumes create cascade_dags --size 1
```

Update `fly.toml`:
```toml
[[mounts]]
  source = "cascade_dags"
  destination = "/app/dags"
```

## Monitoring

```bash
# View logs
fly logs

# Check status
fly status

# SSH into machine
fly ssh console

# Monitor metrics
fly dashboard
```

## Database Access

```bash
# SSH into machine
fly ssh console

# Access database
cd /data
ls -lh cascade.db

# Copy database locally
fly ssh sftp get /data/cascade.db ./cascade_backup.db
```

## Costs

**Typical setup:**
- 1 shared-cpu-1x (512MB): ~$5/month
- 1GB persistent volume: ~$0.15/month
- **Total: ~$5-6/month**

**Free tier eligible:**
- Scale to zero when idle: **$0/month**
- Limited to 256MB RAM, slower startup

## Updating

```bash
# Deploy new version
fly deploy

# Rollback if needed
fly releases
fly releases rollback <version>
```

## Environment Variables

Set additional env vars:
```bash
fly secrets set CASCADE_WORKERS=8
fly secrets set DAGS_SCAN_INTERVAL=60
```

## Troubleshooting

**Container crashes:**
```bash
fly logs --verbose
```

**Database locked:**
```bash
# SQLite doesn't support multiple writers
# Ensure only 1 machine is writing:
fly scale count 1
```

**Out of memory:**
```bash
fly scale memory 1024
```

## Migration from Docker Compose

Your existing DAG files work as-is! Just:
1. Deploy to Fly.io
2. Copy DAG files to `/app/dags`
3. Access at your Fly.io URL

No code changes needed!
