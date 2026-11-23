CLANG ?= clang
OBJDUMP ?= objdump

snake.img: snake.s
	@set -eu; \
	build_dir=$$(mktemp -d); \
	trap 'rm -rf "$$build_dir"' EXIT; \
	$(CLANG) --target=i386-unknown-none-elf -c $< -o "$$build_dir/snake.o"; \
	$(OBJDUMP) -s -j .text "$$build_dir/snake.o" > "$$build_dir/text"; \
	awk '$$1 ~ /^[[:xdigit:]]+$$/ { print $$2 $$3 $$4 $$5 }' "$$build_dir/text" \
	    | xxd -r -p > "$$build_dir/snake.img"; \
	test "$$(wc -c < "$$build_dir/snake.img" | tr -d '[:space:]')" = 512; \
	test "$$(tail -c 2 "$$build_dir/snake.img" | xxd -p)" = 55aa; \
	cp "$$build_dir/snake.img" $@
