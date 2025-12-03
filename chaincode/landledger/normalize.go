package main

func normProject(p *Project) *Project {
	if p == nil {
		return &Project{}
	}
	// sensible defaults
	if p.Status == "" {
		p.Status = ProjectStatusCreated
	}
	if p.CreatedAt == "" {
		p.CreatedAt = nowRFC3339()
	}
	if p.UpdatedAt == "" {
		p.UpdatedAt = p.CreatedAt
	}
	if p.Voters == nil {
		p.Voters = []string{}
	}
	if p.Milestones == nil {
		p.Milestones = []Milestone{}
	}
	return p
}
