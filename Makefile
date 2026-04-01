all: release

NVIM_VERSION	?= 0.12.0
NVIM_TAR		:="$(PWD)/neovim-$(NVIM_VERSION).tar.gz"
NVIM_URL 		?= https://pub.mtdcy.top/packages/neovim-$(NVIM_VERSION).tar.gz
NVIM_URL_DEF 	:= https://github.com/neovim/neovim/archive/refs/tags/v$(NVIM_VERSION).tar.gz

WORKDIR 		:= $(PWD)/out/$(shell gcc -dumpmachine)
PREFIX 			:= $(WORKDIR)/prebuilts
RELEASE 		:= $(WORKDIR)/release

NVIM_BUILD		:= $(WORKDIR)/neovim-$(NVIM_VERSION)

NVIM_BUILD_ARGS += -DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF

# install path
NVIM_BUILD_ARGS += -DCMAKE_INSTALL_PREFIX="$(PREFIX)"

# bundled luajit, prefer luajit over lua
NVIM_BUILD_ARGS += -DUSE_BUNDLED=ON -DUSE_BUNDLED_LUAJIT=ON 

# no multiple languages
NVIM_BUILD_ARGS += -DENABLE_LIBINTL=OFF -DENABLE_LANGUAGES=OFF

# cache deps package
NVIM_BUILD_ARGS += -DDEPS_DOWNLOAD_DIR="$(PWD)/packages"

# we have trouble to build static nvim
#  => luajit crashes because of dlopen
NVIM_BUILD_ARGS += -DCMAKE_EXE_LINKER_FLAGS=''

# build for old macOS
NVIM_BUILD_ARGS += -DMACOSX_DEPLOYMENT_TARGET=12.0

$(PREFIX)/nvim: nvim.sh pathdef.h.in pathdef.c.in
	@if ! test -f $(NVIM_TAR); then \
		echo "🚀 下载 $(NVIM_TAR)"; \
		curl -sL --fail --connect-timeout 3 -o $(NVIM_TAR) $(NVIM_URL) || \
		curl -sL --fail --connect-timeout 3 -o $(NVIM_TAR) $(NVIM_URL_DEF); \
	fi
	@echo "🚀 准备工作区"
	mkdir -pv $(WORKDIR)
	tar -xf $(NVIM_TAR) -C $(WORKDIR)
	cp -fv pathdef.c.in $(NVIM_BUILD)/cmake.config/
	cp -fv pathdef.h.in $(NVIM_BUILD)/cmake.config/
	mkdir -p $(NVIM_BUILD)/build
	mkdir -p $(NVIM_BUILD)/.deps # ⚠️ 只能是这个目录
	@echo "🚀 构建 deps..."
	cd $(NVIM_BUILD)/.deps && cmake ../cmake.deps && make
	@echo "🚀 构建 nvim...";
	cd $(NVIM_BUILD)/build && cmake $(NVIM_BUILD_ARGS) .. && make && make install
	@echo "🌹 添加 nvim 启动脚本"
	cp nvim.sh $@
	chmod a+x $@

# usage: make parser PARSER_URL=...
parser:
	$(eval PARSER_NAME := $(shell echo $(PARSER_URL) | cut -d'/' -f5))
	$(eval PARSER_LANG := $(shell echo $(PARSER_NAME) | cut -d'-' -f3))
	$(eval PARSER_BUILD := $(WORKDIR)/parsers/$(PARSER_LANG))
	@echo "☁️ 下载 $(PARSER_URL)"
	mkdir -pv $(WORKDIR)
	curl -sL $(PARSER_URL) | tar -xz -C $(WORKDIR)
	@echo "🚀 构建 $(PARSER_NAME)"
	mkdir -pv $(PARSER_BUILD) 
	cd $(WORKDIR)/$(PARSER_NAME)-* && cmake -S . -B $(PARSER_BUILD)
	cmake --build $(PARSER_BUILD)
	@echo "📦 安装 $(PARSER_LANG).so"
	mkdir -pv $(PREFIX)/lib/nvim/parser
ifeq ($(shell uname -s),Darwin) # darwin format
	find $(PARSER_BUILD) -type f \( -name "*$(PARSER_NAME)*.dylib" -o -name "*$(PARSER_NAME)*.so" \) -exec cp -fv {} $(PREFIX)/lib/nvim/parser/$(PARSER_LANG).so \;
	install_name_tool -id "@rpath/$(PARSER_LANG).so" $(PREFIX)/lib/nvim/parser/$(PARSER_LANG).so
else # linux format
	find $(PARSER_BUILD) -type f -name "*$(PARSER_NAME).so.*" -exec cp -fv {} $(PREFIX)/lib/nvim/parser/$(PARSER_LANG).so \;
endif
	# install queries
	mkdir -pv $(PREFIX)/share/nvim/runtime/queries/$(PARSER_LANG) 
	find $(PARSER_BUILD) -type f -name "*.scm" -exec cp -fv {} $(PREFIX)/share/nvim/runtime/queries/$(PARSER_LANG)/ \;
	@echo "✅ 完成 $(PARSER_NAME)"
	@echo ""

parsers: parsers.txt
	@(while read -r line; do \
		test -z "$$line" && continue; \
		case "$$line" in \#*) continue ;; esac; \
		make parser PARSER_URL="$$line" || exit 1; \
	done < $<)

.NOTPARALLEL: parsers parser

build:
	$(MAKE) $(PREFIX)/nvim

clean:
	rm -rf $(PREFIX)

distclean:
	rm -rf $(WORKDIR)

check: $(PREFIX)/nvim
	@echo "🌹 测试 nvim 启动脚本"
	$< -V1 -v
	$< --headless -c "checkhealth | w! $(PREFIX)/checkhealth.txt" +quit
	@echo "✅ 测试完成"

release: build parsers check
	@echo "🚀 make nvim-$(NVIM_VERSION) release"
	mkdir -pv $(RELEASE)
	tar -C $(PREFIX) -cf $(RELEASE)/nvim-$(NVIM_VERSION).tar.gz .

