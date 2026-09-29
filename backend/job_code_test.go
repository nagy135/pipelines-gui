package main

import (
	"strings"
	"testing"
)

func TestDecodeJobCodeReturnsResolvedScripts(t *testing.T) {
	data := []byte(`{
		"valid": true,
		"jobs": [{
			"name": "test",
			"stage": "verify",
			"before_script": ["bundle install"],
			"script": ["go test ./...", "go vet ./..."],
			"after_script": ["rm -rf tmp"]
		}]
	}`)

	code, err := decodeJobCode(data, "test")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"# job: test",
		"# stage: verify",
		"# before_script\nbundle install",
		"# script\ngo test ./...\ngo vet ./...",
		"# after_script\nrm -rf tmp",
	} {
		if !strings.Contains(code, want) {
			t.Fatalf("resolved code %q does not contain %q", code, want)
		}
	}
}

func TestDecodeJobCodeReportsInvalidConfiguration(t *testing.T) {
	_, err := decodeJobCode([]byte(`{"valid":false,"errors":["include failed"]}`), "test")
	if err == nil || !strings.Contains(err.Error(), "include failed") {
		t.Fatalf("error = %v", err)
	}
}

func TestDecodeJobCodeReportsMissingJob(t *testing.T) {
	_, err := decodeJobCode([]byte(`{"valid":true,"jobs":[]}`), "test")
	if err == nil || !strings.Contains(err.Error(), `job "test" was not found`) {
		t.Fatalf("error = %v", err)
	}
}
