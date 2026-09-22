#!/usr/bin/env bash
# =============================================================================
# Web Mining Week 03 - Apache Solr
# Reproducible command log for Exercises 0-3 (macOS / Linux, bash)
#
# Tested with: OpenJDK 21.0.12.1, Solr 10.0.0, Apache Tika Server 3.3.2
# Runtime layout: $LAB/solr-10.0.0 and $LAB/tika-server-standard-3.3.2.jar
# =============================================================================
set -euo pipefail

# ---- 0. Environment ---------------------------------------------------------
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}
export PATH="$JAVA_HOME/bin:$PATH"
export SOLR_ULIMIT_CHECKS=false   # silence the macOS "max processes" warning

LAB=${LAB:-$HOME/solr-lab}        # tools live outside the repo (path contains no spaces)
SOLR_DIR=$LAB/solr-10.0.0
SOLR_BIN="$SOLR_DIR/bin/solr"
TIKA_JAR=$LAB/tika-server-standard-3.3.2.jar
SOLR=http://localhost:8983
TIKA=http://localhost:9998
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

java -version

# ---- 1. Install (once) ------------------------------------------------------
# Java 21:            brew install openjdk@21
# Solr 10.0.0:
#   mkdir -p "$LAB" && curl -fL -o /tmp/solr-10.0.0.tgz \
#     https://dlcdn.apache.org/solr/solr/10.0.0/solr-10.0.0.tgz
#   tar zxf /tmp/solr-10.0.0.tgz -C "$LAB"
# Tika Server 3.3.2:
#   curl -fL -o "$TIKA_JAR" \
#     https://dlcdn.apache.org/tika/3.3.2/tika-server-standard-3.3.2.jar

# =============================================================================
# EXERCISE 0 - Five Minutes to Searching
# Note: in Solr 10 `bin/solr start` starts SolrCloud mode by default
#       (single node + embedded ZooKeeper on 9983).
# =============================================================================
"$SOLR_BIN" start
"$SOLR_BIN" status
curl "$SOLR/solr/admin/info/system?wt=json" | jq '{solr: .lucene."solr-spec-version", java: .jvm.version}'

bash "$PROJECT_DIR/queries/exercise0.sh"     # collection + schema + docs + queries

# =============================================================================
# EXERCISE 1 - Techproducts on a two-node SolrCloud cluster
# =============================================================================
"$SOLR_BIN" stop --all

# Prepare two Solr homes on the same machine (mirrors the -e cloud example):
mkdir -p "$LAB/cloud/node1/solr" "$LAB/cloud/node2/solr"
cp "$SOLR_DIR/server/solr/solr.xml" "$LAB/cloud/node1/solr/"
cp "$SOLR_DIR/server/solr/solr.xml" "$LAB/cloud/node2/solr/"

# Start node 1 (embedded ZooKeeper 9983) and node 2, with the extraction module
# enabled so that HTML/PDF files in example/exampledocs also get indexed:
"$SOLR_BIN" start -p 8983 --solr-home "$LAB/cloud/node1/solr" -Dsolr.modules=extraction
sleep 5
"$SOLR_BIN" start -p 7574 --solr-home "$LAB/cloud/node2/solr" -z localhost:9983 -Dsolr.modules=extraction
sleep 3
"$SOLR_BIN" status

# Wait until all replicas of techproducts are active before writing to it
# (writes during recovery can fail; see REPORT.md "troubleshooting").

# Create the collection during startup:
"$SOLR_BIN" create -c techproducts -sh 2 -rf 2 -d sample_techproducts_configs

bash "$PROJECT_DIR/queries/techproducts.sh"  # index + queries + topology

# =============================================================================
# EXERCISE 2 - Films: schema and faceting
# =============================================================================
bash "$PROJECT_DIR/queries/films.sh"

# =============================================================================
# EXERCISE 3 - Index Your Own Data (external Tika + extraction module)
# =============================================================================
# 3a. External Tika Server (official tutorial uses Docker; this uses the jar):
nohup java -jar "$TIKA_JAR" --port 9998 >"$LAB/tika.log" 2>&1 &
curl "$TIKA/version"

# 3b. The extraction module is already enabled on both nodes (Exercise 1).
#     To enable it on a fresh cluster, restart nodes with -Dsolr.modules=extraction:
#       "$SOLR_BIN" stop --all
#       "$SOLR_BIN" start -p 8983 --solr-home "$LAB/cloud/node1/solr" -Dsolr.modules=extraction
#       "$SOLR_BIN" start -p 7574 --solr-home "$LAB/cloud/node2/solr" -z localhost:9983 -Dsolr.modules=extraction

# 3c. Create mydocs + enable handler + index own data + search/update/delete:
bash "$PROJECT_DIR/queries/own_data.sh"

# =============================================================================
# FINAL VERIFICATION
# =============================================================================
bash "$PROJECT_DIR/queries/verify.sh"

# =============================================================================
# STOP EVERYTHING
# =============================================================================
"$SOLR_BIN" stop --all
pkill -f tika-server-standard || true
