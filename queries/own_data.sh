#!/usr/bin/env bash
# Exercise 3 - Index Your Own Data (Tika server + extraction handler + CRUD)
# Usage: SOLR=http://localhost:8983 TIKA=http://localhost:9998 SOLR_DIR=$HOME/solr-lab/solr-10.0.0 ./own_data.sh
#
# Note: the Post Tool indexes extracted files with their absolute path as the
# document id (e.g. /Users/.../data/sample.pdf), so filename queries use id:*name
# and the update demo first looks up the real id.
set -euo pipefail

SOLR=${SOLR:-http://localhost:8983}
TIKA=${TIKA:-http://localhost:9998}
SOLR_DIR=${SOLR_DIR:-$HOME/solr-lab/solr-10.0.0}
COLL=mydocs
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$ROOT/data"

say() { printf '\n=== %s ===\n' "$*"; }

q() {
  local query=$1; shift
  curl -sG "$SOLR/solr/$COLL/select" \
    --data-urlencode "q=$query" --data-urlencode 'wt=json' "$@" \
    | jq '{numFound: .response.numFound, docs: [.response.docs[] | del(._version_, ._root_)]}'
}

say "1. External Tika server version"
curl -s "$TIKA/version" ; echo

say "1b. Direct Tika extraction from the PDF (proves the Tika server itself works)"
curl -s -X PUT -H "Content-Type: application/pdf" --data-binary @"$DATA/sample.pdf" \
  -H "Accept: text/plain" "$TIKA/tika" | grep -i gazelle

say "2. Create collection $COLL (2 shards x 2 replicas)"
if ! curl -s "$SOLR/api/collections" | jq -e --arg c "$COLL" '.collections[]? == $c' >/dev/null; then
  ( cd "$SOLR_DIR" && bin/solr create -c "$COLL" --shards 2 --replication-factor 2 )
else
  echo "collection $COLL already exists"
fi

say "3. Enable the /update/extract handler pointing at the external Tika server"
curl -s -X POST -H 'Content-type:application/json' -d '{
  "add-requesthandler": {
    "name": "/update/extract",
    "class": "solr.extraction.ExtractingRequestHandler",
    "tikaserver.url": "http://localhost:9998",
    "defaults": { "lowernames": "true", "captureAttr": "true" }
  }
}' "$SOLR/solr/$COLL/config" | jq '{errors: (.errors // "none")}'

say "4. Verify the handler is registered"
curl -s "$SOLR/solr/$COLL/config/requestHandler?componentName=/update/extract&wt=json" \
  | jq '.config.requestHandler["/update/extract"]
        | {name, class, tikaserver_url: ."tikaserver.url", defaults}'

say "5. Index the dataset in $DATA (txt, html, csv, pdf) through the extraction pipeline"
( cd "$SOLR_DIR" && bin/solr post -c "$COLL" \
    "$DATA/ai.txt" "$DATA/solr.txt" "$DATA/webmining.txt" \
    "$DATA/sample.html" "$DATA/sample.csv" "$DATA/sample.pdf" )

say "6. Indexed document count"
curl -sG "$SOLR/solr/$COLL/select" --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
  | jq '{numFound: .response.numFound}'

say "7a. Match all"
q '*:*' --data-urlencode 'rows=3' --data-urlencode 'fl=id,content_type'

say "7b. Keyword search over extracted text  q=content:\"information retrieval\""
q 'content:"information retrieval"' --data-urlencode 'fl=id'

say "7c. Filename query  q=id:*ai.txt"
q 'id:*ai.txt' --data-urlencode 'fl=id'

say "7d. PDF extraction proof  q=content:gazelle (word only exists inside sample.pdf)"
q 'content:gazelle' --data-urlencode 'fl=id'

say "7e. HTML extraction proof  q=content:zeppelin (word only exists inside sample.html body)"
q 'content:zeppelin' --data-urlencode 'fl=id'

say "7f. Metadata query  q=dc_title:Apache AND author:Web"
q 'dc_title:Apache AND author:Web' --data-urlencode 'fl=id,dc_title,author'

say "8. UPDATE: add review_status field, then atomic-update the ai.txt document"
curl -s -X POST -H 'Content-type:application/json' \
  --data-binary '{"add-field":{"name":"review_status","type":"string","stored":true}}' \
  "$SOLR/solr/$COLL/schema" | jq '{errors: (.errors // "none")}'

AI_ID=$(curl -sG "$SOLR/solr/$COLL/select" --data-urlencode 'q=id:*ai.txt' \
        | jq -r '.response.docs[0].id')
echo "document id = $AI_ID"

echo '-- before update: q=review_status:updated'
q 'review_status:updated' --data-urlencode 'rows=0'

curl -s -X POST -H 'Content-Type: application/json' \
  --data-binary '[{"id":"'"$AI_ID"'","review_status":{"set":"updated"}}]' \
  "$SOLR/solr/$COLL/update?commit=true" | jq '{status: .responseHeader.status}'

echo '-- after update: q=review_status:updated'
q 'review_status:updated' --data-urlencode 'fl=id,review_status'

say "9. DELETE: delete document csv-003 by id"
echo '-- before delete: q=id:csv-003'
q 'id:csv-003' --data-urlencode 'rows=0'

curl -s -X POST -H 'Content-Type: application/json' \
  --data-binary '{"delete":{"id":"csv-003"}}' \
  "$SOLR/solr/$COLL/update?commit=true" | jq '{status: .responseHeader.status}'

echo '-- after delete: q=id:csv-003'
q 'id:csv-003' --data-urlencode 'rows=0'

say "10. Final count"
q '*:*' --data-urlencode 'rows=0'
