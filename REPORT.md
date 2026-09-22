# Web Mining Week 03 — Apache Solr

Completion of the Basic exercises from `Web_mining_week3.pdf`:
Exercise 0 (Five Minutes to Searching), Exercise 1 (Techproducts),
Exercise 2 (Films + faceting), Exercise 3 (Index Your Own Data).

All commands below were executed on the machine and verified; raw outputs are
in `evidence/`. Reproduce with `commands.sh` / `queries/*.sh`.

## Environment

| Item | Value |
|------|-------|
| OS | macOS 26.1 (Darwin 25.1.0), arm64 (Apple Silicon) |
| Java | OpenJDK **21.0.12.1** (Homebrew, `openjdk@21`) |
| Solr | Apache Solr **10.0.0** (Lucene 10.3.2), installed in `~/solr-lab/solr-10.0.0` |
| Tika | Apache Tika Server **3.3.2** (`tika-server-standard-3.3.2.jar`, port 9998) |
| Other tools | `curl`, `wget`, `jq`, `python3`, `pdftotext`; no pre-existing Solr/Java |
| Ports | Solr nodes 8983 + 7574, embedded ZooKeeper 9983, Tika 9998 (all free before start) |

Install commands (executed):

```bash
brew install openjdk@21
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
curl -fL -o /tmp/solr-10.0.0.tgz https://dlcdn.apache.org/solr/solr/10.0.0/solr-10.0.0.tgz
tar zxf /tmp/solr-10.0.0.tgz -C $HOME/solr-lab
curl -fL -o $HOME/solr-lab/tika-server-standard-3.3.2.jar \
  https://dlcdn.apache.org/tika/3.3.2/tika-server-standard-3.3.2.jar
```

Solr/Tika were installed in a dedicated `~/solr-lab` directory (not inside the
repository) because the repository path contains a space and Solr start scripts
are sensitive to spaces in paths.

---

## Exercise 0 — Five Minutes to Searching

### Setup

```bash
cd ~/solr-lab/solr-10.0.0
bin/solr start
bin/solr status
```

Result: one node on port 8983, embedded ZooKeeper `127.0.0.1:9983`, `liveNodes: 1`
(`evidence/01_solr_status.txt`). In Solr 10 `bin/solr start` starts SolrCloud
mode by default — standalone now requires `--user-managed`.

### Collection

`bookstore` created with 1 shard / 1 replica via the v2 Collections API, then the
schema was defined with the Schema API:

```bash
curl -X POST http://localhost:8983/api/collections \
  -H 'Content-Type: application/json' \
  -d '{"name":"bookstore","numShards":1,"replicationFactor":1}'

curl -X POST http://localhost:8983/solr/bookstore/schema \
  -H 'Content-Type: application/json' \
  --data-binary '{
    "add-field": [
      {"name":"title","type":"text_general"},
      {"name":"category","type":"string"},
      {"name":"author","type":"text_general"},
      {"name":"price","type":"pfloat"},
      {"name":"description","type":"text_general"}
    ],
    "add-copy-field": [
      {"source":"title","dest":"_text_"},
      {"source":"author","dest":"_text_"},
      {"source":"description","dest":"_text_"}
    ]
  }'
```

> **Solr 10 difference:** the five-minute tutorial uses the v2 Schema API
> (`POST /api/collections/<name>/schema`); in 10.0.0 that endpoint returns
> **HTTP 405**, so the classic v1 path `/solr/<name>/schema` was used.

### Indexed documents

8 book documents (`data/bookstore.json`) with `id, title, category, author,
price, description`, posted and committed:

```bash
curl -X POST -H 'Content-Type: application/json' \
  --data-binary @data/bookstore.json \
  'http://localhost:8983/api/collections/bookstore/update?commit=true'
```

### Queries

```bash
curl -sG http://localhost:8983/solr/bookstore/select \
  --data-urlencode 'q=*:*' --data-urlencode 'fq=category:web-mining' \
  --data-urlencode 'fl=id,title,category'
```

### Results

| Query | numFound | Sample / notes |
|-------|----------|----------------|
| `*:*` | **8** | all documents |
| `title:solr` | 1 | bk-003 "Apache Solr: A Practical Approach…" |
| `category:search` | 3 | bk-001, bk-002, bk-003 |
| `*:*` + `fq=category:web-mining` | 2 | bk-004, bk-005 |
| `title:web AND category:web-mining` | 2 | bk-004, bk-005 |
| `description:"information retrieval"` (phrase) | 1 | bk-001 |
| `fq=price:[20 TO 50]&sort=price asc&fl=id,title,price` | 3 | 35.0 → 39.99 → 45.5 |
| `_text_:solr` (catch-all copy field) | 2 | bk-003, bk-007 |

### Verification

All queries returned the expected subsets and the documents shown were the
expected ones (`evidence/02_exercise0.txt`). ✔

---

## Exercise 1 — Techproducts

### Two-node SolrCloud setup

The interactive `bin/solr start -e cloud` from the tutorial cannot be fully
scripted in Solr 10.0 (its extra flags are not accepted by the new CLI), so the
two nodes were started explicitly — this is the same configuration the tutorial
produces (2 nodes, 2 shards, 2 replicas, embedded ZooKeeper):

```bash
bin/solr stop --all
mkdir -p ~/solr-lab/cloud/node1/solr ~/solr-lab/cloud/node2/solr
cp server/solr/solr.xml ~/solr-lab/cloud/node1/solr/
cp server/solr/solr.xml ~/solr-lab/cloud/node2/solr/

bin/solr start -p 8983 --solr-home ~/solr-lab/cloud/node1/solr -Dsolr.modules=extraction
bin/solr start -p 7574 --solr-home ~/solr-lab/cloud/node2/solr -z localhost:9983 -Dsolr.modules=extraction
```

Both nodes report `liveNodes: 2`:

```json
{ "live_nodes": ["localhost:8983_solr", "localhost:7574_solr"],
  "collections": ["techproducts"] }
```

The extraction module (`-Dsolr.modules=extraction`) is enabled from the start
because three files in `example/exampledocs/` (HTML, PDF, JSONL) are sent to
`/update/extract` by the Post Tool; it is reused by Exercise 3.

Collection created "during startup" exactly as in the tutorial (2 shards,
2 replicas, `sample_techproducts_configs`):

```bash
bin/solr create -c techproducts -sh 2 -rf 2 -d sample_techproducts_configs
# -> Created collection 'techproducts' with 2 shard(s), 2 replica(s) with config-set 'techproducts'
```

### Collection topology

```bash
curl -s 'http://localhost:8983/solr/admin/collections?action=CLUSTERSTATUS&collection=techproducts' \
  | jq '.cluster.collections.techproducts.shards | to_entries
        | map({shard: .key, state: .value.state,
               replicas: [.value.replicas[] | {core: .core, node: .node_name, state, leader}]})'
```

| Shard | Leader | Replica | State |
|-------|--------|---------|-------|
| shard1 | `techproducts_shard1_replica_n4` @ localhost:8983 | `techproducts_shard1_replica_n6` @ localhost:7574 | active |
| shard2 | `techproducts_shard2_replica_n1` @ localhost:8983 | `techproducts_shard2_replica_n2` @ localhost:7574 | active |

All 4 replicas `active`; the two shards are spread across both nodes
(`evidence/04_exercise1_techproducts.txt`).

### Indexing

```bash
bin/solr post -c techproducts example/exampledocs/*
# POSTing books.csv, books.json, 13 XML files ... to [base]
# POSTing sample.html, solr-word.pdf, more_books.jsonl to [base]/extract  (via Tika)
```

Result: **48 documents** — 45 structured (10 CSV rows + 4 JSON books + 31 XML
docs) + 3 extracted through Tika (HTML, PDF, JSONL).

> Troubleshooting: the first re-index attempt after restarting the nodes
> returned HTTP 510 because writes were sent while replicas were still
> recovering. Waiting until all replicas were `active` and re-posting fixed it
> (`evidence/04a_troubleshooting_extraction_510.txt`).

### Queries

```bash
curl -sG 'http://localhost:8983/solr/techproducts/select' \
  --data-urlencode 'q=cat:electronics' --data-urlencode 'fl=id,name,cat'
```

### Results

| Query | numFound | Notes |
|-------|----------|-------|
| `*:*` | **48** | full collection |
| `cat:electronics` | 12 | e.g. `SP2514N` Samsung hard drive |
| `*:*` + `fq=price:[0 TO 100]` + `sort=price asc` + `fl=id,name,price` | 16 | cheapest first (`SOLR1000`, price 0.0) |
| `"CAS latency"` (phrase) | 2 | `VDBDB1A16`, `TWINX2048-3200PRO` |
| `+electronics +music` | 1 | `MA147LL/A` (iPod) |
| `+electronics -music` | 13 | exclusion works |

Values match the official tutorial (electronics = 12, CAS latency = 2,
electronics+music = 1).

---

## Exercise 2 — Films

### Schema

`films` collection created with the `_default` configset (2 shards × 2 replicas),
then prepared for schemaless indexing:

```bash
bin/solr create -c films --shards 2 --replication-factor 2

# the first film is named ".45" - define "name" as text so Solr does not guess float
curl -X POST -H 'Content-type:application/json' \
  --data-binary '{"add-field": {"name":"name","type":"text_general","multiValued":false,"stored":true}}' \
  http://localhost:8983/solr/films/schema

# catch-all copy field so plain queries work
curl -X POST -H 'Content-type:application/json' \
  --data-binary '{"add-copy-field": {"source":"*","dest":"_text_"}}' \
  http://localhost:8983/solr/films/schema
```

Field guessing then creates `genre` (text) + `genre_str` (string copy field),
`directed_by` + `directed_by_str`, and `initial_release_date` (date).

### Indexing

```bash
bin/solr post -c films example/films/films.json
```

Result: **1100 documents** (identical to the tutorial).

### Search

| Query | numFound |
|-------|----------|
| `*:*` | 1100 |
| `comedy` (through the `_text_` catch-all) | **417** (tutorial: 417) |

### Faceting

```bash
curl -sG 'http://localhost:8983/solr/films/select' \
  --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
  --data-urlencode 'facet=true' --data-urlencode 'facet.field=genre_str'
```

**A. `facet.field`** — `genre_str` (whole result set):

| Genre | Count |
|-------|-------|
| Drama | 552 |
| Comedy | 389 |
| Romance Film | 270 |
| Thriller | 259 |
| Action Film | 196 |
| Crime Fiction | 170 |
| World cinema | 167 |

These match the tutorial's published counts (Drama 552, Comedy 389, …).

**B. Additional capabilities:**

- `facet.limit=5` → exactly the top 5 genres above.
- `facet.mincount=200` → 4 facets: Drama 552, Comedy 389, Romance Film 270, Thriller 259.
- `facet.field=directed_by_str` → most prolific directors, e.g. Steven Soderbergh,
  Michael Winterbottom. (The raw `directed_by` text field has no docValues, so
  faceting uses the `*_str` copy field — as in the tutorial.)
- **Range facet** on `initial_release_date` (`facet.range.start=NOW/YEAR-25YEAR`,
  `gap=+1YEAR`): peak years 2006 (173 films), 2005 (167), 2004 (166).
- **Pivot facet** `facet.pivot=genre_str,directed_by_str`: Drama →
  Ridley Scott 5, Steven Soderbergh 5, Michael Winterbottom 4.
- **JSON Facet API** (nested terms):

```bash
curl -sG 'http://localhost:8983/solr/films/select' --data-urlencode 'q=*:*' --data-urlencode 'rows=0' \
  --data-urlencode 'json.facet={top_genres:{terms:{field:genre_str,limit:5,mincount:100,
    facet:{top_directors:{terms:{field:directed_by_str,limit:3}}}}}}'
# -> Drama 552 (top director Michael Winterbottom 4), Comedy 389, Romance Film 270, ...
```

### Results

Faceting is the process of grouping the current result set into buckets by field
value (or by range) and returning a document count per bucket, so users can
narrow a search by category. Here `facet.field=genre_str` over `q=*:*` shows that
Drama (552) and Comedy (389) are the largest genres among the 1100 films, while
`facet.mincount=200` filters out rare genres and the range facet shows the
dataset peaks around 2004–2006. Pivot and JSON facets additionally nest
directors inside genres, demonstrating multi-level analysis.

---

## Exercise 3 — Own Data

### Tika setup

The official tutorial starts Tika with Docker; this environment has no Docker,
so the official **Tika Server jar** was used instead (same server, same port,
same protocol):

```bash
java -jar ~/solr-lab/tika-server-standard-3.3.2.jar --port 9998
curl http://localhost:9998/version       # -> Apache Tika 3.3.2
```

Direct extraction (proves the server itself works):

```bash
curl -s -X PUT -H 'Content-Type: application/pdf' --data-binary @data/sample.pdf \
     -H 'Accept: text/plain' http://localhost:9998/tika
# -> ... The distinctive verification keyword for this PDF is: gazelle.
```

Recorded: **Tika version 3.3.2**, **port 9998**, command as above
(`evidence/06_tika.txt`).

### Extraction module

The cluster nodes were started with the extraction module enabled (see Exercise 1):

```bash
bin/solr start -p 8983 --solr-home .../node1/solr -Dsolr.modules=extraction
bin/solr start -p 7574 --solr-home .../node2/solr -z localhost:9983 -Dsolr.modules=extraction
```

The `mydocs` collection (2 shards × 2 replicas) was created and the extraction
handler added through the Config API, pointing at the external Tika server:

```bash
bin/solr create -c mydocs --shards 2 --replication-factor 2

curl -X POST -H 'Content-type:application/json' -d '{
  "add-requesthandler": {
    "name": "/update/extract",
    "class": "solr.extraction.ExtractingRequestHandler",
    "tikaserver.url": "http://localhost:9998",
    "defaults": { "lowernames": "true", "captureAttr": "true" }
  }
}' 'http://localhost:8983/solr/mydocs/config'
```

Verification of the registered handler:

```json
{ "name": "/update/extract",
  "class": "solr.extraction.ExtractingRequestHandler",
  "tikaserver_url": "http://localhost:9998",
  "defaults": { "lowernames": "true", "captureAttr": "true" } }
```

> **Solr 10 difference:** `LocalTikaExtractionBackend` was removed; Solr Cell now
> always uses an external Tika server, configured with `tikaserver.url`.

### Dataset

Small self-made dataset (`data/`), multiple formats so Tika is meaningfully used:

| File | Format | Content |
|------|--------|---------|
| `ai.txt`, `solr.txt`, `webmining.txt` | text/plain | short articles |
| `sample.html` | text/html | page whose body contains the unique word **zeppelin** |
| `sample.csv` | text/csv | 3 rows (ids `csv-001…003`) |
| `sample.pdf` | application/pdf | generated PDF whose text contains **gazelle** |

### Indexing

```bash
bin/solr post -c mydocs data/ai.txt data/solr.txt data/webmining.txt \
                        data/sample.html data/sample.csv data/sample.pdf
```

Result: **8 documents** = 5 extracted through Tika (`/update/extract`) + 3 CSV rows.

> Note: the Post Tool assigns the **absolute file path** as the id for extracted
> documents (e.g. `.../data/sample.pdf`), so filename queries use `id:*name`.

### Searching extracted content

| Query | numFound | Proof |
|-------|----------|-------|
| `*:*` | 8 | collection populated |
| `content:"information retrieval"` | 1 | text extracted from `sample.pdf` |
| `id:*ai.txt` | 1 | filename/metadata query |
| `content:gazelle` | 1 | word exists **only inside the PDF binary** |
| `content:zeppelin` | 1 | word exists **only inside the HTML body** |
| `dc_title:Apache AND author:Web` | 1 | HTML `<title>` + `<meta author>` metadata |

> In the `_default` configset the unfielded default field (`_text_`) has no
> catch-all copy field, so keyword queries target the extracted `content` field
> explicitly (e.g. `content:gazelle`).

### Updating

```bash
# add a field to update
curl -X POST -H 'Content-type:application/json' \
  --data-binary '{"add-field":{"name":"review_status","type":"string","stored":true}}' \
  http://localhost:8983/solr/mydocs/schema

# atomic update of the real document id
curl -X POST -H 'Content-Type: application/json' \
  --data-binary '[{"id":"<real id of ai.txt>","review_status":{"set":"updated"}}]' \
  'http://localhost:8983/solr/mydocs/update?commit=true'
```

Before: `review_status:updated` → **0**. After: → **1** (the `ai.txt` document).

### Deleting

```bash
curl -X POST -H 'Content-Type: application/json' \
  --data-binary '{"delete":{"id":"csv-003"}}' \
  'http://localhost:8983/solr/mydocs/update?commit=true'
```

Before: `id:csv-003` → **1**. After: → **0**. Final collection count: **7**.

### Results

All CRUD operations verified: 8 indexed → update visible (1 hit) → delete
effective (0 hits, count 7) (`evidence/07_exercise3_own_data.txt`).

---

## Final Verification

`queries/verify.sh` checks every requirement against the live services
(`evidence/08_verification.txt`):

```
[PASS] Java >= 21                                    yes
[PASS] Solr HTTP API reachable                       200
[PASS] Two-node SolrCloud cluster alive              2
[PASS] Collections present                           bookstore,films,mydocs,techproducts
[PASS] Exercise 0: bookstore documents               8
[PASS] Exercise 0: category:search                   3
[PASS] Exercise 0: fq=category:web-mining            2
[PASS] Exercise 1: techproducts documents            48
[PASS] Exercise 1: cat:electronics                   12
[PASS] Exercise 1: +electronics +music               1
[PASS] Exercise 1: replicas active (2 shards x 2)    4/4
[PASS] Exercise 2: films documents                   1100
[PASS] Exercise 2: q=comedy                          417
[PASS] Exercise 2: facet genre_str Drama count       552
[PASS] Exercise 3: Tika version                      Apache Tika 3.3.2
[PASS] Exercise 3: mydocs documents (after delete)   7
[PASS] Exercise 3: PDF text searchable content:gazelle 1
[PASS] Exercise 3: HTML text searchable content:zeppelin 1
[PASS] Exercise 3: update visible review_status:updated 1
[PASS] Exercise 3: deleted doc gone id:csv-003       0
[PASS] Exercise 3: extraction handler registered     solr.extraction.ExtractingRequestHandler

RESULT: 21 passed, 0 failed
```

## Admin UI (web interface)

The same indexes can be explored in a browser while Solr is running:

- http://localhost:8983/solr/ (node 1) and http://localhost:7574/solr/ (node 2)
- http://localhost:8983/solr/#/~cloud — cluster graph: nodes, shards, replicas
- http://localhost:8983/solr/#/films/query — Query screen; tick `facet`, set
  `facet.field=genre_str` to see the same facet counts as in the curl output
- http://localhost:8983/solr/#/mydocs/documents — add/delete documents
  (JSON **array** or XML `<add>`/`<delete>`)
- http://localhost:8983/solr/ui/ — new preview UI in Solr 10

Click-by-click instructions for every exercise are in `README.md`
("Interacting with the Solr Admin UI"). Tika itself has no web UI; it is a
REST service (`curl http://localhost:9998/version`).

## Notes on Solr 10 changes (slides vs. current version)

1. `bin/solr start` defaults to **SolrCloud**; `--user-managed` is the new
   standalone switch (Solr 9 tutorials are ambiguous about this).
2. `bin/post` was removed → `bin/solr post` (tutorial already uses the new form).
3. The interactive `start -e cloud` no longer accepts scriptable flags, so the
   two nodes are started explicitly (same topology).
4. v2 Schema API returns HTTP 405 in 10.0.0 → v1 Schema API used.
5. Solr Cell requires an **external Tika server** (`tikaserver.url`); the local
   Tika backend was removed in 10.
6. The Post Tool uses absolute paths as ids for `/update/extract` documents.
7. Range facet `NOW/YEAR-25YEAR` starts at 2001 because the run date is 2026.

## Unresolved issues

None. All 21 verification checks pass.

## Evidence files

| File | Content |
|------|---------|
| `evidence/00_environment.txt` | OS, Java, Solr, Tika versions; ports; final cluster state |
| `evidence/01_solr_status.txt` | `bin/solr status`, HTTP reachability, collection list |
| `evidence/02_exercise0.txt` | Exercise 0: schema, indexing, all queries |
| `evidence/03_cluster_start.txt` | two-node cluster startup, both nodes live |
| `evidence/04_exercise1_techproducts.txt` | techproducts indexing, queries, topology |
| `evidence/04a_troubleshooting_extraction_510.txt` | failed attempt during replica recovery (raw) |
| `evidence/05_exercise2_films.txt` | films indexing, search, all facet outputs |
| `evidence/06_tika.txt` | Tika version, direct PDF/HTML extraction, metadata |
| `evidence/07_exercise3_own_data.txt` | mydocs pipeline, searches, update/delete before/after |
| `evidence/08_verification.txt` | final 21-check verification result |
