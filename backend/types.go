package main

var activeStatuses = []string{"running", "pending", "created", "waiting_for_resource", "preparing", "manual", "scheduled"}

type ciProvider string

const (
	// Keep GitLab as the zero value so existing model construction and stored data
	// continue to behave as they did before provider support was added.
	providerGitLab ciProvider = ""
	providerGitHub ciProvider = "github"
)

type pipeline struct {
	ID           int        `json:"id"`
	IID          int        `json:"iid"`
	Status       string     `json:"status"`
	Ref          string     `json:"ref"`
	SHA          string     `json:"sha"`
	Source       string     `json:"source"`
	UpdatedAt    string     `json:"updated_at"`
	CreatedAt    string     `json:"created_at"`
	StartedAt    string     `json:"started_at"`
	Duration     *float64   `json:"duration"`
	WebURL       string     `json:"web_url"`
	Commit       commitInfo `json:"commit"`
	CommitTitle  string     `json:"commit_title,omitempty"`
	WorkflowPath string     `json:"workflow_path,omitempty"`
}

type commitInfo struct {
	Title      string `json:"title"`
	AuthorName string `json:"author_name"`
}

type job struct {
	ID           int64    `json:"id"`
	Name         string   `json:"name"`
	Status       string   `json:"status"`
	Stage        string   `json:"stage"`
	Ref          string   `json:"ref"`
	WebURL       string   `json:"web_url"`
	CreatedAt    string   `json:"created_at"`
	StartedAt    string   `json:"started_at"`
	FinishedAt   string   `json:"finished_at"`
	Duration     *float64 `json:"duration"`
	AllowFailure bool     `json:"allow_failure"`
	Retried      bool     `json:"retried"`
	Pipeline     pipeline `json:"pipeline"`
}

type uiJob struct {
	Current  job
	Previous *job
}

type detail struct {
	Pipeline    pipeline
	Jobs        []job
	DisplayJobs []uiJob
}

const inlineLogTailBytes = 64 * 1024
