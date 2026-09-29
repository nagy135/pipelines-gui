package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBridgeRejectsInvalidRequestsWithoutInvokingCLI(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	for _, r := range []request{
		{Operation: "list"},
		{Operation: "list", Repo: "a/b", Limit: 101},
		{Operation: "cancel", Repo: "a/b"},
		{Operation: "detail", Repo: "a/b"},
		{Operation: "logs", Repo: "a/b"},
		{Operation: "code", Repo: "a/b"},
	} {
		if _, err := handleRequest(r); err == nil {
			t.Fatalf("accepted invalid request %+v", r)
		}
	}
}

func TestLogBridgeAllowsGHANSIThenSanitizesAndTails(t *testing.T) {
	dir := t.TempDir()
	script := `#!/bin/sh
if [ "$*" != "api --allow-escape-sequences repos/{owner}/{repo}/actions/jobs/7/logs" ]; then
 echo "unexpected arguments: $*" >&2; exit 1
fi
printf '\033[31mone\033[0m\ntwo\nthree\nfour\nfive\nsix\n'
`
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	r, err := handleRequest(request{Operation: "tail", Provider: "github", Repo: "a/b", Job: job{ID: 7}})
	if err != nil {
		t.Fatal(err)
	}
	if r.Text != "two\nthree\nfour\nfive\nsix" {
		t.Fatalf("tail = %q", r.Text)
	}
	r, err = handleRequest(request{Operation: "logs", Provider: "github", Repo: "a/b", Job: job{ID: 7}})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(r.Text, "one\n") || strings.Contains(r.Text, "\033") {
		t.Fatalf("ANSI not sanitized: %q", r.Text)
	}
}

func TestBridgeGroupsRetriesAndRetainsManualLogTarget(t *testing.T) {
	seconds := 42.0
	rows := buildDisplayJobs([]job{
		{ID: 5, Name: "deploy", Stage: "deploy", Status: "failed", Retried: true, Duration: &seconds},
		{ID: 6, Name: "deploy", Stage: "deploy", Status: "manual"},
	})
	if len(rows) != 1 || rows[0].Current.ID != 6 || logTarget(rows[0]).ID != 5 || combinedStatus(rows[0]) != "failed + manual" {
		t.Fatalf("retry rows = %+v", rows)
	}
}
