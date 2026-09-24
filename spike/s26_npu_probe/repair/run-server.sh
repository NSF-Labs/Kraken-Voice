#!/system/bin/sh
set -eu
cd /data/local/tmp/kraken-hexagon-repair
export LD_LIBRARY_PATH="$PWD/lib"
export ADSP_LIBRARY_PATH="$PWD/lib;/system/lib/rfsa/adsp;/vendor/lib/rfsa/adsp"
exec ./bin/llama-server -m gemma4-e2b-w4.gguf \
  -dev HTP0 -ngl 99 -t 6 -c 4096 -fa on \
  --parallel 1 --no-cont-batching --reasoning off \
  --host 127.0.0.1 --port 8099 -lv 5
