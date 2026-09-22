#!/usr/bin/env bash
# Final verification checklist - checks every requirement against the live cluster
# Usage: SOLR=http://localhost:8983 TIKA=http://localhost:9998 SOLR_DIR=$HOME/solr-lab/solr-10.0.0 ./verify.sh
set -uo pipefail

SOLR=${SOLR:-http://localhost:8983}
TIKA=${TIKA:-http://localhost:9998}
SOLR_DIR=${SOLR_DIR:-$HOME/solr-lab/solr-10.0.0}
PASS=0; FAIL=0

check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf '[PASS] %-45s %s\n' "$1" "$3"; PASS=$((PASS+1));
  else printf '[FAIL] %-45s expected=%s actual=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}

nf() { curl -sG "$SOLR/solr/$1/select" --data-urlencode "q=$2" --data-urlencode 'rows=0' \
       | jq -r '.response.numFound'; }

echo "== Web Mining Week 03 - final verification =="
echo

JAVA_MAJOR=$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
check "Java >= 21" "yes" "$([ "${JAVA_MAJOR:-0}" -ge 21 ] && echo yes || echo no)"

HTTP=$(curl -s -o /dev/null -w '%{http_code}' "$SOLR/solr/admin/info/system")
check "Solr HTTP API reachable" "200" "$HTTP"

NODES=$(curl -s "$SOLR/solr/admin/collections?action=CLUSTERSTATUS&wt=json" | jq '.cluster.live_nodes | length')
check "Two-node SolrCloud cluster alive" "2" "$NODES"

COLLS=$(curl -s "$SOLR/solr/admin/collections?action=LIST&wt=json" | jq -r '.collections | sort | join(",")')
check "Collections present" "bookstore,films,mydocs,techproducts" "$COLLS"

check "Exercise 0: bookstore documents" "8" "$(nf bookstore '*:*')"
check "Exercise 0: category:search" "3" "$(nf bookstore 'category:search')"
check "Exercise 0: fq=category:web-mining" "2" "$(curl -sG "$SOLR/solr/bookstore/select" \
  --data-urlencode 'q=*:*' --data-urlencode 'fq=category:web-mining' --data-urlencode 'rows=0' \
  | jq -r '.response.numFound')"

check "Exercise 1: techproducts documents" "48" "$(nf techproducts '*:*')"
check "Exercise 1: cat:electronics" "12" "$(nf techproducts 'cat:electronics')"
check "Exercise 1: +electronics +music" "1" "$(nf techproducts '+electronics +music')"

REPLICAS=$(curl -s "$SOLR/solr/admin/collections?action=CLUSTERSTATUS&collection=techproducts&wt=json" \
  | jq '[.cluster.collections.techproducts.shards[].replicas[]] | length')
ACTIVE=$(curl -s "$SOLR/solr/admin/collections?action=CLUSTERSTATUS&collection=techproducts&wt=json" \
  | jq '[.cluster.collections.techproducts.shards[].replicas[] | select(.state=="active")] | length')
check "Exercise 1: replicas active (2 shards x 2)" "4/4" "$ACTIVE/$REPLICAS"

check "Exercise 2: films documents" "1100" "$(nf films '*:*')"
check "Exercise 2: q=comedy" "417" "$(nf films 'comedy')"
DRAMA=$(curl -sG "$SOLR/solr/films/select" --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
  --data-urlencode 'facet=true' --data-urlencode 'facet.field=genre_str' \
  | jq -r '.facet_counts.facet_fields.genre_str as $f | ($f | index("Drama")) as $i | $f[$i+1]')
check "Exercise 2: facet genre_str Drama count" "552" "$DRAMA"

check "Exercise 3: Tika version" "Apache Tika 3.3.2" "$(curl -s "$TIKA/version")"
check "Exercise 3: mydocs documents (after delete)" "7" "$(nf mydocs '*:*')"
check "Exercise 3: PDF text searchable content:gazelle" "1" "$(nf mydocs 'content:gazelle')"
check "Exercise 3: HTML text searchable content:zeppelin" "1" "$(nf mydocs 'content:zeppelin')"
check "Exercise 3: update visible review_status:updated" "1" "$(nf mydocs 'review_status:updated')"
check "Exercise 3: deleted doc gone id:csv-003" "0" "$(nf mydocs 'id:csv-003')"
HANDLER=$(curl -s "$SOLR/solr/mydocs/config/requestHandler?componentName=/update/extract&wt=json" \
  | jq -r '.config.requestHandler["/update/extract"].class')
check "Exercise 3: extraction handler registered" "solr.extraction.ExtractingRequestHandler" "$HANDLER"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
