#!/usr/bin/env bash
# Exercise 1 - Techproducts on a two-node SolrCloud cluster (ports 8983 + 7574)
# Usage: SOLR=http://localhost:8983 SOLR_DIR=$HOME/solr-lab/solr-10.0.0 ./techproducts.sh
set -euo pipefail

SOLR=${SOLR:-http://localhost:8983}
SOLR_DIR=${SOLR_DIR:-$HOME/solr-lab/solr-10.0.0}
COLL=techproducts

say() { printf '\n=== %s ===\n' "$*"; }

q() {
  local query=$1; shift
  curl -sG "$SOLR/solr/$COLL/select" \
    --data-urlencode "q=$query" \
    --data-urlencode 'wt=json' "$@" \
    | jq '{numFound: .response.numFound, docs: [.response.docs[] | del(._version_, ._root_)]}'
}

say "1. Collection list"
curl -s "$SOLR/solr/admin/collections?action=LIST&wt=json" | jq .

say "2. Cluster topology (live nodes)"
curl -s "$SOLR/solr/admin/collections?action=CLUSTERSTATUS&wt=json" \
  | jq '{live_nodes: .cluster.live_nodes, collections: (.cluster.collections | keys)}'

say "3. Index example/exampledocs/* with the Post Tool"
( cd "$SOLR_DIR" && bin/solr post -c "$COLL" example/exampledocs/* )

say "4. Indexed document count"
q '*:*' --data-urlencode 'rows=0'

say "5a. Match all  q=*:*"
q '*:*' --data-urlencode 'rows=2' --data-urlencode 'fl=id,name,price'

say "5b. Field search  q=cat:electronics"
q 'cat:electronics' --data-urlencode 'rows=3' --data-urlencode 'fl=id,name,cat'

say "5c. Filter query + sort + field list  fq=price:[0 TO 100]&sort=price asc"
q '*:*' --data-urlencode 'fq=price:[0 TO 100]' --data-urlencode 'sort=price asc' \
  --data-urlencode 'fl=id,name,price' --data-urlencode 'rows=5'

say "5d. Phrase search  q=\"CAS latency\""
q '"CAS latency"' --data-urlencode 'fl=id,name'

say "5e. Boolean search  q=+electronics +music"
q '+electronics +music' --data-urlencode 'fl=id,name'

say "5f. Boolean exclusion  q=+electronics -music"
q '+electronics -music' --data-urlencode 'rows=0'

say "6. Collection topology details (shards, replicas, nodes)"
curl -s "$SOLR/solr/admin/collections?action=CLUSTERSTATUS&collection=$COLL&wt=json" \
  | jq '.cluster.collections.techproducts.shards
        | to_entries
        | map({shard: .key, state: .value.state,
               replicas: [.value.replicas[] | {core: .core, node: .node_name, state: .state, leader: .leader}]})'
