# Cascade TODO

## Performance Optimizations

### ETS Caching Layer

**Status**: Not implemented (removed in favor of Postgres-only for correctness)

**Context**: The StateManager previously used ETS (in-memory) tables for fast state lookups, but this created synchronization issues where state updates in ETS weren't immediately reflected in Postgres. This caused bugs where:
- Tasks showed as "pending" in the UI even after completion
- `started_at` field was nil in the database
- Status updates had significant lag

**Solution Implemented**: Switched to Postgres-only state management for correctness and observability.

**Future Improvement**: Add an ETS caching layer on TOP of Postgres for read-heavy operations:

1. **Write-through cache**: All state updates go directly to Postgres first, then update ETS
2. **Cache invalidation**: Clear ETS entries when Postgres is updated
3. **Read strategy**:
   - Check ETS first for hot data (active jobs)
   - Fall back to Postgres if not in cache
   - Populate cache on Postgres reads
4. **Benefits**:
   - ~10-100x faster state lookups for active jobs
   - No stale data issues (Postgres is source of truth)
   - Better scalability for high job volumes

**Acceptance Criteria**:
- All state persistence tests pass
- No stale data in ETS
- Performance improvement measured and documented
- ETS cache TTL strategy implemented

**Estimated Impact**: Could reduce scheduler loop time from ~100ms to ~10ms for typical workloads.

---

## Worker Pool Enhancements

### Dynamic Worker Pool Scaling

**Priority**: Medium

**Context**: Currently, worker count is fixed at startup via `CASCADE_WORKERS` env variable. With a fixed pool:
- Too few workers → tasks queue up, poor throughput
- Too many workers → wasted resources when idle
- No adaptation to varying load

**Proposed Solution**: Auto-scale worker pool based on queue depth and system load.

**Implementation**:
1. **Monitor queue depth**: Track pending tasks in PubSub
2. **Scale up**: Add workers when `pending_tasks > workers * threshold` (e.g., 2x)
3. **Scale down**: Remove idle workers after timeout (e.g., 5 minutes)
4. **Configuration**:
   - `CASCADE_MIN_WORKERS` - Minimum workers to keep alive (default: 2)
   - `CASCADE_MAX_WORKERS` - Maximum workers allowed (default: 32)
   - `CASCADE_SCALE_THRESHOLD` - Tasks per worker before scaling up (default: 2)

**Benefits**:
- Better resource utilization
- Automatic adaptation to load spikes
- Lower idle costs

**Acceptance Criteria**:
- Workers scale up under heavy load
- Workers scale down when idle
- Min/max bounds respected
- No task drops during scaling

**Estimated Impact**: 30-50% reduction in average resource usage while maintaining throughput.

---

### Distributed Workers (Multi-Node)

**Priority**: Low (future optimization)

**Context**: Currently all workers run on a single node. For very high throughput or specialized workloads, distributing workers across multiple nodes/machines would enable:
- Horizontal scaling beyond single-machine limits
- Fault tolerance (node crashes don't kill all workers)
- Geographic distribution
- Hardware specialization (GPU workers, high-memory workers, etc.)

**Implementation**:
1. **Distributed Erlang setup**: Connect nodes into a cluster
2. **Worker registration**: Workers announce capabilities to a registry
3. **Task routing**: Scheduler routes tasks based on requirements
4. **Node monitoring**: Detect node failures and redistribute work

**Prerequisites**:
- Distributed Erlang cluster setup
- Network infrastructure (libcluster or similar)
- Monitoring/observability for multi-node debugging

**Benefits**:
- Scale beyond single machine
- Hardware specialization
- Better fault tolerance

**Acceptance Criteria**:
- Tasks execute on multiple nodes
- Node failures handled gracefully
- Performance benchmarks show linear scaling

**Estimated Impact**: Could support 10-100x higher throughput depending on workload.

---

### Worker Specialization

**Priority**: Low (future feature)

**Context**: Some tasks may require specific resources (GPU, high memory, external credentials). Currently all workers are identical and can run any task.

**Proposed Solution**: Worker pools specialized by task type.

**Implementation**:
1. **Worker tags**: Workers declare capabilities (e.g., `gpu`, `high_memory`)
2. **Task requirements**: Tasks specify required worker capabilities
3. **Routing**: Scheduler only dispatches tasks to compatible workers
4. **Separate pools**: Different supervision trees for different worker types

**Use Cases**:
- GPU-intensive tasks → GPU workers
- High-memory tasks → large RAM workers
- External API tasks → workers with credentials/network access

**Benefits**:
- Better resource utilization
- Isolation of specialized workloads
- Cost optimization (expensive resources only when needed)

**Acceptance Criteria**:
- Tasks routed to correct worker type
- Fallback behavior when no specialized worker available
- Clear error messages for unsatisfiable requirements

**Estimated Impact**: Enables new use cases, reduces costs for mixed workloads.

---

## Other Future Work

(Add other TODOs here as they come up)
