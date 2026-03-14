.PHONY: check lint format lint-ts lint-py format-ts format-py

check: lint-ts lint-py
	@echo "All checks passed."

lint: lint-ts lint-py

lint-ts:
	cd nemoclaw && npm run check

lint-py:
	cd nemoclaw-blueprint && $(MAKE) check

format: format-ts format-py

format-ts:
	cd nemoclaw && npm run lint:fix && npm run format

format-py:
	cd nemoclaw-blueprint && $(MAKE) format
