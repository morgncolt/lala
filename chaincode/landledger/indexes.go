package main

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

/*** parcel index helpers ***/
func addParcelIndexes(ctx contractapi.TransactionContextInterface, p *LandParcel) error {
	if p == nil {
		return nil
	}
	stub := ctx.GetStub()
	if p.Owner != "" {
		key, _ := stub.CreateCompositeKey(ownerIndex, []string{p.Owner, p.ParcelID})
		if err := stub.PutState(key, []byte{0}); err != nil { return err }
	}
	if p.TitleNumber != "" {
		key, _ := stub.CreateCompositeKey(titleIndex, []string{p.TitleNumber, p.ParcelID})
		if err := stub.PutState(key, []byte{0}); err != nil { return err }
	}
	return nil
}

func removeParcelIndexes(ctx contractapi.TransactionContextInterface, p *LandParcel) error {
	if p == nil {
		return nil
	}
	stub := ctx.GetStub()
	if p.Owner != "" {
		key, _ := stub.CreateCompositeKey(ownerIndex, []string{p.Owner, p.ParcelID})
		_ = stub.DelState(key)
	}
	if p.TitleNumber != "" {
		key, _ := stub.CreateCompositeKey(titleIndex, []string{p.TitleNumber, p.ParcelID})
		_ = stub.DelState(key)
	}
	return nil
}

/*** project helpers ***/
func projectKey(id string) string { return projectKeyPrefix + id }

func projectExists(ctx contractapi.TransactionContextInterface, key string) (bool, error) {
	b, err := ctx.GetStub().GetState(key)
	if err != nil { return false, err }
	return b != nil, nil
}

func putProject(ctx contractapi.TransactionContextInterface, key string, p *Project) error {
	if p == nil { return fmt.Errorf("nil project") }
	normProject(p)
	if p.UpdatedAt == "" {
		p.UpdatedAt = nowRFC3339()
	}
	payload, _ := json.Marshal(p)
	return ctx.GetStub().PutState(key, payload)
}

func addProjectIndexes(ctx contractapi.TransactionContextInterface, p *Project) error {
	if p == nil { return nil }
	stub := ctx.GetStub()
	if p.ParcelID != "" && p.ProjectID != "" {
		key, _ := stub.CreateCompositeKey(projectParcelIdx, []string{p.ParcelID, p.ProjectID})
		if err := stub.PutState(key, []byte{0}); err != nil { return err }
	}
	if p.Owner != "" && p.ProjectID != "" {
		key, _ := stub.CreateCompositeKey(projectOwnerIdx, []string{p.Owner, p.ProjectID})
		if err := stub.PutState(key, []byte{0}); err != nil { return err }
	}
	return nil
}

func removeProjectIndexes(ctx contractapi.TransactionContextInterface, p *Project) error {
	if p == nil { return nil }
	stub := ctx.GetStub()
	if p.ParcelID != "" && p.ProjectID != "" {
		key, _ := stub.CreateCompositeKey(projectParcelIdx, []string{p.ParcelID, p.ProjectID})
		_ = stub.DelState(key)
	}
	if p.Owner != "" && p.ProjectID != "" {
		key, _ := stub.CreateCompositeKey(projectOwnerIdx, []string{p.Owner, p.ProjectID})
		_ = stub.DelState(key)
	}
	return nil
}
