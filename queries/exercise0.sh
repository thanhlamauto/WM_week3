#!/usr/bin/env bash
# Exercise 0 - Five Minutes to Searching (standalone Solr on port 8983)
# Usage: SOLR=http://localhost:8983 ./exercise0.sh
set -euo pipefail

SOLR=${SOLR:-http://localhost:8983}
COLL=bookstore
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$ROOT/data"

say() { printf '\n=== %s ===\n' "$*"; }

# Select helper: q <query> [extra curl args...]
q() {
  local query=$1; shift
  curl -sG "$SOLR/solr/$COLL/select" \
    --data-urlencode "q=$query" \
    --data-urlencode 'wt=json' "$@" \
    | jq '{numFound: .response.numFound, docs: [.response.docs[] | del(._version_, ._root_)]}'
}

say "1. Solr status"
curl -s "$SOLR/solr/admin/info/system?wt=json" \
  | jq '{solr: .lucene."solr-spec-version", java: .jvm.version, os: .system.name}'

say "2. Create collection $COLL (idempotent)"
if ! curl -s "$SOLR/api/collections" | jq -e --arg c "$COLL" '.collections[]? == $c' >/dev/null; then
  curl -s -X POST "$SOLR/api/collections" -H 'Content-Type: application/json' \
    --data-binary "{\"name\": \"$COLL\", \"numShards\": 1, \"replicationFactor\": 1}" | jq .
else
  echo "collection $COLL already exists"
fi

say "3. Define schema for $COLL"
curl -s -X POST "$SOLR/solr/$COLL/schema" -H 'Content-Type: application/json' --data-binary '{
  "add-field": [
    {"name": "title",       "type": "text_general", "multiValued": false},
    {"name": "category",    "type": "string",       "multiValued": false},
    {"name": "author",      "type": "text_general", "multiValued": false},
    {"name": "price",       "type": "pfloat",       "multiValued": false},
    {"name": "description", "type": "text_general", "multiValued": false}
  ],
  "add-copy-field": [
    {"source": "title",       "dest": "_text_"},
    {"source": "author",      "dest": "_text_"},
    {"source": "description", "dest": "_text_"}
  ]
}' | jq '{errors: (.errors // "none")}'

say "4. Index documents from $DATA/bookstore.json"
curl -s -X POST -H 'Content-Type: application/json' \
  --data-binary @"$DATA/bookstore.json" \
  "$SOLR/api/collections/$COLL/update?commit=true" | jq '{adds: .responseHeader.status, errors: (.error // "none")}'

say "5. Commit"
curl -s -X POST "$SOLR/solr/$COLL/update?commit=true" -H 'Content-Type: application/json' -d '{}' \
  | jq '{status: .responseHeader.status}'

say "6a. Match all documents  q=*:*"
q '*:*' --data-urlencode 'rows=3' --data-urlencode 'fl=id,title,category,author,price'

say "6b. Text field search  q=title:solr"
q 'title:solr'

say "6c. Exact field search  q=category:search"
q 'category:search' --data-urlencode 'fl=id,title,category'

say "6d. Filtered query  q=*:*&fq=category:web-mining"
q '*:*' --data-urlencode 'fq=category:web-mining' --data-urlencode 'fl=id,title,category'

say "6e. Multiple conditions  q=title:web AND category:web-mining"
q 'title:web AND category:web-mining' --data-urlencode 'fl=id,title,category'

say "6f. Phrase search  q=description:\"information retrieval\""
q 'description:"information retrieval"' --data-urlencode 'fl=id,title'

say "6g. Range filter + sort + field list  fq=price:[20 TO 50]&sort=price asc"
q '*:*' --data-urlencode 'fq=price:[20 TO 50]' --data-urlencode 'sort=price asc' \
  --data-urlencode 'fl=id,title,price' --data-urlencode 'rows=5'

say "6h. Catch-all copy field  q=_text_:solr"
q '_text_:solr' --data-urlencode 'fl=id,title'
