package main

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// ProjectContract manages projects (separate from parcels).
type ProjectContract struct{ contractapi.Contract }

// ---- internal helpers (project-only) ----

func getProject(ctx contractapi.TransactionContextInterface, projectID string) (*Project, []byte, error) {
	b, err := ctx.GetStub().GetState(projectID)
	if err != nil {
		return nil, nil, err
	}
	if b == nil {
		return nil, nil, fmt.Errorf("project %s not found", projectID)
	}
	var p Project
	if err := json.Unmarshal(b, &p); err != nil {
		return nil, nil, err
	}
	return &p, b, nil
}

// ---- transactions ----

// CreateProject stores a new project from JSON.
func (c *ProjectContract) CreateProject(ctx contractapi.TransactionContextInterface, projectJSON string) error {
	var p Project
	if err := json.Unmarshal([]byte(projectJSON), &p); err != nil {
		return fmt.Errorf("invalid project JSON: %w", err)
	}
	if strings.TrimSpace(p.ProjectID) == "" || strings.TrimSpace(p.ParcelID) == "" || strings.TrimSpace(p.Owner) == "" {
		return fmt.Errorf("projectId, parcelId, owner are required")
	}
	// defaults
	if p.Voters == nil {
		p.Voters = []string{}
	}
	if p.Milestones == nil {
		p.Milestones = []Milestone{}
	}
	if p.CreatedAt == "" {
		p.CreatedAt = nowRFC3339()
	}
	if p.UpdatedAt == "" {
		p.UpdatedAt = p.CreatedAt
	}

	// Ensure not exists
	exists, err := c.Exists(ctx, p.ProjectID)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("project %s already exists", p.ProjectID)
	}

	// Write
	b, _ := json.Marshal(&p)
	if err := ctx.GetStub().PutState(p.ProjectID, b); err != nil {
		return err
	}
	// Use helpers from indexes.go (do NOT redeclare locally)
	return addProjectIndexes(ctx, &p)
}

// GetProject returns a project by id.
func (c *ProjectContract) GetProject(ctx contractapi.TransactionContextInterface, projectID string) (*Project, error) {
	p, _, err := getProject(ctx, projectID)
	return p, err
}

// Exists checks if a project key exists.
func (c *ProjectContract) Exists(ctx contractapi.TransactionContextInterface, projectID string) (bool, error) {
	b, err := ctx.GetStub().GetState(projectID)
	if err != nil {
		return false, err
	}
	return b != nil, nil
}

// ListProjectsByParcel returns all projects for a parcel.
// (Scans state to avoid coupling to specific index constant names in this file.)
func (c *ProjectContract) ListProjectsByParcel(ctx contractapi.TransactionContextInterface, parcelID string) ([]*Project, error) {
	iter, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer iter.Close()

	var out []*Project
	for iter.HasNext() {
		kv, err := iter.Next()
		if err != nil {
			return nil, err
		}
		var p Project
		if err := json.Unmarshal(kv.Value, &p); err == nil && p.ProjectID != "" && p.ParcelID == parcelID {
			out = append(out, &p)
		}
	}
	return out, nil
}

// ListProjectsByOwner returns all projects owned by the given owner.
func (c *ProjectContract) ListProjectsByOwner(ctx contractapi.TransactionContextInterface, owner string) ([]*Project, error) {
	iter, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer iter.Close()

	var out []*Project
	for iter.HasNext() {
		kv, err := iter.Next()
		if err != nil {
			return nil, err
		}
		var p Project
		if err := json.Unmarshal(kv.Value, &p); err == nil && p.ProjectID != "" && p.Owner == owner {
			out = append(out, &p)
		}
	}
	return out, nil
}

// Vote records a voter (unique). It does not alter funding.
func (c *ProjectContract) Vote(ctx contractapi.TransactionContextInterface, projectID, voter string) error {
	if strings.TrimSpace(voter) == "" {
		return fmt.Errorf("voter is required")
	}
	p, _, err := getProject(ctx, projectID)
	if err != nil {
		return err
	}
	for _, v := range p.Voters {
		if v == voter {
			return nil // idempotent
		}
	}
	p.Voters = append(p.Voters, voter)
	p.UpdatedAt = nowRFC3339()

	b, _ := json.Marshal(p)
	return ctx.GetStub().PutState(p.ProjectID, b)
}

// Fund increases the project's funded amount.
func (c *ProjectContract) Fund(ctx contractapi.TransactionContextInterface, projectID, amount string) error {
	n, err := strconv.ParseInt(strings.TrimSpace(amount), 10, 64)
	if err != nil || n <= 0 {
		return fmt.Errorf("invalid amount (must be positive integer): %v", amount)
	}
	p, _, err := getProject(ctx, projectID)
	if err != nil {
		return err
	}
	p.Funded += n
	p.UpdatedAt = nowRFC3339()

	b, _ := json.Marshal(p)
	return ctx.GetStub().PutState(p.ProjectID, b)
}

// UpdateProjectStatus updates the status field verbatim.
func (c *ProjectContract) UpdateProjectStatus(ctx contractapi.TransactionContextInterface, projectID, status string) error {
	if strings.TrimSpace(status) == "" {
		return fmt.Errorf("status is required")
	}
	p, _, err := getProject(ctx, projectID)
	if err != nil {
		return err
	}
	p.Status = ProjectStatus(status)
	p.UpdatedAt = nowRFC3339()

	b, _ := json.Marshal(p)
	return ctx.GetStub().PutState(p.ProjectID, b)
}

// SetContractor assigns or updates contractor contact.
func (c *ProjectContract) SetContractor(ctx contractapi.TransactionContextInterface, projectID, contractor string) error {
	if strings.TrimSpace(contractor) == "" {
		return fmt.Errorf("contractor is required")
	}
	p, _, err := getProject(ctx, projectID)
	if err != nil {
		return err
	}
	p.Contractor = contractor
	p.UpdatedAt = nowRFC3339()

	b, _ := json.Marshal(p)
	return ctx.GetStub().PutState(p.ProjectID, b)
}

// AddMilestone appends a milestone.
func (c *ProjectContract) AddMilestone(ctx contractapi.TransactionContextInterface, projectID, label string, amount string) error {
	if strings.TrimSpace(label) == "" {
		return fmt.Errorf("label is required")
	}
	amt, err := strconv.ParseInt(strings.TrimSpace(amount), 10, 64)
	if err != nil || amt <= 0 {
		return fmt.Errorf("invalid milestone amount: %v", amount)
	}
	p, _, err := getProject(ctx, projectID)
	if err != nil {
		return err
	}
	p.Milestones = append(p.Milestones, Milestone{
		Label:    label,
		Amount:   amt,
		Released: false,
	})
	p.UpdatedAt = nowRFC3339()

	b, _ := json.Marshal(p)
	return ctx.GetStub().PutState(p.ProjectID, b)
}

// ReleaseMilestone marks a milestone as released and deducts funds.
func (c *ProjectContract) ReleaseMilestone(ctx contractapi.TransactionContextInterface, projectID, label string) error {
	if strings.TrimSpace(label) == "" {
		return fmt.Errorf("label is required")
	}
	p, _, err := getProject(ctx, projectID)
	if err != nil {
		return err
	}
	idx := -1
	for i := range p.Milestones {
		if p.Milestones[i].Label == label {
			idx = i
			break
		}
	}
	if idx < 0 {
		return fmt.Errorf("milestone not found: %s", label)
	}
	if p.Milestones[idx].Released {
		return nil // idempotent
	}
	if p.Funded < p.Milestones[idx].Amount {
		return fmt.Errorf("insufficient funded amount to release %s", label)
	}
	p.Funded -= p.Milestones[idx].Amount
	p.Milestones[idx].Released = true
	p.UpdatedAt = nowRFC3339()

	b, _ := json.Marshal(p)
	return ctx.GetStub().PutState(p.ProjectID, b)
}

// DeleteProject removes a project and its indexes.
func (c *ProjectContract) DeleteProject(ctx contractapi.TransactionContextInterface, projectID string) error {
	p, _, err := getProject(ctx, projectID)
	if err != nil {
		return err
	}
	if err := ctx.GetStub().DelState(projectID); err != nil {
		return err
	}
	// Use helper from indexes.go
	return removeProjectIndexes(ctx, p)
}

// GetProjectHistory returns per-key history with project values.
type ProjectHistoryEntry struct {
	TxID     string   `json:"txId"`
	IsDelete bool     `json:"isDelete"`
	Value    *Project `json:"value"`
}

func (c *ProjectContract) GetProjectHistory(ctx contractapi.TransactionContextInterface, projectID string) ([]*ProjectHistoryEntry, error) {
	iter, err := ctx.GetStub().GetHistoryForKey(projectID)
	if err != nil {
		return nil, err
	}
	defer iter.Close()

	var out []*ProjectHistoryEntry
	for iter.HasNext() {
		r, err := iter.Next()
		if err != nil {
			return nil, err
		}
		var val *Project
		if !r.IsDelete && len(r.Value) > 0 {
			var tmp Project
			if err := json.Unmarshal(r.Value, &tmp); err == nil {
				val = &tmp
			}
		}
		out = append(out, &ProjectHistoryEntry{TxID: r.TxId, IsDelete: r.IsDelete, Value: val})
	}
	return out, nil
}
