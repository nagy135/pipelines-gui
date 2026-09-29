package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type request struct {
	Operation string   `json:"operation"`
	Provider  string   `json:"provider"`
	Repo      string   `json:"repo"`
	Status    string   `json:"status"`
	Limit     int      `json:"limit"`
	Pipeline  pipeline `json:"pipeline"`
	Job       job      `json:"job"`
}

type jobRow struct {
	Current         job     `json:"current"`
	Previous        *job    `json:"previous,omitempty"`
	LogTarget       job     `json:"log_target"`
	Status          string  `json:"status"`
	TypicalDuration float64 `json:"typical_duration"`
}

type response struct {
	Provider  string     `json:"provider"`
	Pipelines []pipeline `json:"pipelines,omitempty"`
	Pipeline  *pipeline  `json:"pipeline,omitempty"`
	Jobs      []jobRow   `json:"jobs,omitempty"`
	Text      string     `json:"text,omitempty"`
	Error     string     `json:"error,omitempty"`
}

func main() {
	var r request
	var result response
	if err := json.NewDecoder(os.Stdin).Decode(&r); err != nil {
		result.Error = "Invalid request: " + err.Error()
	} else {
		var err error
		result, err = handleRequest(r)
		if err != nil {
			result.Error = err.Error()
		}
	}
	_ = json.NewEncoder(os.Stdout).Encode(result)
}

func handleRequest(r request) (response, error) {
	var result response
	if strings.TrimSpace(r.Repo) == "" {
		return result, fmt.Errorf("choose a repository first")
	}
	p, err := parseProvider(r.Provider)
	if err != nil {
		return result, err
	}
	if r.Provider == "" || r.Provider == "auto" {
		p = detectProvider(r.Repo)
	}
	result.Provider = "gitlab"
	if p == providerGitHub {
		result.Provider = "github"
	}
	switch r.Operation {
	case "list":
		if r.Limit < 1 || r.Limit > 100 {
			return result, fmt.Errorf("limit must be between 1 and 100")
		}
		if r.Status == "" {
			r.Status = "active"
		}
		result.Pipelines, err = fetchProviderPipelines(p, r.Repo, r.Status, r.Limit)
	case "detail":
		if r.Pipeline.ID <= 0 {
			return result, fmt.Errorf("pipeline ID must be positive")
		}
		var d detail
		d, err = fetchProviderDetail(p, r.Repo, r.Pipeline)
		if err == nil {
			result.Pipeline = &d.Pipeline
			scope := providerScope(p, r.Repo)
			stats := loadJobDurations(scope)
			if recordJobDurations(stats, d.Jobs) {
				saveJobDurations(scope, stats)
			}
			for _, row := range d.DisplayJobs {
				result.Jobs = append(result.Jobs, jobRow{row.Current, row.Previous, logTarget(row), combinedStatus(row), stats[row.Current.Name].Average})
			}
		}
	case "logs", "tail":
		if r.Job.ID <= 0 {
			return result, fmt.Errorf("job ID must be positive")
		}
		var data []byte
		data, err = fetchProviderLogs(p, r.Repo, r.Job.ID, r.Operation == "tail")
		result.Text = sanitizeTerminalText(string(data))
		if r.Operation == "tail" {
			lines := strings.Split(strings.TrimRight(result.Text, "\n"), "\n")
			if len(lines) > 5 {
				lines = lines[len(lines)-5:]
			}
			result.Text = strings.Join(lines, "\n")
		}
	case "code":
		if r.Job.ID <= 0 {
			return result, fmt.Errorf("job ID must be positive")
		}
		result.Text, err = fetchProviderJobCode(p, r.Repo, r.Job)
		result.Text = sanitizeTerminalText(result.Text)
	default:
		return result, fmt.Errorf("unknown operation %q", r.Operation)
	}
	return result, err
}

func dataStorePath(name string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".local", "share", "glab-pipelines", name), nil
}
