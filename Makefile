.PHONY: install install-dev format lint lint-check type-check test test-cov test-examples clean build deps-update deps-sync quality style fixup venv venv-recreate setup-dev docker-build-gpu docker-build-cpu docker-build docker-run-gpu docker-run-cpu ci-quality ci-test
# Use stage 0 container pip constraints
CONSTRAINTS := --constraint /etc/pip/constraint.txt

export PYTHONPATH = src
check_dirs := examples tests src utils
VENV_DIR := .venv
VENV_PY := $(VENV_DIR)/bin/python
UV := /usr/bin/uv

# Create venv using uv
$(VENV_DIR)/bin/activate:
	rm -rf $(VENV_DIR)
	$(UV) venv $(VENV_DIR) --python 3.10

venv: $(VENV_DIR)/bin/activate

# Installation targets
install: venv
	$(UV) pip install --python $(VENV_PY) -e .

install-dev: venv
	$(UV) pip install --python $(VENV_PY) -e ".[dev]"


# Development workflow targets
format: install-dev
	$(UV) run --python $(VENV_PY) ruff format $(check_dirs)

lint: install-dev
	$(UV) run --python $(VENV_PY) ruff check $(check_dirs) --fix

lint-check: install-dev
	$(UV) run --python $(VENV_PY) ruff check $(check_dirs)

type-check: install-dev
	$(UV) run --python $(VENV_PY) mypy src/

# Combined quality checks
quality: lint-check type-check
	@echo "All quality checks passed!"

# Quick style fix
style: format lint
	@echo "Code formatting and linting completed!"

# Quick fix for modified files only
fixup: install-dev
	$(eval modified_py_files := $(shell $(VENV_PY) utils/get_modified_files.py $(check_dirs) 2>/dev/null || echo ""))
	@if test -n "$(modified_py_files)"; then \
		echo "Checking/fixing $(modified_py_files)"; \
		$(UV) run --python $(VENV_PY) ruff check $(modified_py_files) --fix; \
		$(UV) run --python $(VENV_PY) ruff format $(modified_py_files); \
		$(UV) run --python $(VENV_PY) mypy $(modified_py_files) || true; \
	else \
		echo "No library .py files were modified"; \
	fi

# Testing targets
test: install-dev
	$(UV) run --python $(VENV_PY) pytest

test-cov: install-dev
	$(UV) run --python $(VENV_PY) pytest --cov=rvc3python --cov-report=html --cov-report=term

test-examples: install-dev
	$(UV) run --python $(VENV_PY) pytest examples/

# Dependency management
deps-update: venv
	$(UV) pip compile --python $(VENV_PY) pyproject.toml --upgrade

deps-sync: venv
	$(UV) sync --python $(VENV_PY)

deps-table-update: venv
	$(VENV_PY) utils/update_dependency_table.py

# Build and release targets
clean:
	rm -rf dist/
	rm -rf build/
	rm -rf *.egg-info/
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete

build: clean
	$(UV) build

build-install: build
	$(UV) pip install --python $(VENV_PY) dist/*.whl

# Utility targets
venv-recreate:
	rm -rf $(VENV_DIR)
	$(MAKE) venv


# Docker targets
docker-build-gpu:
	docker build -f docker/Dockerfile.torch.gpu -t rvc3-python:gpu .

docker-build-cpu:
	docker build -f docker/Dockerfile.torch.cpu -t rvc3-python:cpu .

docker-build: docker-build-gpu docker-build-cpu

docker-run-gpu:
	docker run --gpus all -it --rm \
		-v $(PWD):/workspace \
		-w /workspace \
		rvc3-python:gpu

docker-run-cpu:
	docker run -it --rm \
		-v $(PWD):/workspace \
		-w /workspace \
		rvc3-python:cpu

# Development setup
setup-dev: install-dev
	$(UV) run --python $(VENV_PY) pre-commit install
	@echo "Development environment setup complete!"

# CI/CD helpers
ci-quality: lint-check type-check
ci-test: test-cov

start:
	$(MAKE) venv-recreate
	$(MAKE) deps-sync || { echo "Error: deps-sync failed"; exit 1; }
	$(MAKE) install-dev || { echo "Error: install-dev failed"; exit 1; }
	@echo "Development environment ready!"
	@echo "To activate the virtual environment, run: source .venv/bin/activate"
