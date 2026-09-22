#!/usr/bin/env bash
# Exercise 2 - Films: schema + faceting (SolrCloud, ports 8983 + 7574)
# Usage: SOLR=http://localhost:8983 SOLR_DIR=$HOME/solr-lab/solr-10.0.0 ./films.sh
set -euo pipefail

SOLR=${SOLR:-http://localhost:8983}
SOLR_DIR=${SOLR_DIR:-$HOME/solr-lab/solr-10.0.0}
COLL=films

say() { printf '\n=== %s ===\n' "$*"; }

facet() {  # facet <curl args...>
  curl -sG "$SOLR/solr/$COLL/select" --data-urlencode 'wt=json' "$@" \
    | jq '{numFound: .response.numFound, facet_counts: .facet_counts}'
}

say "1. Create collection $COLL (2 shards x 2 replicas, _default configset)"
if ! curl -s "$SOLR/api/collections" | jq -e --arg c "$COLL" '.collections[]? == $c' >/dev/null; then
  ( cd "$SOLR_DIR" && bin/solr create -c "$COLL" --shards 2 --replication-factor 2 )
else
  echo "collection $COLL already exists"
fi

say "2. Schema: define 'name' field (so the first film '.45' is not guessed as float)"
curl -s -X POST -H 'Content-type:application/json' \
  --data-binary '{"add-field": {"name":"name", "type":"text_general", "multiValued":false, "stored":true}}' \
  "$SOLR/solr/$COLL/schema" | jq '{errors: (.errors // "none")}'

say "3. Schema: catch-all copy field * -> _text_"
curl -s -X POST -H 'Content-type:application/json' \
  --data-binary '{"add-copy-field" : {"source":"*","dest":"_text_"}}' \
  "$SOLR/solr/$COLL/schema" | jq '{errors: (.errors // "none")}'

say "4. Index example/films/films.json"
( cd "$SOLR_DIR" && bin/solr post -c "$COLL" example/films/films.json )

say "5. Indexed document count"
curl -sG "$SOLR/solr/$COLL/select" --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
  | jq '{numFound: .response.numFound}'

say "6. Normal search via catch-all field  q=comedy"
curl -sG "$SOLR/solr/$COLL/select" --data-urlencode 'q=comedy' \
  --data-urlencode 'fl=id,name,directed_by' --data-urlencode 'rows=3' \
  | jq '{numFound: .response.numFound, docs: [.response.docs[] | del(._version_)]}'

say "7a. FACET: facet.field=genre_str"
facet --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
      --data-urlencode 'facet=true' --data-urlencode 'facet.field=genre_str'

say "7b. FACET: facet.limit=5 (top 5 genres)"
facet --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
      --data-urlencode 'facet=true' --data-urlencode 'facet.field=genre_str' \
      --data-urlencode 'facet.limit=5'

say "7c. FACET: facet.mincount=200"
facet --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
      --data-urlencode 'facet=true' --data-urlencode 'facet.field=genre_str' \
      --data-urlencode 'facet.mincount=200'

say "7d. FACET: facet.field=directed_by_str"
facet --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
      --data-urlencode 'facet=true' --data-urlencode 'facet.field=directed_by_str' \
      --data-urlencode 'facet.limit=5'

say "8. RANGE FACET: initial_release_date per year"
facet --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
      --data-urlencode 'facet=true' \
      --data-urlencode 'facet.range=initial_release_date' \
      --data-urlencode 'facet.range.start=NOW/YEAR-25YEAR' \
      --data-urlencode 'facet.range.end=NOW' \
      --data-urlencode 'facet.range.gap=+1YEAR'

say "9. PIVOT FACET: genre_str,directed_by_str"
facet --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
      --data-urlencode 'facet=true' \
      --data-urlencode 'facet.pivot=genre_str,directed_by_str' \
      --data-urlencode 'facet.pivot.mincount=5'

say "10. JSON Facet API (additional faceting capability)"
curl -sG "$SOLR/solr/$COLL/select" --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
  --data-urlencode 'json.facet={top_genres:{terms:{field:genre_str, limit:5, mincount:100, facet:{top_directors:{terms:{field:directed_by_str, limit:3}}}}}}' \
  | jq '{numFound: .response.numFound, facets: .facets}'
