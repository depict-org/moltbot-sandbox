---
name: depict-logs
description: Query Depict's central OpenSearch logs (logs.depict.ai) for container logs from the production Kubernetes clusters. Use when investigating errors, crashes, latency, or any "what happened in prod" question. Read-only access via the OpenSearch REST API.
---

# Depict central logs (logs.depict.ai)

All cluster container logs ship to a central OpenSearch. Humans browse them at
https://logs.depict.ai (Google SSO); you query the same data via the OpenSearch
REST API.

## Access

Credentials are in the environment (read-only user, writes are denied):

- `OPENSEARCH_LOGS_URL` (https://log-ingestion.depict.ai:9200)
- `OPENSEARCH_LOGS_USERNAME` / `OPENSEARCH_LOGS_PASSWORD`

The endpoint uses a self-signed cert, so pass `-k` to curl:

```bash
curl -sk -u "$OPENSEARCH_LOGS_USERNAME:$OPENSEARCH_LOGS_PASSWORD" \
  "$OPENSEARCH_LOGS_URL/_cat/indices?h=index,docs.count&s=index"
```

## Index patterns

One index per day, 14-day retention (ISM policy):

| Pattern | Source | Notable fields |
|---------|--------|----------------|
| `foundation-logs-ovh-*` | foundation-prod OVH k8s (realtime, smoketests, monitoring, ...) | `@timestamp`, `message`, `level`, `kubernetes.namespace_name`, `kubernetes.pod_name`, `kubernetes.container_name`, `kubernetes.labels.app`, `gitsha`, `span_id` |
| `foundation-production-*` | foundation-production GKE cluster | `@timestamp`, `msg`, `level`, `subsys`, `stream`, `count` |

Field shapes differ per source. When unsure, sample one doc
(`size: 1, sort @timestamp desc`) or check `GET <index>/_mapping` before
building a complex query.

## Query recipes

Errors in a namespace in the last hour:

```bash
curl -sk -u "$OPENSEARCH_LOGS_USERNAME:$OPENSEARCH_LOGS_PASSWORD" \
  "$OPENSEARCH_LOGS_URL/foundation-logs-ovh-*/_search" \
  -H 'Content-Type: application/json' -d '{
    "size": 20,
    "sort": [{"@timestamp": "desc"}],
    "query": {"bool": {"filter": [
      {"match": {"kubernetes.namespace_name": "foundation"}},
      {"match": {"level": "ERROR"}},
      {"range": {"@timestamp": {"gte": "now-1h"}}}
    ]}}
  }'
```

Full-text search across everything:

```bash
curl -sk -u "$OPENSEARCH_LOGS_USERNAME:$OPENSEARCH_LOGS_PASSWORD" \
  "$OPENSEARCH_LOGS_URL/foundation-*/_search" \
  -H 'Content-Type: application/json' -d '{
    "size": 20,
    "sort": [{"@timestamp": "desc"}],
    "query": {"bool": {"must": [{"query_string": {"query": "\"connection refused\""}}],
      "filter": [{"range": {"@timestamp": {"gte": "now-6h"}}}]}}
  }'
```

Log volume per pod (find crashloops / spammers):

```bash
curl -sk -u "$OPENSEARCH_LOGS_USERNAME:$OPENSEARCH_LOGS_PASSWORD" \
  "$OPENSEARCH_LOGS_URL/foundation-logs-ovh-*/_search" \
  -H 'Content-Type: application/json' -d '{
    "size": 0,
    "query": {"range": {"@timestamp": {"gte": "now-1h"}}},
    "aggs": {"pods": {"terms": {"field": "kubernetes.pod_name", "size": 15}}}
  }'
```

## Tips

- Always constrain `@timestamp` and use `size` limits; the prod indices have
  tens of millions of docs per day.
- Most fields here (e.g. `level`) are mapped as `text` WITHOUT a `.keyword`
  sub-field, so `term` filters silently return nothing — use `match` queries
  for filtering. Check `GET <index>/_mapping` when in doubt.
- `_cat/indices` 404s on a pattern means logs for that day rotated out
  (14-day retention).
- When sharing findings in Slack, quote the matching `message` lines and name
  the pod + timestamp so humans can find them in https://logs.depict.ai.
