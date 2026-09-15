.PHONY: help test-visitor-counter reset-visitor-counter

AWS_REGION ?= us-east-1
TABLE_NAME ?= cloudresume-visitor-counts
COUNTER_KEY ?= visitor-counter
RESET_HITS ?= 0

help:
	@echo "Targets:"
	@echo "  make test-visitor-counter   Run pytest for the visitor counter Lambda"
	@echo "  make reset-visitor-counter Reset DynamoDB hits (requires AWS CLI + your creds)"

test-visitor-counter:
	cd lambda/visitor_counter && python -m pytest -q

reset-visitor-counter:
	AWS_REGION=$(AWS_REGION) TABLE_NAME=$(TABLE_NAME) COUNTER_KEY=$(COUNTER_KEY) \
		./scripts/reset-visitor-counter.sh --hits $(RESET_HITS)
