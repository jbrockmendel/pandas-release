# TO EDIT
TAG ?= v0.25.2
GH_USERNAME ?= jbrockmendel
PANDAS_VERSION=$(TAG:v%=%)
PANDAS_BASE_VERSION=$(shell echo $(PANDAS_VERSION) | awk -F '.' '{OFS="."} { print $$1, $$2}')
TARGZ=pandas-$(PANDAS_VERSION).tar.gz

# to ensure pushd and popd works
SHELL := /bin/bash

# -----------------------------------------------------------------------------
# Host filesystem initialization
# -----------------------------------------------------------------------------

init-repos:
	git clone https://github.com/pandas-dev/pandas                   && git -C pandas           remote rename origin upstream && git -C pandas 		     remote add origin https://github.com/$(GH_USERNAME)/pandas
	git clone https://github.com/pandas-dev/pandas-website           && git -C pandas-website   remote rename origin upstream && git -C pandas-website   remote add origin https://github.com/$(GH_USERNAME)/pandas-website
	git clone https://github.com/conda-forge/pandas-feedstock        && git -C pandas-feedstock remote rename origin upstream && git -C pandas-feedstock remote add origin https://github.com/$(GH_USERNAME)/pandas-feedstock
	git clone --recursive https://github.com/MacPython/pandas-wheels && git -C pandas-wheels    remote rename origin upstream && git -C pandas-wheels    remote add origin https://github.com/$(GH_USERNAME)/pandas-wheels

update-repos:
	git -C pandas checkout master           && git -C pandas pull
	git -C pandas-wheels checkout master    && git -C pandas-wheels pull
	git -C pandas-website checkout master   && git -C pandas-website pull
	git -C pandas-feedstock checkout master && git -C pandas-feedstock pull
	pushd pandas-wheels && git submodule update --recursive --remote && popd

# -----------------------------------------------------------------------------
# Git Tag
# -----------------------------------------------------------------------------

tag:
	# This doesn't push the tag
	pushd pandas && ../scripts/tag.py $(TAG) && popd


# -----------------------------------------------------------------------------
#  Builder Images
# -----------------------------------------------------------------------------

docker-image: pandas
	docker build -t pandas-build .


docker-doc:
	docker build -t pandas-docs -f docker-files/docs/Dockerfile .


# -----------------------------------------------------------------------------
# sdist
# -----------------------------------------------------------------------------

pandas/dist/$(TARGZ):
	docker run -it --rm \
		--name=pandas-sdist-build \
		-v ${CURDIR}/pandas:/pandas \
		-v ${CURDIR}/scripts:/scripts \
		pandas-build \
		sh /scripts/build_sdist.sh

# -----------------------------------------------------------------------------
# Tests
# These can be done in parallel
# -----------------------------------------------------------------------------

conda-test:
	docker run -it --rm \
		--name=pandas-conda-test \
		--env PANDAS_VERSION=$(PANDAS_VERSION) \
		-v ${CURDIR}/pandas:/pandas \
		-v ${CURDIR}/recipe:/recipe \
		pandas-build \
		sh -c "conda build --numpy=1.13 --python=3.6 /recipe --output-folder=/pandas/dist"

pip-test: pandas/dist/$(TARGZ)
	docker run -it --rm \
		--name=pandas-pip-test \
		-v ${CURDIR}/pandas:/pandas \
		-v ${CURDIR}/scripts/pip_test.sh:/pip_test.sh \
		pandas-build /bin/bash /pip_test.sh /pandas/dist/$(TARGZ)

# -----------------------------------------------------------------------------
# Docs
# -----------------------------------------------------------------------------

# this had a non-zero exit, but seemed to succeed
# Output written on pandas.pdf (2817 pages, 10099368 bytes).
# Transcript written on pandas.log.
# Traceback (most recent call last):
#   File "./make.py", line 372, in <module>
#     sys.exit(main())
#   ...
#   File "/opt/conda/envs/pandas/lib/python3.7/subprocess.py", line 347, in check_call
#     raise CalledProcessError(retcode, cmd)
# subprocess.CalledProcessError: Command '('pdflatex', '-interaction=nonstopmode', 'pandas.tex')' returned non-zero exit status 1.

doc:
	docker run -it --rm \
		--name=pandas-docs \
		-v ${CURDIR}/pandas:/pandas \
		-v ${CURDIR}/scripts/build-docs.sh:/build-docs.sh \
		pandas-docs \
		/build-docs.sh


upload-doc:
	rsync -rv -e ssh pandas/doc/build/html/            pandas.pydata.org:/usr/share/nginx/pandas/pandas-docs/version/$(PANDAS_VERSION)/
	rsync -rv -e ssh pandas/doc/build/latex/pandas.pdf pandas.pydata.org:/usr/share/nginx/pandas/pandas-docs/version/$(PANDAS_VERSION)/pandas.pdf

link-stable:
	ssh pandas.pydata.org "cd /usr/share/nginx/pandas/pandas-docs && ln -sfn version/$(PANDAS_VERSION) stable"

link-version:
	ssh pandas.pydata.org "cd /usr/share/nginx/pandas/pandas-docs/version && ln -sfn $(PANDAS_VERSION) $(PANDAS_BASE_VERSION)"

push-doc: | upload-doc link-stable link-version

website:
	# TODO: handle previous.rst, latest.rst
	pushd pandas-website && \
		../scripts/update-website.py $(TAG) && \
		git add . && \
		git commit -m "RLS $(TAG)" && \
		make html && \
	popd



make push-website:
	pushd pandas-website && \
		git push upstream master && \
		make html && \
		make upload && \
	popd


push-tag:
	pushd pandas && ../scripts/push-tag.py $(TAG) && popd


github-release:
	echo TODO


conda-forge:
	./scripts/conda-forge.sh $(TAG) $(GH_USERNAME)


wheels:
	rm -rf pandas/dist/pandas-$(PANDAS_VERSION)-cp37m-linux_x86_64.whl
	rm -rf pandas/dist/pandas-$(PANDAS_VERSION)-cp37-cp37m-linux_x86_64.whl
	./scripts/wheels.sh $(TAG) $(GH_USERNAME)


download-wheels:
	cd pandas && python scripts/download_wheels.py $(PANDAS_VERSION)
	# TODO: Fetch from https://www.lfd.uci.edu/~gohlke/pythonlibs/


upload-pypi:
	twine upload pandas/dist/pandas-$(PANDAS_VERSION)*.{whl,tar.gz} --skip-existing
