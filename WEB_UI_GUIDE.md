# Cascade Web UI Guide

## 🎨 Live View UI - Complete!

The Cascade web UI has been fully implemented with 5 real-time LiveView pages.

## Starting the Web Server

```bash
# From project root
cd /Users/tim/cascade_project/cascade

# Start the Phoenix server
mix phx.server

# Or start with IEx for debugging
iex -S mix phx.server
```

Then visit **http://localhost:4000** in your browser!

## Pages Overview

### 1. Dashboard (`/`)
**Real-time overview of your Cascade cluster**

Features:
- 📊 **Stats Cards**: Total DAGs, Active Jobs, Success Rate, Worker Count
- 🔄 **Active Jobs Table**: See all running jobs with real-time status updates
- 📜 **Recent Jobs**: Last 10 jobs with duration and status
- ⚡ **Auto-refresh**: Updates every 5 seconds

![Dashboard shows job metrics and active executions]

---

### 2. DAGs List (`/dags`)
**Manage all your workflow definitions**

Features:
- 📋 **DAG Cards**: Grid view of all DAGs with metadata
- 🔀 **Enable/Disable Toggle**: Control which DAGs are active
- 📊 **Stats Per DAG**: Task count, job runs, schedule info
- 🆕 **Empty State**: Helpful message when no DAGs exist yet

Quick Actions:
- Click "View Details" to see DAG structure and trigger jobs
- Toggle DAGs on/off without deleting them
- See when each DAG was last updated

---

### 3. DAG Detail (`/dags/:id`)
**Deep dive into a specific DAG**

Features:
- 🚀 **Job Trigger Form**: Manually trigger jobs with custom JSON context
- 🎯 **DAG Structure Visualization**: See all tasks and their dependencies
- 📊 **Task Cards**: Visual representation of the workflow
- 📜 **Recent Jobs Table**: Last 20 job executions for this DAG
- 🔔 **Real-time Updates**: Get notified when jobs complete

Example: Trigger a job with custom context
```json
{
  "environment": "production",
  "batch_size": 1000,
  "notification_email": "team@example.com"
}
```

---

### 4. Job Detail (`/jobs/:id`)
**Real-time job execution monitoring**

Features:
- 📊 **Job Status Badge**: Large, color-coded status indicator
- ⏱️ **Timing Info**: Start time, duration, completion status
- 🎯 **Real-time Task Status**: Live updates as tasks execute
  - Pending, Running, Completed, Failed counts
  - Auto-refreshes every 2 seconds for active jobs
- 📋 **Task Execution Table**: Detailed view of each task
  - Task ID, Status, Type (local/lambda), Worker node
  - Duration, Retry count, Error messages
  - Expandable result viewer (JSON)
- 🔴 **Error Display**: Full error messages when tasks fail
- 💚 **Success Details**: View task output and results

Real-time Features:
- Tasks update status as they execute
- Flash messages when tasks complete
- Color-coded rows (running = blue, failed = red)
- Progress tracking for multi-task jobs

---

### 5. Workers (`/workers`)
**Monitor your distributed cluster**

Features:
- 🖥️ **Cluster Stats**: Total online workers, capacity, utilization
- 📊 **Worker Table**: All worker nodes with real-time heartbeats
- 📈 **Utilization Progress Bars**: Visual capacity tracking
- 🔴🟡🟢 **Status Indicators**: Online, Warning, Offline states
- ⏰ **Last Seen**: Time since last heartbeat
- 🌐 **Cluster Info**: Current node, connected nodes

Worker Status:
- **Online** (green): Last seen < 15 seconds ago
- **Warning** (yellow): Last seen 15-60 seconds ago
- **Offline** (red): Last seen > 60 seconds ago

---

## Quick Start Guide

### 1. Load Example DAG

```elixir
# In IEx or mix run
{:ok, dag} = Cascade.Examples.DAGLoader.load_etl_dag()
```

### 2. View in UI

1. Visit **http://localhost:4000/dags**
2. Click on "daily_etl_pipeline"
3. Scroll to "Trigger New Job"
4. Click "Trigger Job" (or add custom JSON context)
5. View job execution in real-time!

### 3. Monitor Execution

- The job page automatically updates as tasks execute
- See tasks progress from Pending → Running → Success
- View task execution times and results
- Get flash notifications when tasks complete

### 4. Check Workers

- Visit **http://localhost:4000/workers**
- See your 16 local worker processes
- Monitor capacity and utilization
- Watch heartbeats update in real-time

---

## UI Features

### Real-time Updates (via Phoenix PubSub)

All pages subscribe to relevant events and update automatically:

- **Dashboard**: Refreshes on job/worker events
- **DAG Detail**: Updates when new jobs are triggered
- **Job Detail**: Live task status changes
- **Workers**: Real-time heartbeat monitoring

### Responsive Design (Tailwind + DaisyUI)

- Mobile-friendly layouts
- Grid-based responsive design
- Beautiful card components
- Color-coded status badges
- Progress bars and stats

### Color Coding

**Job/Task Status:**
- 🟡 Pending/Queued: Yellow (warning)
- 🔵 Running: Blue (info)
- 🟢 Success: Green (success)
- 🔴 Failed: Red (error)
- ⚪ Cancelled/Skipped: Gray (ghost)

**Worker Status:**
- 🟢 Online: Green
- 🟡 Warning: Yellow
- 🔴 Offline: Red

---

## Navigation

The top navbar provides quick access:

```
🌊 Cascade  |  Dashboard  |  DAGs  |  Workers
```

- Click the Cascade logo to go home
- Current page is bold
- Consistent navigation across all pages

---

## Advanced Features

### JSON Context for Jobs

When triggering jobs, you can pass custom context:

```json
{
  "date": "2025-12-24",
  "environment": "staging",
  "dry_run": false,
  "batch_size": 500
}
```

This context is available to all tasks in the job via `context.config`.

### DAG Structure Visualization

The DAG detail page shows:
- All tasks as cards
- Task type badges (local/lambda)
- Dependencies listed below each task
- Visual flow of the workflow

### Task Result Viewing

Click "View Result" on completed tasks to see:
- Full JSON output
- Pretty-printed format
- Expandable/collapsible details

---

## Tips & Tricks

1. **Keep Job Detail page open** while a job runs to see real-time updates
2. **Use the Dashboard** to see all active work across DAGs
3. **Monitor Workers** to understand cluster health and capacity
4. **Trigger with context** to parameterize your workflows
5. **Check task errors** inline without leaving the job page

---

## Keyboard Shortcuts

- Click anywhere on a DAG card → Navigate to DAG detail
- Click "View" on any job row → Jump to job detail
- All links support browser back/forward navigation

---

## What's Next?

The UI is fully functional for Phase 1 (single-node)! Future enhancements:

**Phase 2+** (Distributed Clustering):
- Cluster topology visualization
- Worker add/remove controls
- Task distribution heatmap

**Phase 4+** (Advanced):
- DAG graph visualization with D3.js/Cytoscape
- Gantt chart for job timeline
- Cron schedule editor
- DAG version diff viewer
- Live log streaming
- Task retry controls

---

## Summary

✅ **Dashboard**: Overview & metrics
✅ **DAGs**: Workflow management
✅ **DAG Detail**: Trigger & monitor
✅ **Job Detail**: Real-time execution
✅ **Workers**: Cluster monitoring

All pages are **live**, **real-time**, and **responsive**!

Enjoy your Cascade workflow orchestrator! 🌊
