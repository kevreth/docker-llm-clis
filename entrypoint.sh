set -euo pipefail
cd /workspace
git clone https://${GH_TOKEN}@github.com/kevreth/kev-labs.git
cd kev-labs
make clone-all
cd /workspace/kev-labs/inquirita/inquirita-website
git submodule update --init --recursive
cd /workspace/kev-labs/inquirita/inquirita-website/asciidoctor
make
corepack prepare yarn@${YARN_VERSION} --activate
cd /workspace/kev-labs/inquirita/inquirita-website/
yarn install
yarn build
cd /workspace/kev-labs/spoonfeeder/SpoonFeeder/
yarn install
cd /workspace/kev-labs
echo "execute 'docker exec -it kev-labs-kev-labs:latest bash'" to reconnect later.
echo "ALL DONE. You're in the fully built kev-labs development container."
exec /bin/bash
