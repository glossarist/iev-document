#!make
SHELL := /bin/bash

DERIVABLE_YAML_SRC := $(wildcard concepts/concept-192*.yaml)
DERIVED_ADOC   := $(patsubst concepts/%,sources/sections/terms/%,$(patsubst %.yaml,%.adoc,$(DERIVABLE_YAML_SRC)))
ADOC_GENERATOR := scripts/split_codes.rb

IEVDATA_DOWNLOAD_PATH := https://github.com/glossarist/iev-data/releases/download/v0.24.20201217/concepts-0.24.20201217.zip

# Two step process that requires an external call to `make`
# 1. Expand all concept YAML files into adoc files
# 2. Build the site
all: concepts/.done
	$(MAKE) site/index.html

concepts.zip:
	curl -sSL ${IEVDATA_DOWNLOAD_PATH} -o $@

concepts/.done: concepts.zip
	unzip $<
	touch concepts/.done

concepts/%.yaml: concepts/.done

sources/sections/terms/%.adoc: concepts/%.yaml $(ADOC_GENERATOR)
	$(ADOC_GENERATOR) $< $@

site/index.html: $(DERIVED_ADOC)
	bundle exec metanorma site generate

%.adoc:

clean:
	rm -rf site/

distclean: clean
	rm -rf concepts/ images/ sources/sections/terms concepts.zip

.PHONY: bundle all open clean