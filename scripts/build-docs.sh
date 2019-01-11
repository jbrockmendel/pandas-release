#!/bin/bash
set -e

source activate pandas
conda uninstall -y --force pandas ||:

# this should have been built by pip-test
# ugh that's 3.7, this is 3.6. boooooo
# python3 -m pip install --no-deps --no-index --find-links=/pandas/dist --only-binary=pandas pandas
apt-get update && apt-get install -y build-essential
cd /pandas
python setup.py build_ext -i && pip install -e .

cd /pandas/doc

./make.py html
./make.py zip_html
./make.py latex_forced
