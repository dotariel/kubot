default: test

test:
	@go test -v -coverprofile=coverage.txt -covermode=atomic ./...
