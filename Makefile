CC?=clang
ERLANG_PATH:=$(shell erl -eval 'io:format("~s~n", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)
ERLANG_FLAGS?=-I$(ERLANG_PATH)
EBIN_DIR?=ebin

NOOUT=2>&1 >/dev/null

BUILD_DIR=_build
PRIV_DIR=priv
SRC_DIR=src
TEST_DIR=test

CMARK=cmark
CMARK_SRC_DIR=src_$(CMARK)
CMARK_C_SRC_DIR=$(CMARK_SRC_DIR)/$(SRC_DIR)
CMARK_BUILD_DIR=$(CMARK_SRC_DIR)/build
CMARK_SPECS_RUNNER=test/spec_tests.py
CMARK_SPECS_JSON=$(TEST_DIR)/$(CMARK)_specs.json

C_SRC_DIR=c_src
C_SRC_C_FILES=$(shell find $(C_SRC_DIR) -name "*.c")
C_SRC_O_FILES=$(shell echo $(C_SRC_C_FILES) | sed "s/\.c/\.o/g")

NIF_SRC=$(SRC_DIR)/$(CMARK)_nif.c
NIF_LIB=$(PRIV_DIR)/$(CMARK).so

OPTIONS=-shared
ifeq ($(shell uname),Darwin)
OPTIONS+= -dynamiclib -undefined dynamic_lookup
endif
INCLUDES=-I$(C_SRC_DIR)

OPTFLAGS?=-fPIC
CFLAGS?=-g -O2 $(OPTFLAGS) $(OPTIONS) $(INCLUDES)

### TARGETS

all: version check-cc $(NIF_LIB)

build-objects: $(C_SRC_O_FILES)

$(C_SRC_DIR)/%.o : $(C_SRC_DIR)/%.c
	$(CC) $(CFLAGS) $< -o $@

$(C_SRC_DIR):
	mkdir -p $@

$(PRIV_DIR):
	@mkdir -p $@ $(NOOUT)

$(NIF_LIB): $(PRIV_DIR) $(C_SRC_O_FILES)
	$(CC) $(CFLAGS) $(ERLANG_FLAGS) $(OPTIONS) $(C_SRC_O_FILES) $(NIF_SRC) -o $@

$(CMARK):
	@mix deps.get
	@mix compile

### TEST

spec: all $(CMARK_SPECS_JSON)
	@mix deps.get
	@mix test

test: spec

### PUBLISH

publish: version publish-code publish-docs

publish-code: all
	@mix hex.publish

publish-docs:
	@MIX_ENV=docs mix hex.docs

### HELPERS/TOOLS

check-cc:
	@hash clang 2>/dev/null || \
	hash gcc 2>/dev/null || ( \
	echo '`clang` or `gcc` seem not to be installed or in your PATH.' && \
	echo 'Maybe you need to install one of it first.' && \
	exit 1)

version:
	@echo "+==============+"
	@echo "| Cmark v`cat VERSION` |"
	@echo "+==============+"

### CLEAN UP

clean: clean-$(CMARK_SRC_DIR) clean-objects clean-dirs

clean-$(CMARK_SRC_DIR):
	cd $(CMARK_SRC_DIR) && $(MAKE) clean && git clean -d -f -x && git reset --hard

clean-objects:
	rm -f $(C_SRC_O_FILES)

clean-dirs:
	rm -rf $(PRIV_DIR) $(BUILD_DIR)

### DEVELOPMENT

dev-prepare: dev-copy-code dev-spec-dump

$(CMARK_SRC_DIR):
	git submodule update --init --force --recursive

dev-update-deps: $(CMARK_SRC_DIR)
	git submodule foreach "git clean -x -f -d && git checkout master && git pull"

dev-copy-code: $(C_SRC_DIR) dev-prebuilt-lib
	cp $(CMARK_C_SRC_DIR)/*.c $(C_SRC_DIR)/
	cp $(CMARK_C_SRC_DIR)/*.h $(C_SRC_DIR)/
	cp $(CMARK_C_SRC_DIR)/*.inc $(C_SRC_DIR)/
	cp $(CMARK_SRC_DIR)/build/src/config.h $(C_SRC_DIR)/
	cp $(CMARK_SRC_DIR)/build/src/cmark_export.h $(C_SRC_DIR)/

dev-prebuilt-lib: dev-update-deps dev-clean-deps
	mkdir -p $(CMARK_BUILD_DIR) && cd $(CMARK_BUILD_DIR) && cmake .. && $(MAKE)

dev-clean-deps:
	git submodule foreach "git clean -x -f -d"

dev-build-objects: dev-copy-code build-objects

$(CMARK_SPECS_JSON): dev-spec-dump

dev-spec-dump: $(CMARK_SRC_DIR)
	@python $(CMARK_SRC_DIR)/$(CMARK_SPECS_RUNNER) \
	--spec $(CMARK_SRC_DIR)/spec.txt \
	--dump-tests > $(CMARK_SPECS_JSON) \
	|| true

### PHONY


.PHONY: all check-cc clean dev-build-objects dev-clean-deps dev-copy-code dev-prebuilt-lib dev-prepare dev-spec-dump dev-update-deps spec test $(CMARK)
