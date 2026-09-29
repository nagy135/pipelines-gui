package main

func buildDisplayJobs(jobs []job) []uiJob {
	byKey := map[string]int{}
	var rows []uiJob
	for _, j := range jobs {
		key := j.Stage + "\x00" + j.Name
		idx, ok := byKey[key]
		if !ok {
			byKey[key] = len(rows)
			rows = append(rows, uiJob{Current: j})
			continue
		}

		row := rows[idx]
		switch {
		case !j.Retried && (row.Current.Retried || j.ID > row.Current.ID):
			row.Previous = betterPrevious(row.Previous, row.Current)
			row.Current = j
		case j.Status == "manual" && j.ID > row.Current.ID:
			row.Previous = betterPrevious(row.Previous, row.Current)
			row.Current = j
		default:
			row.Previous = betterPrevious(row.Previous, j)
		}
		rows[idx] = row
	}
	return rows
}

func betterPrevious(existing *job, candidate job) *job {
	if (candidate.Status == "manual" && !jobHasRun(candidate)) || candidate.Status == "created" {
		return existing
	}
	if existing == nil || candidate.ID > existing.ID {
		c := candidate
		return &c
	}
	return existing
}

func jobHasRun(j job) bool {
	return j.StartedAt != "" || j.FinishedAt != "" || j.Duration != nil
}

func augmentPreviousRuns(rows []uiJob, history []job, p pipeline) {
	for i := range rows {
		if rows[i].Current.Status != "manual" {
			continue
		}
		for _, candidate := range history {
			if candidate.ID == rows[i].Current.ID || candidate.Name != rows[i].Current.Name || candidate.Stage != rows[i].Current.Stage || !samePipelineJob(candidate, p) {
				continue
			}
			rows[i].Previous = betterPrevious(rows[i].Previous, candidate)
		}
	}
}

func logTarget(row uiJob) job {
	if row.Current.Status == "manual" && row.Previous != nil {
		return *row.Previous
	}
	return row.Current
}

func combinedStatus(row uiJob) string {
	if row.Current.Status == "manual" && row.Previous != nil {
		return previousStatus(*row.Previous) + " + manual"
	}
	return row.Current.Status
}

func previousStatus(j job) string {
	if j.Status == "manual" && jobHasRun(j) {
		return "ran"
	}
	return j.Status
}
