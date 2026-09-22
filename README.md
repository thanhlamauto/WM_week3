# Web Mining Week 03 — Apache Solr (Exercises 0–3)

Hands-on completion of the Week 03 Solr exercises:

| Exercise | Topic | Collection(s) |
|----------|-------|---------------|
| 0 | Five minutes to searching | `bookstore` (8 docs) |
| 1 | Techproducts on a two-node SolrCloud cluster | `techproducts` (48 docs) |
| 2 | Films: schema + faceting | `films` (1100 docs) |
| 3 | Index your own data (Tika + extraction + CRUD) | `mydocs` (7 docs after delete) |

Everything in this repository was executed and verified on the machine described
below. See `REPORT.md` for results and `evidence/` for raw outputs.

## Prerequisites

- macOS or Linux (tested on macOS 26.1, arm64)
- **Java 21 or newer** — Solr 10 requires Java 21 (`brew install openjdk@21`)
- `curl`, `jq` (used by the scripts)
- Optional: `pdftotext` only if you want to regenerate `data/sample.pdf`

Versions used:

- OpenJDK **21.0.12.1** (Homebrew)
- Apache Solr **10.0.0**
- Apache Tika Server **3.3.2**

## Installation

Install Java 21:

```bash
brew install openjdk@21
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
```

Install Solr and Tika into a tools directory **without spaces in the path**
(the scripts default to `~/solr-lab`; override with `LAB=/your/path`):

```bash
export LAB=$HOME/solr-lab
mkdir -p "$LAB"

curl -fL -o /tmp/solr-10.0.0.tgz https://dlcdn.apache.org/solr/solr/10.0.0/solr-10.0.0.tgz
tar zxf /tmp/solr-10.0.0.tgz -C "$LAB"

curl -fL -o "$LAB/tika-server-standard-3.3.2.jar" \
  https://dlcdn.apache.org/tika/3.3.2/tika-server-standard-3.3.2.jar
```

## How to reproduce Exercises 0–3

The scripts in `queries/` contain the full workflow; `commands.sh` is the
annotated master command log. Set the environment first:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
export SOLR_DIR=$HOME/solr-lab/solr-10.0.0   # used by the query scripts
```

### Exercise 0 — standalone (Solr 10 default = single-node SolrCloud)

```bash
$SOLR_DIR/bin/solr start
bash queries/exercise0.sh
```

### Exercise 1 — two-node cluster + techproducts

```bash
$SOLR_DIR/bin/solr stop --all

mkdir -p $HOME/solr-lab/cloud/node1/solr $HOME/solr-lab/cloud/node2/solr
cp $SOLR_DIR/server/solr/solr.xml $HOME/solr-lab/cloud/node1/solr/
cp $SOLR_DIR/server/solr/solr.xml $HOME/solr-lab/cloud/node2/solr/

$SOLR_DIR/bin/solr start -p 8983 --solr-home $HOME/solr-lab/cloud/node1/solr -Dsolr.modules=extraction
sleep 5
$SOLR_DIR/bin/solr start -p 7574 --solr-home $HOME/solr-lab/cloud/node2/solr -z localhost:9983 -Dsolr.modules=extraction

$SOLR_DIR/bin/solr create -c techproducts -sh 2 -rf 2 -d sample_techproducts_configs
bash queries/techproducts.sh
```

### Exercise 2 — films + faceting

```bash
bash queries/films.sh
```

### Exercise 3 — Tika + own data

```bash
nohup java -jar $HOME/solr-lab/tika-server-standard-3.3.2.jar --port 9998 >$HOME/solr-lab/tika.log 2>&1 &
bash queries/own_data.sh
```

### Verify everything

```bash
bash queries/verify.sh    # 21/21 checks pass on a complete run
```

## Interacting with the Solr Admin UI (web interface)

While Solr is running, both nodes serve a browser UI:

- Node 1: **http://localhost:8983/solr/**
- Node 2: **http://localhost:7574/solr/** (same cluster/state as node 1)
- Solr 10 also ships a preview UI: http://localhost:8983/solr/ui/

Main screens (left sidebar → pick a collection → tabs):

| Screen | Direct URL | What you can do |
|--------|-----------|-----------------|
| **Query** | `/solr/#/<collection>/query` | run `q`, `fq`, `sort`, `fl`, `rows`; tick the `facet` checkbox and set `facet.field`; click **Execute Query** |
| **Documents** | `/solr/#/<collection>/documents` | add documents (JSON / XML / CSV / Document Builder) and delete them; **Submit Document** commits immediately |
| **Schema** | `/solr/#/<collection>/schema` | browse fields, field types, dynamic fields, copy fields |
| **Overview** | `/solr/#/<collection>/collection-overview` | `numDocs`, `maxDoc`, shard/replica summary |
| **Cloud** | `/solr/#/~cloud` | Graph / Tree / Dump of nodes, shards and replicas |
| **Logging / Metrics** | `/solr/#/~logging`, `/solr/#/~metrics` | server log and OpenTelemetry metrics |

### Exercise 0 — `bookstore`

1. Open http://localhost:8983/solr/#/bookstore/query
2. `q=*:*` → **Execute Query** → `"numFound": 8` in the JSON panel
3. Try `q=title:solr` (1 hit), `q=category:search` (3 hits)
4. `q=*:*` with `fq=category:web-mining` → 2 hits
5. `fq=price:[20 TO 50]`, `sort=price asc`, `fl=id,title,price` → 3 hits, cheapest first
6. **Schema** tab: inspect the field types (`category` = string, `price` = pfloat) and the `_text_` copy fields

### Exercise 1 — `techproducts` + cluster topology

1. **Cloud → Graph** (http://localhost:8983/solr/#/~cloud): two nodes (`8983`, `7574`),
   `techproducts` with 2 shards × 2 replicas; click a replica to see its core/node
2. Query screen for techproducts: `q=cat:electronics` → 12 hits;
   `fq=price:[0 TO 100]`, `sort=price asc` → 16 hits
3. **Overview** tab shows `numDocs = 48`
4. Open node 2's UI (http://localhost:7574/solr/) — same collections and state

### Exercise 2 — `films` + faceting in the UI

1. Open http://localhost:8983/solr/#/films/query, `q=*:*` → 1100
2. Tick the **facet** checkbox, set `facet.field=genre_str`, **Execute Query** →
   the `facet_counts` section shows Drama 552, Comedy 389, Romance Film 270, …
3. Add `facet.mincount=200` → only 4 buckets; `facet.limit=5` → top 5 genres
4. `facet.field=directed_by_str` → most prolific directors
5. **Schema** tab: `name` = text_general, `genre_str`/`directed_by_str` = strings
   (with docValues — that is why faceting uses the `_str` fields), `initial_release_date` = pdates
6. Range, pivot and JSON facets have no UI widgets → use the curl commands in `REPORT.md`
7. The Query screen accepts URL parameters too, e.g.
   http://localhost:8983/solr/#/films/query?q=*:*&facet=true&facet.field=genre_str

### Exercise 3 — `mydocs`

1. Query screen: `content:gazelle` → `sample.pdf`; `content:zeppelin` → `sample.html`
   (proves text was extracted from the binary/markup files)
2. **Documents** tab → Document Type = `JSON`, paste a **JSON array** (a single
   object is interpreted as a JSON *command* and fails with
   `Unknown command 'id'`):

   ```json
   [{"id":"ui-demo","title":"Added from Admin UI","review_status":"ui"}]
   ```

   → **Submit Document** → run `q=id:ui-demo` on the Query screen (1 hit).
   Equivalent XML form: `<add><doc><field name="id">ui-demo</field>…</doc></add>`
3. Delete in the same screen with Document Type = `XML`:

   ```xml
   <delete><id>ui-demo</id></delete>
   ```

   → **Submit Document** → `q=id:ui-demo` → 0 hits
4. Tika has **no web UI** (it is a REST service): check `curl http://localhost:9998/version`,
   see `evidence/06_tika.txt`

The Admin UI is only a thin client over the same REST API used by the scripts:
anything you do in the UI is visible to `curl`/`queries/*.sh` and vice versa.

## Stopping the services

```bash
$SOLR_DIR/bin/solr stop --all
pkill -f tika-server-standard
```

## Repository layout

```
web-mining-week3/
├── README.md              # this file
├── REPORT.md              # full report with commands, outputs and findings
├── commands.sh            # annotated master command log
├── data/
│   ├── bookstore.json     # Exercise 0 sample documents
│   ├── ai.txt  solr.txt  webmining.txt     # Exercise 3 text documents
│   ├── sample.html  sample.csv  sample.pdf # Exercise 3 other formats
│   └── sample_pdf_source.txt               # source used to generate sample.pdf
├── queries/
│   ├── exercise0.sh  techproducts.sh  films.sh  own_data.sh
│   └── verify.sh          # final verification checklist
└── evidence/              # real outputs captured during execution
```

## Solr 10 differences vs. the lecture slides / tutorial

- `bin/solr start` now starts **SolrCloud** by default (`--user-managed` for standalone).
- `bin/post` was removed; use `bin/solr post` (the tutorial already does).
- The interactive `bin/solr start -e cloud` cannot be fully scripted in 10.0,
  so the two nodes are started explicitly (same result: two nodes, embedded
  ZooKeeper on 9983).
- The v2 Schema API (`POST /api/collections/<name>/schema`) returns **HTTP 405**
  in 10.0.0; the v1 Schema API (`/solr/<name>/schema`) is used instead.
- Solr Cell now **requires an external Tika server** (`tikaserver.url`);
  the bundled/local Tika backend was removed in Solr 10.
